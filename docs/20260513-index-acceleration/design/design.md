# ES 索引加速 — 深度设计文档

> 基于 origin-design.md 的 deepdive，对齐现有工程模式（ES 7.10.2、QSchedule、QConfig、ElasticsearchDataSource）

---

## 一、总体架构

### 1.1 位置关系

```
RawContentSyncService.sync()        ← 同步业务表到 MySQL（已有）
        │
        ▼
ContentSearchIndexService.index()   ← 同步完成后触发 ES 索引（新增）
        │
        ├── IndexRequest（首次全量）
        ├── UpdateRequest + upsert（指标/标签更新）
        ├── BulkRequest（批量场景）
        └── SearchRequest（查询）
                │
                ▼
        ElasticsearchDataSource      ← 增强现有类，新增 update/search 操作
                │
                ▼
        RestHighLevelClient          ← ES 7.10.2，已有
```

### 1.2 核心策略：同步写入 + 异步修复

| 策略 | 说明 |
|------|------|
| 同步写入 | MySQL 事务提交后，同一线程同步写 ES。ES 失败不影响 MySQL，仅记录异常，依赖修复任务兜底 |
| 定时修复 | 30 分钟间隔扫描 ES 中不完整/缺失的文档，从 MySQL 补全 |
| 全量对账 | 每日凌晨对比 MySQL base_id 与 ES _id，补全缺失文档 |
| 全量重建 | 手动触发，Mapping 变更或索引损坏时使用 |

**为什么不异步（MQ）？**

1. 内容数量级不大（日增量数百~数千），同步开销可接受
2. 避免引入 MQ 带来的运维复杂度
3. 修复任务已覆盖 ES 写入失败场景

---

## 二、索引管理

### 2.1 索引设计

| 项目 | 值 |
|------|-----|
| 索引名 | `content_search` |
| 别名 | `content_search_alias`（用于零停机重建） |
| Shards | QConfig 可配，默认 3 |
| Replicas | QConfig 可配，默认 1 |
| Refresh interval | QConfig 可配，默认 `5s`，批量导入时可调大 |

### 2.2 Mapping

详见 origin-design.md 第一节。

与工程上下文的关键对齐点：

| 字段 | 类型 | 对标原始设计 |
|------|------|-------------|
| base_id | long | 对应 `content_base.id` |
| content_id | keyword | 对应 `content_base.content_id` |
| content_type | keyword | 对应 `content_base.content_type` |
| city/poi/ai_tag | keyword | 冗余自 `content_label` |
| 全部指标 | integer/float | 冗余自 `content_metrics` |
| sync_time | date | 记录最后同步时间，用于对账 |

### 2.3 初始化

系统启动时通过 `@PostConstruct` 或 `ApplicationListener` 确保索引存在：

```
if (!existIndex("content_search")):
    create("content_search", settings, mapping)
```

settings 和 mapping 使用与 `EsDemoService` 相同的模式：settings 从 QConfig 读，mapping 硬编码在类中。

---

## 三、写入流程

### 3.1 文档模型

```java
public class ContentSearchDocument {
    private Long baseId;
    private String contentId;
    private String contentType;
    private String publishPlatform;
    private String publishTime;       // yyyy-MM-dd HH:mm:ss
    private String businessLine;
    private String contentSource;
    private String productionTeam;
    private String operationProject;
    private String placementPosition;
    private String city;
    private String poi;
    private List<String> aiTag;       // JSON array → List<String>
    private Integer totalImpressions;
    private Integer totalClicks;
    private Integer totalReads;
    private Integer totalInteractions;
    // ... 其余指标字段（略，与 mapping 一一对应）
    private String syncTime;          // yyyy-MM-dd HH:mm:ss
}
```

**序列化说明：** ES 层使用 Gson（`ElasticsearchDataSource` 硬编码）。Gson 序列化 `List<String>` 为 `["a","b"]`，`Integer` 默认值为 `0` 时也会序列化，但 ES 接受 `0` 不需要特殊处理。

### 3.2 场景一：新内容入库（首次同步）

**触发位置：** `RawContentSyncServiceImpl.sync()` MySQL 事务成功后，调用方（`triggerSync`）继续调用索引服务。

```java
// RawContentSyncServiceImpl.triggerSync() 中
rawContentSyncService.sync(raw);                    // MySQL 写入（已有）

// 新增：ES 索引
ContentSearchDocument doc = docAssembler.assembleByContentId(raw.getContentId());
if (doc != null) {
    contentSearchIndexService.index(doc);           // ES 写入
}
```

**操作类型：** `IndexRequest`，`_id = baseId.toString()`，幂等覆盖

### 3.3 场景二：指标每日批量更新

**触发位置：** `RawContentSyncService.sync()` 二次同步时 MySQL metrics 更新后。

与场景一相同的位置，但数据不同：

```java
// sync() 中 baseId != null 分支完成后
ContentSearchDocument doc = docAssembler.assembleMetricsOnly(baseId, raw);
contentSearchIndexService.update(doc);   // UpdateRequest + upsert
// 或批量场景用 bulkUpdate
```

**操作类型：** `UpdateRequest + upsert = true`

- doc 中携带**全部字段**（从 MySQL 6 张表 JOIN 组装），确保 upsert 创建完整文档
- 批量场景（数仓同步）：每 500 条一批，BulkRequest 并行更新

### 3.4 场景三：AI 标签更新

**触发位置：** AI 任务回调接口中

```java
// AIService 回调
ContentSearchDocument doc = new ContentSearchDocument();
doc.setBaseId(baseId);
doc.setAiTag(aiTags);
doc.setCity(city);
doc.setPoi(poi);
doc.setSyncTime(LocalDateTime.now());

contentSearchIndexService.update(doc);   // UpdateRequest + upsert
```

**操作类型：** `UpdateRequest + upsert = true`

- doc 仅含标签字段，**不携带基础字段**
- 若文档不存在，upsert 会创建不完整文档，由修复任务补全

**注意：** 这与 origin-design 一致 — AI 回调不需要查 MySQL 组装完整文档。不完整文档由修复任务兜底。

### 3.5 序列化策略深究

`ContentSearchDocument` 使用 `Gson` 序列化。Gson 默认 `new Gson()` 会**跳过 null 字段**（不序列化到 JSON 中）。

**场景一（IndexRequest 全量）：需要所有字段都有值**

- IndexRequest 用 `GSON.toJson(doc)` 生成完整 JSON 写入 ES
- Gson 跳过 null → ES 中该字段**不存在**（不是 null，而是不存在于 `_source`）
- 对于 `keyword` 字段：字段不存在 = term 查询无法命中
- 对于 `integer` 字段：字段不存在 = range/sort 报错

**解决方案：** `ContentSearchDocAssembler` 组装时，确保**所有指标字段有默认值 0**，**字符串字段有默认值 ""**，不要留 null：

```java
// assembleByContentId 返回的 doc 中
doc.setTotalImpressions(Optional.ofNullable(metrics.getTotalImpressions()).orElse(0));
doc.setContentType(Optional.ofNullable(base.getContentType()).orElse(""));
// 其余字段同理
```

**场景二/三（UpdateRequest + upsert）：Gson 跳过 null 正好符合语义**

- `UpdateRequest.doc(GSON.toJson(doc))` 中，null 字段被跳过 → ES 侧该字段**不被修改**
- 这正是 partial update 想要的效果：只更新非 null 字段
- 所以 `ContentSearchIndexService.updateDocument()` 可以直接调用 `GSON.toJson(doc)`，不需要额外处理

**验证：** 如果用 Gson 的 `GsonBuilder().serializeNulls().create()` 会序列化 null 为 JSON literal `null`，导致 UpdateRequest 把字段显式设置为 null（覆盖原有值）。所以必须用默认 `new Gson()`，保持跳过 null 的行为。

**结论：**

| 场景 | 序列化方式 | null 处理 | 行为 |
|------|-----------|----------|------|
| 场景一 IndexRequest | `GSON.toJson(doc)` | 跳过 null（需组装默认值） | ES 写入所有字段 |
| 场景二 UpdateRequest + upsert | `GSON.toJson(doc)` | 跳过 null（符合语义） | ES 只更新非 null 字段 |
| 场景三 UpdateRequest + upsert | `GSON.toJson(doc)` | 同上 | 同上 |

---

## 四、搜索查询

> ES 索引不存储 `content_title`、`publish_url`、`content_text`，搜索基于过滤 + 排序 + 分页。如需展示标题/正文，由调用方根据返回的 `base_id` 查 MySQL。

### 4.1 功能列表

| 功能 | 说明 |
|------|------|
| 精确过滤 | content_type(多选)、publish_platform(多选)、business_line、content_source |
| 标签过滤 | city、poi、ai_tag |
| 时间范围 | publish_time 起止 |
| 指标排序 | 按 total_impressions、total_clicks 等降序/升序 |
| 分页 | from + size |

### 4.2 请求/响应模型

```java
public class ContentSearchRequest {
    private List<String> contentTypes;   // 内容类型过滤
    private List<String> platforms;      // 平台过滤
    private String businessLine;         // 业务线
    private List<String> cities;         // 城市过滤
    private List<String> aiTags;         // AI标签过滤
    private String publishTimeStart;     // 发布开始时间
    private String publishTimeEnd;       // 发布结束时间
    private String sortField;            // 排序字段
    private String sortOrder;            // asc / desc
    private Integer from;                // 分页起始，默认 0
    private Integer size;                // 每页条数，默认 20
}

public class ContentSearchResponse {
    private List<ContentSearchHit> hits; // 命中列表
    private long total;                  // 总数
    private Integer took;                // ES 耗时(ms)
}

public class ContentSearchHit {
    private Long baseId;
    private String contentId;
    private String contentType;
    private String publishPlatform;
    private String publishTime;
    private String businessLine;
    private String contentSource;
    private String productionTeam;
    private String operationProject;
    // ... 指标字段（可选返回）
}
```

### 4.3 查询 DSL（伪代码）

```
SearchSourceBuilder search = new SearchSourceBuilder();
BoolQueryBuilder filter = bool()

// 精确过滤（全部走 filter，不参与评分）
if contentTypes is not empty: filter.filter(terms("content_type", contentTypes))
if platforms is not empty: filter.filter(terms("publish_platform", platforms))
if businessLine is not blank: filter.filter(term("business_line", businessLine))
if cities is not empty: filter.filter(terms("city", cities))
if aiTags is not empty: filter.filter(terms("ai_tag", aiTags))
if publishTimeStart is not blank: filter.filter(range("publish_time").gte(publishTimeStart))
if publishTimeEnd is not blank: filter.filter(range("publish_time").lte(publishTimeEnd))

search.query(filter)

// 排序
if sortField is not blank:
    search.sort(sortField, sortOrder)
else:
    search.sort("publish_time", "desc")   // 默认按发布时间倒序

// 分页
search.from(from).size(size)
```

### 4.4 排序白名单 + 搜索防护

**问题：** `sortField` 开放传入 → 用户可以指定任意 ES 字段名排序。若字段不存在、类型不支持排序、或字段名拼错 → ES 返回错误。

### 4.4 排序白名单 + 搜索防护

**问题：** `sortField` 开放传入 → 用户可以指定任意 ES 字段名排序。若字段不存在、类型不支持排序（如 `text`）、或字段名拼错 → ES 返回错误。

**方案 A：白名单校验**

```java
private static final Set<String> SORT_WHITELIST = new HashSet<>(Arrays.asList(
    "publish_time", "total_impressions", "total_clicks", "total_reads",
    "total_interactions", "completion_rate", "cpm", "ctr", "app_downloads",
    "total_orders"
));

// ContentSearchServiceImpl.search() 中
if (StringUtils.isNotBlank(request.getSortField())) {
    if (!SORT_WHITELIST.contains(request.getSortField())) {
        throw new IllegalArgumentException("不支持的排序字段: " + request.getSortField());
    }
    SortOrder order = "desc".equalsIgnoreCase(request.getSortOrder()) ? SortOrder.DESC : SortOrder.ASC;
    builder.sort(request.getSortField(), order);
}
```

**方案 B：try-catch 兜底回退**

```java
try {
    SortOrder order = "desc".equalsIgnoreCase(request.getSortOrder()) ? SortOrder.DESC : SortOrder.ASC;
    builder.sort(request.getSortField(), order);
} catch (Exception e) {
    log.warn("sort field {} failed, fallback to default", request.getSortField());
    builder.sort("publish_time", SortOrder.DESC);
}
```

| 方案 | 优点 | 缺点 |
|------|------|------|
| A 白名单 | 明确拒绝，用户感知清晰 | 多一个 Set + 判断 |
| B try-catch | 灵活，不需维护白名单 | 等到执行才报错，性能略差 |

**推荐方案 A**。排序字段有限且明确，白名单维护成本极低，且能在请求到达 ES 前快速拒绝。

**其他防护：**

| 参数 | 防护规则 |
|------|---------|
| `size` | `Math.max(1, Math.min(size, 100))`，默认 20，上限 100 |
| `from` | `Math.max(0, from)`，上限 10000（ES `max_result_window` 默认值） |
| `sortField` | 白名单校验，非法返回 400 |

---

## 五、ElasticsearchDataSource 增强

现有类缺少 update、bulkUpdate、search 能力，需要新增 3 个方法。

### 5.1 接口设计

```java
// 新增：单条更新（partial update + upsert）
boolean update(String index, String id, Object doc);

// 新增：批量更新（bulk partial update + upsert）
boolean bulkUpdate(String index, List<IndexRequest> requests);

// 新增：搜索
String search(String index, String queryJson);
```

### 5.2 update 实现概要

```java
public boolean update(String index, String id, Object doc) {
    try {
        UpdateRequest request = new UpdateRequest(index, id)
            .doc(GSON.toJson(doc), XContentType.JSON)
            .docAsUpsert(true);
        restHighLevelClient.update(request, RequestOptions.DEFAULT);
        return true;
    } catch (Exception e) {
        log.error("ES update error", e);
        QMonitor.recordOne("es_update_error");
        return false;
    }
}
```

注意：Java 8 的 `UpdateRequest` 构造函数需要 index + id。ES 7.10.2 的 HLRC 中 `new UpdateRequest(index, id)` 已标记为 `@Deprecated` 但仍然可用。或者使用 `new UpdateRequest().index(index).id(id)` 的形式。

### 5.3 bulkUpdate 实现概要

```java
public boolean bulkUpdate(String index, List<UpdateRequest> requests) {
    try {
        BulkRequest bulk = new BulkRequest();
        requests.forEach(bulk::add);
        BulkResponse response = restHighLevelClient.bulk(bulk, RequestOptions.DEFAULT);
        if (response.hasFailures()) {
            log.warn("ES bulk update has failures: {}", response.buildFailureMessage());
            return false;
        }
        return true;
    } catch (Exception e) {
        log.error("ES bulk update error", e);
        QMonitor.recordOne("es_bulk_update_error");
        return false;
    }
}
```

### 5.4 search 实现概要

```java
public String search(String index, String queryJson) {
    try {
        SearchRequest request = new SearchRequest(index);
        SearchSourceBuilder builder = new SearchSourceBuilder();
        // queryJson → SearchSourceBuilder
        // 使用 Gson 解析 queryJson 并填充 builder
        // 或直接使用 SearchSourceBuilder 的 Java API（推荐）
        request.source(builder);
        SearchResponse response = restHighLevelClient.search(request, RequestOptions.DEFAULT);
        return GSON.toJson(response);  // 或提取 hits 后返回精简结果
    } catch (Exception e) {
        log.error("ES search error", e);
        QMonitor.recordOne("es_search_error");
        return null;
    }
}
```

**设计决策：** search 方法在 DataSource 层保持通用，接收 `SearchSourceBuilder` 参数，返回 `SearchResponse`。上层 `ContentSearchService` 负责构建查询逻辑和解析响应。

---

## 六、服务层设计

### 6.1 ContentSearchIndexService（写入服务）

```java
public interface ContentSearchIndexService {
    /**
     * 全量索引单条文档（首次同步）
     */
    void indexDocument(ContentSearchDocument doc);

    /**
     * 部分更新（指标/标签更新）
     */
    void updateDocument(ContentSearchDocument doc);

    /**
     * 批量更新（数仓指标同步）
     */
    void batchUpdateDocuments(List<ContentSearchDocument> docs);
}
```

职责：
- 组装 Document (JSON) → 调用 `ElasticsearchDataSource.update/bulkUpdate`
- 记录 QMonitor
- 失败时日志告警（不抛异常，不阻断主流程）

### 6.2 ContentSearchService（查询服务）

```java
public interface ContentSearchService {
    /**
     * 综合检索
     */
    ContentSearchResponse search(ContentSearchRequest request);
}
```

职责：
- 构建 `SearchSourceBuilder`（查询 DSL）
- 调用 `ElasticsearchDataSource.search`
- 解析 `SearchResponse` → `ContentSearchResponse`
- 高亮处理

### 6.3 DocAssembler（文档组装）

```java
public interface ContentSearchDocAssembler {
    /**
     * 根据 content_id 组装完整文档（6 表 JOIN）
     */
    ContentSearchDocument assembleByContentId(String contentId);

    /**
     * 根据 base_id 组装完整文档
     */
    ContentSearchDocument assembleByBaseId(Long baseId);

    /**
     * 批量查询 → 批量组装
     */
    List<ContentSearchDocument> assembleByBaseIds(List<Long> baseIds);
}
```

MySQL 查询：

```sql
SELECT
    cb.id AS base_id,
    cb.content_id,
    cb.content_type,
    cb.publish_platform,
    cb.publish_time,
    cb.business_line,
    cb.content_source,
    cb.production_team,
    cb.operation_project,
    cb.placement_position,
    cl.city,
    cl.poi,
    cl.ai_tag,
    cm.total_impressions,
    cm.total_clicks,
    -- ... 其余指标
FROM content_base cb
LEFT JOIN content_label cl ON cl.base_id = cb.id
LEFT JOIN content_metrics cm ON cm.base_id = cb.id
WHERE cb.content_id = #{contentId}   -- 或 cb.id IN (ids)
```

注意：ES 不存原标题/正文/URL。image/video 数据不入 ES（ES 只存分类+指标+标签）。

### 6.4 DocAssembler SQL 详细设计

#### 6.4.1 单条查询（assembleByContentId / assembleByBaseId）

```sql
SELECT
    cb.id              AS base_id,
    cb.content_id,
    cb.content_type,
    cb.publish_platform,
    cb.publish_time,
    cb.business_line,
    cb.content_source,
    cb.production_team,
    cb.operation_project,
    cb.placement_position,
    cl.city,
    cl.poi,
    cl.ai_tag,
    -- 以下指标字段，如果 content_metrics 行不存在则为 NULL
    cm.total_impressions,
    cm.total_clicks,
    cm.total_reads,
    cm.total_interactions,
    cm.completion_rate,
    cm.three_sec_completion_rate,
    cm.five_sec_completion_rate,
    cm.two_sec_bounce_rate,
    cm.cpm,
    cm.ctr,
    cm.cvr,
    cm.app_downloads,
    cm.new_activations,
    cm.new_registrations,
    cm.drive_uv,
    cm.exposure_to_read_ratio,
    cm.potential_new_uv,
    cm.potential_new_cac,
    cm.attributed_new_customers,
    cm.new_customer_cac,
    cm.order_uv,
    cm.total_orders
FROM content_base cb
LEFT JOIN content_label cl
    ON cl.base_id = cb.id
LEFT JOIN content_metrics cm
    ON cm.base_id = cb.id
WHERE cb.content_id = #{contentId}   -- 或 cb.id = #{baseId}
```

> 注：不再需要 JOIN `content_text`，ES 不存储正文内容。

#### 6.4.2 批量查询（assembleByBaseIds）

```sql
SELECT
    cb.id              AS base_id,
    cb.content_id,
    cb.content_type,
    -- ...（同上所有字段）
FROM content_base cb
LEFT JOIN content_label cl
    ON cl.base_id = cb.id
LEFT JOIN content_metrics cm
    ON cm.base_id = cb.id
<where>
    <if test="baseIds != null and baseIds.size() > 0">
        AND cb.id IN
        <foreach collection="baseIds" item="id" open="(" separator="," close=")">
            #{id}
        </foreach>
    </if>
</where>
```

#### 6.4.3 数据类型转换（MySQL → Java）

| MySQL 字段 | MySQL 类型 | Java 类型 | 注意 |
|-----------|-----------|-----------|------|
| `cl.ai_tag` | JSON | `String` / `List<String>` | MyBatis 接收为 String，`ContentSearchDocument` 中为 `List<String>`，需要自定 TypeHandler 或在 Service 层用 `Gson.fromJson(aiTagStr, List.class)` 转换 |
| `cm.*_rate` | DECIMAL(8,3) | `String` / `Float` | ES mapping 中为 float，可以直接 CAST 或 MyBatis 用 BigDecimal 接收后转 Float |
| `cm.cpm` | DECIMAL(8,4) | `String` / `Float` | 同上 |

**ai_tag 类型处理方案：**

MyBatis 不支持直接将 JSON 列映射为 `List<String>`。两种方案：

| 方案 | 实现 | 评价 |
|------|------|------|
| **A: MyBatis TypeHandler** | 新建 `JsonToListTypeHandler`，在 XML resultMap 中引用 | 代码更干净，但多一个类 |
| **B: Service 手动转换** | MyBatis 用 `String` 接收，`ContentSearchDocAssemblerImpl` 中 `new Gson().fromJson(aiTagStr, List.class)` | 更简单，不增加类 |

推荐方案 B，因为只有 `ai_tag` 一个字段需要处理，引入 TypeHandler 过于重量级。

#### 6.4.4 分页全量扫描（全量重建、全量对账场景）

```sql
SELECT
    cb.id              AS base_id,
    cb.content_id,
    -- ...（同上所有字段）
FROM content_base cb
LEFT JOIN content_label cl
    ON cl.base_id = cb.id
LEFT JOIN content_metrics cm
    ON cm.base_id = cb.id
ORDER BY cb.id
LIMIT #{offset}, #{pageSize}
```

---

## 七、异常处理方案

### 7.1 写入失败

| 场景 | 处理 |
|------|------|
| ES 集群不可用 | IndexService 记录 error + QMonitor，不抛异常。MySQL 数据不受影响。 |
| BULK 部分失败 | 记录失败 batch 日志，修复任务兜底 |
| 单条更新失败 | 记录日志，跳过本条 |

**原则：ES 失败不影响 MySQL 主流程。**

### 7.2 修复任务

#### 7.2.1 不完整文档修复

```java
@Service
public class EsRepairTask {

    @QSchedule("es_repair_task")
    public void repairTask(Parameter param) {
        // 1. 查询 ES 中基础字段缺失的文档（exist(content_id) = false 或 content_id = ""）
        // 2. 分批查询 MySQL 组装完整文档
        // 3. Bulk index 修复
    }
}
```

执行频率：QConfig 可配，默认每 30 分钟。

#### 7.2.2 全量对账

```java
@Service
public class EsReconcileTask {

    @QSchedule("es_reconcile_task")
    public void reconcileTask(Parameter param) {
        // 1. 分页查询 MySQL content_base 所有 id
        // 2. 与 ES _id 对比
        // 3. 缺失的调用 assembleByBaseId 补齐
    }
}
```

执行频率：QConfig 可配，默认每天凌晨 03:00。

#### 7.2.3 全量重建

```java
@Service
public class EsFullRebuildTask {
    // 手动触发，不在 QSchedule 中
    public void fullRebuild() {
        // 1. 创建新索引 content_search_v2（settings + mapping）
        // 2. 分页从 MySQL 6 表 JOIN 全部数据
        // 3. Bulk index 到新索引
        // 4. 切换别名 content_search_alias → content_search_v2
        // 5. 删除旧索引
    }
}
```

### 7.3 修复任务实现深挖

#### 7.3.1 不完整文档修复 — ES 查询条件

使用 `SearchSourceBuilder` 构造查询基础字段缺失的文档：

```java
// EsRepairTask 中
SearchSourceBuilder builder = new SearchSourceBuilder();
BoolQueryBuilder bool = QueryBuilders.boolQuery();
bool.should(QueryBuilders.boolQuery().mustNot(QueryBuilders.existsQuery("content_id")));
bool.should(QueryBuilders.boolQuery().mustNot(QueryBuilders.existsQuery("business_line")));
bool.should(QueryBuilders.boolQuery().mustNot(QueryBuilders.existsQuery("content_type")));
bool.should(QueryBuilders.termQuery("content_id", ""));
bool.should(QueryBuilders.termQuery("business_line", ""));
bool.minimumShouldMatch(1);
builder.query(bool);
builder.size(100);
builder.fetchSource(false);  // 只需要 _id

SearchResponse response = elasticsearchDataSource.search("content_search", builder);
List<Long> incompleteBaseIds = new ArrayList<>();
for (SearchHit hit : response.getHits().getHits()) {
    incompleteBaseIds.add(Long.parseLong(hit.getId()));
}
```

**注意：** `termQuery("content_id", "")` 匹配 content_id 为空字符串的文档。`existsQuery("content_id")` 匹配字段**存在**的文档。组合 `must_not exists` + `term = ""` 覆盖全部缺失场景。

#### 7.3.2 全量对账 — 方案对比

| 方式 | 优点 | 缺点 |
|------|------|------|
| **MySQL 分页遍历**（推荐） | 简单，MyBatis 分页 | offset 越大越慢（< 1000w 可接受） |
| **ES Scroll API** | 服务端游标，大量数据高效 | 维护 scroll context，需清理 |
| **ES ids 查询** | 精确对比一批 id | 每次查询有长度限制 |

推荐 **MySQL 分页遍历** 方案（< 1000w 数据量，MySQL offset 性能可接受）：

```java
// EsReconcileTask
long total = contentBaseMapper.count();           // SELECT COUNT(*) FROM content_base
int pageSize = 1000;

for (int offset = 0; offset < total; offset += pageSize) {
    // 1. MySQL 分页取 baseIds
    List<Long> mysqlIds = contentBaseMapper.selectIdsPage(offset, pageSize);
    
    // 2. ES ids 查询
    SearchSourceBuilder builder = new SearchSourceBuilder();
    builder.query(QueryBuilders.idsQuery().addIds(
        mysqlIds.stream().map(String::valueOf).toArray(String[]::new)));
    builder.size(mysqlIds.size());
    builder.fetchSource(false);
    SearchResponse response = elasticsearchDataSource.search("content_search", builder);
    Set<Long> esIdSet = Arrays.stream(response.getHits().getHits())
        .map(h -> Long.parseLong(h.getId()))
        .collect(Collectors.toSet());
    
    // 3. 对比：缺失的补全
    List<Long> missingIds = mysqlIds.stream()
        .filter(id -> !esIdSet.contains(id))
        .collect(Collectors.toList());
    
    if (!missingIds.isEmpty()) {
        List<ContentSearchDocument> docs = docAssembler.assembleByBaseIds(missingIds);
        contentSearchIndexService.batchUpdateDocuments(docs);
        QMonitor.recordOne("es_reconcile_missing", missingIds.size());
    }
}
```

#### 7.3.3 全量重建 — 别名切换流程

```
EsFullRebuildTask.fullRebuild():
│
├─ 1. 生成新索引名: "content_search_v{timestamp}"
│      String newIndex = "content_search_v" + Instant.now().toEpochMilli();
│
├─ 2. 创建新索引（settings + mapping）
│      elasticsearchDataSource.create(newIndex, settings, mapping);
│
├─ 3. 分页从 MySQL 6 表 JOIN 全量数据
│      for (offset = 0; offset < total; offset += pageSize):
│          List<ContentSearchDocument> docs = assembler.assembleByPage(offset, pageSize);
│          elasticsearchDataSource.batchInsert(newIndex, docs);
│
├─ 4. 切换别名（原子操作）
│      IndicesAliasesRequest aliasRequest = new IndicesAliasesRequest();
│      aliasRequest.addAliasAction(AliasActions.remove()
│          .index("content_search").alias("content_search_alias"));
│      aliasRequest.addAliasAction(AliasActions.add()
│          .index(newIndex).alias("content_search_alias"));
│      restHighLevelClient.indices().updateAliases(aliasRequest, RequestOptions.DEFAULT);
│
└─ 5. 删除旧索引
        DeleteIndexRequest deleteRequest = new DeleteIndexRequest("content_search");
        restHighLevelClient.indices().delete(deleteRequest, RequestOptions.DEFAULT);
```

**别名设计方案：**

| 别名 | 指向 | 用途 |
|------|------|------|
| `content_search_alias` | 当前活跃索引 | 搜索 API、写入服务均通过别名访问 |
| `content_search` | 初始索引名 | 启动时创建，重建后由别名接管 |

**写入路径统一走别名：**

```java
// IndexQConfig 或常量
private static final String ES_INDEX = "content_search_alias";

// ContentSearchIndexService 中：
elasticsearchDataSource.update(ES_INDEX, id, doc);
```

而非写死 `content_search`。这样全量重建切换别名后，写入路径自动指向新索引，无需修改代码。

**双写策略（重建期间）：**

```java
// ContentSearchIndexService 中
void indexDocument(ContentSearchDocument doc) {
    if (rebuildInProgress) {
        elasticsearchDataSource.batchInsert(newIndex, Collections.singletonList(doc));
    }
    elasticsearchDataSource.update(ES_INDEX, doc.getBaseId().toString(), doc);
}
```

- `rebuildInProgress` 是 `EsFullRebuildTask` 中设置的 `volatile boolean` 标志
- 双写确保重建期间写入的数据不丢失
- 别名切换后，新写入自动进入新索引

---

## 八、动态配置（QConfig）

### 8.1 配置项

```properties
# es-index.properties
es.sync.enabled=true              # ES 同步总开关，关闭后跳过所有 ES 写入
es.index.shards=3
es.index.replicas=1
es.index.refresh.interval=5s
es.batch.size=500
es.repair.enabled=true
es.repair.interval.minutes=30
```

### 8.2 配置类

```java
@Service
public class IndexQConfig {

    private volatile boolean syncEnabled = true;   // ES 同步总开关
    private volatile int shards = 3;
    private volatile int replicas = 1;
    private volatile String refreshInterval = "5s";
    private volatile int batchSize = 500;
    private volatile boolean repairEnabled = true;
    private volatile int repairIntervalMinutes = 30;

    @QConfig("es-index.properties")
    private void onChanged(Map<String, String> map) {
        if (map == null) return;
        syncEnabled = Boolean.parseBoolean(map.getOrDefault("es.sync.enabled", "true"));
        // 解析各项...
    }
}
```

---

## 九、文件清单

### 新增文件

| 文件 | 说明 |
|------|------|
| `domain/entity/es/ContentSearchDocument.java` | ES 文档 POJO |
| `domain/request/es/ContentSearchRequest.java` | 搜索请求 DTO |
| `domain/response/es/ContentSearchResponse.java` | 搜索响应 DTO |
| `domain/response/es/ContentSearchHit.java` | 搜索命中 DTO |
| `service/es/ContentSearchIndexService.java` | 写入服务接口 |
| `service/es/impl/ContentSearchIndexServiceImpl.java` | 写入服务实现 |
| `service/es/ContentSearchService.java` | 查询服务接口 |
| `service/es/impl/ContentSearchServiceImpl.java` | 查询服务实现 |
| `service/es/ContentSearchDocAssembler.java` | 文档组装接口 |
| `service/es/impl/ContentSearchDocAssemblerImpl.java` | 文档组装实现 |
| `task/EsRepairTask.java` | 不完整文档修复任务（QSchedule） |
| `task/EsReconcileTask.java` | 全量对账任务（QSchedule） |
| `task/EsFullRebuildTask.java` | 全量重建（手动触发） |
| `infra/qconfig/IndexQConfig.java` | ES 索引动态配置 |

### 修改文件

| 文件 | 改动 |
|------|------|
| `infra/elasticsearch/ElasticsearchDataSource.java` | 新增 update、bulkUpdate、search 方法 |
| `service/raw/impl/RawContentSyncServiceImpl.java` | sync() 成功后调用 ES 索引 |
| `controller/RawContentController.java` 或新建 | 搜索 API 入口 |

---

## 十、搜索 API（Controller）

```
GET /api/content/search

参数（与 ContentSearchRequest 对应）：
  keyword=酒店
  contentTypes=图文,短视频
  businessLine=hotel
  publishTimeStart=2026-01-01
  sortField=total_impressions
  sortOrder=desc
  from=0
  size=20

响应：
  {
    "code": 0,
    "message": "success",
    "data": {
      "hits": [...],
      "total": 1280,
      "took": 15
    }
  }
```

---

## 十一、与 raw-content-sync 的集成时序

### 11.1 现有代码结构

```java
// RawContentServiceImpl.triggerSync(int limit) ← 无 @Transactional
for (RawContentInfo raw : records) {
    syncDb(data);       // @Transactional MySQL 写入
    doPostSync(data);   // OSS 转存（图文转存图片，短视频转存视频）
    updateSyncStatus(data.getContentId(), SyncStatus.SYNCED);
}
```

```java
// RawContentSyncServiceImpl.sync(RawContentInfo raw)
@Transactional(rollbackFor = Exception.class)
void sync(RawContentInfo raw) {
    ContentBase existing = contentBaseMapper.selectByContentId(raw.getContentId());
    if (existing != null) {
        // 二次同步：只更新指标 + 标签
        buildLabel(raw, existing.getId());
        buildMetrics(raw, existing.getId());
        return;
    }
    // 首次同步：6 表全写...
}
```

### 11.2 集成方案

**ES 写入的钩入点：** `triggerSync()` 中 `syncDb()` 和 `doPostSync()` 之后，`updateSyncStatus()` 之前。这个位置已脱离 `@Transactional` 范围，ES 失败不会回滚 MySQL。

```java
// RawContentServiceImpl.triggerSync(int limit) 改造后
for (RawContentInfo raw : records) {
    syncDb(data);                         // 1. MySQL（@Transactional）
    doPostSync(data);                     // 2. OSS 转存
    
    // 3. ES 索引（新增，开关控制）
    if (indexQConfig.isSyncEnabled()) {
        try {
            ContentBase base = contentBaseMapper.selectByContentId(raw.getContentId());
            if (base != null) {
                ContentSearchDocument doc = docAssembler.assembleByContentId(base.getContentId());
                if (doc != null) {
                    contentSearchIndexService.indexDocument(doc);
                }
            }
        } catch (Exception e) {
            log.error("ES sync failed for contentId: {}", raw.getContentId(), e);
            // 不抛异常，不阻断主流程
        }
    }
    
    updateSyncStatus(data.getContentId(), SyncStatus.SYNCED);
}
```

**为什么在 triggerSync 中做而不是 sync 内部：**

1. `sync()` 有 `@Transactional`，ES 调用放在里面会导致 ES 失败触发事务回滚（即使 catch 了，Spring 的 `@Transactional` 默认对 `Exception` 回滚，放在外层更安全）
2. `triggerSync` 已有 `syncDb` / `doPostSync` 的分离职责模式，ES 写入作为第三步自然对齐

### 11.3 分段说明

| 步骤 | 方法 | 事务 | 失败影响 |
|------|------|------|---------|
| 1. MySQL 写入 | `syncDb()` → `sync()` | `@Transactional` | 全部回滚 |
| 2. OSS 转存 | `doPostSync()` | 无事务 | 下次重试 |
| 3. ES 索引 | `contentSearchIndexService.indexDocument()` | 无事务 | 修复任务兜底 |
| 4. 状态更新 | `updateSyncStatus()` | 无事务 | 下次重试 |

### 11.4 时序图

```
[数仓宽表] → RawContentSyncTask
    │
    ▼
RawContentServiceImpl.triggerSync(raw)
    │
    ├── 1. syncDb(raw)                       ← @Transactional
    │       └── RawContentSyncService.sync(raw)
    │               ├── content_base (INSERT / ON DUPLICATE KEY UPDATE)
    │               ├── content_text (INSERT, 孤儿策略)
    │               ├── content_image/video (INSERT, 按 contentType 分流)
    │               ├── content_metrics (INSERT / ON DUPLICATE KEY UPDATE)
    │               └── content_label (INSERT / ON DUPLICATE KEY UPDATE)
    │
    ├── 2. doPostSync(raw)                   ← OSS 转存
    │
    ├── 3. [es.sync.enabled=true]            ← 开关检查
    │       └── ContentSearchIndexService.indexDocument(doc)
    │               ├── docAssembler.assembleByContentId(contentId)
    │               │       └── MySQL 6 表 LEFT JOIN → ContentSearchDocument
    │               └── ElasticsearchDataSource.update(
    │                       "content_search_alias",
    │                       doc.baseId.toString(),
    │                       doc)            ← UpdateRequest + upsert
    │
    └── 4. updateSyncStatus(SYNCED)
```

二次同步（仅指标更新）：

```
[数仓宽表] → RawContentSyncTask
    │
    ▼
RawContentServiceImpl.triggerSync(raw)
    │
    ├── 1. syncDb(raw): content_metrics ON DUPLICATE KEY UPDATE  ← MySQL
    │
    ├── 2. [es.sync.enabled=true]
    │       └── ContentSearchIndexService.batchUpdateDocuments(docs)
    │               ├── docAssembler.assembleByBaseIds(baseIds)  ← 批量 6 表 JOIN
    │               └── ElasticsearchDataSource.bulkUpdate(
    │                       "content_search_alias",
    │                       updateRequests)                     ← Bulk UpdateRequest + upsert
    │
    └── 3. updateSyncStatus(SYNCED)
```

---

## 十二、边界情况处理

| 场景              | 处理                                                           |
| --------------- | ------------------------------------------------------------ |
| ES 索引不存在        | 启动时自动创建，search/update 时若抛出 `IndexNotFoundException` 则触发创建后重试 |
| 指标全为零           | 正常写入 ES，0 是合法值                                               |
| AI 标签为空数组       | ES 中 `ai_tag` 为 `[]`，term 查询不会命中                             |
| 全量重建期间写入        | 双写策略：同时写旧索引和新索引，切换别名后停写旧索引                                   |
| 并发索引同一条         | UpdateRequest 的 upsert 幂等，last write wins                    |

---

## 十三、监控指标

| 指标名 | 类型 | 说明 |
|--------|------|------|
| `es_index_document` | 耗时 | 单条索引耗时 |
| `es_index_document_error` | 计数 | 单条索引失败 |
| `es_bulk_update` | 耗时 | 批量更新耗时 |
| `es_bulk_update_error` | 计数 | 批量更新失败 |
| `es_search` | 耗时 | 搜索耗时 |
| `es_search_error` | 计数 | 搜索失败 |
| `es_repair_count` | 计数 | 修复任务修复条数 |
| `es_reconcile_missing_count` | 计数 | 对账发现缺失条数 |