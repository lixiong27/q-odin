# content_dict 与前端展示一致性分析

## 1. detail.jsx 标签硬编码与 dict 不一致

detail.jsx 的 Descriptions 组件使用硬编码 label，与 content_dict.json 的 columns 定义不同。

| detail.jsx 标签 | dict columns 标签 | 是否一致 |
|---|---|---|
| 曝光量 | 总曝光 | 不一致 |
| 阅读量 | 总阅读 | 不一致 |
| 互动量 | 总互动 | 不一致 |
| 5s完播率 | 5秒完播率 | 不一致 |
| 3s完播率 | 3秒完播率 | 不一致 |
| 2s跳出率 | 2秒跳出率 | 不一致 |
| 潜新UV | 潜在新客UV | 不一致 |
| 归一新客量 | 新增归因用户 | 不一致 |
| 潜新CAC | 潜在新客CAC | 不一致 |
| 累计下单UV | 下单UV | 不一致 |
| 累计订单量 | 总订单 | 不一致 |

## 2. detail.jsx 字段展示格式与 dict 不一致

| 字段 | dict metricGroups format | detail.jsx 实际渲染 | 是否一致 |
|---|---|---|---|
| exposureToReadRatio | decimal | formatPercent（带 %） | **可能不一致**（取决于后端是否 *100） |

## 3. detail.jsx 缺少 dict 定义的指标字段

以下字段在 `metricGroups` 中有定义，但 detail.jsx 未渲染：

| 字段 | 所属分组 | 格式 |
|---|---|---|
| totalClicks | 曝光与点击 | integer |
| totalDownloads | 转化与下载 | integer |
| appDownloads | 转化与下载 | integer |
| newActivations | 用户与激活 | integer |
| newRegistrations | 用户与激活 | integer |

## 4. list.jsx FIELD_LABELS 标签与 dict 不一致（无运行时影响）

FIELD_LABELS 作为 dict.columns 的兜底，其中 5 个字段标签与 dict 不同。因 dict columns 正常加载时 `fieldLabelMap` 会覆盖，无运行时影响，但代码是脏数据。

| FIELD_LABELS key | FIELD_LABELS 标签 | dict columns 标签 |
|---|---|---|
| totalImpressions | 曝光量 | 总曝光 |
| totalClicks | 点击量 | 总点击 |
| totalReads | 阅读量 | 总阅读 |
| totalInteractions | 互动量 | 总互动 |
| totalDownloads | 下载次数 | 总下载 |

## 5. list.jsx 筛选条件单位标识不一致

metricFilters 高级筛选中，totalImpressions 和 totalOrders 有 `(K)` 后缀，但同为 formatCompact 展示的 attributedNewCustomers 没有 `(K)` 后缀。

| metricFilter key | dict type | 筛选后缀 | 表格展示方式 | 是否一致 |
|---|---|---|---|---|
| totalImpressions | integer | (K) | formatCompact | 一致 |
| totalOrders | integer | (K) | formatCompact | 一致 |
| attributedNewCustomers | integer | 无 | formatCompact | 不一致 |

## 6. list.jsx 整数字段展示方式不统一

dict columns 中 renderType 为 integer 的字段有 14 个，其中部分用 formatCompact（K/M 单位），部分用 toLocaleString（千分位）：

| 字段 | 展示方式 | 值示例 |
|---|---|---|
| totalImpressions | formatCompact | 1.5K |
| totalClicks | formatCompact | 1.5K |
| totalReads | formatCompact | 1.5K |
| totalInteractions | formatCompact | 1.5K |
| driveUv | formatCompact | 1.5K |
| orderUv | formatCompact | 1.5K |
| potentialNewUv | formatCompact | 1.5K |
| attributedNewCustomers | formatCompact | 1.5K |
| totalOrders | formatCompact | 1.5K |
| totalDownloads | toLocaleString | 1,500 |
| appDownloads | toLocaleString | 1,500 |
| newActivations | toLocaleString | 1,500 |
| newRegistrations | toLocaleString | 1,500 |