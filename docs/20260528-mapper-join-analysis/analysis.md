# Mapper 联表操作分析

> 分析目标：梳理所有 mapper 层 JOIN 及 Java 层模拟 JOIN（多次查询聚合），定位重复查询、冗余回查等可优化点

---

## 一、SQL 级 JOIN（Mapper XML）

### 1.1 EsDoc 系列：3 表 LEFT JOIN

```sql
-- selectEsDocByContentId / selectEsDocByBaseId / selectEsDocByBaseIds / selectEsDocByPage
SELECT <EsDoc_Column_List>
FROM content_base cb
LEFT JOIN content_label cl ON cl.base_id = cb.id
LEFT JOIN content_metrics cm ON cm.base_id = cb.id
```

**查询字段：** `content_base`（全部基础字段）+ `content_label`（city/poi/ai_tag）+ `content_metrics`（全部指标字段）

**调用方：**

| 方法 | 调用方 |
|------|--------|
| `selectEsDocByBaseId` | `ContentSearchDocAssemblerImpl.assembleByBaseId()` → `ContentSearchController.detail()`, `ContentSearchController.editTags()` |
| `selectEsDocByBaseIds` | `ContentSearchDocAssemblerImpl.assembleByBaseIds()` → `ContentDataAggregator.aggregate()` → `ContentSearchOrchestrator.retrieve()` (搜索主流程) |
| `selectEsDocByBaseIds` | `ContentSearchSyncServiceImpl.syncMetricsBatch()` (ES 同步) |
| `selectEsDocByContentId` | `ContentSearchDocAssemblerImpl.assembleByContentId()` (下游暂无调用) |
| `selectEsDocByPage` | `ContentSearchDocAssemblerImpl.assembleByPage()` → `ContentFullRebuildTask`, `ContentReconcileTask`, `ContentRepairTask` |

### 1.2 Filter 系列：条件性 LEFT JOIN

```sql
-- selectIdsByFilter / countByFilter
FROM content_base cb
[LEFT JOIN content_label cl ON cl.base_id = cb.id]  -- 仅当按 city/poi/aiTags 筛选时
```

**优化点：** 条件性 JOIN 已经做了——只有筛选条件涉及 `content_label` 字段时才 JOIN，不会无谓扫描 label 表。

**调用方：**

| 方法 | 调用方 |
|------|--------|
| `selectIdsByFilter` | `MySQLSearchServiceImpl.search()` (搜索路由 → MySQL) |
| `countByFilter` | `MySQLSearchServiceImpl.search()` (搜索路由 → MySQL) |

### 1.3 结论：SQL JOIN 的现状

- **`content_label`**：无 UNIQUE 索引（`base_id` 应为 UNIQUE），LEFT JOIN 时 `cb.id = cl.base_id` 走索引状态待确认
- **`content_metrics`**：同上，`base_id` 索引状态待确认
- **数据量级：** 3 表 LEFT JOIN 扫描 20w 行时性能可接受；百万级需核实索引

---

## 二、Java 层模拟 JOIN（多次查询聚合）

### 2.1 `ContentDataAggregator.aggregate()`（搜索主流程）

```
1. docAssembler.assembleByBaseIds(baseIds)
   → ContentBaseMapper.selectEsDocByBaseIds(baseIds)   ← 3表 JOIN
2. backfillBaseFields(documents)
   ↓
   → ContentBaseMapper.selectBatchByIds(ids)           ← 第2次查 content_base
   → ContentImageMapper.selectBatchByIds(allImageIds)  ← 查封面图
   → ContentVideoMapper.selectBatchByIds(allVideoIds)  ← 查视频封面
```

**冗余分析：** `EsDoc_Column_List` 已经包含了 `cb.content_title` 和 `cb.publish_url`，`mapToDocument()` 也会将其设置到 `ContentSearchDocument。但 backfillBaseFields 又通过 selectBatchByIds` 重新查询了 `content_base`，然后重新 `setContentTitle()` 和 `setPublishUrl()`。

**这是冗余回查**——EsDoc JOIN 结果中已有这两个字段的值，`mapToDocument` 也已正确赋值。`backfillBaseFields` 只是覆写了相同的值。

> 推测历史原因：ES 索引早期不存储 title/url，所以聚合层回查 MySQL 补全。但 EsDoc SQL 查询走的是 MySQL，本身就包含了全部字段，回查就没有必要了。

### 2.2 `DataAggregator.fillBaseFields()`（搜索命中结果回填）

```java
// 用于旧搜索流程的批量回填
List<ContentBase> bases = contentBaseMapper.selectBatchByIds(baseIds);
// → 按需查 content_image / content_video 取封面
```

**现状：** 现在搜索主流程走的是 `ContentDataAggregator` 而非 `DataAggregator`。`fillBaseFields` 仅在 `ContentSearchServiceImpl.filter()` (快捷过滤接口) 中调用。

### 2.3 `DataAggregator.assemblePreview()`（预览弹窗）

| # | 查询 | 说明 |
|---|------|------|
| 1 | `contentBaseMapper.selectById(baseId)` | 查单行 base |
| 2 | `contentVideoMapper.selectBatchByIds(videoIds)` | 取视频 URL |
| 3 | `contentImageMapper.selectBatchByIds(imageIds)` | 取图片 URL |
| 4 | `contentTextMapper.selectBatchByIds(textIds)` | 取正文 |

**这是合理的小范围聚合**——仅 1 条内容，媒体资源分散在不同子表中，按需查无法避免。

### 2.4 `TagAssembler` 启动时全量加载

```java
@PostConstruct
tagCategoryMapper.selectAll();    // 全量表
tagLeafMapper.selectAll();        // 全量表
```

**分析：** 这是启动时内存加载，每日一次，可接受。但如果标签表数据量极大（>10w 行），可以考虑懒加载 + 缓存。

---

## 三、联表操作全景图

```
┌─────────────────────────────────────────────────────────────────────┐
│                   内容检索主流程 (ContentSearchOrchestrator)         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  POST /api/content/search                                            │
│    ↓                                                                │
│  SearchRouterService.route()                                        │
│    ├── MySQL → MySQLSearchServiceImpl.search()                      │
│    │    ├── countByFilter (条件JOIN content_label)                  │
│    │    └── selectIdsByFilter (条件JOIN content_label)              │
│    └── ES    → EsSearchService (未实现，占位)                        │
│    ↓                                                                │
│  ContentDataAggregator.aggregate(baseIds)                           │
│    ├── selectEsDocByBaseIds  (3表 JOIN)                             │
│    ├── selectBatchByIds      (content_base，冗余回查)               │
│    ├── selectBatchByIds      (content_image，封面)                  │
│    └── selectBatchByIds      (content_video，视频封面)              │
│    ↓                                                                │
│  ContentSecurityFilter.filter()                                     │
│    ↓                                                                │
│  ContentResponseAssembler.assemble()                                │
│    → 字典映射 + 响应组装                                             │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                   内容详情 (ContentSearchController)                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  GET /api/content/detail?baseId=X                                    │
│    ↓                                                                │
│  docAssembler.assembleByBaseId → selectEsDocByBaseId (3表 JOIN)     │
│    ↓                                                                │
│  dataAggregator.assemblePreview (4次查询: base+image+video+text)    │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                   快捷过滤 (filter)                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  GET /api/content/filter                                             │
│    ↓                                                                │
│  contentSearchService.filter()                                      │
│    └── DataAggregator.fillBaseFields (回查 base + image + video)     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 单次「内容检索」的总 SQL 开销

| # | SQL | 类型 | 说明 |
|---|-----|------|------|
| 1 | `countByFilter` | 条件 JOIN | 分页总数 |
| 2 | `selectIdsByFilter` | 条件 JOIN | 获取 baseIds |
| 3 | `selectEsDocByBaseIds` | 3表 LEFT JOIN | 全量数据 |
| 4 | `selectBatchByIds(content_base)` | 单表 IN查询 | **冗余** — 与 #3 重复 |
| 5 | `selectBatchByIds(content_image)` | 单表 IN查询 | 封面图 |
| 6 | `selectBatchByIds(content_video)` | 单表 IN查询 | 视频封面 |

**最低 5 次 SQL 查询完成一次内容检索。（#4 可消除）**

---

## 四、风险与优化建议

### P0 风险：联合查询缺少索引确认

**问题：** `content_label` 和 `content_metrics` 的 LEFT JOIN 条件是 `ON cl.base_id = cb.id`，这两个表的 `base_id` 是否有索引？

**建议：** 确认 DDL，确保：

```sql
ALTER TABLE content_label ADD UNIQUE INDEX idx_base_id (base_id);
ALTER TABLE content_metrics ADD UNIQUE INDEX idx_base_id (base_id);
```

### P1 优化：消除冗余回查

**涉及文件：** `ContentDataAggregator.java`

**当前：**
```java
// 1. 3表 JOIN 已查出 content_title / publish_url
List<ContentSearchDocument> documents = docAssembler.assembleByBaseIds(baseIds);
// 2. 又回查 content_base 覆盖相同的值 ← 冗余
backfillBaseFields(documents);
```

**建议：**
- 移除 `backfillBaseFields` 中对 `content_base` 的额外查询（`selectBatchByIds`）
- 封面图逻辑（image/video coverUrl）可以保留，但移到 `ContentResponseAssembler` 中按需处理，或合并到 EsDoc_Column_List 中

**收益：** 每次搜索减少 1 次 SQL 查询，且避免回查 `content_image`/`content_video`（可在 N 条结果时产生 2N 条 IN 查询的数据传输量）。

### P1 优化：检测 `DataAggregator.fillBaseFields` 是否可合并

**现状：** `fillBaseFields` 是 `ContentDataAggregator.backfillBaseFields` 的近似重复（copy-paste 风格）。两者逻辑几乎相同，只是操作的对象不同（Hit vs Document）。

**建议：** 抽取公共的「根据 baseIds 查询 coverUrl 回填」方法，避免两份代码不一致。

### P2 优化：驳回数据库内容字典映射

**问题：** `publishPlatform` 和 `businessLine` 的字典映射现在已经用 Java 内存查询实现了（`ContentDictService`），但数据库中存储的仍是原始值。如果未来字典映射表放在数据库中（字典表 + JOIN），需要考虑 JOIN 性能。

**建议：** 当前 Java 内存方案已足够，不需要改为 SQL JOIN。保持现状。

### P2 优化：TagAssembler 全量加载

**问题：** `TagAssembler` 在 `@PostConstruct` 时全量加载 `tag_category` 和 `tag_leaf` 表。如果标签数量增长到 10w+，启动加载和内存占用会成问题。

**建议：** 当前可以接受。如未来标签量大，可改为懒加载 + 定时刷新缓存。

### P3 优化：countByFilter + selectIdsByFilter 总是成对出现

**问题：** `MySQLSearchServiceImpl.search()` 总是先 `countByFilter` 再 `selectIdsByFilter`，两次查询的 WHERE 条件完全一样。MySQL 需要两次解析执行。

**建议：** 使用 `SQL_CALC_FOUND_ROWS` 或在一个查询中用 `COUNT(*) OVER()` 窗口函数，但 MySQL 5.7 对 `SQL_CALC_FOUND_ROWS` 支持存在性能争议。先维持现状，仅作记录。

---

## 五、总结

| 维度 | 结论 |
|------|------|
| SQL JOIN 复杂度 | 中等，最高 3 表 LEFT JOIN |
| 冗余查询 | `backfillBaseFields` 对 content_base 的回查是冗余的 |
| 重复代码 | `backfillBaseFields` vs `fillBaseFields` — 逻辑高度重复 |
| 索引风险 | content_label.base_id / content_metrics.base_id 需要确认索引 |
| 整体并发 | 单次搜索 5-6 次 SQL，对几百 QPS 场景 MySQL 可承受 |
| 短期行动项 | ①确认索引 ②消除冗余回查 ③合并回填逻辑 |