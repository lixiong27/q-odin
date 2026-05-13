# ES 查询加速技术方案

---

## 一、索引 Mapping

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

### Mapping 说明

| 设计点 | 说明 |
|------|------|
| `base_id` long | 仅存储，不用于 `_id` 以外的检索 |
| keyword 字段 | 枚举/过滤/聚合字段，精确匹配 |
| content_title text + keyword | text 分词检索，raw 子字段精确匹配 |
| content_text text | 正文全文检索 |
| ai_tag keyword | 数组类型，天然支持 term/terms/aggregations |
| publish_url index:false | 仅存储不索引，节省空间 |
| 指标字段 integer/float | 支持范围过滤、排序、聚合 |
| refresh_interval 5s | 准实时，批量场景可临时调大 |

---

## 二、三种场景策略

### 2.1 场景一：新内容入库

**触发时机**：新内容首次写入 MySQL 后

**策略**：全量文档索引

**伪代码**：

```
function onNewContent(base, text, images, metrics, label):
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

### 2.2 场景二：数仓指标每日批量更新

**触发时机**：T+1 数仓宽表同步，每日一次

**特点**：批量（可能数千~数万条），只更新 metrics 字段

**策略**：BULK partial update + 基础字段兜底

**伪代码**：

```
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
                total_reads:              m.totalReads,
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

### 2.3 场景三：AI 标签更新

**触发时机**：AI 任务完成后回调，单条或小批量，随机触发

**策略**：单条 partial update

**伪代码**：

```
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

## 三、异常处理方案

### 3.1 异常场景总览

| 场景 | 现象 | 影响 |
|------|------|------|
| 指标/标签更新时，upsert 创建了新文档且无基础字段 | 文档缺少 content_id、business_line 等 | 过滤/聚合漏掉该数据 |
| ES 集群短暂不可用 | 写入失败 | ES 数据落后 MySQL |
| BULK 部分失败 | 部分文档写入失败 | 部分数据不一致 |
| 程序 Bug 或网络超时 | 个别写入丢失 | 个别数据不一致 |

### 3.2 统一兜底：定时对账任务

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

### 3.3 查询不完整文档

**ES 查询条件**：基础字段为空或不存在

```
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

### 3.4 补全修复

```
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

### 3.5 全量重建（极端情况）

```
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

## 四、任务调度

| 任务 | 频率 | 说明 |
|------|------|------|
| 不完整文档修复 | 每 30 分钟 | 查询 + 补全缺失基础字段的文档 |
| 全量对账 | 每天凌晨 | MySQL 全量 base_id 与 ES `_id` 对比，补全缺失文档 |
| 全量重建 | 手动触发 | 仅极端情况使用 |

---


