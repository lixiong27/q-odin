# ES 索引加速 — 已有代码分析与实现指引

> 参考 ErrorLocateService#list ES 查询模式 + ElasticsearchDataSourceImpl 写入模式，对标 index-acceleration 设计文档需求，给出可落地的实现指引。

---

## 一、ErrorLocateService#list ES 流程拆解

### 1.1 完整调用链

```
ErrorLocateController#list(request)
  │
  └─ ErrorLocateService#list(request, response)
       │
       ├── 1. 参数校验（checkErrorLocateRequestParam）
       │       ├── errorLocateType 映射为 ErrorLocateTypeEnum（索引前缀）
       │       ├── 至少一个查询条件非空
       │       ├── 时间格式正则校验（HH:mm:ss）
       │       └── pageSize 上限 1000
       │
       ├── 2. 手机号 → 用户名查询（UserCenter 兜底）
       │
       ├── 3. 动态拼接索引名
       │       index = errorLocateESConfig.getEsIndex(typeEnum.indexName, dateSuffix)
       │       → 格式: "{prefix}_{typeEnum}_{dateSuffix}"
       │
       ├── 4. 校验索引是否存在（elasticsearchDataSource.existIndex）
       │       → 不存在则直接返回"非法的日期 不存在索引"
       │
       ├── 5. Eq 条件查询 + Range 时间查询
       │       BoolQueryBuilder
       │         ├── .must(termQuery("userName", value))    // 精确匹配
       │         ├── .must(termQuery("activityCode", value))
       │         ├── .must(termQuery("activityType", value))
       │         └── .must(rangeQuery("createTime").gte(start).lte(end))
       │
       ├── 6. 查总数 → 查列表（分页）
       │       count = elasticsearchDataSource.queryTotalCount(index, queryBuilder)
       │       list  = elasticsearchDataSource.queryPageData(index, pageSize, pageNum, queryBuilder, Entity.class)
       │
       └── 7. 实体 → VO 转换，设置 response
```

### 1.2 关键模式总结

| 模式       | ErrorLocateService 做法                                                | 对标 index-acceleration 场景                                                  |
| -------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| **查询构造** | BoolQueryBuilder，静态 Java API（term/range）                             | ContentSearchService 需要更复杂的查询：全文检索（match/multi_match）+ 过滤（terms/term）+ 高亮 |
| **索引路由** | `prefix + "_" + type + "_" + dateSuffix`，按日期分片                       | content_search 单索引 + 别名，不需要日期后缀                                           |
| **分页**   | `queryPageData` 内置 `.from((pageNum-1)*pageSize).size(pageSize)`      | 相同模式，from + size 即可                                                       |
| **排序**   | queryPageData 硬编码 `.sort("createTime", SortOrder.DESC)`              | 需要动态排序（按指标字段可配）                                                           |
| **结果映射** | 泛型方法 `transformToPageData(searchHit, clazz)`，Gson 反序列化               | 相同模式，用 ContentSearchHit.class 反序列化                                        |
| **总数统计** | `queryTotalCount` 使用 `searchResponse.getHits().getTotalHits().value` | 直接复用                                                                      |
| **错误处理** | 异常捕获 + QMonitor + 返回空列表（不抛异常）                                        | 相同模式，搜索失败不阻断页面                                                            |
| **响应格式** | PageResponse（success/code/msg/data/totalCount/pageIndex/pageSize）    | ContentSearchResponse 需要包含 hits/total/took                                |

---

## 二、ElasticsearchDataSourceImpl 写入模式拆解（poseidon-superman）

### 2.1 现有方法

| 方法 | 实现要点 | 是否可复用 |
|------|---------|-----------|
| `create()` | CreateIndexRequest(settings+mapping → XContentType.JSON) → HLRC.indices().create() | odin 版已对标实现 |
| `existIndex()` | GetIndexRequest → HLRC.indices().exists() | odin 版已对标实现 |
| `insert()` | IndexRequest → source(GSON.toJson(data), XContentType.JSON) → HLRC.index() | odin 版缺失，需要新增 |
| `batchInsert()` | BulkRequest → transform(data) 转为 IndexRequest 列表 → HLRC.bulk() | odin 版已对标实现 |
| `query()` | SearchRequest → SearchSourceBuilder.query(queryBuilder) → HLRC.search() | odin 版缺失，需要新增 |
| `queryTotalCount()` | SearchSourceBuilder.size(0).aggregation(count) | 可直接复用模式 |
| `queryPageData()` | SearchSourceBuilder.query().from().size().sort() → HLRC.search() → Gson 反序列化 | odin 版缺失，需要新增 |

### 2.2 关键实现细节（参考价值）

**序列化方式（ElasticsearchDataSourceImpl.java:258）：**
```java
// 单条：用 JsonUtils（Jackson）
private <T> String transform(T data) { return JsonUtils.toJson(data); }

// 批量：用 Gson（注意上下文！）
return new IndexRequest(index).source(new Gson().toJson(data), XContentType.JSON);
```

> 注意：单条 insert 用 `JsonUtils`（Jackson），批量 insert 用 `Gson`。odin 的 `ElasticsearchDataSource` 已统一为 `Gson`，建议保持统一。

**Gson 反序列化（ElasticsearchDataSourceImpl.java:465）：**
```java
private <T> T transformToPageData(SearchHit searchHit, Class<T> clazz) {
    T data = JsonUtils.jsonToObject(searchHit.getSourceAsString(), clazz);
    // ...
    return data;
}
```

**queryPageData 泛型约束（ElasticsearchDataSourceImpl.java:432）：**
```java
<T extends ElasticsearchDataTemplate> List<T> queryPage(...)
```
- `ElasticsearchDataTemplate` 需要提供 setId 能力（ES document _id 回写），但 odin 不需要这个能力，直接用无约束泛型即可。

**QMonitor 埋点模式：**
- 每个方法入口处 `QMonitor.recordOne("elasticsearch_data_source_XXX")` 记录次数
- 每个异常处 `QMonitor.recordOne("elasticsearch_data_source_XXX_error")` 记录异常

---

## 三、odin 项目现有 ES 基础设施

### 3.1 已实现能力

| 文件 | 能力 | 状态 |
|------|------|------|
| `ElasticsearchConfig.java` | RestHighLevelClient Bean（认证、超时、失败监听） | ✅ 可直接使用 |
| `ElasticsearchDataSource.java` | create / existIndex / batchInsert | ✅ 可直接使用 |
| `EsDemoService.java` | 索引检查创建 + 批量插入 + settings/mapping 动态配置 | ✅ 可作为参考模板 |

### 3.2 缺失能力（需新增）

| 方法 | 设计文档要求 | 对应 ErrorLocateService 参考 |
|------|------------|-----------------------------|
| `update()` | UpdateRequest + upsert（partial update） | **无参考**（superman 也没有，需要从零实现）|
| `bulkUpdate()` | Bulk 多个 UpdateRequest + upsert | **无参考**（需要从零实现）|
| `search()` | SearchSourceBuilder 搜索 | 参考 `queryPageData` + `queryTotalCount` |
| `queryPageData()` | 泛型分页查询 | 直接参考 `ElasticsearchDataSourceImpl.queryPageData` |
| `queryTotalCount()` | 总数统计 | 直接参考 `ElasticsearchDataSourceImpl.queryTotalCount` |

### 3.3 与 ErrorLocateService 对比汇总

| 维度 | ErrorLocateService（poseidon-superman） | odin 预期做法 |
|------|----------------------------------------|--------------|
| Client 获取 | @Resource private RestHighLevelClient | 同，已有 ElasticsearchConfig 提供 |
| DataSource 层 | 接口 + 实现分离 | 单类，可直接在 `ElasticsearchDataSource` 中新增方法 |
| 查询 | 参数直传 QueryBuilder | 同 |
| 分页 | queryPageData(泛型 + Gson 反序列化) | 同，可直接复用模式 |
| 响應 | 手动构建 response | 同 |
| 监控 | QMonitor 记录次数 + 耗时 | 同 |

---

## 四、增强 ElasticsearchDataSource 的实现方案

### 4.1 新增方法列表

在 `ElasticsearchDataSource.java`（odin 版）中新增以下方法：

```java
// ========== 写入 ==========

/**
 * 单条插入（覆盖写入）
 */
public <T> boolean insert(String index, String id, T data) {
    // 参考 superman ElasticsearchDataSourceImpl#insert
    // IndexRequest → source(GSON.toJson(data), XContentType.JSON) → HLRC.index()
}

/**
 * 单条部分更新（UpdateRequest + upsert）
 * 设计文档场景二、三需要
 */
public boolean update(String index, String id, Object doc) {
    // 全新实现，superman 没有此方法
    // UpdateRequest(index, id).doc(GSON.toJson(doc), XContentType.JSON).docAsUpsert(true)
    // → HLRC.update()
}

/**
 * 批量部分更新（Bulk UpdateRequest + upsert）
 * 设计文档场景二批量场景需要
 */
public boolean bulkUpdate(String index, List<UpdateRequest> requests) {
    // 全新实现
    // BulkRequest → forEach add → HLRC.bulk()
}

// ========== 查询 ==========

/**
 * 泛型分页查询
 * 参考 superman ElasticsearchDataSourceImpl#queryPageData
 */
public <T> List<T> queryPageData(String index, int pageSize, int pageNum,
                                 QueryBuilder queryBuilder, SortBuilder<?> sortBuilder,
                                 Class<T> clazz) {
    // SearchRequest → SearchSourceBuilder.query().from().size().sort() → HLRC.search()
    // → transformToPageData(searchHit, clazz) 反序列化
}

/**
 * 统计总数
 * 参考 superman ElasticsearchDataSourceImpl#queryTotalCount
 */
public long queryTotalCount(String index, QueryBuilder queryBuilder) {
    // SearchSourceBuilder.query(queryBuilder).size(0) → getTotalHits().value
    // 注意：不一定需要 aggregation
}

/**
 * 通用搜索（灵活 SearchSourceBuilder）
 * 设计文档场景四搜索需要
 */
public SearchResponse search(String index, SearchSourceBuilder builder) {
    // SearchRequest(index).source(builder) → HLRC.search()
}
```

### 4.2 新增引入

```java
import org.elasticsearch.action.update.UpdateRequest;
import org.elasticsearch.action.update.UpdateResponse;
import org.elasticsearch.search.SearchHit;
import org.elasticsearch.search.builder.SearchSourceBuilder;
import org.elasticsearch.search.sort.SortBuilder;
```

### 4.3 update 方法实现要点

```java
public boolean update(String index, String id, Object doc) {
    if (StringUtils.isBlank(index) || StringUtils.isBlank(id) || doc == null) {
        return false;
    }
    try {
        UpdateRequest request = new UpdateRequest()
                .index(index)
                .id(id)
                .doc(GSON.toJson(doc), XContentType.JSON)
                .docAsUpsert(true);  // 文档不存在时自动创建
        restHighLevelClient.update(request, RequestOptions.DEFAULT);
        return true;
    } catch (Exception e) {
        log.error("ES update error, index: {}, id: {}", index, id, e);
        QMonitor.recordOne("es_update_error");
        return false;
    }
}
```

### 4.4 search 方法实现要点

```java
public SearchResponse search(String index, SearchSourceBuilder builder) {
    try {
        SearchRequest request = new SearchRequest(index);
        request.source(builder);
        return restHighLevelClient.search(request, RequestOptions.DEFAULT);
    } catch (Exception e) {
        log.error("ES search error, index: {}", index, e);
        QMonitor.recordOne("es_search_error");
        return null;
    }
}
```

---

## 五、ContentSearchService 查询实现指引

### 5.1 对比 ErrorLocateService#list 的差异

| 环节 | ErrorLocateService | ContentSearchService（设计文档） | 差异说明 |
|------|-------------------|--------------------------------|---------|
| 查询构造 | BoolQueryBuilder ─ term/range | BoolQueryBuilder ─ terms(多选) + range(时间) | 多值过滤，无全文检索 |
| 排序 | 硬编码 `.sort("createTime", DESC)` | 动态：sortField + sortOrder 参数 | 需要 `SortBuilder` 动态构造 |
| 分页 | `from = (pageNum-1)*pageSize` | `from` 参数直接传入 | 更简单，from + size |
| 响应 | PageResponse（泛用型） | ContentSearchResponse（专用型） | 解耦搜索与通用响应 |

> 注：ES 索引不存储 `content_title`、`content_text`、`publish_url`，因此无全文检索和高亮能力。搜索基于过滤 + 排序 + 分页。

### 5.2 SearchSourceBuilder 构造模板

```java
SearchSourceBuilder builder = new SearchSourceBuilder();
BoolQueryBuilder filter = QueryBuilders.boolQuery();

// 精确过滤（全部走 filter，不参与评分）
if (CollectionUtils.isNotEmpty(request.getContentTypes())) {
    filter.filter(QueryBuilders.termsQuery("content_type", request.getContentTypes()));
}
if (CollectionUtils.isNotEmpty(request.getPlatforms())) {
    filter.filter(QueryBuilders.termsQuery("publish_platform", request.getPlatforms()));
}
if (StringUtils.isNotBlank(request.getBusinessLine())) {
    filter.filter(QueryBuilders.termQuery("business_line", request.getBusinessLine()));
}
if (CollectionUtils.isNotEmpty(request.getCities())) {
    filter.filter(QueryBuilders.termsQuery("city", request.getCities()));
}
if (CollectionUtils.isNotEmpty(request.getAiTags())) {
    filter.filter(QueryBuilders.termsQuery("ai_tag", request.getAiTags()));
}
if (request.getPublishTimeStart() != null) {
    filter.filter(QueryBuilders.rangeQuery("publish_time").gte(request.getPublishTimeStart()));
}

builder.query(filter);

// 排序
if (StringUtils.isNotBlank(request.getSortField())) {
    builder.sort(request.getSortField(), SortOrder.valueOf(request.getSortOrder().toUpperCase()));
} else {
    builder.sort("publish_time", SortOrder.DESC);
}

// 分页
builder.from(request.getFrom()).size(request.getSize());
```
```

### 5.3 结果解析模式

```java
SearchResponse response = elasticsearchDataSource.search("content_search_alias", builder);
if (response == null) {
    return ContentSearchResponse.empty();
}

SearchHits hits = response.getHits();
List<ContentSearchHit> hitList = new ArrayList<>();
for (SearchHit hit : hits.getHits()) {
    ContentSearchHit item = GSON.fromJson(hit.getSourceAsString(), ContentSearchHit.class);
    hitList.add(item);
}

ContentSearchResponse result = new ContentSearchResponse();
result.setHits(hitList);
result.setTotal(hits.getTotalHits().value);
result.setTook(response.getTook().getMillis());
return result;
```

---

## 六、ContentSearchDocAssembler 实现指引

### 6.1 MySQL 查询 SQL

设计文档给出的 JOIN SQL 需要注意：

ES 索引不存储 content_text 字段，因此无需 JOIN content_text 表。

### 6.2 分页全量扫描（全量重建场景）

```sql
SELECT cb.id, cb.content_id, ...
FROM content_base cb
LEFT JOIN content_label cl ON cl.base_id = cb.id
LEFT JOIN content_metrics cm ON cm.base_id = cb.id
ORDER BY cb.id
LIMIT #{offset}, #{pageSize}
```

---

## 七、实现步骤建议

### 7.1 实施顺序

| 步骤  | 内容                                                                                                   | 依赖       | 参考来源                                               |
| --- | ---------------------------------------------------------------------------------------------------- | -------- | -------------------------------------------------- |
| 1   | `ElasticsearchDataSource` 增强：insert + update + bulkUpdate + search + queryPageData + queryTotalCount | 无        | superman ElasticsearchDataSourceImpl + 设计文档第五章     |
| 2   | `ContentSearchDocument`、`ContentSearchRequest`、`ContentSearchResponse`、`ContentSearchHit`            | 步骤 1     | 设计文档第三章 + 第四章                                      |
| 3   | `ContentSearchDocAssembler`（MySQL 6 表 JOIN）                                                          | 无        | 设计文档第六章                                            |
| 4   | `ContentSearchIndexService`（写入服务：indexDocument / updateDocument / batchUpdateDocuments）              | 步骤 1 + 2 | ErrorLocateService#errorLocateBatchInsertES 批量写入模式 |
| 5   | `ContentSearchService`（搜索服务）                                                                         | 步骤 1 + 2 | ErrorLocateService#list 查询模式 + 本章第五节模板             |
| 6   | `RawContentSyncServiceImpl` 集成：sync() 成功后调用 ES 索引                                                    | 步骤 4     | 设计文档第十一章时序图                                        |
| 7   | 搜索 API Controller                                                                                    | 步骤 5     | ErrorLocateController#list                         |
| 8   | 定时修复/对账/重建任务                                                                                         | 步骤 3 + 4 | 设计文档第七章                                            |
| 9   | `IndexQConfig` 动态配置                                                                                  | 步骤 1     | EsDemoService#buildDefaultSettings + 设计文档第八章       |

### 7.2 各步骤文件清单

| 步骤 | 操作 | 文件 |
|------|------|------|
| 1 | **修改** | `infra/elasticsearch/ElasticsearchDataSource.java` |
| 2 | **新增** | `domain/entity/es/ContentSearchDocument.java`、`domain/request/es/ContentSearchRequest.java`、`domain/response/es/ContentSearchResponse.java`、`domain/response/es/ContentSearchHit.java` |
| 3 | **新增** | `service/es/ContentSearchDocAssembler.java` + `service/es/impl/ContentSearchDocAssemblerImpl.java` |
| 4 | **新增** | `service/es/ContentSearchIndexService.java` + `service/es/impl/ContentSearchIndexServiceImpl.java` |
| 5 | **新增** | `service/es/ContentSearchService.java` + `service/es/impl/ContentSearchServiceImpl.java` |
| 6 | **修改** | `service/raw/impl/RawContentServiceImpl.java`（triggerSync 中 syncDb + doPostSync 后调用 ES） |
| 7 | **新增或修改** | controller 层新增搜索端点 |
| 8 | **新增** | `task/EsRepairTask.java`、`task/EsReconcileTask.java`、`task/EsFullRebuildTask.java` |
| 9 | **新增** | `infra/qconfig/IndexQConfig.java` |

---

## 八、关键注意事项

### 8.1 UpdateRequest 在 ES 7.10.2 的兼容性

`new UpdateRequest(index, id)` 在 ES 7.10.2 中已被 `@Deprecated` 但可用。为规避告警，使用：

```java
UpdateRequest request = new UpdateRequest().index(index).id(id);
```

### 8.2 Gson 序列化 null 值问题

Gson 默认不序列化 null 字段。UpdateRequest 的 doc 中如果字段为 null，该字段会被 Gson 跳过（不在 JSON 中），进而导致 ES 侧该字段不被覆盖。这是符合预期的行为（partial update）。

但对于 IndexRequest（首次全量索引），确保字段有默认值（如空字符串、0 等），避免 ES 中字段不存在。

### 8.3 queryTotalCount 实现细节

参考 ElasticsearchDataSourceImpl#queryTotalCount 的做法：

```java
SearchSourceBuilder builder = new SearchSourceBuilder()
    .query(queryBuilder)
    .size(0);
    // 不需要 aggregation，直接取 totalHits 即可
SearchResponse response = restHighLevelClient.search(
    new SearchRequest(index).source(builder), RequestOptions.DEFAULT);
long totalCount = response.getHits().getTotalHits().value;
```

### 8.4 动态排序实现

ErrorLocateService 中排序是硬编码的，但 ContentSearchService 需要动态排序：

```java
if (StringUtils.isNotBlank(request.getSortField())) {
    SortOrder order = "desc".equalsIgnoreCase(request.getSortOrder())
            ? SortOrder.DESC : SortOrder.ASC;
    builder.sort(request.getSortField(), order);
} else {
    builder.sort("publish_time", SortOrder.DESC);
}
```

### 8.5 QMonitor 埋点规范

参考 ErrorLocateService 和 ElasticsearchDataSourceImpl，为每个 ES 操作记录：
- 成功次数：`QMonitor.recordOne("es_xxx")`
- 失败计数：`QMonitor.recordOne("es_xxx_error")`  
- 耗时记录：`QMonitor.recordOne("es_xxx", stopWatch.getTime())`