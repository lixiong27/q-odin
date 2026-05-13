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
| content_title | text(ik_max_word) + keyword raw | 冗余自 `content_base` |
| content_text | text(ik_max_word) | 冗余自 `content_text` |
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
    private String contentTitle;
    private String publishPlatform;
    private String publishTime;       // yyyy-MM-dd HH:mm:ss
    private String publishUrl;
    private String businessLine;
    private String contentSource;
    private String productionTeam;
    private String operationProject;
    private String placementPosition;
    private String contentText;
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

**注意：** 长文本字段 `content_text`（LONGTEXT）全部写入 ES，ES 的 text 类型默认 `ignore_above` 不限。Gson 序列化 String 没有问题。

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

---

## 四、搜索查询

### 4.1 功能列表

| 功能 | 说明 |
|------|------|
| 关键词全文检索 | content_title + content_text，ik_max_word 分词 |
| 精确过滤 | content_type(多选)、publish_platform(多选)、business_line、content_source |
| 标签过滤 | city、poi、ai_tag |
| 时间范围 | publish_time 起止 |
| 指标排序 | 按 total_impressions、total_clicks 等降序/升序 |
| 分页 | from + size |
| 高亮 | 标题/正文命中关键词高亮 |

### 4.2 请求/响应模型

```java
public class ContentSearchRequest {
    private String keyword;              // 全文检索关键词
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
    private String contentTitle;
    private String publishPlatform;
    private String publishTime;
    private String businessLine;
    private String contentSource;
    private String productionTeam;
    private String operationProject;
    private String contentText;          // 仅返回摘要片段
    private String titleHighlight;       // 高亮标题
    private String textHighlight;        // 高亮正文片段
    // ... 指标字段（可选返回）
}
```

### 4.3 查询 DSL（伪代码）

```
SearchSourceBuilder search = new SearchSourceBuilder();

// 关键词全文检索
if (keyword is not blank):
    BoolQueryBuilder keywordQuery = bool()
        .should(matchQuery("content_title", keyword).boost(2.0))
        .should(matchQuery("content_text", keyword))
        .minimumShouldMatch(1)
    search.query(keywordQuery)

// 过滤
BoolQueryBuilder filter = bool()
if contentTypes is not empty: filter.filter(terms("content_type", contentTypes))
if platforms is not empty: filter.filter(terms("publish_platform", platforms))
if businessLine is not blank: filter.filter(term("business_line", businessLine))
if cities is not empty: filter.filter(terms("city", cities))
if aiTags is not empty: filter.filter(terms("ai_tag", aiTags))
if publishTimeStart is not blank: filter.filter(range("publish_time").gte(publishTimeStart))
if publishTimeEnd is not blank: filter.filter(range("publish_time").lte(publishTimeEnd))

search.postFilter(filter)

// 排序
if sortField is not blank:
    search.sort(sortField, sortOrder)
else:
    search.sort("publish_time", "desc")   // 默认按发布时间倒序

// 分页
search.from(from).size(size)

// 高亮
if keyword is not blank:
    search.highlighter(
        HighlightBuilder()
            .field("content_title")
            .field("content_text", 200)   // 片段长度 200
            .preTags("<em>").postTags("</em>")
    )
```

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
    cb.content_title,
    cb.publish_platform,
    cb.publish_time,
    cb.publish_url,
    cb.business_line,
    cb.content_source,
    cb.production_team,
    cb.operation_project,
    cb.placement_position,
    ct.content_text,
    cl.city,
    cl.poi,
    cl.ai_tag,
    cm.total_impressions,
    cm.total_clicks,
    -- ... 其余指标
FROM content_base cb
LEFT JOIN content_text ct ON ct.id = JSON_EXTRACT(cb.content_relations, '$.text_ids[0]')
LEFT JOIN content_label cl ON cl.base_id = cb.id
LEFT JOIN content_metrics cm ON cm.base_id = cb.id
WHERE cb.content_id = #{contentId}   -- 或 cb.id IN (ids)
```

注意：`content_relations` 中的 `text_ids` 是 JSON 数组，取第一个元素。`content_text` 是写后只读的（孤儿策略），取第一个即可。image/video 数据不入 ES（ES 只存文本+指标+标签）。

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

---

## 八、动态配置（QConfig）

### 8.1 配置项

```properties
# es-index.properties
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

    private volatile int shards = 3;
    private volatile int replicas = 1;
    private volatile String refreshInterval = "5s";
    private volatile int batchSize = 500;
    private volatile boolean repairEnabled = true;
    private volatile int repairIntervalMinutes = 30;

    @QConfig("es-index.properties")
    private void onChanged(Map<String, String> map) {
        if (map == null) return;
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

```
[数仓宽表] → RawContentSyncTask
    │
    ▼
RawContentServiceImpl.triggerSync(raw)
    │
    ├── RawContentSyncService.sync(raw)     ← @Transactional MySQL 写入
    │       ├── content_base (INSERT)
    │       ├── content_text (INSERT)
    │       ├── content_image/video (INSERT)
    │       ├── content_metrics (INSERT)
    │       └── content_label (INSERT)
    │
    └── ContentSearchIndexService.index(doc)  ← ES 写入，失败不影响 MySQL
            └── ElasticsearchDataSource.update(index, id, doc) ← UpdateRequest + upsert
```

二次同步（仅指标更新）：

```
[数仓宽表] → RawContentSyncTask
    │
    ▼
RawContentServiceImpl.triggerSync(raw)
    │
    ├── RawContentSyncService.sync(raw)     ← MySQL 仅更新 content_metrics
    │
    └── ContentSearchIndexService.update(doc) ← ES 批量更新指标
```

---

## 十二、边界情况处理

| 场景 | 处理 |
|------|------|
| ES 索引不存在 | 启动时自动创建，search/update 时若抛出 `IndexNotFoundException` 则触发创建后重试 |
| content_text 为空 | ES 文档中 `content_text` 为 null，text 字段允许 null |
| 指标全为零 | 正常写入 ES，0 是合法值 |
| AI 标签为空数组 | ES 中 `ai_tag` 为 `[]`，term 查询不会命中 |
| 全量重建期间写入 | 双写策略：同时写旧索引和新索引，切换别名后停写旧索引 |
| 并发索引同一条 | UpdateRequest 的 upsert 幂等，last write wins |

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