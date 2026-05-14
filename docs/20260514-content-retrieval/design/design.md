# 内容检索模块 — 设计文档

> 在 ES 索引加速层（已实现）之上，构建统一内容检索路由模块。
> 集成前置校验、用户行为埋点、路由决策、数据聚合、安全过滤、自定义列等能力。
> 大量复用已有基础设施（ContentSearchService、DocAssembler、DTO 类），新增部分仅为路由编排层。

---

## 一、总体架构

### 1.1 位置关系

```
Client (前端)
  │ POST /api/content/retrieve
  ▼
┌──────────────────┐          ┌──────────────────────────────────────────┐
│  前端页面         │          │       retrieve 包（新增）                 │
└──────────────────┘          │                                          │
                              │  ┌─ ValidationFilter (Servlet Filter)    │
                              │  │   参数校验 + 权限 + 限流(TODO)        │
                              │  └──┬───────────────────────────────────-┤
                              │     │ 请求通过                          │
                              │     ▼                                   │
                              │  ┌────────────────────────────────────┐  │
                              │  │ RetrieveController                 │  │
                              │  │  POST /api/content/retrieve        │  │
                              │  │  POST /track-columns               │  │
                              │  └──────┬───────────────────────────-─┘  │
                              │         │ 委托                          │
                              │         ▼                               │
                              │  ┌────────────────────────────────────┐  │
                              │  │ SearchOrchestrator (编排核心)       │  │
                              │  │  track→route→aggregate→            │  │
                              │  │  security→response                 │  │
                              │  └──┬─────┬──────┬───────┬──────────-─┘  │
                              │     │     │      │       │              │
                              │     ▼     ▼      ▼       ▼              │
                              │  ┌───┐ ┌───┐ ┌────┐ ┌────────┐         │
                              │  │ T │ │ R │ │ A  │ │ S      │         │
                              │  │ r │ │ o │ │ g  │ │ e      │         │
                              │  │ a │ │ u │ │ g  │ │ c      │         │
                              │  │ c │ │ t │ │ r  │ │ u      │         │
                              │  │ k │ │ e │ │ e  │ │ r      │         │
                              │  │   │ │ r │ │ g  │ │ i      │         │
                              │  │ S │ │   │ │ a  │ │ t      │         │
                              │  │ e │ │ M │ │ t  │ │ y      │         │
                              │  │ r │ │ y │ │ o  │ │ F      │         │
                              │  │ v │ │ S │ │ r  │ │ i      │         │
                              │  │   │ │ Q │ │    │ │ l      │         │
                              │  │   │ │ L │ │ R  │ │ t      │         │
                              │  │   │ │ \ │ │ e  │ │ e      │         │
                              │  │   │ │ E │ │ s  │ │ r      │         │
                              │  │   │ │ S │ │ p  │ │        │         │
                              │  └───┘ └───┘ └────┘ └────────┘         │
                              │                                          │
                              │  ┌─ ContentTrackService (异步埋点)       │
                              │  │   线程池: core=2, max=4, queue=1k    │
                              └──────────────────────────────────────────┘
```

### 1.2 与已有模块的关系

| 已有模块（已实现） | 本模块的使用方式 |
|-------------------|----------------|
| `ContentSearchService` | **复用**，在其基础上包一层只提取 base_id |
| `ContentSearchDocAssembler` | **复用**，DataAggregator 调用其批量查询能力 |
| `ContentSearchDocument` | **复用**，直接作为聚合后的全量数据载体 |
| `ContentSearchRequest` | **复用/扩展**，新增路由相关参数 |
| `ContentSearchResponse` / `ContentSearchHit` | **复用/扩展**，Response 新增 `fieldMeta` 字段 |
| `ContentSearchController` | **不修改**，新建 `RetrieveController` 作为检索入口 |
| `ElasticsearchDataSource` | **不直接使用**，通过 ContentSearchService 间接调用 |

### 1.3 分层职责

| 层级 | 职责 | 失败影响 |
|------|------|---------|
| 1. ValidationLayer | 参数合法性校验、权限校验、限流 | 拒绝请求，返回错误码 |
| 2. InterceptLayer | 异步记录用户搜索/浏览/下载/排序/自定义列行为 | 不影响主流程，埋点失败只记日志 |
| 3. SearchRouter | 分析检索条件复杂度，决定 MySQL 还是 ES | 路由错误导致查询结果不正确 |
| 4. DataAggregator | 调用已有 DocAssembler 批量组装全量字段 | 聚合失败返回空数据 |
| 5. SecurityFilter | 替换返回数据中的图片/视频 URL 为内网前缀 | 返回外网 URL，产生 CDN 费用 |
| 6. ResponseAssembler | 组装最终响应，生成 fieldMeta 标记默认展示字段 | 前端展示异常 |

### 1.4 数据流转

```
请求 → ValidationFilter → RetrieveController → SearchOrchestrator(异步埋点 → Router)
       → MySQLSearch(select id from content_base)
         或 ESSearch(复用 ContentSearchService → 提取 base_id)
       → DataAggregator(复用 DocAssembler → 全量 Document)
       → SecurityFilter(URL 替换)
       → ResponseAssembler(含 fieldMeta)
       → 响应
```

Router 层返回 **base_id 列表 + 分页信息**，Aggregator 层在此基础上复用已有 DocAssembler 组装**全量业务字段**，两层完全解耦。


## 二、SearchRouter 路由决策

### 2.1 核心逻辑

```
SearchRouterService.route(SearchRequest):
    │
    ├─ 1. 分析检索条件中的字段归属
    │
    ├─ 2. 如果仅涉及 content_base 字段 → MySQLSearchService
    │      SELECT id FROM content_base WHERE ... ORDER BY id DESC LIMIT ?, ?
    │      ← 只返回 base_id，不涉及任何 JOIN
    │
    └─ 3. 如果涉及以下任一字段 → ESSearchService（复用已有 ContentSearchService）
            ├─ content_label: city / poi / ai_tag
            ├─ content_metrics: 全部指标字段（触发排序）
            └─ publish_time 范围查询
           Search content_search index → 从 hits 提取 base_id

    4. 统一返回: SearchRouteResult(baseIds, total)
```

### 2.2 字段归属判断规则

```
SearchRequest 中的字段 → 归属判定：

contentTypes      → content_base
platforms         → content_base
businessLine      → content_base
contentSource     → content_base
productionTeam    → content_base
operationProject  → content_base
placementPosition → content_base
publishTimeStart  → content_base.publish_time → 触发 ES
publishTimeEnd    → content_base.publish_time → 触发 ES
cities            → content_label            → 触发 ES
poi               → content_label            → 触发 ES
aiTags            → content_label            → 触发 ES
sortField         → 指标字段                  → 触发 ES
```

**路由原则：** 一旦任一条件触发 ES 路由，全部条件走 ES，不拆分为部分走 MySQL 部分走 ES。

### 2.3 路由优先级矩阵

| 检索条件组合 | 路由 | 原因 |
|-------------|------|------|
| 仅 content_type + platform | MySQL | 全部命中 content_base |
| 任意条件 + city/poi/aiTag | **ES** | label 表，MySQL 无法简单过滤 |
| 任意条件 + sortField 为指标 | **ES** | 指标排序依赖 ES 索引 |
| 任意条件 + publishTime 范围 | **ES** | publish_time 范围查询统一走 ES |
| publishTime 范围（唯一条件） | **ES** | publish_time 不走 MySQL，强制 ES 路由 |

---

## 三、MySQLSearchService

### 3.1 查询模式

仅从 `content_base` 单表过滤，返回 `base_id` 列表，**不 JOIN 其他表**。

```sql
SELECT cb.id
FROM content_base cb
<where>
    <if test="contentTypes != null and contentTypes.size > 0">
        AND cb.content_type IN
        <foreach collection="contentTypes" item="t" open="(" separator="," close=")">#{t}</foreach>
    </if>
    <if test="platforms != null and platforms.size > 0">
        AND cb.publish_platform IN
        <foreach collection="platforms" item="p" open="(" separator="," close=")">#{p}</foreach>
    </if>
    <if test="businessLine != null and businessLine != ''">
        AND cb.business_line = #{businessLine}
    </if>
    <if test="contentSource != null and contentSource != ''">
        AND cb.content_source = #{contentSource}
    </if>
</where>
ORDER BY cb.id DESC        ← 固定按主键倒序，不支持自定义排序
                           ← 自定义排序只针对数据指标字段，涉及指标排序走 ES
LIMIT #{offset}, #{size}
```

**关于排序：** MySQL 路由不支持自定义排序字段，固定按 `cb.id DESC`。自定义排序仅适用于数据指标字段（CPM、CTR、CVR 等），这些字段属于 `content_metrics` 表，只要涉及指标排序就走 ES。MySQL 路由仅适用于简单条件过滤场景。

> **TODO：** `total_downloads`（下载次数）字段需补充到 `content_metrics` 表 schema 和 ES 索引 mapping 中，确认后加入排序白名单。

### 3.2 分页策略

```sql
-- 总数查询
SELECT COUNT(*) FROM content_base <where> ... </where>

-- 列表查询
SELECT cb.id FROM content_base <where> ... ORDER BY cb.id DESC LIMIT #{offset}, #{size}
```

---

## 四、ESSearchService

### 4.1 查询模式

**不复用已存在的 Controller/Response 格式，换成复用已有 ContentSearchService 的查询能力**，从搜索结果中提取 base_id。

```java
// 复用已有 ContentSearchService 构建查询
SearchSourceBuilder builder = new SearchSourceBuilder();
BoolQueryBuilder boolQuery = QueryBuilders.boolQuery();

// content_base 字段 — 使用 filter() 而非 must()，跳过评分计算
if (notEmpty(contentTypes))
    boolQuery.filter(termsQuery("content_type", contentTypes));
if (notEmpty(platforms))
    boolQuery.filter(termsQuery("publish_platform", platforms));
// ... 其余基础字段过滤

// content_label 字段（触发走 ES 的核心原因）
if (notEmpty(cities))
    boolQuery.filter(termsQuery("city", cities));
if (notEmpty(aiTags))
    boolQuery.filter(termsQuery("ai_tag", aiTags));

// 指标排序（触发走 ES 的核心原因）
if (notBlank(sortField)) {
    validateSortField(sortField);  // 白名单校验
    builder.sort(sortField, sortOrder);
} else {
    builder.sort("publish_time", SortOrder.DESC);
}

// 分页
builder.from(from).size(size);
builder.query(boolQuery);
builder.fetchSource(false);  // 只需要 _id，不返回 _source，减少网络开销
```

> **优化点：** 使用 `filter()` 而非 `must()`。现有实现 `ContentSearchServiceImpl:144` 使用了 `must()`，但内容检索不需要相关性评分。`filter` 不评分、可利用 ES 查询结果缓存，性能更好。

### 4.2 ES 查询结果解析

```java
SearchResponse response = elasticsearchDataSource.search("content_search_alias", builder);
List<Long> baseIds = Arrays.stream(response.getHits().getHits())
    .map(hit -> Long.parseLong(hit.getId()))    // _id = base_id
    .collect(Collectors.toList());
long total = response.getHits().getTotalHits().value;

return new SearchRouteResult(baseIds, total);
```

对比 MySQLSearchService，两者输出一致：`(List<Long> baseIds, long total)`。

### 4.3 分页一致性

| 引擎 | 分页方式 | 注意事项 |
|------|---------|---------|
| MySQL | `LIMIT offset, size` | offset 越大越慢，但仅简单场景走 MySQL |
| ES | `from + size` | ES `max_result_window` 默认 10000，前端分页不超过此限制 |

---

## 五、DataAggregator 数据聚合

### 5.1 聚合流程

```
SearchRouter 返回 (baseIds, total) → DataAggregator.aggregate(baseIds):
    │
    ├─ 复用已有 ContentSearchDocAssembler.assembleByBaseIds(baseIds)
    │   ↓
    │   内部：6 表 LEFT JOIN → List<ContentSearchDocument>
    │
    └─ 返回 List<ContentSearchDocument>（全量字段）
```

**不复写 SQL，不重复造轮子。** DataAggregator 直接调用已有 DocAssembler 的批量查询方法。

> **注意：** 当前 `EsDoc_Column_List`（ContentBaseMapper.xml:72）和 `EsDocResultMap`（ContentBaseMapper.xml:110）缺少 `cb.content_title` 和 `cb.publish_url` 两列。使用前需先在 Mapper XML 中追加这两列和对应映射，否则 DataAggregator 返回的数据没有标题和链接。详见第十四章（深潜差距）。

### 5.2 assembleByBaseIds 已有实现

查询 SQL（已有，在 DocAssemblerImpl 中）：

```sql
SELECT cb.id AS base_id, cb.content_id, cb.content_type, cb.content_title,
       cb.publish_platform, cb.publish_time, cb.publish_url,
       cb.business_line, cb.content_source, cb.production_team,
       cb.operation_project, cb.placement_position,
       cl.city, cl.poi, cl.ai_tag,
       cm.total_impressions, cm.total_clicks, cm.total_reads,
       cm.total_interactions, cm.completion_rate,
       cm.three_sec_completion_rate, cm.five_sec_completion_rate,
       cm.two_sec_bounce_rate, cm.cpm, cm.ctr, cm.cvr,
       cm.app_downloads, cm.new_activations, cm.new_registrations,
       cm.drive_uv, cm.exposure_to_read_ratio, cm.potential_new_uv,
       cm.potential_new_cac, cm.attributed_new_customers,
       cm.new_customer_cac, cm.order_uv, cm.total_orders
FROM content_base cb
LEFT JOIN content_label cl ON cl.base_id = cb.id
LEFT JOIN content_metrics cm ON cm.base_id = cb.id
<where>
    <if test="baseIds != null and baseIds.size() > 0">
        AND cb.id IN
        <foreach collection="baseIds" item="id" open="(" separator="," close=")">#{id}</foreach>
    </if>
</where>
```

### 5.3 DataAggregator 实现

```java
@Service
public class ContentDataAggregator {

    @Resource
    private ContentSearchDocAssembler docAssembler;

    /**
     * 根据 baseIds 组装全量 ContentSearchDocument 列表
     * 复用已有 DocAssembler，不做额外逻辑
     */
    public List<ContentSearchDocument> aggregate(List<Long> baseIds) {
        if (CollectionUtils.isEmpty(baseIds)) {
            return Collections.emptyList();
        }
        return docAssembler.assembleByBaseIds(baseIds);
    }
}
```

### 5.4 边界处理

| 场景 | 处理 |
|------|------|
| baseIds 为空 | 直接返回空列表，不查数据库 |
| DocAssembler 返回 null | 返回空列表 |
| aggregate 中部分 base_id 无 label/metrics 数据 | DocAssembler 已有默认值处理（LEFT JOIN 特性） |

---

## 六、SecurityFilter 安全过滤

### 6.1 背景

返回数据中的 `publish_url`（图片/视频链接）指向外网 CDN，直接返回会产生额外 CDN 费用。需要在返回前端前替换为内网代理前缀。

### 6.2 替换规则

通过 QConfig 配置 URL 前缀映射规则，支持多前缀匹配：

```properties
# security-url-filter.properties
# 外网前缀=内网前缀
cdn.example.com=internal-cdn.example.com
img.example.com=internal-img.example.com
```

### 6.3 实现

```java
@Component
public class ContentSecurityFilter {

    @Resource
    private SecurityUrlFilterConfig urlFilterConfig;  // QConfig 配置类

    /**
     * 扫描 ContentSearchDocument 中的 URL 字段，替换前缀
     */
    public void filter(List<ContentSearchDocument> documents) {
        if (CollectionUtils.isEmpty(documents) || urlFilterConfig.isEmpty()) {
            return;
        }
        for (ContentSearchDocument doc : documents) {
            String url = doc.getPublishUrl();
            if (StringUtils.isNotBlank(url)) {
                doc.setPublishUrl(replaceUrlPrefix(url));
            }
        }
    }

    private String replaceUrlPrefix(String url) {
        for (Map.Entry<String, String> entry : urlFilterConfig.getMappings().entrySet()) {
            if (url.contains(entry.getKey())) {
                return url.replace(entry.getKey(), entry.getValue());
            }
        }
        return url;
    }
}
```

### 6.4 边界处理

| 场景 | 处理 |
|------|------|
| publish_url 为空 | 跳过，不处理 |
| URL 不匹配任何配置前缀 | 保持原值返回 |
| QConfig 配置为空 | 跳过全部替换逻辑 |
| 多个前缀命中 | 按配置顺序，第一个匹配生效 |

> **QConfig 配置变更实时生效**，无需重启服务。

---

## 七、InterceptLayer 异步埋点

### 7.1 埋点事件列表

| 事件 | 触发时机 | 记录内容 |
|------|---------|---------|
| `content_search` | 用户点击搜索/触发检索 | 检索条件 + 命中数量 |
| `content_browse` | 用户浏览内容详情 | 内容 ID + 内容类型 |
| `content_download` | 用户下载内容 | 内容 ID + 内容类型 |
| `content_sort` | 用户切换排序字段 | 排序字段 + 排序方向 |
| `content_column_customize` | 用户确认自定义列变更 | 启用的列字段列表 |

### 7.2 自定义列埋点接口

自定义列配置存前端本地，**不调后端接口保存配置**。但需要在用户确认变更后触发一次埋点上报，用于分析用户关注哪些字段。

```
POST /api/content/retrieve/track-columns
  Body: { "fields": ["contentTitle", "ctr", "cvr"] }
  响应: { "code": 0, "msg": "success" }
```

**接口语义：** 后端收到后触发异步埋点 `content_column_customize`，直接返回成功，不做任何持久化。埋点数据用于分析字段关注度，指导 `fieldMeta.default` 调整。

**Controller 示例：**

```java
@PostMapping("/api/content/retrieve/track-columns")
public BaseResponse<Void> trackColumns(@RequestBody TrackColumnsRequest request) {
    contentTrackService.trackColumnCustomize(request.getFields());
    return BaseResponse.success();
}
```

### 7.3 实现

使用 `CompletableFuture.runAsync()` + 独立线程池，埋点逻辑与主流程完全异步解耦。

```java
@Component
public class ContentTrackService {

    /** 独立线程池：核心 2 线程，最大 4 线程，队列 1000 */
    private static final ExecutorService TRACK_POOL = new ThreadPoolExecutor(
            2, 4, 60, TimeUnit.SECONDS,
            new LinkedBlockingQueue<>(1000),
            new ThreadFactoryBuilder().setNameFormat("track-pool-%d").build(),
            new ThreadPoolExecutor.CallerRunsPolicy()
    );

    /**
     * 异步记录用户检索行为
     */
    public void trackSearch(ContentSearchRequest request, long hitCount) {
        CompletableFuture.runAsync(() -> {
            try {
                TrackEvent event = new TrackEvent()
                        .setEventType(TrackEventType.SEARCH)
                        .setUserId(RequestContext.getUserId())
                        .setDetail(buildSearchDetail(request, hitCount));
                doTrack(event);
            } catch (Exception e) {
                log.warn("Track search event failed", e);
            }
        }, TRACK_POOL);
    }

    /**
     * 异步记录内容浏览行为
     */
    public void trackBrowse(Long baseId, String contentType) {
        CompletableFuture.runAsync(() -> {
            try {
                TrackEvent event = new TrackEvent()
                        .setEventType(TrackEventType.BROWSE)
                        .setUserId(RequestContext.getUserId())
                        .setDetail(buildDetail(baseId, contentType));
                doTrack(event);
            } catch (Exception e) {
                log.warn("Track browse event failed", e);
            }
        }, TRACK_POOL);
    }

    /**
     * 异步记录内容下载行为
     */
    public void trackDownload(Long baseId, String contentType) {
        CompletableFuture.runAsync(() -> {
            try {
                TrackEvent event = new TrackEvent()
                        .setEventType(TrackEventType.DOWNLOAD)
                        .setUserId(RequestContext.getUserId())
                        .setDetail(buildDetail(baseId, contentType));
                doTrack(event);
            } catch (Exception e) {
                log.warn("Track download event failed", e);
            }
        }, TRACK_POOL);
    }

    /**
     * 异步记录排序行为
     */
    public void trackSort(String sortField, String sortOrder) {
        CompletableFuture.runAsync(() -> {
            try {
                TrackEvent event = new TrackEvent()
                        .setEventType(TrackEventType.SORT)
                        .setUserId(RequestContext.getUserId())
                        .setDetail(JsonUtils.toJson(Map.of("sortField", sortField, "sortOrder", sortOrder)));
                doTrack(event);
            } catch (Exception e) {
                log.warn("Track sort event failed", e);
            }
        }, TRACK_POOL);
    }

    /**
     * 异步记录自定义列行为
     */
    public void trackColumnCustomize(List<String> fields) {
        CompletableFuture.runAsync(() -> {
            try {
                TrackEvent event = new TrackEvent()
                        .setEventType(TrackEventType.COLUMN_CUSTOMIZE)
                        .setUserId(RequestContext.getUserId())
                        .setDetail(JsonUtils.toJson(fields));
                doTrack(event);
            } catch (Exception e) {
                log.warn("Track column customize event failed", e);
            }
        }, TRACK_POOL);
    }

    private void doTrack(TrackEvent event) {
        QMonitor.recordOne("track_" + event.getEventType().name().toLowerCase());
        log.info("TrackEvent: {}", JsonUtils.toJson(event));
    }
}
```

### 7.4 失败影响

**零容忍。** 埋点失败只记日志，不抛出异常，不阻塞请求。所有埋点代码在最外层包 `try-catch`。

---

## 八、ValidationLayer 前置校验

### 8.1 校验项

| 校验项   | 校验逻辑                    | 失败处理        |
| ----- | ----------------------- | ----------- |
| 参数合法性 | pageSize 上限、时间格式、枚举值合法性 | 400 + 错误提示  |
| 权限校验  | 用户是否有内容检索权限             | 403 + 无权限提示 |
| 限流    | TODO                     | TODO        |

### 8.2 实现（部分 TODO）

Spring Filter 或 Interceptor 实现，在请求进入 Controller 前完成校验：

```java
@Component
public class ContentRetrieveValidationFilter implements Filter {

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain) {
        HttpServletRequest httpRequest = (HttpServletRequest) request;

        // 1. 权限校验
        String userId = httpRequest.getHeader("X-User-Id");
        if (!checkPermission(userId)) {
            writeErrorResponse(response, 403, "无内容检索权限");
            return;
        }

        chain.doFilter(request, response);
    }
}
```

> **TODO：** 限流逻辑待实现。后续可按用户/接口粒度增加 QPS 限流，拒绝超限请求并返回 429。

### 8.3 参数校验

请求体中的参数校验在 Controller 层通过 Spring `@Valid` 或手动校验完成：

```java
@PostMapping("/api/content/retrieve")
public BaseResponse<ContentSearchResponse> search(@RequestBody @Valid ContentSearchRequest request) {
    // pageSize 最大 100
    if (request.getPageSize() > 100) {
        return BaseResponse.error(400, "pageSize 不能超过 100");
    }
    // ...
}
```

### 8.4 限流策略（TODO）

> **TODO：** 限流逻辑待实现，后续按需补充。

---

## 九、ResponseAssembler 响应组装

### 9.1 响应结构

```json
{
    "hits": [
        {
            "baseId": 1,
            "contentTitle": "标题",
            "contentType": "VIDEO",
            "publishTime": "2026-05-14 12:00:00",
            "totalImpressions": 10000,
            "totalClicks": 500,
            "ctr": 0.05
        }
    ],
    "total": 100,
    "fieldMeta": {
        "contentTitle":     {"name": "内容标题",   "default": true},
        "contentType":      {"name": "内容类型",   "default": true},
        "publishTime":      {"name": "发布时间",   "default": true},
        "publishPlatform":  {"name": "发布平台",   "default": true},
        "businessLine":     {"name": "业务线",     "default": false},
        "totalImpressions": {"name": "总曝光",     "default": false},
        "totalClicks":      {"name": "总点击",     "default": false},
        "ctr":              {"name": "点击率",     "default": false},
        "cvr":              {"name": "转化率",     "default": false}
    }
}
```

### 9.2 fieldMeta 机制

`fieldMeta` 由后端固定定义，不依赖前端传入。包含两部分信息：

- **default: true** — 前端默认展示的字段
- **default: false** — 前端可通过自定义列功能选择展示

前端自定义列操作通过单独接口保存用户偏好（存前端本地或后端用户配置），但每次搜索响应都携带完整 `fieldMeta`，前端根据 `default` 标记 + 用户自定义配置决定最终展示列。

### 9.3 实现

```java
@Component
public class ContentResponseAssembler {

    /** 全量字段元数据，固定定义 */
    private static final Map<String, FieldMeta> FIELD_META = new LinkedHashMap<>();

    static {
        FIELD_META.put("contentTitle",     new FieldMeta("内容标题", true));
        FIELD_META.put("contentType",      new FieldMeta("内容类型", true));
        FIELD_META.put("publishTime",      new FieldMeta("发布时间", true));
        FIELD_META.put("publishPlatform",  new FieldMeta("发布平台", true));
        FIELD_META.put("businessLine",     new FieldMeta("业务线", false));
        FIELD_META.put("totalImpressions", new FieldMeta("总曝光", false));
        FIELD_META.put("totalClicks",      new FieldMeta("总点击", false));
        FIELD_META.put("ctr",              new FieldMeta("点击率", false));
        // ... 其余字段
    }

    public ContentSearchResponse assemble(List<ContentSearchDocument> documents, long total) {
        ContentSearchResponse response = new ContentSearchResponse();
        response.setHits(convertToHits(documents));
        response.setTotal(total);
        response.setFieldMeta(FIELD_META);
        return response;
    }
}
```

### 9.4 前端自定义列交互

自定义列配置**由前端本地存储**（localStorage 或用户配置），后端不保存用户的列配置。因为：

1. 搜索接口每次返回**全量字段** + `fieldMeta`，前端已有所有数据
2. 前端根据 `fieldMeta.default` + 本地自定义配置决定展示哪些列
3. 不调后端接口，减少网络开销

**选择自定义列时只触发行为埋点上报：**

```
POST /api/content/retrieve/track-columns
  Body: { "fields": ["contentTitle", "ctr", "cvr"] }
  响应: { "code": 0, "msg": "success" }
```

前端在用户确认自定义列变更后，异步调用此接口，后端记录埋点后直接返回成功，不做任何持久化。埋点数据用于分析用户关注哪些字段，指导 `fieldMeta.default` 的调整。

---

## 十、编排层实现

### 10.1 SearchOrchestrator 独立编排服务

编排逻辑抽取为独立 Service 类，Controller 只做入口转发：

```java
@Service
public class ContentSearchOrchestrator {

    @Resource
    private SearchRouterService searchRouter;
    @Resource
    private ContentDataAggregator dataAggregator;
    @Resource
    private ContentSecurityFilter securityFilter;
    @Resource
    private ContentResponseAssembler responseAssembler;
    @Resource
    private ContentTrackService trackService;

    /**
     * 完整编排流程：路由 → 聚合 → 安全 → 响应组装
     */
    public ContentSearchResponse search(ContentSearchRequest request) {
        // 1. Async Track — 异步埋点（不阻塞主流程）
        trackService.trackSearch(request);

        // 2. Route — 路由决策
        SearchRouteResult routeResult = searchRouter.route(request);
        if (routeResult.isEmpty()) {
            return responseAssembler.emptyResponse();
        }

        // 3. Aggregate — 数据聚合（复用 DocAssembler）
        List<ContentSearchDocument> documents = dataAggregator.aggregate(routeResult.getBaseIds());

        // 4. Security — URL 安全过滤
        securityFilter.filter(documents);

        // 5. Response — 组装响应（含 fieldMeta）
        return responseAssembler.assemble(documents, routeResult.getTotal());
    }
}
```

### 10.2 RetrieveController 调用编排

```java
@PostMapping("/api/content/retrieve")
public BaseResponse<ContentSearchResponse> retrieve(@RequestBody @Valid ContentSearchRequest request) {
    // 1. 参数校验（Controller 层 @Valid + 手动校验）
    if (request.getPageSize() > 100) {
        return BaseResponse.error(400, "pageSize 不能超过 100");
    }

    // 2. 调用编排服务
    ContentSearchResponse response = searchOrchestrator.search(request);
    return BaseResponse.success(response);
}
```

### 10.3 与已有 Controller 的关系

新建 `RetrieveController` 作为检索入口，**不修改**已有的 `ContentSearchController`。二者共存：

| 端点 | 说明 | 是否修改 |
|------|------|---------|
| `POST /api/content/retrieve` | 新增入口，走完整编排流程 | 新增（`retrieve` 包） |
| `POST /api/content/search` | 原有搜索入口，保持不变 | 不修改 |
| `GET /api/content/filter` | 原有过滤入口，保持不变 | 不修改 |

---

## 十一、文件清单

### 11.1 新增文件

| 文件 | 所属层 | 说明 |
|------|--------|------|
| `service/retrieve/SearchRouterService.java` | Router | 路由决策接口 |
| `service/retrieve/impl/SearchRouterServiceImpl.java` | Router | 路由决策实现 |
| `service/retrieve/MySQLSearchService.java` | Router | MySQL 搜索接口 |
| `service/retrieve/impl/MySQLSearchServiceImpl.java` | Router | MySQL 搜索实现 |
| `service/retrieve/ESSearchService.java` | Router | ES 搜索接口 |
| `service/retrieve/impl/ESSearchServiceImpl.java` | Router | ES 搜索实现（复用 ContentSearchService） |
| `service/retrieve/SearchRouteResult.java` | Router | 路由结果 DTO（baseIds + total） |
| `service/retrieve/ContentDataAggregator.java` | Aggregator | 数据聚合器 |
| `service/retrieve/ContentSearchOrchestrator.java` | Orchestrator | 编排服务，串联路由→聚合→安全→响应 |
| `service/retrieve/ContentSecurityFilter.java` | Security | URL 安全过滤器 |
| `service/retrieve/ContentResponseAssembler.java` | Response | 响应组装器（含 fieldMeta） |
| `service/retrieve/config/SecurityUrlFilterConfig.java` | Config | QConfig URL 映射配置类 |
| `web/retrieve/ContentRetrieveValidationFilter.java` | Validation | 前置校验 Filter |
| `service/retrieve/ContentTrackService.java` | Track | 异步埋点服务（CompletableFuture + 独立线程池） |

### 11.2 修改文件

| 文件 | 变更 |
|------|------|
| `web/retrieve/RetrieveController.java` | 新增，检索入口 |
| `domain/response/es/ContentSearchResponse.java` | 新增 `fieldMeta` 字段 |
| `MyBatis Mapper (ContentBaseMapper + XML)` | 新增 MySQLSearch 所需的单表查询 |

---

## 十二、与已有代码的关系

### 12.1 集成策略：新增 retrieve 包，不修改既有代码

新建 `retrieve` 包，与已有 `ContentSearchController` 和其他组件**共存但不耦合**：

| 端点 | 已有实现 | 本模块 |
|------|---------|--------|
| `POST /api/content/search` | `ContentSearchController` — 不变 | 不修改 |
| `POST /api/content/retrieve` | 新增入口 | `RetrieveController` 走编排流程 |
| `POST /api/content/track-columns` | 新增埋点入口 | `RetrieveController` |
| `GET /api/content/filter` | `ContentSearchController.filter()` — 不变 | 不修改 |

### 12.2 复用方式

| 组件 | 复用方式 |
|------|---------|
| `ContentSearchService` | ESSearchService 内部复用，仅取 base_id |
| `ContentSearchDocAssembler` | DataAggregator 直接调用 |
| `ContentSearchDocument` / `ContentSearchHit` | 作为全量数据载体，新增 fieldMeta |
| `ElasticsearchDataSource` | 通过 ContentSearchService 间接使用 |

### 12.3 过渡兼容

保留原有的 `ContentSearchService.search()` 方法不变（其他调用方仍可使用），新建 `ESSearchService` 内部调用之。

---

## 十三、分层依赖关系

```
RetrieveController (web/retrieve/)
  │
  ├─→ ContentSearchValidationFilter (Servlet Filter, 前置)
  │
  └─→ SearchOrchestrator (service/retrieve/)
        ├─→ ContentTrackService (异步埋点，不阻塞)
        ├─→ SearchRouterService
        │     ├─→ MySQLSearchService       (ContentBaseMapper)
        │     └─→ ESSearchService          (ContentSearchService → ElasticsearchDataSource)
        ├─→ ContentDataAggregator          (ContentSearchDocAssembler → ContentBaseMapper)
        ├─→ ContentSecurityFilter          (SecurityUrlFilterConfig → QConfig)
        └─→ ContentResponseAssembler
```

**核心原则：** 新增层只依赖已有服务/组件，不产生循环依赖。Router → Service → Mapper 单向调用。

---

## 十四、代码深潜 — 设计文档与现有代码的差距

### 14.1 ContentSearchRequest 缺少 5 个字段

**当前代码**（`ContentSearchRequest.java`）只有 11 个字段：contentTypes、platforms、businessLine、cities、aiTags、publishTimeStart/End、sortField、sortOrder、from、size。

**设计需要额外 5 个**（MySQL 路由单表过滤必需）：

| 缺失字段 | MySQL 路由中对应 SQL | 类型 |
|---------|-------------------|------|
| `contentSource` | `content_source = #{contentSource}` | `String` |
| `productionTeam` | `production_team = #{productionTeam}` | `String` |
| `operationProject` | `operation_project = #{operationProject}` | `String` |
| `placementPosition` | `placement_position = #{placementPosition}` | `String` |
| `poi` | `poi IN (...)` — 但 poi 在 content_label 表，poi 本身触发 ES 路由 | `List<String>` |

**影响：** 扩展前 MySQL 路由无法做内容来源/团队/项目的精确筛选。

> **注意：** 暂不支持 keyword 检索，不需要检索 title。keyword 相关需求后续按需支持。

### 14.2 ES 索引不存储 content_title / publish_url

**当前代码：**
- `ContentSearchHit.java`（ES 搜索返回 DTO）没有 `contentTitle`、`publishUrl`
- `ContentSearchDocument.java`（ES 文档 POJO）也没有这 2 个字段
- MySQL `EsDocResultMap` 的查询 SQL 虽然包含了 `cb.content_title`，但 `EsDoc_Column_List` 没选它，`EsDocResultMap` 也没映射它

**验证过程：** `ContentSearchDocAssemblerImpl.mapToDocument()` 从 MySQL row Map 取值（Map 的 key 是 MyBatis resultMap 定义的 property，如 `contentId`），但 `EsDoc_Column_List`（ContentBaseMapper.xml:72-108）**没有 SELECT `cb.content_title` 和 `cb.publish_url`**，`EsDocResultMap`（ContentBaseMapper.xml:110-146）也没有对应的 `<result>` 映射。所以当前 DocAssembler 返回的 `ContentSearchDocument` 也没有标题。

**影响：**
- 当前搜索 API 返回的命中结果**没有标题和链接**，前端无法展示内容标题
- **设计文档假设 ES 搜索后需要 DataAggregator 回查 MySQL**，这正是原因
- DataAggregator 复用 DocAssembler 走 3 表 LEFT JOIN 时，需要**先在 `EsDoc_Column_List` 中加入 `cb.content_title`、`cb.publish_url`**，否则聚合结果也没有标题

### 14.3 ContentSearchDocument / ContentSearchHit 缺少 contentTitle + publishUrl

这与 14.2 是同一问题的两种表现：

| DTO | 有 baseId | 有 contentTitle | 有 publishUrl |
|------|----------|----------------|--------------|
| `ContentSearchHit` | yes | **no** | **no** |
| `ContentSearchDocument` | yes | **no** | **no** |

**修正方案：** 在 `ContentSearchDocument` 中新增 2 个字段，并更新相应的 Mapper XML：

```java
// ContentSearchDocument.java — 新增字段
private String contentTitle;
private String publishUrl;

// Mapper XML — EsDoc_Column_List 追加
//     cb.content_title,
//     cb.publish_url,

// Mapper XML — EsDocResultMap 追加映射
//     <result column="content_title" property="contentTitle" jdbcType="VARCHAR"/>
//     <result column="publish_url" property="publishUrl" jdbcType="VARCHAR"/>
```

`ContentSearchHit` 可以保持现状（它是 ES 直接返回的 DTO，新架构中由 ResponseAssembler 从 Document 转换而来）。

### 14.4 ContentBaseMapper 缺少单表过滤查询

**当前代码**有 6 个 ES 相关查询（均在 `ContentBaseMapper.xml` 中）：
- `selectEsDocByContentId` / `selectEsDocByBaseId` / `selectEsDocByBaseIds` / `selectEsDocByPage` — 3 表 LEFT JOIN
- `count` — 全表计数 `SELECT COUNT(*) FROM content_base`，**无条件**
- `selectIdsPage` — 全表 ID 分页 `SELECT cb.id FROM content_base cb ORDER BY cb.id ASC LIMIT #{offset}, #{pageSize}`，**无条件**

**缺少的：** MySQL 路由需要的条件查询（`<where>` 动态 SQL）：

```sql
-- 按条件过滤 content_base，返回 base_id（用于 MySQL 路由）
SELECT id FROM content_base
<where>
    <if test="contentTypes != null">AND content_type IN ...</if>
    <if test="platforms != null">AND publish_platform IN ...</if>
    <if test="businessLine != null">AND business_line = ...</if>
    <!-- 等（暂不支持 keyword 检索） -->
</where>
ORDER BY id DESC LIMIT #{offset}, #{size}

-- 条件计数
SELECT COUNT(*) FROM content_base
<where>...</where>
```

**新增 Mapper 方法：**

```java
List<Long> selectIdsByFilter(MySQLSearchRequest request);
Long countByFilter(MySQLSearchRequest request);
```

### 14.5 aiTag 类型不一致

| 位置 | 类型 | 来源 |
|------|------|------|
| `ContentSearchHit.aiTag` | `String` | ES 返回 JSON 字符串如 `["酒店","攻略型"]` |
| `ContentSearchDocument.aiTag` | `List<String>` | MySQL 查询后 Gson 解析 |

**影响：** DataAggregator 将 `ContentSearchDocument` 转为 `ContentSearchHit` 时，`aiTag` 需要做类型转换：`List<String>` → `toJsonString()` → `String`。

**现有实现可复用：** `ContentSearchServiceImpl.toJsonString()` 已有此转换逻辑。

### 14.6 ES BoolQueryBuilder 使用 must() 而非 filter()

`ContentSearchServiceImpl:144` — 所有过滤条件都用 `boolQuery.must()`：

```java
boolQuery.must(QueryBuilders.termsQuery(field, values));
```

`must()` 参与 Lucene 相关性评分，计算 TF/IDF/norms，不缓存。内容检索场景：
- 不需要评分（只按 publish_time 或指标排序）
- 不使用 `_score` 字段

**建议：** 新模块的 ES 查询改用 `boolQuery.filter()`，可跳过评分计算、利用 ES 查询结果缓存。

> **不修改已有 ContentSearchService**（其他调用方可能依赖它），仅在新 `ESSearchServiceImpl` 中使用 `filter()`。

### 14.7 当前 Controller 未使用 BaseResponse 包装

`ContentSearchController` 的 `search()` 方法直接返回 `ContentSearchResponse`，没有用 `BaseResponse<T>` 包装：

```java
@PostMapping("/search")
public ContentSearchResponse search(@RequestBody ContentSearchRequest request) {
    // ...
}
```

**影响：** 设计文档中所有响应都走 `BaseResponse`（含 `code`/`msg`/`data`）。改造后的 Controller 需要改为：

```java
@PostMapping("/api/content/search")
public BaseResponse<ContentSearchResponse> search(@RequestBody ContentSearchRequest request) { ... }
```

### 14.8 深潜补充发现

#### 14.8.1 ElasticsearchDataSource 已有 update/bulkUpdate/search — 无差距

**验证结果：** 三个方法均已存在（`ElasticsearchDataSource.java`，261 行）：

| 方法 | 签名 | 与设计一致 |
|------|------|-----------|
| `update` | `update(String index, String id, Object doc)` — `UpdateRequest` + `.doc(GSON.toJson(doc), XContentType.JSON)` + `.docAsUpsert(true)` | 一致 |
| `bulkUpdate` | `bulkUpdate(String index, List<UpdateRequest> requests)` — `BulkRequest` + `forEach(bulk::add)` | 一致 |
| `search` | `search(String index, SearchSourceBuilder builder)` — 返回 `SearchResponse` | 一致（设计推荐的方式） |

**结论：** 写入路径无 gap，`ContentSearchIndexService` + `ContentSearchIndexServiceImpl` 已存在，`ContentSearchServiceImpl.search()` 已正常使用 `elasticsearchDataSource.search()`。设计文档中无需新增 DataSource 方法。

#### 14.8.2 修复/对账任务已存在

`ContentRepairTask.java` — `@QSchedule("mkt_odin_es_repair")`：查询 ES 中不完整文档，从 MySQL 组装修复。
`ContentReconcileTask.java` — `@QSchedule("mkt_odin_es_reconcile")`：每小时 MySQL vs ES 计数对比，差异 > 5% 告警。

**结论：** 设计文档中提到的修复/对账机制已全部存在，无需新增。

#### 14.8.3 ContentTextMapper 无任何 select 方法

`ContentTextMapper.java` 只有 `insert()` 方法，**没有任何查询方法**（不仅没有 `selectBatchByIds`，连 `selectById` 也没有）。

| Mapper | 现有查询方法 |
|--------|------------|
| `ContentImageMapper` | `selectByOriginalUrl`、`selectById` |
| `ContentVideoMapper` | `selectByVideoUrl`、`selectById` |
| `ContentTextMapper` | **无** |

**影响：** 第十五章下载功能的 `contentTextMapper.selectBatchByIds(ids)` 需要：
1. 在 `ContentTextMapper.java` 新增 `selectBatchByIds`
2. 在 `ContentTextMapper.xml` 新增对应 `<select>`（需要确认现有 `BaseResultMap` 和 `Base_Column_List` 是否存在，若不存在则需新增）

#### 14.8.4 ContentSearchResponse.took 单位

当前代码 `ContentSearchServiceImpl:182` 使用 `response.getTook().getSeconds()` 获取耗时，但 `getSeconds()` 返回的是**秒级精度**。对于搜索场景，毫秒级精度更有意义。

```java
result.setTook(response.getTook() != null ? (int) response.getTook().getSeconds() : 0);
```

**建议：** 改为 `response.getTook().millis()` 或 `(int) response.getTook().getMillis()`，以毫秒为单位返回。

#### 14.8.5 EsDocResultMap 字段对照

当前 `EsDocResultMap` 实际映射的字段列表：

| property | column | 状态 |
|----------|--------|------|
| baseId | id | 存在 |
| contentId | content_id | 存在 |
| contentType | content_type | 存在 |
| publishPlatform | publish_platform | 存在 |
| publishTime | publish_time | 存在 |
| businessLine | business_line | 存在 |
| contentSource | content_source | 存在 |
| productionTeam | production_team | 存在 |
| operationProject | operation_project | 存在 |
| placementPosition | placement_position | 存在 |
| city | city | 存在 |
| poi | poi | 存在 |
| aiTag | ai_tag | 存在 |
| 全部 19 个指标字段 | 全部 19 个 metrics 列 | 存在 |
| **contentTitle** | **content_title** | **缺失** |
| **publishUrl** | **publish_url** | **缺失** |

**结论：** 只需加 2 列 + 2 个 `<result>` 映射，无需大改。

### 14.9 总结：改动清单

| 优先级 | 改动 | 涉及文件 | 工作量 | 验证状态 |
|--------|------|---------|--------|---------|
| **P0** | ContentSearchRequest 新增 5 个字段（不含 keyword） | `ContentSearchRequest.java` | 小 | 确认缺少 |
| **P0** | Mapper EsDoc_Column_List + EsDocResultMap 补充 | `ContentBaseMapper.xml` | 小 | 确认缺少 |
| **P0** | ContentSearchDocument 新增 contentTitle + publishUrl | `ContentSearchDocument.java` | 小 | 确认缺少 |
| **P0** | ContentBaseMapper 新增单表查询/计数 | `ContentBaseMapper.java` + XML | 中 | 确认缺少 |
| **P0** | ContentTextMapper 新增 selectBatchByIds | `ContentTextMapper.java` + XML | 小 | 确认缺少 |
| **P0** | ContentImage/VideoMapper 新增 selectBatchByIds | Mapper + XML | 小 | 确认缺少 |
| **P1** | Controller 改为 BaseResponse 包装 | `ContentSearchController.java` | 小 | 确认未包装 |
| **P1** | 新增 ESSearchService 用 filter() 替代 must() | 新文件 | 中 | 确认现有用 must() |
| **P2** | took 单位改为毫秒 | `ContentSearchServiceImpl.java` | 极小 | 建议优化 |

| 优先级 | 改动 | 涉及文件 | 工作量 |
|--------|------|---------|--------|
| **P0** | ContentSearchRequest 新增 5 个字段（不含 keyword） | `ContentSearchRequest.java` | 小 |
| **P0** | Mapper EsDoc_Column_List + EsDocResultMap 补充 | `ContentBaseMapper.xml` | 小 |
| **P0** | ContentSearchDocument 新增 contentTitle + publishUrl | `ContentSearchDocument.java` | 小 |
| **P0** | ContentBaseMapper 新增单表查询/计数 | `ContentBaseMapper.java` + XML | 中 |
| **P1** | Controller 改为 BaseResponse 包装 | `ContentSearchController.java` | 小 |
| **P1** | 新增 ESSearchService 用 filter() 替代 must() | 新文件 | 中 |
| **P2** | 检查其他调用方是否受 Controller 返回类型影响 | — | 小 |

---

## 十五、ContentDownload — 内容下载打包（ZIP）

### 15.1 背景

检索结果中的每条内容包含图片、视频、正文文本。用户需要一键下载单条内容的所有素材，打包为 ZIP 压缩包。下载链路只允许内网访问，防止外网 CDN 流量和未经授权的下载。

### 15.2 数据模型

`content_base.content_relations` 存储了该内容关联的资源 ID 列表：

```json
{"text_ids": [1], "image_ids": [1, 2, 3], "video_ids": [4]}
```

各子表的存储关系：

| 资源类型 | 表 | 关键字段 | 实际文件 URL |
|---------|-----|---------|-------------|
| 图片 | `content_image` | `original_url`（外网）、`internal_url`（内网 OSS） | `internal_url` |
| 视频 | `content_video` | `video_url`（外网）、`internal_video_url`（内网 OSS） | `internal_video_url` |
| 正文 | `content_text` | `content_text`（文本内容） | 直接写入 .txt |

> **注意：** `internal_url` / `internal_video_url` 是 OSS 转存后回写的内网地址，下载时直接用内网地址拉取，不产生外网 CDN 费用。

### 15.3 接口定义

```
GET /api/content/download?contentId=xxx

权限: 仅内网可访问（Nginx/IP 白名单）
限流: 5 QPS/用户，防止资源耗尽
```

**请求参数：** `contentId`（String，必填，从检索结果中获得）

**响应：** `application/zip` 八进制流，文件名 `{contentId}_素材.zip`

### 15.4 整体流程

```
Client → Nginx(内网域名校验) → DownloadController → Validation(权限+限流)
  → ContentBaseMapper.selectByContentId → 解析 content_relations
  → 并行查询: ContentTextMapper / ContentImageMapper / ContentVideoMapper
  → TempDir 组织目录结构
  → URL 资源下载到 temp 目录
  → ZipOutputStream 打包
  → 返回 ResponseEntity<byte[]> (application/zip)
  → 清理 temp 目录
  → 异步埋点 trackDownload
```

### 15.5 ZIP 目录结构

```
{contentId}_素材.zip
├── images/
│   ├── 1.jpg              ← 从 content_image.internal_url 下载
│   ├── 2.png
│   └── ...
├── videos/
│   ├── 4.mp4              ← 从 content_video.internal_video_url 下载
│   └── ...
└── text/
    └── 正文.txt            ← 从 content_text.content_text 写入
```

### 15.6 核心实现

```java
@Component
public class ContentDownloadService {

    // 下载线程池（IO 密集型，核心 4，最大 8）
    private static final ExecutorService DOWNLOAD_POOL = new ThreadPoolExecutor(
            4, 8, 60, TimeUnit.SECONDS,
            new LinkedBlockingQueue<>(200),
            new ThreadFactoryBuilder().setNameFormat("download-pool-%d").build(),
            new ThreadPoolExecutor.CallerRunsPolicy()
    );

    @Resource
    private ContentBaseMapper contentBaseMapper;

    // 三个 Mapper 需要在现有基础上新增 selectBatchByIds 方法
    @Resource
    private ContentImageMapper contentImageMapper;
    @Resource
    private ContentVideoMapper contentVideoMapper;
    @Resource
    private ContentTextMapper contentTextMapper;

    public DownloadResult download(String contentId) throws IOException {
        // 1. 查询 content_base → 获取 content_relations
        ContentBase base = contentBaseMapper.selectByContentId(contentId);
        if (base == null) {
            throw new NotFoundException("内容不存在: " + contentId);
        }
        ContentRelations relations = GSON.fromJson(base.getContentRelations(), ContentRelations.class);

        // 2. 并行查询各子表（CompletableFuture.supplyAsync）
        CompletableFuture<List<ContentImage>> imageFuture =
                supplyAsync(() -> contentImageMapper.selectBatchByIds(relations.getImageIds()), DOWNLOAD_POOL);
        CompletableFuture<List<ContentVideo>> videoFuture =
                supplyAsync(() -> contentVideoMapper.selectBatchByIds(relations.getVideoIds()), DOWNLOAD_POOL);
        CompletableFuture<List<ContentText>> textFuture =
                supplyAsync(() -> contentTextMapper.selectBatchByIds(relations.getTextIds()), DOWNLOAD_POOL);

        CompletableFuture.allOf(imageFuture, videoFuture, textFuture).join();

        // 3. 在 temp 目录构建文件结构
        Path tempDir = Files.createTempDirectory("content-dl-");
        try {
            buildImageFiles(tempDir, imageFuture.get());
            buildVideoFiles(tempDir, videoFuture.get());
            buildTextFile(tempDir, textFuture.get(), base.getContentTitle());

            // 4. 打包 ZIP
            Path zipPath = tempDir.resolve(base.getContentId() + "_素材.zip");
            try (ZipOutputStream zos = new ZipOutputStream(Files.newOutputStream(zipPath))) {
                Files.walk(tempDir)
                        .filter(p -> !p.equals(zipPath) && !Files.isDirectory(p))
                        .forEach(p -> addToZip(zos, tempDir.relativize(p), p));
            }

            byte[] data = Files.readAllBytes(zipPath);
            return new DownloadResult(data, zipPath.getFileName().toString());

        } finally {
            FileUtils.deleteDirectory(tempDir.toFile());  // 清理 temp
        }
    }

    private void buildTextFile(Path tempDir, List<ContentText> texts, String title) throws IOException {
        if (CollectionUtils.isEmpty(texts)) return;
        Path textDir = tempDir.resolve("text");
        Files.createDirectories(textDir);
        Path txtFile = textDir.resolve("正文.txt");
        try (BufferedWriter writer = Files.newBufferedWriter(txtFile, StandardCharsets.UTF_8)) {
            writer.write("标题: " + (title != null ? title : "") + "\n\n");
            for (ContentText text : texts) {
                writer.write(text.getContentText() != null ? text.getContentText() : "");
                writer.write("\n");
            }
        }
    }

    private void buildImageFiles(Path tempDir, List<ContentImage> images) {
        if (CollectionUtils.isEmpty(images)) return;
        Path imgDir = tempDir.resolve("images");
        Files.createDirectories(imgDir);
        AtomicInteger idx = new AtomicInteger(1);
        // 并行下载图片
        CountDownLatch latch = new CountDownLatch(images.size());
        for (ContentImage img : images) {
            DOWNLOAD_POOL.execute(() -> {
                try {
                    String url = img.getInternalUrl();  // 使用内网 OSS URL
                    if (StringUtils.isNotBlank(url)) {
                        String ext = extractExtension(url, ".jpg");
                        Path file = imgDir.resolve(idx.getAndIncrement() + ext);
                        downloadFile(url, file);
                    }
                } catch (Exception e) {
                    log.warn("Download image failed: {}", img.getId(), e);
                } finally {
                    latch.countDown();
                }
            });
        }
        latch.await(30, TimeUnit.SECONDS);
    }
}
```

### 15.7 新增/修改 Mapper 方法

现有 `ContentImageMapper` / `ContentVideoMapper` 只有单条 `selectById`，需要新增批量查询：

```java
// ContentImageMapper.java
List<ContentImage> selectBatchByIds(@Param("ids") List<Long> ids);

// ContentVideoMapper.java
List<ContentVideo> selectBatchByIds(@Param("ids") List<Long> ids);

// ContentTextMapper.java
List<ContentText> selectBatchByIds(@Param("ids") List<Long> ids);
```

对应 XML（以 image 为例）：

```xml
<select id="selectBatchByIds" resultMap="BaseResultMap">
    SELECT <include refid="Base_Column_List"/>
    FROM content_image
    WHERE id IN
    <foreach collection="ids" item="id" open="(" separator="," close=")">#{id}</foreach>
</select>
```

### 15.8 内网域名限制

两种策略结合：

| 策略 | 实现方式 | 说明 |
|------|---------|------|
| **Nginx 层限制** | Nginx 只在内网 VIP 上暴露 `/api/content/download` 路径 | 外网根本无法到达此接口，最可靠 |
| **应用层二次校验** | Filter 检查 `Host` 头或 `X-Forwarded-Host` | 防止 Nginx 配置失误，作为兜底 |

```java
// DownloadSecurityFilter.java — 应用层兜底校验
@Component
public class DownloadSecurityFilter implements Filter {
    // QConfig 维护的内网域名列表
    @Resource
    private InternalDomainConfig internalDomainConfig;

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain) {
        HttpServletRequest httpRequest = (HttpServletRequest) request;
        String host = httpRequest.getHeader("Host");
        if (!internalDomainConfig.isInternal(host)) {
            writeErrorResponse(response, 403, "下载接口仅限内网访问");
            return;
        }
        chain.doFilter(request, response);
    }
}
```

### 15.9 超时与边界处理

| 场景 | 处理 |
|------|------|
| contentId 不存在 | 返回 404 |
| content_relations 为空 | 只打包 text 文件夹（写入"无关联资源"） |
| 图片/视频下载失败 | 跳过失败项继续打包其他资源，日志记录失败 ID |
| 下载超时（单文件 > 30s） | CountDownLatch.await 超时，已下载的保留，超时的跳过 |
| ZIP 包太大（> 500MB） | 限制打包大小，超过时返回 413 |
| content_text 为空 | text/正文.txt 写入"无正文内容" |
| 并发下载 | 独立线程池，CallerRunsPolicy 兜底 |

### 15.10 限流

| 维度   | 阈值           | 说明               |
| ---- | ------------ | ---------------- |
| 用户级别 | 5 QPS        | 打包是 IO/CPU 密集型操作 |
| 全局并发 | 同时最多 3 个打包任务 | 防止多个大包撑爆内存       |

### 15.11 文件清单变更

**新增文件：**
| 文件 | 说明 |
|------|------|
| `service/download/ContentDownloadService.java` | 下载打包核心逻辑 |
| `web/download/DownloadController.java` | 下载端点 |
| `web/download/DownloadSecurityFilter.java` | 内网域名校验 Filter |
| `service/download/config/InternalDomainConfig.java` | QConfig 内网域名配置 |
| `service/download/DownloadResult.java` | 下载结果 DTO |

**修改文件：**
| 文件 | 变更 |
|------|------|
| `ContentImageMapper.java` + XML | 新增 `selectBatchByIds` |
| `ContentVideoMapper.java` + XML | 新增 `selectBatchByIds` |
| `ContentTextMapper.java` + XML | 新增 `selectBatchByIds` |