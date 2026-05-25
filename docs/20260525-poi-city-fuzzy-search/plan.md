# POI / 城市筛选下拉框支持搜索

> 去掉对 content_dict 静态值的依赖，Select 下拉框支持输入搜索过滤选项，选项值从 ES 动态获取

---

## 一、现状分析

### 1.1 当前实现

| 环节 | 实现方式 | 问题 |
|------|---------|------|
| **城市筛选** | `Select mode="tags"` 自由输入，无下拉选项 | 用户需手动输入完整值，不便利 |
| **POI 筛选** | `Select mode="tags"` 自由输入，无下拉选项 | 同上，且 `request.getPoi()` 在 search 中未参与过滤 |
| **选项来源** | `content_dict.json` → `suggestionFields` 中 POI 的 `commonValues` | 需人工维护，容易与 ES 实际数据不一致 |
| **ES 查询** | `termsQuery("city", cities)` 精确匹配 | 无需改动 |

### 1.2 需求澄清

- **查询不改**：search 执行时保持 `termsQuery` 精确匹配
- **下拉框搜索**：Select 增加 `showSearch`，输入文字时从 ES 动态匹配选项
- **选项动态化**：城市/POI 选项值从 ES suggest 接口获取，不再依赖 content_dict

---

## 二、方案设计

### 2.1 数据流

```
┌──────────────────┐  打开下拉框 (请求热门)   ┌────────────────────────┐
│  Select showSearch │ ──────────────────→  │  GET /api/content/suggest │
│  前端组件 (tags)    │                      │  ?field=city             │
│                    │ ←──────────────────  └────────────────────────┘
│                    │  ["北京","上海","广州"...]                        │
│                    │                                                    │
│                    │  键入"深圳"             ┌────────────────────────┐
│                    │ ──────────────────→  │  GET /api/content/suggest │
│                    │                      │  ?field=city&q=深圳      │
│                    │ ←──────────────────  └────────────────────────┘
│                    │  ["深圳","深圳市","深圳南山区"...]                  │
│                    │                                                    │
│                    │  选中"深圳"             ┌────────────────────────┐
│                    │ ──────────────────→  │  POST /api/content/search │
│                    │                      │  cities:["深圳"]         │
│                    │                      │  termsQuery 精确匹配     │
└──────────────────┘                      └────────────────────────┘
```

### 2.2 不变的部分

| 模块 | 说明 |
|------|------|
| `ContentSearchServiceImpl.search()` | 保持 `termsQuery("city", cities)` 精确匹配 |
| `ContentSearchRequest` | `cities` / `poi` 字段不变 |
| ES mapping | `city` / `poi` 仍是 `keyword` 类型 |

---

## 三、后端改动

### 3.1 新增 Suggest 接口

#### 接口定义

```
GET /api/content/suggest?field=city&q=深圳&size=20
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `field` | String | 是 | 建议字段名：`city` / `poi` |
| `q` | String | 否 | 用户输入关键字，为空返回热门 top N |
| `size` | Integer | 否 | 返回条数，默认 20 |

响应：
```json
{
  "code": 0,
  "message": "success",
  "data": ["深圳", "深圳市", "深圳南山区", "深圳福田区"]
}
```

#### 实现

**新增文件**：`service/es/ContentSuggestService.java`

```java
@Service
public class ContentSuggestService {

    private static final String INDEX_BASE_NAME = "content_search";

    @Resource
    private ElasticsearchDataSource elasticsearchDataSource;

    @Resource
    private EsIndexConfig esIndexConfig;

    public List<String> suggest(String field, String keyword, int size) {
        SearchSourceBuilder builder = new SearchSourceBuilder();
        BoolQueryBuilder boolQuery = QueryBuilders.boolQuery();

        if (StringUtils.isNotBlank(keyword)) {
            // 通配符匹配包含关键字的文档
            boolQuery.filter(QueryBuilders.wildcardQuery(field, "*" + keyword + "*"));
        } else {
            boolQuery.must(QueryBuilders.matchAllQuery());
        }
        builder.query(boolQuery);

        // terms 聚合取词频最高的值
        TermsAggregationBuilder termsAgg = AggregationBuilders.terms("suggestions")
                .field(field)
                .size(size)
                .order(Terms.Order.count(false));
        builder.aggregation(termsAgg);
        builder.size(0);

        SearchResponse response = elasticsearchDataSource.search(getIndexName(), builder);
        return parseSuggestions(response);
    }

    private List<String> parseSuggestions(SearchResponse response) {
        Terms terms = response.getAggregations().get("suggestions");
        return terms.getBuckets().stream()
                .map(bucket -> bucket.getKeyAsString())
                .collect(Collectors.toList());
    }

    private String getIndexName() {
        return esIndexConfig.getIndexName(INDEX_BASE_NAME);
    }
}
```

**ES 查询本质**（用户输入"深圳"）：
```json
{
  "query": { "bool": { "filter": [{"wildcard": {"city": "*深圳*"}}] } },
  "aggs": {
    "suggestions": {
      "terms": { "field": "city", "size": 20, "order": {"_count": "desc"} }
    }
  },
  "size": 0
}
```

#### Controller 新增端点

在 `ContentSearchController` 中新增：

```java
@Resource
private ContentSuggestService contentSuggestService;

@GetMapping("/suggest")
public BaseResponse<List<String>> suggest(
        @RequestParam String field,
        @RequestParam(required = false) String q,
        @RequestParam(defaultValue = "20") int size) {
    try {
        List<String> suggestions = contentSuggestService.suggest(field, q, size);
        return BaseResponse.success(suggestions);
    } catch (Exception e) {
        log.error("Failed to get suggestions, field={}, q={}", field, q, e);
        return BaseResponse.fail(-1, e.getMessage());
    }
}
```

### 3.2 修复 POI 筛选不生效

当前 `ContentSearchRequest.getPoi()` 在 `search()` 中未参与 ES 查询。

**改动**：`ContentSearchServiceImpl.search()` 新增 POI 过滤：

```java
// 现有
addFilterTerms(boolQuery, "city", request.getCities());

// 新增
addFilterTerms(boolQuery, "poi", request.getPoi());
```

---

## 四、前端改动

### 4.1 content/list.jsx — Select 增加 showSearch

改动点：城市/POI 的 `Select mode="tags"` 添加 `showSearch` + `onSearch` 动态加载选项。

```jsx
const [cityOptions, setCityOptions] = useState([]);
const [poiOptions, setPoiOptions] = useState([]);

// 获取建议选项
const fetchOptions = useCallback(async (field, keyword, setter) => {
    try {
        const res = await getContentSuggest(field, keyword);
        setter(res.data || []);
    } catch {
        setter([]);
    }
}, []);

// 页面初始化时加载热门选项
useEffect(() => {
    fetchOptions('city', '', setCityOptions);
    fetchOptions('poi', '', setPoiOptions);
}, []);

// JSX 中
<Col span={6}>
  <div style={{ marginBottom: 4 }}><Text type="secondary" style={{ fontSize: 12 }}>POI</Text></div>
  <Select mode="tags" placeholder="搜索POI" style={{ width: '100%' }}
      value={state.poi}
      showSearch
      onSearch={v => fetchOptions('poi', v, setPoiOptions)}
      onChange={v => dispatch({ type: 'SET_FILTER', key: 'poi', value: v })}>
    {poiOptions.map(v => <Select.Option key={v}>{v}</Select.Option>)}
  </Select>
</Col>
<Col span={6}>
  <div style={{ marginBottom: 4 }}><Text type="secondary" style={{ fontSize: 12 }}>城市</Text></div>
  <Select mode="tags" placeholder="搜索城市" style={{ width: '100%' }}
      value={state.cities}
      showSearch
      onSearch={v => fetchOptions('city', v, setCityOptions)}
      onChange={v => dispatch({ type: 'SET_FILTER', key: 'cities', value: v })}>
    {cityOptions.map(v => <Select.Option key={v}>{v}</Select.Option>)}
  </Select>
</Col>
```

关键行为：
- **初始化**：`fetchOptions(field, '')` 加载热门 top 20，下拉框打开即有选项
- **用户输入**：`onSearch` 触发，从 ES wildcard 匹配候选值
- **选中**：值写入 `state.cities`/`state.poi`，点击搜索时传精确值到后端
- **输入不存在的新值**：保留 `mode="tags"`，用户可自由输入任意值

### 4.2 src/api/content.js — 新 API

```javascript
export async function getContentSuggest(field, q, size = 20) {
    return request('/api/content/suggest', {
        params: { field, q, size },
    });
}
```

---

## 五、文件变更清单

### 后端

| 文件 | 改动 | 类型 |
|------|------|------|
| `service/es/ContentSuggestService.java` | **新增**：ES terms 聚合获取 field 候选值 | 新增 |
| `service/es/impl/ContentSearchServiceImpl.java` | `search()` 新增 `addFilterTerms("poi", request.getPoi())` | 修改 |
| `web/ContentSearchController.java` | 新增 `GET /api/content/suggest` 端点 | 修改 |
| `content_dict.json` (QConfig) | 从 `suggestionFields` 移除 poi 条目 | 配置变更 |

### 前端

| 文件 | 改动 | 类型 |
|------|------|------|
| `src/pages/content/list.jsx` | 城市/POI Select 增加 `showSearch` + `onSearch` + 动态选项 | 修改 |
| `src/api/content.js` | 新增 `getContentSuggest()` | 修改 |

---

## 六、注意事项

### 6.1 空输入的场景
- `q` 为空时返回词频最高的前 N 个值，用于初始化下拉选项
- 如果 ES 尚无数据，suggest 返回空列表，用户仍可自由输入文本

### 6.2 content_dict 清理
POI 从 `suggestionFields` 移除后，前端 `suggestionMap['poi']` 引用需确认。当前 `list.jsx` 中 `suggestionMap` 仅在 line 661 用于 `contentSource`，移除 POI 无影响。

### 6.3 POI 筛选修复
当前 `request.getPoi()` 在 `search()` 中未使用，这次一并修复。

### 6.4 Select 组件行为
`showSearch` 启用后，Select 的搜索框出现，用户输入会过滤 Option 列表，同时 `onSearch` 返回输入值供我们异步更新 Option。

---

## 七、验证方式

| 场景 | 预期 |
|------|------|
| 打开城市下拉框（不输入） | 显示热门城市 top 20 |
| 输入"深圳" | 下拉框过滤出含"深圳"的选项（深圳、深圳市、深圳南山区等） |
| 选中"深圳" | 标签添加"深圳"，搜索时 `termsQuery` 精确匹配 |
| 输入"不存在的值"并回车 | 标签添加输入值，搜索时精确匹配 |
| POI 下拉框输入"酒店" | 下拉框过滤出含"酒店"的选项 |