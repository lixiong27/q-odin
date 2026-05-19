# ContentSearchServiceImpl 指标范围查询修复 + CTR/CVR 百分比归一化

## Context

内容库检索模块（`POST /api/content/search`）排序正常，指标范围查询失效。

**根因：** `ContentSearchServiceImpl.search()` 只实现了 `publish_time` 的范围查询，所有指标的 `addFilterRange` 缺失。

**百分比问题：** CTR/CVR ES 存 float 比值（`0.1654`），用户输入 `16.54`（百分比），后端需 ÷100 归一化。

## 改动清单

### 1. `ContentSearchServiceImpl.java`

`odin_server/mkt_odin_server_web/src/main/java/com/qunar/ug/flight/contact/odin/server/service/es/impl/ContentSearchServiceImpl.java`

- 追加 `addFilterRange(BoolQueryBuilder, String, Integer, Integer)`
- 追加 `addFilterRange(BoolQueryBuilder, String, Float, Float)`
- 在 `search()` 中 `publish_time` 之后追加 6 个指标范围调用
- CTR/CVR 调用 `convertPercentToRatio()` 归一化
- 追加 `convertPercentToRatio(Float)` 私有方法

### 2. `list.jsx`（前端）

`odin_node/src/pages/content/list.jsx`

- InputNumber 为 `m.type === 'percent'` 的指标加 `%` suffix

## 不修改

- `ESSearchServiceImpl.java` — 已有，不改
- `ContentSearchRequest.java` — 字段已齐全
- `ContentDictConfig.java` — MetricFilter.type 已存在

## 验证

1. `mvn compile` 通过
2. `ctrMin=16.54` → `0.1654` → ES `ctr >= 0.1654`
3. `totalImpressionsMin=1000` → ES `total_impressions >= 1000`
4. 前端 CTR/CVR 输入框显示 `%` 后缀