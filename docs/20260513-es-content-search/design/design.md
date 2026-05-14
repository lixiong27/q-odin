# 数仓宽表 ES 加速查询方案

## 一、需求概述

### 1.1 背景

当前数仓宽表（`content_base` + 子表）数据存储在 MySQL 中，支持存量和增量同步。随着数据量增长，MySQL 的复杂查询（如按标题/正文/POI/标签模糊检索、多维度筛选）性能下降明显。

**业务指标：**
- 宽表每日更新（部分数据更新，非全量覆盖）
- AI 标签（aiTag）通过定时任务异步更新，具有随机性
- 根据 `content_id` 确认是否已同步到 `content_base`，实现去重

### 1.2 目标

- 使用 Elasticsearch 加速宽表数据的查询能力
- 支持存量初始化 + 增量实时同步
- 只能使用原生 ES Client（`RestHighLevelClient`），不引入 ORM 封装
- 与现有 `content_base` 表保持数据一致性

### 1.3 约束

- 不使用 Spring Data ES 等高级封装，只用原生 `RestHighLevelClient`
- ES 索引使用统一索引名 `content_search`，不分日期（简化查询）
- 与现有 `RawContentSyncService` 同步流程解耦，通过调用方触发 ES 更新

---

## 二、索引 Mapping

```json
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1,
    "refresh_interval": "5s"
  },
  "mappings": {
    "properties": {
      "base_id":                  { "type": "long" },

      "content_id":               { "type": "keyword" },
      "content_type":             { "type": "keyword" },
      "content_title":            { "type": "text", "analyzer": "ik_max_word", "fields": { "raw": { "type": "keyword" } } },
      "publish_platform":         { "type": "keyword" },
      "publish_time":             { "type": "date" },
      "publish_url":              { "type": "keyword", "index": false },
      "business_line":            { "type": "keyword" },
      "content_source":           { "type": "keyword" },
      "production_team":          { "type": "keyword" },
      "operation_project":        { "type": "keyword" },
      "placement_position":       { "type": "keyword" },

      "content_text":             { "type": "text", "analyzer": "ik_max_word" },

      "city":                     { "type": "keyword" },
      "poi":                      { "type": "keyword" },
      "ai_tag":                   { "type": "keyword" },

      "total_impressions":        { "type": "integer" },
      "total_clicks":             { "type": "integer" },
      "total_reads":              { "type": "integer" },
      "total_interactions":       { "type": "integer" },
      "completion_rate":          { "type": "float" },
      "three_sec_completion_rate":{ "type": "float" },
      "five_sec_completion_rate": { "type": "float" },
      "two_sec_bounce_rate":      { "type": "float" },
      "cpm":                      { "type": "float" },
      "ctr":                      { "type": "float" },
      "cvr":                      { "type": "float" },
      "app_downloads":            { "type": "integer" },
      "new_activations":          { "type": "integer" },
      "new_registrations":        { "type": "integer" },
      "drive_uv":                 { "type": "integer" },
      "exposure_to_read_ratio":   { "type": "float" },
      "potential_new_uv":         { "type": "integer" },
      "potential_new_cac":        { "type": "float" },
      "attributed_new_customers": { "type": "integer" },
      "new_customer_cac":         { "type": "float" },
      "order_uv":                 { "type": "integer" },
      "total_orders":             { "type": "integer" },

      "sync_time":                { "type": "date" }
    }
  }
}
```

### Mapping 设计说明

| 设计点 | 说明 |
|--------|------|
| `base_id` long | 仅存储，不用于 `_id` 以外的检索 |
| keyword 字段 | 枚举/过滤/聚合字段，精确匹配 |
| content_title text + keyword.raw | text 分词检索，raw 子字段精确匹配/排序 |
| content_text text | 正文全文检索 |
| ai_tag keyword | 数组类型，天然支持 term/terms/aggregations |
| publish_url index:false | 仅存储不索引，节省空间 |
| 指标字段 integer/float | 支持范围过滤、排序、聚合 |
| refresh_interval 5s | 准实时，批量场景可临时调大 |

---

## 三、三种场景策略

### 3.1 场景一：新内容入库

**触发时机**：新内容首次写入 MySQL 后

**策略**：全量文档索引

```java
function onNewContent(base, text, metrics, label):
    // 1. MySQL 写入（略）

    // 2. ES 全量索引
    doc = {
        base_id:             base.id,
        content_id:          base.contentId,
        content_type:        base.contentType,
        content_title:       base.contentTitle,
        publish_platform:    base.publishPlatform,
        publish_time:        base.publishTime,
        publish_url:         base.publishUrl,
        business_line:       base.businessLine,
        content_source:      base.contentSource,
        production_team:     base.productionTeam,
        operation_project:   base.operationProject,
        placement_position:  base.placementPosition,
        content_text:        text.contentText,
        city:                label.city,
        poi:                 label.poi,
        ai_tag:              label.aiTag,
        total_impressions:   0,
        total_clicks:        0,
        // ... 其余指标初始零值
        sync_time:           now()
    }

    esClient.index(
        index = "content_search",
        id    = base.id.toString(),   // _id = base_id
        body  = doc
    )
```

**操作类型**：`IndexRequest`，幂等覆盖

---

### 3.2 场景二：数仓指标每日批量更新

**触发时机**：T+1 数仓宽表同步，每日一次

**特点**：批量（可能数千~数万条），只更新 metrics 字段

**策略**：BULK partial update + 基础字段兜底

```java
function batchSyncMetrics(metricList):
    // metricList: [{baseId, totalImpressions, totalClicks, ...}]

    // 1. 批量查询基础信息（用于兜底）
    baseIds = metricList.map(r -> r.baseId)
    baseMap = contentBaseMapper.selectByIds(baseIds)

    // 2. 分批 BULK 更新
    for batch in partition(metricList, 500):
        bulk = []
        for m in batch:
            base = baseMap.get(m.baseId)
            doc = {
                total_impressions:        m.totalImpressions,
                total_clicks:             m.totalClicks,
                total_reads:             m.totalReads,
                total_interactions:       m.totalInteractions,
                completion_rate:          m.completionRate,
                three_sec_completion_rate:m.threeSecCompletionRate,
                five_sec_completion_rate: m.fiveSecCompletionRate,
                two_sec_bounce_rate:      m.twoSecBounceRate,
                cpm:                      m.cpm,
                ctr:                      m.ctr,
                cvr:                      m.cvr,
                app_downloads:            m.appDownloads,
                new_activations:          m.newActivations,
                new_registrations:        m.newRegistrations,
                drive_uv:                 m.driveUv,
                exposure_to_read_ratio:   m.exposureToReadRatio,
                potential_new_uv:         m.potentialNewUv,
                potential_new_cac:        m.potentialNewCac,
                attributed_new_customers: m.attributedNewCustomers,
                new_customer_cac:         m.newCustomerCac,
                order_uv:                 m.orderUv,
                total_orders:             m.totalOrders,
                sync_time:                now()
            }

            // 兜底：带上基础字段，防止 upsert 创建不完整文档
            if base != null:
                doc["content_id"]        = base.contentId
                doc["content_type"]      = base.contentType
                doc["content_title"]     = base.contentTitle
                doc["publish_platform"]  = base.publishPlatform
                doc["business_line"]     = base.businessLine
                doc["content_source"]    = base.contentSource

            bulk.add(UpdateRequest(
                index  = "content_search",
                id     = m.baseId.toString(),
                doc    = doc,
                upsert = true
            ))

        esClient.bulk(bulk)
```

**操作类型**：`UpdateRequest + upsert`

**设计要点**：doc 中附带 base 基础字段，确保 upsert 时若文档不存在也能创建出完整文档

---

### 3.3 场景三：AI 标签更新

**触发时机**：AI 任务完成后回调，单条或小批量，随机触发

**策略**：单条 partial update

```java
function onAiTaskComplete(taskId, baseId, aiTags, aiTagDetail, city, poi):
    // 1. MySQL upsert（略）

    // 2. ES 部分更新（仅标签字段）
    doc = {
        ai_tag:    aiTags,   // ["酒店","攻略型","景德镇"]
        city:      city,
        poi:       poi,
        sync_time: now()
    }

    esClient.update(
        index  = "content_search",
        id     = baseId.toString(),
        doc    = doc,
        upsert = true
    )
```

**操作类型**：`UpdateRequest + upsert`

**注意**：此场景 doc 仅含标签字段，未带基础字段兜底。若文档不存在会创建不完整文档，依赖对账任务修复。

---

## 四、异常处理方案

### 4.1 异常场景总览

| 场景 | 现象 | 影响 |
|------|------|------|
| 指标/标签更新时，upsert 创建了新文档且无基础字段 | 文档缺少 content_id、business_line 等 | 过滤/聚合漏掉该数据 |
| ES 集群短暂不可用 | 写入失败 | ES 数据落后 MySQL |
| BULK 部分失败 | 部分文档写入失败 | 部分数据不一致 |
| 程序 Bug 或网络超时 | 个别写入丢失 | 个别数据不一致 |

### 4.2 统一兜底：定时对账任务

不依赖写入侧的回滚重试，统一用**定时任务**兜底修复。

**任务流程**：

```
function scheduledRepairTask():
    INTERVAL = 每 30 分钟执行

    // 第一步：查询 ES 中文档缺少基础字段的数据
    incompleteDocs = queryIncompleteDocs()

    // 第二步：分批补全
    for batch in partition(incompleteDocs, 200):
        repairBatch(batch)

    // 第三步：记录日志
    log("修复完成，本次修复 {} 条", incompleteDocs.size())
```

### 4.3 查询不完整文档

**ES 查询条件**：基础字段为空或不存在

```java
function queryIncompleteDocs():
    response = esClient.search(
        index = "content_search",
        body = {
            query: {
                bool: {
                    should: [
                        { bool: { must_not: { exists: { field: "content_id" } } } },
                        { bool: { must_not: { exists: { field: "business_line" } } } },
                        { bool: { must_not: { exists: { field: "content_type" } } } },
                        { term: { "content_id": "" } },
                        { term: { "business_line": "" } }
                    ],
                    minimum_should_match: 1
                }
            },
            size: 1000,
            _source: false   // 只需要 _id，不需要文档内容
        }
    )

    // 从 _id 提取 base_id
    return response.hits.hits.map(hit -> Long.parseLong(hit._id))
```

### 4.4 补全修复

```java
function repairBatch(baseIds):
    // 1. 从 MySQL 批量查询完整数据
    docs = assembleFullDocsFromMySQL(baseIds)

    // 2. ES Bulk 全量更新
    bulk = []
    for doc in docs:
        doc["sync_time"] = now()
        bulk.add(UpdateRequest(
            index  = "content_search",
            id     = doc.baseId.toString(),
            doc    = doc,
            upsert = true
        ))

    // 3. 逐条检查结果
    response = esClient.bulk(bulk)
    for item in response.items:
        if item.status >= 400:
            failedIds.add(item.id)
            log("修复失败 base_id={}, error={}", item.id, item.error)

    // 4. 失败的重试或告警
    if failedIds is not empty:
        retryOrAlert(failedIds)
```

### 4.5 全量重建（极端情况）

```java
function fullRebuild():
    // 场景：ES 索引损坏 / 数据大面积缺失 / Mapping 变更
    total = contentBaseMapper.count()
    pageSize = 1000

    for offset in range(0, total, pageSize):
        rows = assembleFullDocsFromMySQL(offset, pageSize)  // 6表 JOIN 组装
        bulk = []
        for r in rows:
            doc = assembleEsDoc(r)
            doc["sync_time"] = now()
            bulk.add(IndexRequest(
                index = "content_search",
                id    = r.baseId.toString(),
                body  = doc
            ))
        esClient.bulk(bulk)
```

---

## 五、ES 服务封装

### 5.1 ContentIndexService

```java
@Component
@Slf4j
public class ContentIndexService {

    private static final String INDEX_NAME = "content_search";

    @Resource
    private ElasticsearchDataSource elasticsearchDataSource;

    @Resource
    private HotFileQConfig hotFileQConfig;

    /**
     * 确保索引存在
     */
    public void ensureIndexExists() {
        if (!elasticsearchDataSource.existIndex(INDEX_NAME)) {
            String settings = buildSettings();
            String mappings = buildMappings();
            elasticsearchDataSource.create(INDEX_NAME, settings, mappings);
            log.info("ES 索引创建成功: {}", INDEX_NAME);
        }
    }

    /**
     * 全量索引（场景一）
     */
    public boolean indexDocument(ContentEsDoc doc) {
        ensureIndexExists();
        try {
            IndexRequest request = new IndexRequest(INDEX_NAME)
                    .id(String.valueOf(doc.getBaseId()))
                    .source(JsonUtils.toJson(doc), XContentType.JSON);
            restClient().index(request, RequestOptions.DEFAULT);
            return true;
        } catch (Exception e) {
            log.error("ES 索引文档失败, baseId={}", doc.getBaseId(), e);
            return false;
        }
    }

    /**
     * 批量更新（场景二、三）
     */
    public boolean batchUpdate(List<UpdateRequest> requests) {
        if (CollectionUtils.isEmpty(requests)) {
            return true;
        }
        BulkRequest bulkRequest = new BulkRequest();
        requests.forEach(bulkRequest::add);

        try {
            BulkResponse response = restClient().bulk(bulkRequest, RequestOptions.DEFAULT);
            if (response.hasFailures()) {
                log.error("ES bulk update failed: {}", response.buildFailureMessage());
                return false;
            }
            return true;
        } catch (Exception e) {
            log.error("ES bulk update error", e);
            return false;
        }
    }

    private RestHighLevelClient restClient() {
        return elasticsearchDataSource.getRestHighLevelClient();
    }

    private String buildSettings() {
        int shards = hotFileQConfig.getInt("es.index.shards", 3);
        int replicas = hotFileQConfig.getInt("es.index.replicas", 1);
        return String.format("{\"number_of_shards\": %d, \"number_of_replicas\": %d, \"refresh_interval\": \"5s\"}",
                shards, replicas);
    }

    private String buildMappings() {
        // 详见第二章 Mapping 定义
        return "{...}";
    }
}
```

### 5.2 同步服务入口

```java
@Service
@Slf4j
public class ContentIndexSyncService {

    @Resource
    private ContentBaseMapper contentBaseMapper;

    @Resource
    private ContentLabelMapper contentLabelMapper;

    @Resource
    private ContentMetricsMapper contentMetricsMapper;

    @Resource
    private ContentIndexService contentIndexService;

    private static final int BATCH_SIZE = 500;

    /**
     * 场景一：新内容入库（由 RawContentSyncService 调用）
     */
    public void syncNewContent(Long baseId) {
        ContentBase base = contentBaseMapper.selectById(baseId);
        ContentText text = contentTextMapper.selectByBaseId(baseId);
        ContentMetrics metrics = contentMetricsMapper.selectByBaseId(baseId);
        ContentLabel label = contentLabelMapper.selectByBaseId(baseId);

        ContentEsDoc doc = assembleDoc(base, text, metrics, label);
        contentIndexService.indexDocument(doc);
    }

    /**
     * 场景二：数仓指标批量更新（定时任务）
     */
    public void syncMetricsFromWarehouse(Date syncDate) {
        // 查询指定日期需要更新的指标
        List<ContentMetrics> metricsList = contentMetricsMapper.selectBySyncDate(syncDate);

        // 分批处理
        List<List<ContentMetrics>> batches = Lists.partition(metricsList, BATCH_SIZE);
        for (List<ContentMetrics> batch : batches) {
            syncMetricsBatch(batch);
        }
    }

    private void syncMetricsBatch(List<ContentMetrics> metricsList) {
        // 批量查询 base 基础信息（兜底用）
        List<Long> baseIds = metricsList.stream()
                .map(ContentMetrics::getBaseId).collect(Collectors.toList());
        Map<Long, ContentBase> baseMap = contentBaseMapper.selectByIds(baseIds)
                .stream().collect(Collectors.toMap(ContentBase::getId, Function.identity()));

        // 构建 UpdateRequest 列表
        List<UpdateRequest> requests = new ArrayList<>();
        for (ContentMetrics m : metricsList) {
            ContentBase base = baseMap.get(m.getBaseId());
            Map<String, Object> doc = buildMetricsDoc(m);
            // 兜底：带基础字段
            if (base != null) {
                doc.put("content_id", base.getContentId());
                doc.put("content_type", base.getContentType());
                doc.put("content_title", base.getContentTitle());
                doc.put("publish_platform", base.getPublishPlatform());
                doc.put("business_line", base.getBusinessLine());
                doc.put("content_source", base.getContentSource());
            }
            doc.put("sync_time", new Date());

            requests.add(new UpdateRequest(INDEX_NAME, String.valueOf(m.getBaseId()))
                    .doc(doc).upsert(true));
        }

        contentIndexService.batchUpdate(requests);
    }

    /**
     * 场景三：AI 标签更新（AI 任务回调触发）
     */
    public void syncAiTags(Long baseId, List<String> aiTags, String city, String poi) {
        Map<String, Object> doc = new HashMap<>();
        doc.put("ai_tag", aiTags);
        doc.put("city", city);
        doc.put("poi", poi);
        doc.put("sync_time", new Date());

        UpdateRequest request = new UpdateRequest(INDEX_NAME, String.valueOf(baseId))
                .doc(doc).upsert(true);
        contentIndexService.batchUpdate(List.of(request));
    }

    /**
     * 全量重建（管理接口触发）
     */
    public void fullRebuild(int batchSize) {
        long total = contentBaseMapper.count();
        long offset = 0;

        while (offset < total) {
            List<ContentBase> batch = contentBaseMapper.selectPage(offset, batchSize);
            for (ContentBase base : batch) {
                syncNewContent(base.getId());
            }
            offset += batchSize;
            log.info("ES 全量重建进度: {}/{}", offset, total);
        }
    }
}
```

---

## 六、查询封装

### 6.1 ContentSearchService

```java
@Service
@Slf4j
public class ContentSearchService {

    private static final String INDEX_NAME = "content_search";

    @Resource
    private ElasticsearchDataSource elasticsearchDataSource;

    /**
     * 按标题/正文/POI 搜索
     */
    public EsSearchResponse search(String keyword, Integer page, Integer size) {
        SearchRequest request = new SearchRequest(INDEX_NAME);
        SearchSourceBuilder sourceBuilder = new SearchSourceBuilder();

        // 多字段匹配
        MultiMatchQueryBuilder multiMatch = QueryBuilders.multiMatchQuery(keyword,
                "contentTitle", "contentText", "poi", "city");
        sourceBuilder.query(multiMatch);

        // 分页
        sourceBuilder.from((page - 1) * size);
        sourceBuilder.size(size);

        // 按发布时间排序
        sourceBuilder.sort("publishTime", SortOrder.DESC);

        request.source(sourceBuilder);

        try {
            SearchResponse response = restClient().search(request, RequestOptions.DEFAULT);
            return parseResponse(response);
        } catch (Exception e) {
            log.error("ES 搜索失败, keyword={}", keyword, e);
            return EsSearchResponse.empty();
        }
    }

    /**
     * 按业务线 + 时间范围 + 标签筛选
     */
    public EsSearchResponse filter(String businessLine, Date start, Date end,
                                   List<String> tags, Integer page, Integer size) {
        BoolQueryBuilder boolQuery = QueryBuilders.boolQuery();

        if (StringUtils.isNotBlank(businessLine)) {
            boolQuery.must(QueryBuilders.termQuery("business_line", businessLine));
        }
        if (start != null && end != null) {
            boolQuery.must(QueryBuilders.rangeQuery("publishTime").gte(start).lte(end));
        }
        if (CollectionUtils.isNotEmpty(tags)) {
            boolQuery.must(QueryBuilders.termsQuery("ai_tag", tags.toArray()));
        }

        SearchRequest request = new SearchRequest(INDEX_NAME);
        SearchSourceBuilder sourceBuilder = new SearchSourceBuilder();
        sourceBuilder.query(boolQuery);
        sourceBuilder.from((page - 1) * size);
        sourceBuilder.size(size);
        request.source(sourceBuilder);

        // ... 执行查询并返回结果
    }

    private RestHighLevelClient restClient() {
        return elasticsearchDataSource.getRestHighLevelClient();
    }
}
```

### 6.2 查询 API

```
GET /api/es/content/search?keyword=xxx&page=1&size=20
GET /api/es/content/filter?businessLine=xxx&start=xxx&end=xxx&tags=xxx,yyy
```

---

## 七、文件变更清单

### 新增文件

| 文件 | 说明 |
|------|------|
| `service/es/ContentIndexService.java` | ES 索引管理，提供 index/update/batchUpdate |
| `service/es/ContentSearchService.java` | ES 查询服务 |
| `service/es/ContentIndexSyncService.java` | ES 同步服务（3 场景入口） |
| `task/es/ContentRepairTask.java` | ES 数据对账修复定时任务 |
| `domain/dto/es/ContentEsDoc.java` | ES 文档 DTO |
| `controller/web/ContentEsController.java` | 查询 API 控制器 |

### 修改文件

| 文件 | 变更 |
|------|------|
| `ElasticsearchDataSource.java` | 暴露 `getRestHighLevelClient()` |
| `RawContentSyncService.java` | 同步完成后调用 `syncNewContent()` |
| `AiTaggingCallbackService.java` | AI 标签更新后调用 `syncAiTags()` |

### SQL 变更

无（复用现有表结构）

---

## 八、监控指标

| 指标名 | 说明 |
|--------|------|
| es_content_index | 新内容索引次数 |
| es_content_index_error | 新内容索引失败次数 |
| es_metrics_update | 指标批量更新次数 |
| es_metrics_update_error | 指标批量更新失败次数 |
| es_ai_tag_update | AI 标签更新次数 |
| es_ai_tag_update_error | AI 标签更新失败次数 |
| es_repair_incomplete | 对账任务发现不完整文档数 |
| es_repair_fixed | 对账任务修复数 |

---

## 九、风险与注意事项

1. **数据一致性**：采用最终一致性，通过定时对账任务兜底
2. **ES 内存**：全量重建期间注意 ES JVM 内存，避免 OOM
3. **mapping 变更**：上线后如需修改 mapping，需重建索引
4. **upsert 不完整文档**：场景二已做兜底，场景三依赖对账任务修复

---

## 十、后续扩展

1. **搜索建议**：接入 ES Completion Suggester 实现搜索提示
2. **聚合分析**：基于 ES Aggregation 实现实时统计报表
3. **向量检索**：结合向量检索实现语义搜索（需引入 embedding 服务）