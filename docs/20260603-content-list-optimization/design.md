# 内容敏感字段隐藏方案

## 背景

内容模块的 CPM、新客 CAC、潜新 CAC 属于敏感业务数据，需要在内容列表页（list）和详情页（detail）统一隐藏。要求做到配置驱动、后端统一拦截、前端零硬编码。

---

## 方案总览

以 QConfig `content_dict.json` 的 `columns[].disabled` 作为"唯一真相源"，后端和前端统一从此处读取隐藏判定。

```
                    content_dict.json (QConfig)
                    columns[].disabled = true
                           │
                           ▼
                    ContentDictService
                           │
              ┌────────────┼──────────────────────────┐
              ▼            ▼                          ▼
       ContentResponse   Controller               前端 /api/content/dict
       Assembler         .convertToDetail()           │
       .buildFieldMeta()  │                          ▼
       .convertToHit()    │              dict.columns 含 disabled
              │           │                   │
              ▼           ▼                   ├── list: fieldLabelMap 过滤
       ContentSearchHit  ContentDetail         │   → 列选项/筛选消失
       ContentDetailResponse                   │
       (disabled 字段设 null，                   └── detail: disabledFields 集合
        非 disabled 字段原样保留)                     → 整行跳过渲染
```

### 关键原则

| 原则 | 说明 |
|------|------|
| **隐藏判定 = columns[].disabled** | 不依赖字段值是否为 null/0，数据本身为 null 正常显示 `-`，只有 disabled 的字段才隐藏 |
| **后端掩码 = 安全层** | disabled 字段值设 null，防止 API 被直接调用窃取数据；非 disabled 字段原样保留 |
| **前端隐藏 = UI 层** | 从 dict.columns 读取 disabled 标志，在渲染层跳过隐藏字段，不依赖后端返回值 |

---

## 数据存储层：ColumnConfig 新增 disabled 字段

```java
// ContentDictConfig.java
public static class ColumnConfig {
    private String field;
    private String label;
    private String renderType;
    private boolean defaultField;
    private boolean disabled;       // ← 新增，默认 false
}
```

---

## QConfig 配置示例

```json
{
  "columns": [
    { "field": "baseId", "label": "内容ID", "renderType": "text", "defaultField": true },
    { "field": "content", "label": "内容", "renderType": "custom", "defaultField": true },
    { "field": "cpm", "label": "CPM", "renderType": "decimal", "defaultField": false, "disabled": true },
    { "field": "newCustomerCac", "label": "新客CAC", "renderType": "decimal", "defaultField": false, "disabled": true },
    { "field": "potentialNewCac", "label": "潜新CAC", "renderType": "decimal", "defaultField": false, "disabled": true },
    { "field": "contentSource", "label": "内容来源", "renderType": "text", "defaultField": true }
  ]
}
```

---

## 后端改动

### 1. ContentFieldMaskService（新建）

安全层：读取 `columns[].disabled`，对响应体字段值设 null。

```java
/**
 * 内容字段掩码服务
 * 
 * 从 content_dict.json 的 columns[].disabled 读取禁用字段列表，
 * 在响应组装和详情查询后做数据掩码，防止 API 直接调用泄露敏感数据。
 * disabled 状态变更通过 QConfig 热加载即时生效。
 * 
 * 注意：掩码是安全层，与前端展示解耦。
 * 前端隐藏判定同样基于 disabled 标志，而非字段值是否为 null。
 */
@Service
public class ContentFieldMaskService {

    @Resource
    private ContentDictService contentDictService;

    public Set<String> getDisabledFieldKeys() {
        List<ContentDictConfig.ColumnConfig> columns = contentDictService.getColumns();
        if (columns == null) return Collections.emptySet();
        return columns.stream()
                .filter(ContentDictConfig.ColumnConfig::isDisabled)
                .map(ContentDictConfig.ColumnConfig::getField)
                .collect(Collectors.toSet());
    }

    /**
     * 对 ContentSearchHit 做掩码（列表搜索结果）
     */
    public void maskHit(ContentSearchHit hit) {
        Set<String> disabled = getDisabledFieldKeys();
        if (disabled.isEmpty() || hit == null) return;

        if (disabled.contains("cpm"))               hit.setCpm(null);
        if (disabled.contains("newCustomerCac"))    hit.setNewCustomerCac(null);
        if (disabled.contains("potentialNewCac"))   hit.setPotentialNewCac(null);
        // ↑ 后续新增 disabled 字段在此追加
    }

    /**
     * 对 ContentDetailResponse 做掩码（详情查询结果）
     */
    public void maskDetail(ContentDetailResponse resp) {
        Set<String> disabled = getDisabledFieldKeys();
        if (disabled.isEmpty() || resp == null) return;

        if (disabled.contains("cpm"))               resp.setCpm(null);
        if (disabled.contains("newCustomerCac"))    resp.setNewCustomerCac(null);
        if (disabled.contains("potentialNewCac"))   resp.setPotentialNewCac(null);
    }
}
```

### 2. ContentResponseAssembler.buildFieldMeta() — fieldMeta 过滤

```diff
 private Map<String, FieldMeta> buildFieldMeta() {
     Map<String, FieldMeta> meta = new LinkedHashMap<>();
     List<ContentDictConfig.ColumnConfig> columns = contentDictService.getColumns();
     if (columns != null) {
         for (ContentDictConfig.ColumnConfig col : columns) {
+            if (col.isDisabled()) continue;     // ← 跳过 disabled 列
             meta.put(col.getField(), new FieldMeta(col.getLabel(), col.isDefaultField()));
         }
     }
     return meta;
 }
```

**效果**：`fieldMeta` 不包含 disabled 字段 → 前端 `fieldLabelMap` 不包含 → 自定义列选项自动消失。

### 3. ContentResponseAssembler.convertToHit() — 列表结果掩码

```diff
 private ContentSearchHit convertToHit(ContentSearchDocument doc) {
     // ... 现有字段赋值 ...
+    maskService.maskHit(hit);    // ← 末尾追加掩码
     return hit;
 }
```

### 4. ContentSearchController.convertToDetail() — 详情结果掩码

```diff
 private ContentDetailResponse convertToDetail(ContentSearchDocument doc) {
     // ... 现有字段赋值 ...
+    maskService.maskDetail(resp);    // ← 末尾追加掩码
     return resp;
 }
```

### 5. ESSearchServiceImpl.SORT_WHITELIST — 排序白名单过滤

```diff
 private static final Set<String> SORT_WHITELIST = new HashSet<String>() {{
-    add("cpm");
     // ...
 }};
```

**效果**：通过 API 传 `sortField=cpm` 不再生效，降级为默认 `publish_time DESC`。

---

## 前端改动

### 1. list.jsx — 从 dict 读取 disabled 标志, 替代 HIDDEN_METRIC_KEYS 硬编码

```jsx
// 从 dict.columns 提取 disabled 字段集合（替代 HIDDEN_METRIC_KEYS）
const disabledFields = React.useMemo(() => {
    if (!dict?.columns) return new Set();
    return new Set(dict.columns.filter(c => c.disabled).map(c => c.field));
}, [dict]);
```

**a) fieldLabelMap 过滤 — 自定义列选项自动消失**

```diff
 const fieldLabelMap = React.useMemo(() => {
     if (!dict?.columns) return {};
     const map = {};
-    dict.columns.forEach(col => { map[col.field] = col.label; });
+    dict.columns.forEach(col => {
+        if (!col.disabled) {                // ← 跳过 disabled
+            map[col.field] = col.label;
+        }
+    });
     return map;
 }, [dict]);
```

**b) displayFields 兜底过滤 localStorage 残留**

```diff
 const displayFields = (visibleFields || DEFAULT_FIELDS).filter(
-    f => !HIDDEN_METRIC_KEYS.includes(f)
+    f => fieldLabelMap[f] || DEFAULT_FIELDS.includes(f)
 );
```

> `fieldLabelMap` 已过滤 disabled 字段，localStorage 中缓存的旧列配置即使包含这些字段也会被过滤掉。

**c) 高级筛选 metricFilters 过滤**

```diff
-{(dict?.metricFilters || []).filter(m => !HIDDEN_METRIC_KEYS.includes(m.key)).map(m => (
+{(dict?.metricFilters || []).filter(m => !disabledFields.has(m.key)).map(m => (
```

**d) 移除 HIDDEN_METRIC_KEYS 常量定义**

---

### 2. detail.jsx — 从 dict 读取 disabledFields，条件渲染

core: **隐藏判定依据是 `dict.columns[].disabled`，与字段值是否为 null 无关**

```jsx
// 从 dict.columns 提取 disabled 字段集合
const detailDisabledFields = React.useMemo(() => {
    if (!dict?.columns) return new Set();
    return new Set(dict.columns.filter(c => c.disabled).map(c => c.field));
}, [dict]);
```

每个 `Descriptions.Item` 外套一层条件跳过：

```jsx
<Descriptions column={1} size="small" bordered>
    <Descriptions.Item label="曝光量">{formatCompact(detail.totalImpressions)}</Descriptions.Item>
    {isVideo ? (
        <>
            <Descriptions.Item label="完播率">{formatPercent(detail.completionRate)}</Descriptions.Item>
            {/* ... 其他视频指标 ... */}
        </>
    ) : (
        <Descriptions.Item label="阅读量">{formatCompact(detail.totalReads)}</Descriptions.Item>
    )}
    <Descriptions.Item label="互动量">{formatCompact(detail.totalInteractions)}</Descriptions.Item>
    {!detailDisabledFields.has('cpm') && (
        <Descriptions.Item label="CPM">{formatDecimal(detail.cpm)}</Descriptions.Item>
    )}
    <Descriptions.Item label="CTR">{formatPercent(detail.ctr)}</Descriptions.Item>
    <Descriptions.Item label="CVR">{formatPercent(detail.cvr)}</Descriptions.Item>
</Descriptions>
```

```jsx
<Descriptions column={1} size="small" bordered>
    <Descriptions.Item label="引流UV">{formatCompact(detail.driveUv)}</Descriptions.Item>
    <Descriptions.Item label="阅读/曝光引流比">{formatDecimal(detail.exposureToReadRatio)}</Descriptions.Item>
    <Descriptions.Item label="潜新UV">{formatCompact(detail.potentialNewUv)}</Descriptions.Item>
    <Descriptions.Item label="归一新客量">{formatCompact(detail.attributedNewCustomers)}</Descriptions.Item>
    {!detailDisabledFields.has('newCustomerCac') && (
        <Descriptions.Item label="新客CAC">{formatDecimal(detail.newCustomerCac)}</Descriptions.Item>
    )}
    {!detailDisabledFields.has('potentialNewCac') && (
        <Descriptions.Item label="潜新CAC">{formatDecimal(detail.potentialNewCac)}</Descriptions.Item>
    )}
    <Descriptions.Item label="累计下单UV">{formatCompact(detail.orderUv)}</Descriptions.Item>
    <Descriptions.Item label="累计订单量">{formatCompact(detail.totalOrders)}</Descriptions.Item>
</Descriptions>
```

---

## 三层过滤体系总览

```
                      ┌──────────────────────────────────────┐
                      │  QConfig content_dict.json            │
                      │  columns[].disabled = true            │
                      └──────────────┬───────────────────────┘
                                     │
                 ┌───────────────────┼───────────────────┐
                 ▼                   ▼                   ▼
           后端 buildFieldMeta   后端 maskHit/maskDetail  前端 disabledFields
           跳过 disabled 列       disabled 字段设 null    读取 disabled 标志
                 │                   │                   │
                 ▼                   ▼                   ├── list: fieldLabelMap
            fieldMeta 不包含      API 返回 null          │    列选项/筛选全消失
            敏感字段              (防直接调用窥探)          │
                                                         └── detail: 条件渲染
                                                               行完全消失
```

| 层次 | 机制 | 目的 |
|------|------|------|
| fieldMeta 过滤 | fieldMeta 不返回 disabled 列 | 前端列勾选框/fieldLabelMap 不出现 |
| 后端掩码 | disabled 字段设 null | 防 API 直接调用窃取数据 |
| 前端 disabledFields | 从 dict 读取 disabled 标志 | UI 层跳过渲染，不依赖字段值 |

---

## 改动用例

### 场景：新增 `totalDownloads` 为隐藏字段

1. `content_dict.json` → `columns` 中 `totalDownloads` 加 `"disabled": true`
2. `ContentFieldMaskService` → `maskHit`/`maskDetail` 各加一行
3. `SORT_WHITELIST` 移除 `total_downloads`
4. QConfig 热加载 → 即时生效 ✅

### 场景：取消 `cpm` 隐藏

1. `content_dict.json` → `cpm` 的 `"disabled": true` 改为 `false` 或删除
2. `ContentFieldMaskService` → 去掉对应 setter 行（或保留无影响）
3. QConfig 热加载 → 即时生效 ✅

---

## 影响分析

### 不变的点
- `ContentSearchDocument` 实体类不变，ES 索引不变，同步逻辑不变
- 下载导出（`ContentMetricsVO`）不变
- 非 disabled 字段的 null/0 值原样保留，前端正常显示 `-`

### 变动的点
| 层 | 文件 | 改动量 |
|----|------|--------|
| 数据模型 | `ContentDictConfig.java` | +1 字段（disabled） |
| Service(新建) | `ContentFieldMaskService.java` | ~50 行 |
| Service | `ContentResponseAssembler.java` | +3 行 |
| Controller | `ContentSearchController.java` | +1 行 |
| Service | `ESSearchServiceImpl.java` | -1 行 |
| QConfig | `content_dict.json` | 加 disabled 配置 |
| 前端 | `list.jsx` | ~20 行，去硬编码 |
| 前端 | `detail.jsx` | ~15 行，条件渲染 |