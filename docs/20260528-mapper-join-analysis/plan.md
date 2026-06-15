# Mapper 联表优化方案

> 目标：简化 MySQL 查询路径（去掉 content_label 条件 JOIN），聚合阶段拆为分表查询（去掉 3 表 LEFT JOIN），消除重复回查

---

## 一、现状分析

### MySQL 路径的问题

当前 MySQL 路由路径 `countByFilter` / `selectIdsByFilter` 虽然做了条件 JOIN（仅当 city/poi/aiTags 非空时 JOIN `content_label`），但根据路由规则，**只要这些字段有值就应该走 ES**。所以 `selectIdsByFilter` 中的条件 JOIN 逻辑永远不应触发——它是死代码。

同理，WHERE 子句中 `cl.city IN`、`cl.poi IN`、`cl.ai_tag IN` 也永远不会命中——因为路由规则决定了这些字段只会出现在 ES 请求中。

### 聚合阶段的问题

`selectEsDocByBaseIds` 是 3 表 LEFT JOIN：
```sql
FROM content_base cb
LEFT JOIN content_label cl ON cl.base_id = cb.id
LEFT JOIN content_metrics cm ON cm.base_id = cb.id
```

之后又通过 `backfillBaseFields` 冗余回查 `content_base`、`content_image`、`content_video`。

将 3 表 JOIN 拆为 3 次独立查询，可以：
- 消除冗余回查（不再需要 `backfillBaseFields`）
- 查询可并行化（每个表独立查询）
- 查询语句更简单，数据库执行计划更高效
- `content_label` 和 `content_metrics` 的 `base_id` 索引只需是普通索引而非覆盖索引

---

## 二、MySQL 路径简化

### 2.1 Mapper XML 改动

**文件：** `ContentBaseMapper.xml`

**`Filter_Where_Clause`** 移除 label 字段条件：
```sql
<sql id="Filter_Where_Clause">
    <where>
        <if test="contentTypes != null and contentTypes.size() > 0">
            AND cb.content_type IN ...
        </if>
        <if test="platforms != null and platforms.size() > 0">
            AND cb.publish_platform IN ...
        </if>
        <if test="businessLines != null and businessLines.size() > 0">
            AND cb.business_line IN ...
        </if>
        <if test="contentSources != null and contentSources.size() > 0">
            AND cb.content_source IN ...
        </if>
        <!-- 移除 cities / poi / aiTags / publishTimeStart / publishTimeEnd -->
    </where>
</sql>
```

**`selectIdsByFilter`** 移除条件 JOIN：
```sql
<select id="selectIdsByFilter" resultType="long">
    SELECT cb.id
    FROM content_base cb
    <!-- 移除条件 LEFT JOIN content_label -->
    <include refid="Filter_Where_Clause"/>
    ORDER BY cb.id ${sortOrder}
    LIMIT #{offset}, #{pageSize}
</select>
```

**`countByFilter`** 同样移除条件 JOIN：
```sql
<select id="countByFilter" resultType="long">
    SELECT COUNT(*)
    FROM content_base cb
    <!-- 移除条件 LEFT JOIN content_label -->
    <include refid="Filter_Where_Clause"/>
</select>
```

**移除 `EsDoc_Column_List` 和所有 `selectEsDoc*` 方法**（不再使用 3 表 JOIN）

### 2.2 Mapper Java 接口改动

**文件：** `ContentBaseMapper.java`

- `countByFilter` / `selectIdsByFilter` 去掉 cities / poi / aiTags / publishTimeStart / publishTimeEnd 参数
- 移除 `selectEsDocByContentId`（无调用方，可验证）
- 移除 `selectEsDocByBaseId`（改为分表查询）
- 移除 `selectEsDocByBaseIds`（改为分表查询）
- 移除 `selectEsDocByPage`（改为分表查询）

### 2.3 MySQLSearchServiceImpl 改动

**文件：** `MySQLSearchServiceImpl.java`

移除传 `null` 的 label/时间参数：
```java
long total = contentBaseMapper.countByFilter(
    request.getContentTypes(),
    request.getPlatforms(),
    request.getBusinessLines(),
    request.getContentSources()
    // 移除 null 参数
);
```

---

## 三、聚合阶段改为分表查询

### 3.1 新聚合架构

```
getBaseIds 之后：
                  ┌─────────────────────────┐
                  │  CompletableFuture.allOf │
                  │  (并行查询 3 表)          │
                  └────────┬───────┬────────┘
                           │       │
              ┌────────────┘   ┌───┴──────────────┐
              ▼                ▼                  ▼
    selectBatchByIds    labelMapper      metricsMapper
    (content_base)      .selectByBaseIds  .selectByBaseIds
         │                  │                  │
         └──────────────────┼──────────────────┘
                            ▼
                  ContentSearchDocument
                   (Java merge)
```

### 3.2 新增 Mapper 查询

**`ContentLabelMapper.java` + `ContentLabelMapper.xml`：**

```sql
<select id="selectByBaseIds" resultMap="BaseResultMap">
    SELECT <include refid="Base_Column_List"/>
    FROM content_label
    WHERE base_id IN
    <foreach collection="baseIds" item="id" open="(" separator="," close=")">
        #{id}
    </foreach>
</select>
```

**`ContentMetricsMapper.java` + `ContentMetricsMapper.xml`：**

`selectByBaseIds` 已存在，无需新增。

### 3.3 ContentSearchDocAssemblerImpl 改造

改为使用分表查询 + 并行化：

```java
public List<ContentSearchDocument> assembleByBaseIds(List<Long> baseIds) {
    // 3 表并行查询
    CompletableFuture<List<ContentBase>> baseFuture =
        CompletableFuture.supplyAsync(() -> contentBaseMapper.selectBatchByIds(baseIds));
    CompletableFuture<List<ContentLabel>> labelFuture =
        CompletableFuture.supplyAsync(() -> contentLabelMapper.selectByBaseIds(baseIds));
    CompletableFuture<List<ContentMetrics>> metricsFuture =
        CompletableFuture.supplyAsync(() -> contentMetricsMapper.selectByBaseIds(baseIds));

    CompletableFuture.allOf(baseFuture, labelFuture, metricsFuture).join();

    // Merge → ContentSearchDocument
    Map<Long, ContentBase> baseMap = ...;
    Map<Long, ContentLabel> labelMap = ...;
    Map<Long, ContentMetrics> metricsMap = ...;

    List<ContentSearchDocument> docs = new ArrayList<>();
    for (Long baseId : baseIds) {
        ContentSearchDocument doc = new ContentSearchDocument();
        // 填充 base 字段
        ContentBase base = baseMap.get(baseId);
        if (base != null) { ... }
        // 填充 label 字段
        ContentLabel label = labelMap.get(baseId);
        if (label != null) { ... }
        // 填充 metrics 字段
        ContentMetrics metrics = metricsMap.get(baseId);
        if (metrics != null) { ... }
        docs.add(doc);
    }
    return docs;
}
```

### 3.4 消除 backfillBaseFields

由于分表查询直接拿到了 `content_base` 的全部字段（含 `content_title`、`publish_url`），不再需要 `backfillBaseFields`。可以整体移除 `ContentDataAggregator` 这个中间类，将聚合逻辑直接放入 `ContentSearchDocAssemblerImpl`。

对于 coverUrl 逻辑，在 assembleByBaseIds 中同时查询 `content_image` / `content_video`：

```java
// 收集所有 imageId / videoId
List<Long> allImageIds = relations.stream()
    .map(ContentRelations::getImageIds).flatMap(List::stream).collect(...);
List<Long> allVideoIds = ...;

CompletableFuture<List<ContentImage>> imageFuture =
    CompletableFuture.supplyAsync(() -> contentImageMapper.selectBatchByIds(allImageIds));
CompletableFuture<List<ContentVideo>> videoFuture =
    CompletableFuture.supplyAsync(() -> contentVideoMapper.selectBatchByIds(allVideoIds));
```

## 四、影响范围

| 文件 | 改动类型 | 说明 |
|------|----------|------|
| `ContentBaseMapper.xml` | 修改 | 简化 `Filter_Where_Clause`、`selectIdsByFilter`、`countByFilter`；移除 `EsDoc_Column_List` 和全部 `selectEsDoc*` |
| `ContentBaseMapper.java` | 修改 | 调整 `countByFilter`/`selectIdsByFilter` 参数；移除 `selectEsDoc*` |
| `ContentLabelMapper.java` | 新增方法 | 加 `selectByBaseIds` |
| `ContentLabelMapper.xml` | 新增 SQL | 加 `selectByBaseIds` |
| `ContentMetricsMapper.java` | 已有 | `selectByBaseIds` 已存在 |
| `MySQLSearchServiceImpl.java` | 修改 | 移除 label/时间 null 参数 |
| `SearchRouterServiceImpl.java` | 不变 | 路由规则不变 |
| `ContentSearchDocAssemblerImpl.java` | 重写 | 3 表 JOIN → 3 次并行分表查询 + 合并 coverUrl |
| `ContentDataAggregator.java` | 移除 | 逻辑合并到 DocAssemblerImpl |
| `ContentResponseAssembler.java` | 不变 | 输入接口不变 |
| `ContentSearchController.java` | 不变 | Controller 层不变 |
| `ContentSearchSyncServiceImpl.java` | 修改 | `syncMetricsBatch` 调用了 `selectEsDocByBaseIds`，需改为分表 |

## 五、收益评估

| 指标 | 改造前 | 改造后 |
|------|--------|--------|
| MySQL 路径 SQL 数 | 2（count + selectIds，条件 JOIN label） | 2（count + selectIds，单表，更轻量） |
| 聚合阶段 SQL 数 | 4（1 次 3 表 JOIN + base回查 + image + video） | 3~5（3 表并行 + image + video，但可并行） |
| 总 SQL 数（搜索） | 5~6 次串行 | 5 次并行，总耗时 ≈ 最慢的单次查询 |
| `ContentDataAggregator` | 独立类 150 行 | 移除 |
| `backfillBaseFields` | 冗余回查 | 消除 |
| 3 表 JOIN | ← 随 data 增长性能衰减 | 3 次单表，索引简单，扩展性好 |

## 六、实施顺序

1. Mapper XML 简化（移除条件 JOIN + label 条件）
2. Java Mapper 接口调整（参数精简 + 新增 label.selectByBaseIds）
3. `ContentSearchDocAssemblerImpl` 重写（分表并行查询）
4. `ContentDataAggregator` 移除、调用方直连 DocAssembler
5. `ContentSearchSyncServiceImpl` 适配
6. 清理：删除 `EsDoc_Column_List` 及相关 SQL

每个步骤不依赖上一步的运行时结果，可以逐步提交、分段上线。