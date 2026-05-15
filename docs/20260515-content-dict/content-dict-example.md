# 内容字典配置示例

## 说明

本配置对应 QConfig `content_dict.json`，用于内容模块的前端动态渲染（选项列表、列配置、指标分组等）。

## 配置示例

```json
{
  "contentTypes": [
    { "label": "图文帖", "value": "图文帖" },
    { "label": "短视频", "value": "短视频" },
    { "label": "长视频", "value": "长视频" },
    { "label": "图片", "value": "图片" }
  ],
  "publishPlatforms": [
    { "label": "微信公众号", "value": "微信公众号" },
    { "label": "抖音", "value": "抖音" },
    { "label": "小红书", "value": "小红书" },
    { "label": "微博", "value": "微博" },
    { "label": "B站", "value": "B站" },
    { "label": "视频号", "value": "视频号" },
    { "label": "官网", "value": "官网" },
    { "label": "其他", "value": "其他" }
  ],
  "businessLines": [
    { "label": "酒店", "value": "酒店" },
    { "label": "机票", "value": "机票" },
    { "label": "火车票", "value": "火车票" },
    { "label": "用车", "value": "用车" },
    { "label": "度假", "value": "度假" },
    { "label": "门票", "value": "门票" },
    { "label": "餐饮", "value": "餐饮" },
    { "label": "综合", "value": "综合" }
  ],
  "sortOptions": [
    { "label": "发布时间", "value": "publish_time" },
    { "label": "总曝光", "value": "total_impressions" },
    { "label": "总点击", "value": "total_clicks" },
    { "label": "总阅读", "value": "total_reads" },
    { "label": "总互动", "value": "total_interactions" },
    { "label": "完播率", "value": "completion_rate" },
    { "label": "CPM", "value": "cpm" },
    { "label": "CTR", "value": "ctr" },
    { "label": "CVR", "value": "cvr" },
    { "label": "APP下载", "value": "app_downloads" },
    { "label": "新增激活", "value": "new_activations" },
    { "label": "新增注册", "value": "new_registrations" },
    { "label": "GMV", "value": "total_orders" },
    { "label": "总下载", "value": "total_downloads" }
  ],
  "suggestionFields": [
    {
      "field": "contentSource",
      "label": "内容来源",
      "commonValues": ["UGC", "PGC", "OGC", "AIGC"]
    },
    {
      "field": "productionTeam",
      "label": "生产团队",
      "commonValues": ["新媒体部", "品牌部", "市场部", "运营部", "外包团队"]
    },
    {
      "field": "operationProject",
      "label": "运营项目",
      "commonValues": ["暑期活动", "双十一", "新年特辑", "品牌宣传", "日常运营"]
    },
    {
      "field": "placementPosition",
      "label": "投放版位",
      "commonValues": ["首页推荐", "搜索页", "详情页", "个人中心", "发现页"]
    },
    {
      "field": "poi",
      "label": "POI",
      "commonValues": []
    }
  ],
  "metricFilters": [
    { "key": "totalImpressions", "label": "总曝光", "type": "integer" },
    { "key": "ctr", "label": "CTR", "type": "float", "unit": "%" },
    { "key": "cvr", "label": "CVR", "type": "float", "unit": "%" },
    { "key": "totalOrders", "label": "总订单", "type": "integer" },
    { "key": "attributedNewCustomers", "label": "新增归因用户", "type": "integer" },
    { "key": "newCustomerCac", "label": "新客CAC", "type": "float" }
  ],
  "metricGroups": [
    {
      "title": "曝光与点击",
      "fields": [
        { "key": "totalImpressions", "label": "总曝光", "format": "integer" },
        { "key": "totalClicks", "label": "总点击", "format": "integer" },
        { "key": "totalReads", "label": "总阅读", "format": "integer" },
        { "key": "totalInteractions", "label": "总互动", "format": "integer" },
        { "key": "ctr", "label": "CTR", "format": "percent" },
        { "key": "cvr", "label": "CVR", "format": "percent" },
        { "key": "cpm", "label": "CPM", "format": "decimal" }
      ]
    },
    {
      "title": "播放与跳出",
      "fields": [
        { "key": "completionRate", "label": "完播率", "format": "percent" },
        { "key": "threeSecCompletionRate", "label": "3秒完播率", "format": "percent" },
        { "key": "fiveSecCompletionRate", "label": "5秒完播率", "format": "percent" },
        { "key": "twoSecBounceRate", "label": "2秒跳出率", "format": "percent" },
        { "key": "exposureToReadRatio", "label": "曝光-阅读比", "format": "decimal" }
      ]
    },
    {
      "title": "转化与下载",
      "fields": [
        { "key": "totalOrders", "label": "总订单", "format": "integer" },
        { "key": "orderUv", "label": "下单UV", "format": "integer" },
        { "key": "totalDownloads", "label": "总下载", "format": "integer" },
        { "key": "appDownloads", "label": "APP下载", "format": "integer" },
        { "key": "driveUv", "label": "引流UV", "format": "integer" }
      ]
    },
    {
      "title": "用户与激活",
      "fields": [
        { "key": "newActivations", "label": "新增激活", "format": "integer" },
        { "key": "newRegistrations", "label": "新增注册", "format": "integer" },
        { "key": "attributedNewCustomers", "label": "新增归因用户", "format": "integer" },
        { "key": "newCustomerCac", "label": "新客CAC", "format": "decimal" },
        { "key": "potentialNewUv", "label": "潜在新客UV", "format": "integer" },
        { "key": "potentialNewCac", "label": "潜在新客CAC", "format": "decimal" }
      ]
    }
  ],
  "columns": [
    { "field": "baseId", "label": "ID", "renderType": "text", "defaultField": false },
    { "field": "contentId", "label": "内容ID", "renderType": "text", "defaultField": false },
    { "field": "contentTitle", "label": "标题", "renderType": "link", "defaultField": true },
    { "field": "publishUrl", "label": "发布链接", "renderType": "link", "defaultField": false },
    { "field": "contentType", "label": "内容类型", "renderType": "tag", "defaultField": true },
    { "field": "publishPlatform", "label": "发布平台", "renderType": "tag", "defaultField": true },
    { "field": "publishTime", "label": "发布时间", "renderType": "text", "defaultField": true },
    { "field": "businessLine", "label": "业务线", "renderType": "tag", "defaultField": false },
    { "field": "contentSource", "label": "内容来源", "renderType": "text", "defaultField": false },
    { "field": "productionTeam", "label": "生产团队", "renderType": "text", "defaultField": false },
    { "field": "operationProject", "label": "运营项目", "renderType": "text", "defaultField": false },
    { "field": "placementPosition", "label": "投放版位", "renderType": "text", "defaultField": false },
    { "field": "city", "label": "城市", "renderType": "tag", "defaultField": false },
    { "field": "poi", "label": "POI", "renderType": "tag", "defaultField": false },
    { "field": "aiTag", "label": "AI标签", "renderType": "tagList", "defaultField": false },
    { "field": "totalImpressions", "label": "总曝光", "renderType": "integer", "defaultField": false },
    { "field": "totalClicks", "label": "总点击", "renderType": "integer", "defaultField": false },
    { "field": "totalReads", "label": "总阅读", "renderType": "integer", "defaultField": false },
    { "field": "totalInteractions", "label": "总互动", "renderType": "integer", "defaultField": false },
    { "field": "completionRate", "label": "完播率", "renderType": "percent", "defaultField": false },
    { "field": "threeSecCompletionRate", "label": "3秒完播率", "renderType": "percent", "defaultField": false },
    { "field": "fiveSecCompletionRate", "label": "5秒完播率", "renderType": "percent", "defaultField": false },
    { "field": "twoSecBounceRate", "label": "2秒跳出率", "renderType": "percent", "defaultField": false },
    { "field": "cpm", "label": "CPM", "renderType": "decimal", "defaultField": false },
    { "field": "ctr", "label": "CTR", "renderType": "percent", "defaultField": false },
    { "field": "cvr", "label": "CVR", "renderType": "percent", "defaultField": false },
    { "field": "appDownloads", "label": "APP下载", "renderType": "integer", "defaultField": false },
    { "field": "newActivations", "label": "新增激活", "renderType": "integer", "defaultField": false },
    { "field": "newRegistrations", "label": "新增注册", "renderType": "integer", "defaultField": false },
    { "field": "driveUv", "label": "引流UV", "renderType": "integer", "defaultField": false },
    { "field": "exposureToReadRatio", "label": "曝光-阅读比", "renderType": "decimal", "defaultField": false },
    { "field": "potentialNewUv", "label": "潜在新客UV", "renderType": "integer", "defaultField": false },
    { "field": "potentialNewCac", "label": "潜在新客CAC", "renderType": "decimal", "defaultField": false },
    { "field": "attributedNewCustomers", "label": "新增归因用户", "renderType": "integer", "defaultField": false },
    { "field": "newCustomerCac", "label": "新客CAC", "renderType": "decimal", "defaultField": false },
    { "field": "orderUv", "label": "下单UV", "renderType": "integer", "defaultField": false },
    { "field": "totalOrders", "label": "总订单", "renderType": "integer", "defaultField": false },
    { "field": "totalDownloads", "label": "总下载", "renderType": "integer", "defaultField": true }
  ]
}
```

## 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `contentTypes` | `OptionItem[]` | 内容类型下拉选项 |
| `publishPlatforms` | `OptionItem[]` | 发布平台下拉选项 |
| `businessLines` | `OptionItem[]` | 业务线下拉选项 |
| `sortOptions` | `SortOption[]` | 排序选择项，value 映射 ES 排序字段 |
| `suggestionFields` | `SuggestionField[]` | 提示型字段，前端用 AutoComplete，可输入 |
| `metricFilters` | `MetricFilter[]` | 高级筛选中指标范围过滤配置 |
| `metricGroups` | `MetricGroup[]` | 详情页数据指标分组展示配置 |
| `columns` | `ColumnConfig[]` | 表格列配置，含渲染类型和默认展示 |

### 类型定义

**OptionItem** — `{ label: string, value: string }`

**SortOption** — `{ label: string, value: string }`

**SuggestionField** — `{ field: string, label: string, commonValues: string[] }`

**MetricFilter** — `{ key: string, label: string, type: "integer" | "float", unit?: string }`

**MetricGroup** — `{ title: string, fields: MetricField[] }`

**MetricField** — `{ key: string, label: string, format: "integer" | "decimal" | "percent" }`

**ColumnConfig** — `{ field: string, label: string, renderType: string, defaultField: boolean }`

### renderType 取值

- `text` — 纯文本
- `tag` — Tag 标签
- `tagList` — 多个 Tag（JSON 数组）
- `link` — 链接（标题显示文本，其他显示"查看"）
- `integer` — 整数（千分位）
- `decimal` — 小数（保留两位）
- `percent` — 百分比（乘 100 加 %）