# 素材库 — 后端技术方案

> 版本：v1.0
> 日期：2026-06-11

---

## 目录

- [一、架构概览](#一架构概览)
- [二、数据流设计](#二数据流设计)
- [三、模块划分与类设计](#三模块划分与类设计)
- [四、关键实现细节](#四关键实现细节)
- [五、接口定义](#五接口定义)
- [六、ES 索引与查询设计](#六es-索引与查询设计)
- [七、QConfig 字典设计](#七qconfig-字典设计)
- [八、涉及文件清单](#八涉及文件清单)
- [九、监控与异常处理](#九监控与异常处理)

---

## 一、架构概览

```
┌──────────────────────────────────────────────┐
│                CrawlScheduler                  │
│   (抓取调度系统，外部依赖)                       │
└──────────────────┬───────────────────────────┘
                   │ QMQ 回调
                   ▼
┌──────────────────────────────────────────────┐
│            CrawlTaskResultConsumer             │
│   @QmqConsumer 消费抓取结果                     │
└──────────────────┬───────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────┐
│           CrawlTaskResultProcessor             │
│   按 source 分发到具体 Handler                  │
└──────────────────┬───────────────────────────┘
                   │
         ┌─────────┴──────────┐
         ▼                    ▼
┌──────────────────┐  ┌──────────────────────────┐
│ DouyinHandler    │  │ XhsHandler                │
│ handleBigSearch  │  │ handleDetail              │
│ →MaterialCrawlResult│  │ handleBigSearch          │
│ →sub_task.result │  │ →MaterialCrawlResult      │
│ →status=SUCCESS  │  │ →sub_task.result          │
└──────────────────┘  │ →status=SUCCESS           │
                      └──────────────────────────┘
         │                    │
         └─────────┬──────────┘
                   │ 定时扫描 SUCCESS 子任务
                   ▼
┌──────────────────────────────────────────────┐
│          MaterialProcessTask                   │
│   @QSchedule("mkt_odin_crawtask_material_process")  │
│   扫描 → 校验 → 查重 → 验证 → OSS → 入库 → ES  │
└──────┬───────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────┐
│           MaterialProcessService              │
│   核心处理：校验/查重/验证/OSS/写入/ES          │
│                                              │
│   ┌──────────┐  ┌─────────┐  ┌────────────┐ │
│   │ oss检查   │→│ OSS转存  │→│ DB写入     │ │
│   └──────────┘  └─────────┘  └─────┬──────┘ │
│                                     │        │
│   ┌────────┐  ┌──────────┐          │        │
│   │ ES同步  │←│ 组装Doc   │←────────┘        │
│   └────────┘  └──────────┘                   │
└──────────────────────────────────────────────┘
```

---

## 二、数据流设计

### 2.1 阶段二：回调 → sub_task.result

```
QMQ 消息 (JSON)
  ↓ CrawlTaskResultConsumer
CrawlTaskResultCallback (taskId, source, data)
  ↓ CrawlTaskResultProcessor.resolveRunningSubTask → findHandler → buildContext
XxxCrawlTaskResultHandler.handle(context)
  ↓ resolveParsedData → 提取字段
MaterialCrawlResult
  ↓ JsonUtils.toJson
sub_task.result = {
  "source": "douyin",
  "crawlType": "BIG_SEARCH",
  "keyword": "旅游",
  "items": [{
    "sourceId": "734567890123456",
    "title": "...",
    "videoUrl": "https://...",
    "totalLikes": 1200,
    "materialType": "video",
    ...
  }]
}
  ↓ subTaskService.updateSubTaskStatus(id, SUCCESS)
```

### 2.2 阶段三：定时任务 → 入库

```
MaterialProcessTask.scanAndProcess()
  ↓
SELECT FROM sub_task WHERE status='SUCCESS' AND executor='materialCrawl' AND result IS NOT NULL
  ↓ 逐条处理
MaterialProcessService.process(result)
  ↓ for each item:
  1. 合法性校验     → material_id = source + "_" + sourceId
  2. 查重           → SELECT FROM material_base WHERE material_id = ?
  3. 链接验证       → HTTP HEAD videoUrl（超时 3s）
  4. OSS 转存       → OssClient.upload(videoUrl)
  5. DB 写入        → INSERT INTO material_base/video/metrics（事务内）
  6. ES 同步        → MaterialSearchSyncService.sync(materialId)
  7. 更新子任务状态  → ANALYSIS_SUCCESS / ANALYSIS_FAIL + error_msg
```

### 2.3 小红书两段式处理

```
BIG_SEARCH 回调:
  items[].totalLikes = 0, items[].totalFavorites = 0
  → 入库，metrics 存 0

DETAIL 回调:
  items[].totalLikes = 实际值, items[].totalFavorites = 实际值
  → 查重命中 → UPDATE material_metrics SET total_likes=?, total_favorites=?
  → OSS 链接已存在 → 仅更新 metrics
```

---

## 三、模块划分与类设计

### 3.1 Entity 层

```java
// ==================== material_base ====================
public class MaterialBase {
    private Long id;
    private String materialId;
    private String title;
    private String materialType;    // video / image
    private String origin;          // crawl_task
    private String source;          // douyin / redbook
    private String sourceId;
    private String publishUrl;
    private Date publishTime;
    private String videoUrl;        // OSS 内部 URL
    private String materialLabel;   // JSON: {"common_tag":[],"poi":[],"city":[],"ai_tag":[]}
    private String extParam;
    private Date dt;
    private Date createTime;
    private Date updateTime;
}

// ==================== material_video ====================
public class MaterialVideo {
    private Long id;
    private String materialId;
    private String videoUrl;        // 原始下载链接
    private String coverUrl;
    private String internalCoverUrl;
    private Integer duration;
    private Integer width;
    private Integer height;
    private String aspectRatio;
    private Long videoSize;
    private String videoFormat;
    private BigDecimal frameRate;
    private Integer preprocessStatus;
    private String videoFrameParam;
    private String audioUrl;
    private String audioText;
    private String extParam;
    private Date createTime;
    private Date updateTime;
}

// ==================== material_metrics ====================
public class MaterialMetrics {
    private Long id;
    private String materialId;
    private Integer totalLikes;
    private Integer totalFavorites;
    private Integer totalViews;
    private Integer totalComments;
    private Integer totalShares;
    private String extParam;
    private Date createTime;
    private Date updateTime;
}
```

### 3.2 DTO（回调中间结构）

```java
// ==================== MaterialCrawlResult ====================
public class MaterialCrawlResult {
    private String source;
    private String crawlType;
    private String keyword;
    private List<MaterialCrawlItem> items;
}

// ==================== MaterialCrawlItem ====================
public class MaterialCrawlItem {
    private String materialType;
    private String sourceId;
    private String title;
    private String authorId;
    private String authorName;
    private String videoUrl;
    private String coverUrl;
    private Integer duration;
    private Integer width;
    private Integer height;
    private String videoFormat;
    private Long videoSize;
    private Double frameRate;
    private String publishTime;
    private String publishUrl;
    private Integer totalLikes;
    private Integer totalFavorites;
    private Integer totalViews;
    private Integer totalComments;
    private Integer totalShares;
    private MaterialLabel label;
    private Map<String, Object> extra;
}

// ==================== MaterialLabel ====================
public class MaterialLabel {
    private List<String> commonTag;
    private List<String> poi;
    private List<String> city;
    private List<String> aiTag;
}
```

### 3.3 Service 层

| 类 | 职责 | 关键方法 |
|----|------|---------|
| `MaterialProcessService` | 定时任务核心处理 | `process(MaterialCrawlResult)` — 校验→查重→验证→OSS→入库→ES |
| `MaterialProcessTask` | @QSchedule 入口 | `scanAndProcess()` — 扫描子任务 → 委托 MaterialProcessService |
| `MaterialOssService` | OSS 转存 | `transferVideo(videoUrl)` → internalUrl；`transferCover(coverUrl)` → internalCoverUrl |
| `MaterialSearchService` | ES 检索 | `search(MaterialSearchRequest)` → ES query → 返回 id list；`detail(id)` → DB 三表 JOIN |
| `MaterialSearchSyncService` | ES 索引同步 | `sync(materialId)` → 组装 doc → index |
| `MaterialSearchDocAssembler` | ES 文档组装 | `assemble(materialId)` → MaterialSearchDocument（含 material_label 展开） |
| `MaterialDictService` | dict 配置 | `@QConfig("material_dict.json")` 热加载；`getDictConfig()` → MaterialDictConfig |

### 3.4 Controller

```java
@RestController
@RequestMapping("/api/material")
public class MaterialSearchController {

    @PostMapping("/search")
    public BaseResponse<MaterialSearchResult> search(@RequestBody MaterialSearchRequest request);

    @GetMapping("/detail/{id}")
    public BaseResponse<MaterialDetailVO> detail(@PathVariable Long id);

    @GetMapping("/dict")
    public BaseResponse<MaterialDictConfig> dict();
}
```

### 3.5 回复组装 VO

```java
// 列表搜索结果
public class MaterialSearchResult {
    private List<MaterialHit> hits;  // ES id 列表 → DB 组装
    private long total;
    private int took;
}

// 列表单条（ES 返回 id → DB JOIN 组装）
public class MaterialHit {
    private Long id;
    private String materialId;
    private String coverUrl;        // oss internal_cover_url
    private String title;
    private String durationDisplay; // "30s"
    private String aspectRatio;
    private String totalLikesDisplay; // "1.2K"
    private String totalFavoritesDisplay;
    private String sourceLabel;     // "抖音"
}

// 详情页（三表 JOIN）
public class MaterialDetailVO {
    // 基本信息
    private Long id;
    private String materialId;
    private String title;
    private String materialType;
    private String origin;
    private String source;
    private String sourceId;
    private String publishUrl;
    private Date publishTime;
    // 视频
    private String videoUrl;        // OSS 内部
    private String coverUrl;
    private String originalVideoUrl;
    private Integer duration;
    private Integer width;
    private Integer height;
    private String aspectRatio;
    private Long videoSize;
    private String videoFormat;
    private BigDecimal frameRate;
    // 指标
    private Integer totalLikes;
    private Integer totalFavorites;
    private Integer totalViews;
    private Integer totalComments;
    private Integer totalShares;
    // 标签
    private MaterialLabel materialLabel;
}
```

---

## 四、关键实现细节

### 4.1 Handler 增强（DouyinHandler / XhsHandler）

```java
// DouyinCrawlTaskResultHandler.handleBigSearch
@Override
protected void handleBigSearch(CrawlTaskResultContext context, Object parsedData) {
    DouyinCrawlBigSearchTaskResultData data = (DouyinCrawlBigSearchTaskResultData) parsedData;
    if (data == null) {
        log.error("douyin crawl bigSearch result parse failed, subTaskId={}", context.getSubTask().getId());
        return;
    }

    MaterialCrawlResult result = new MaterialCrawlResult();
    result.setSource("douyin");
    result.setCrawlType(CrawlTaskTypeEnum.BIG_SEARCH.getCode());
    result.setKeyword(context.getKeyword());

    List<MaterialCrawlItem> items = new ArrayList<>();
    for (BigSearchPage page : data.getData()) {
        for (BusinessData bd : page.getBusinessData()) {
            // 提取字段装入 MaterialCrawlItem
            MaterialCrawlItem item = extractItem(bd);
            items.add(item);
        }
    }
    result.setItems(items);

    // 持久化到 sub_task.result
    String resultJson = JsonUtils.toJson(result);
    subTaskService.completeSubTask(context.getSubTask().getId(), resultJson);
}
```

### 4.2 MaterialProcessService 核心逻辑

```java
public void process(MaterialCrawlResult result, Long subTaskId) {
    List<FailedNode> failedNodes = new ArrayList<>();
    int successCount = 0, failCount = 0;

    for (MaterialCrawlItem item : result.getItems()) {
        try {
            // Step 1: 合法性校验
            String materialId = result.getSource() + "_" + item.getSourceId();
            if (StringUtils.isBlank(materialId) || StringUtils.isBlank(item.getVideoUrl())) {
                failCount++;
                failedNodes.add(new FailedNode(materialId, "合法性校验失败: 必填字段为空"));
                continue;
            }

            // Step 2: 查重
            MaterialBase existing = materialBaseMapper.selectByMaterialId(materialId);
            if (existing != null) {
                // 更新 metrics
                materialMetricsMapper.upsert(buildMetrics(materialId, item));
                // 检查 OSS 链接
                if (StringUtils.isNotBlank(existing.getVideoUrl())) {
                    successCount++;
                    continue; // 已有 OSS，跳过
                }
                // OSS 为空，继续走转存
            }

            // Step 3: 链接验证
            if (!checkUrlAccessible(item.getVideoUrl())) {
                failCount++;
                failedNodes.add(new FailedNode(materialId, "下载链接不可达"));
                continue;
            }

            // Step 4: OSS 转存
            String internalVideoUrl = materialOssService.transferVideo(item.getVideoUrl());

            // Step 5: DB 写入（事务内）
            materialProcessService.saveMaterial(materialId, item, internalVideoUrl);

            // Step 6: ES 同步
            materialSearchSyncService.sync(materialId);

            successCount++;
        } catch (Exception e) {
            failCount++;
            failedNodes.add(new FailedNode(item.getSourceId(), e.getMessage()));
        }
    }

    // Step 7: 更新子任务状态
    if (failCount == 0) {
        subTaskService.updateSubTaskStatus(subTaskId, "ANALYSIS_SUCCESS");
    } else {
        subTaskService.updateSubTaskStatus(subTaskId, "ANALYSIS_FAIL");
        subTaskService.updateSubTaskError(subTaskId, JsonUtils.toJson(failedNodes));
    }
}
```

### 4.3 OSS 转存

```java
@Component
public class MaterialOssService {

    @Resource
    private OssClient ossClient;

    /**
     * 转存视频到 OSS
     * 路径: mkt_odin_material/{materialId}/{filename}
     */
    public String transferVideo(String videoUrl, String materialId) {
        String fileName = extractFileName(videoUrl);
        String ossPath = "mkt_odin_material/" + materialId + "/" + fileName;
        return ossClient.upload(videoUrl, ossPath);
    }

    /**
     * 转存封面到 OSS
     * 路径: mkt_odin_material/{materialId}/cover_{filename}
     */
    public String transferCover(String coverUrl, String materialId) {
        String fileName = "cover_" + extractFileName(coverUrl);
        String ossPath = "mkt_odin_material/" + materialId + "/" + fileName;
        return ossClient.upload(coverUrl, ossPath);
    }
}
```

### 4.4 画面比例自动判断

```java
// 工具方法
public static String detectAspectRatio(int width, int height) {
    if (width <= 0 || height <= 0) return "";
    double ratio = (double) width / height;
    if (Math.abs(ratio - 9.0/16) < 0.01) return "9:16";
    if (Math.abs(ratio - 4.0/3) < 0.01) return "4:3";
    if (Math.abs(ratio - 3.0/4) < 0.01) return "3:4";
    if (Math.abs(ratio - 16.0/9) < 0.01) return "16:9";
    return "其他";
}
```

### 4.5 ES Document 组装（material_label 展开）

```java
public class MaterialSearchDocAssembler {

    public MaterialSearchDocument assemble(String materialId) {
        // 三表 JOIN 查询
        MaterialBase base = materialBaseMapper.selectByMaterialId(materialId);
        MaterialVideo video = materialVideoMapper.selectByMaterialId(materialId);
        MaterialMetrics metrics = materialMetricsMapper.selectByMaterialId(materialId);

        MaterialSearchDocument doc = new MaterialSearchDocument();
        doc.setId(base.getId());
        doc.setMaterialId(base.getMaterialId());
        doc.setTitle(base.getTitle());
        doc.setSource(base.getSource());
        doc.setPublishTime(base.getPublishTime());
        doc.setCreateTime(base.getCreateTime());

        if (video != null) {
            doc.setDuration(video.getDuration());
            doc.setAspectRatio(video.getAspectRatio());
            doc.setWidth(video.getWidth());
            doc.setHeight(video.getHeight());
            doc.setFrameRate(video.getFrameRate());
        }
        if (metrics != null) {
            doc.setTotalLikes(metrics.getTotalLikes());
            doc.setTotalFavorites(metrics.getTotalFavorites());
            doc.setTotalViews(metrics.getTotalViews());
            doc.setTotalComments(metrics.getTotalComments());
        }

        // material_label 展开
        MaterialLabel label = JsonUtils.jsonToObject(base.getMaterialLabel(), MaterialLabel.class);
        if (label != null) {
            doc.setMaterialLabelCommonTag(label.getCommonTag());
            doc.setMaterialLabelPoi(label.getPoi());
            doc.setMaterialLabelCity(label.getCity());
            doc.setMaterialLabelAiTag(label.getAiTag());
        }

        return doc;
    }
}
```

### 4.6 ES 查询构建（分辨率/帧率映射）

```java
public class MaterialSearchService {

    public SearchResult search(MaterialSearchRequest request) {
        BoolQueryBuilder boolQuery = QueryBuilders.boolQuery();

        // 标题模糊检索
        if (StringUtils.isNotBlank(request.getTitle())) {
            boolQuery.must(QueryBuilders.matchQuery("title", request.getTitle()));
        }
        // 时长范围
        if (request.getDurationMin() != null || request.getDurationMax() != null) {
            RangeQueryBuilder range = QueryBuilders.rangeQuery("duration");
            if (request.getDurationMin() != null) range.gte(request.getDurationMin());
            if (request.getDurationMax() != null) range.lte(request.getDurationMax());
            boolQuery.filter(range);
        }
        // 画面比例
        if (CollectionUtils.isNotEmpty(request.getAspectRatios())) {
            boolQuery.filter(QueryBuilders.termsQuery("aspect_ratio", request.getAspactRatios()));
        }
        // 点赞量范围
        if (request.getTotalLikesMin() != null || request.getTotalLikesMax() != null) {
            RangeQueryBuilder range = QueryBuilders.rangeQuery("total_likes");
            if (request.getTotalLikesMin() != null) range.gte(request.getTotalLikesMin());
            if (request.getTotalLikesMax() != null) range.lte(request.getTotalLikesMax());
            boolQuery.filter(range);
        }
        // 收藏量范围
        if (request.getTotalFavoritesMin() != null || request.getTotalFavoritesMax() != null) {
            RangeQueryBuilder range = QueryBuilders.rangeQuery("total_favorites");
            if (request.getTotalFavoritesMin() != null) range.gte(request.getTotalFavoritesMin());
            if (request.getTotalFavoritesMax() != null) range.lte(request.getTotalFavoritesMax());
            boolQuery.filter(range);
        }
        // 分辨率映射
        if (CollectionUtils.isNotEmpty(request.getResolutions())) {
            BoolQueryBuilder resolutionBool = QueryBuilders.boolQuery();
            for (String res : request.getResolutions()) {
                switch (res) {
                    case "4k":
                        resolutionBool.should(QueryBuilders.boolQuery()
                            .should(QueryBuilders.rangeQuery("width").gte(3840))
                            .should(QueryBuilders.rangeQuery("height").gte(2160)));
                        break;
                    case "2k":
                        resolutionBool.should(QueryBuilders.boolQuery()
                            .should(QueryBuilders.rangeQuery("width").gte(2560))
                            .should(QueryBuilders.rangeQuery("height").gte(1440)));
                        break;
                    case "1080p":
                        resolutionBool.should(QueryBuilders.boolQuery()
                            .should(QueryBuilders.rangeQuery("width").gte(1920))
                            .should(QueryBuilders.rangeQuery("height").gte(1080)));
                        break;
                    case "720p":
                        resolutionBool.should(QueryBuilders.boolQuery()
                            .should(QueryBuilders.rangeQuery("width").gte(1280))
                            .should(QueryBuilders.rangeQuery("height").gte(720)));
                        break;
                    case "other":
                        resolutionBool.should(QueryBuilders.boolQuery()
                            .mustNot(QueryBuilders.rangeQuery("width").gte(1280))
                            .mustNot(QueryBuilders.rangeQuery("height").gte(720)));
                        break;
                }
            }
            if (resolutionBool.hasClauses()) {
                boolQuery.filter(resolutionBool);
            }
        }
        // 帧率映射
        if (CollectionUtils.isNotEmpty(request.getFrameRates())) {
            BoolQueryBuilder frameBool = QueryBuilders.boolQuery();
            for (String fr : request.getFrameRates()) {
                switch (fr) {
                    case "gte30":
                        frameBool.should(QueryBuilders.rangeQuery("frame_rate").gte(30));
                        break;
                    case "gte24":
                        frameBool.should(QueryBuilders.boolQuery()
                            .must(QueryBuilders.rangeQuery("frame_rate").gte(24))
                            .must(QueryBuilders.rangeQuery("frame_rate").lt(30)));
                        break;
                    case "lt24":
                        frameBool.should(QueryBuilders.boolQuery()
                            .must(QueryBuilders.rangeQuery("frame_rate").gt(0))
                            .must(QueryBuilders.rangeQuery("frame_rate").lt(24)));
                        break;
                }
            }
            if (frameBool.hasClauses()) {
                boolQuery.filter(frameBool);
            }
        }
        // 发布时间范围
        if (request.getPublishTimeStart() != null || request.getPublishTimeEnd() != null) {
            RangeQueryBuilder range = QueryBuilders.rangeQuery("publish_time");
            if (request.getPublishTimeStart() != null) range.gte(request.getPublishTimeStart());
            if (request.getPublishTimeEnd() != null) range.lte(request.getPublishTimeEnd());
            boolQuery.filter(range);
        }

        // 执行查询
        SearchSourceBuilder builder = new SearchSourceBuilder();
        builder.query(boolQuery);
        builder.from(request.getFrom());
        builder.size(request.getSize());
        builder.fetchSource(new String[]{"id"}, null); // 只返回 id

        SearchResponse response = elasticsearchDataSource.search(indexName, builder);
        // 解析 hits → id list → DB 组装
        return assembleResult(response);
    }

    private SearchResult assembleResult(SearchResponse response) {
        SearchResult result = new SearchResult();
        result.setTotal(response.getHits().getTotalHits().value);
        List<Long> ids = new ArrayList<>();
        for (SearchHit hit : response.getHits().getHits()) {
            ids.add(Long.valueOf(hit.getId()));
        }
        // 从 DB 三表 JOIN 查询组装
        result.setHits(batchQueryHits(ids));
        return result;
    }
}
```

---

## 五、接口定义

### 5.1 素材检索

| 项目 | 说明 |
|------|------|
| **URL** | `POST /api/material/search` |
| **请求体** | `{ title, durationMin, durationMax, aspectRatios[], resolutions[], frameRates[], totalLikesMin/Max, totalFavoritesMin/Max, publishTimeStart, publishTimeEnd, from, size }` |
| **响应** | `{ code:0, data:{ hits:[], total, took } }` |

**MaterialSearchRequest：**

```java
public class MaterialSearchRequest {
    private String title;              // 素材名称模糊
    private Integer durationMin;       // 时长最小值（秒）
    private Integer durationMax;       // 时长最大值
    private List<String> aspectRatios; // 画面比例 ["9:16","4:3",...]
    private List<String> resolutions;  // 分辨率 ["4k","1080p",...]
    private List<String> frameRates;   // 帧率 ["gte30","gte24","lt24"]
    private Integer totalLikesMin;     // 点赞量最小值
    private Integer totalLikesMax;     // 点赞量最大值
    private Integer totalFavoritesMin; // 收藏量最小值
    private Integer totalFavoritesMax; // 收藏量最大值
    private String publishTimeStart;   // 发布时间起始
    private String publishTimeEnd;     // 发布时间结束
    private int from = 0;
    private int size = 10;
}
```

### 5.2 素材详情

| 项目 | 说明 |
|------|------|
| **URL** | `GET /api/material/detail/{id}` |
| **路径参数** | `id` — material_base 主键 |
| **响应** | `{ code:0, data: MaterialDetailVO }` |

### 5.3 字典接口

| 项目 | 说明 |
|------|------|
| **URL** | `GET /api/material/dict` |
| **响应** | `{ code:0, data: MaterialDictConfig }` |

---

## 六、ES 索引与查询设计

### 6.1 索引 mapping

```json
{
  "mappings": {
    "properties": {
      "id":                          { "type": "long" },
      "material_id":                 { "type": "keyword" },
      "title":                       { "type": "text", "analyzer": "ik_smart" },
      "source":                      { "type": "keyword" },
      "duration":                    { "type": "integer" },
      "aspect_ratio":                { "type": "keyword" },
      "width":                       { "type": "integer" },
      "height":                      { "type": "integer" },
      "frame_rate":                  { "type": "float" },
      "material_label_common_tag":   { "type": "keyword" },
      "material_label_poi":          { "type": "keyword" },
      "material_label_city":         { "type": "keyword" },
      "material_label_ai_tag":       { "type": "keyword" },
      "total_likes":                 { "type": "integer" },
      "total_favorites":             { "type": "integer" },
      "total_views":                 { "type": "integer" },
      "total_comments":              { "type": "integer" },
      "publish_time":                { "type": "date", "format": "yyyy-MM-dd HH:mm:ss||yyyy-MM-dd||epoch_millis" },
      "create_time":                 { "type": "date", "format": "yyyy-MM-dd HH:mm:ss||yyyy-MM-dd||epoch_millis" }
    }
  }
}
```

### 6.2 索引名称

| 环境 | 索引名称 |
|------|---------|
| 本地 | `odin_material_search` |
| Beta | `odin_material_search` |
| 生产 | `odin_material_search` |

索引名称通过 `EsIndexConfig` 拼接前缀：`{prefix}_material_search`。

### 6.3 ES 同步策略

| 策略 | 说明 |
|------|------|
| 写入时机 | 阶段三入库后同步 |
| 方式 | `indexDocument`（全量覆盖） |
| 失败处理 | log + QMonitor 告警，不影响主流程 |
| 数据来源 | material_base + material_video + material_metrics 三表 JOIN |

### 6.4 查询组装策略

```
ES 查询 → 返回 id 列表 + total
  → MaterialSearchService.batchQueryHits(ids)
    → SELECT FROM material_base b
      LEFT JOIN material_video v ON b.material_id = v.material_id
      LEFT JOIN material_metrics m ON b.material_id = m.material_id
      WHERE b.id IN (ids)
    → 组装 MaterialHit（含 cover_url / source label）
```

---

## 七、QConfig 字典设计

### 7.1 配置文件名

`material_dict.json`，托管于 QConfig，通过 `@QConfig("material_dict.json")` 热加载。

### 7.2 配置结构

```java
public class MaterialDictConfig {
    private List<OptionItem> sources;          // 来源平台 ["抖音","小红书"]
    private List<OptionItem> materialTypes;     // 素材类型 ["视频","图片"]
    private List<OptionItem> aspectRatios;      // 画面比例 ["9:16","4:3",...]
    private List<OptionItem> resolutions;       // 分辨率 ["4K","2K",...]
    private List<OptionItem> frameRates;        // 帧率 [">=30fps",...]
    private List<OptionItem> quickDateRanges;   // 快捷日期 ["半年内","1年内",...]
    private List<MetricFilter> metricFilters;   // 指标筛选配置
    private List<ColumnConfig> columns;         // 表格列配置
}
```

完整示例见 `material_dict.example.json`。

### 7.3 前端回退策略

当 dict 接口返回 null 或配置为空时，前端使用默认值：

```js
const DEFAULT_SOURCES = [
  { label: '抖音', value: 'douyin' },
  { label: '小红书', value: 'redbook' },
];
const DEFAULT_ASPECT_RATIOS = [
  { label: '9:16', value: '9:16' },
  { label: '4:3', value: '4:3' },
  { label: '3:4', value: '3:4' },
  { label: '16:9', value: '16:9' },
  { label: '其他', value: '其他' },
];
const DEFAULT_RESOLUTIONS = [
  { label: '4K', value: '4k' },
  { label: '2K', value: '2k' },
  { label: '1080P', value: '1080p' },
  { label: '720P', value: '720p' },
  { label: '其他', value: 'other' },
];
// ... 类似内容模块的前端回退逻辑
```

---

## 八、涉及文件清单

### 8.1 新增文件

| 序号 | 文件路径 | 说明 |
|------|---------|------|
| 1 | `domain/entity/material/MaterialBase.java` | 素材主表 Entity |
| 2 | `domain/entity/material/MaterialVideo.java` | 素材视频表 Entity |
| 3 | `domain/entity/material/MaterialMetrics.java` | 素材指标表 Entity |
| 4 | `domain/dto/crawl/MaterialCrawlResult.java` | 回调结果中间结构 |
| 5 | `domain/dto/crawl/MaterialCrawlItem.java` | 回调单条素材 DTO |
| 6 | `domain/dto/crawl/MaterialLabel.java` | 标签结构 DTO |
| 7 | `domain/dto/material/MaterialSearchRequest.java` | ES 检索请求 DTO |
| 8 | `domain/dto/material/MaterialSearchResult.java` | 检索响应 DTO |
| 9 | `domain/dto/material/MaterialHit.java` | 列表单条数据 VO |
| 10 | `domain/dto/material/MaterialDetailVO.java` | 详情 VO |
| 11 | `domain/entity/es/MaterialSearchDocument.java` | ES 索引 Document POJO |
| 12 | `domain/entity/config/MaterialDictConfig.java` | QConfig 字典配置 Entity |
| 13 | `infra/dao/MaterialBaseMapper.java` | MyBatis Mapper |
| 14 | `infra/dao/MaterialVideoMapper.java` | MyBatis Mapper |
| 15 | `infra/dao/MaterialMetricsMapper.java` | MyBatis Mapper |
| 16 | `infra/dao/mapper/MaterialBaseMapper.xml` | MyBatis XML |
| 17 | `infra/dao/mapper/MaterialVideoMapper.xml` | MyBatis XML |
| 18 | `infra/dao/mapper/MaterialMetricsMapper.xml` | MyBatis XML |
| 19 | `service/material/MaterialOssService.java` | OSS 转存服务 |
| 20 | `service/material/MaterialProcessService.java` | 素材入库核心服务 |
| 21 | `service/material/MaterialSearchService.java` | ES 检索服务 |
| 22 | `service/material/MaterialDictService.java` | dict 配置服务 (@QConfig) |
| 23 | `service/es/MaterialSearchSyncService.java` | ES 同步接口 |
| 24 | `service/es/impl/MaterialSearchSyncServiceImpl.java` | ES 同步实现 |
| 25 | `service/es/MaterialSearchDocAssembler.java` | ES 文档组装器 |
| 26 | `task/material/MaterialProcessTask.java` | @QSchedule 定时任务 |
| 27 | `web/MaterialSearchController.java` | 素材模块 Controller |

### 8.2 修改文件

| 序号 | 文件路径 | 改动内容 |
|------|---------|---------|
| 1 | `DouyinCrawlTaskResultHandler.java` | handleBigSearch → 提取字段写 result + SUCCESS |
| 2 | `XhsCrawlTaskResultHandler.java` | handleDetail + handleBigSearch → 同上 |
| 3 | `EsIndexConfig.java` | 新增 `material_search` 索引常量 |
| 4 | `SubTaskStatus.java` | 新增 `ANALYSIS_SUCCESS` / `ANALYSIS_FAIL` |
| 5 | `config/config.js` | 新增 `/material` 和 `/material/detail` 路由 |
| 6 | `src/api/material.js` | 新增素材模块 API 封装 |

---

## 九、监控与异常处理

### 9.1 QMonitor 指标

| 指标 | 触发条件 |
|------|---------|
| `material_download_check_fail` | 下载链接验证失败 |
| `material_oss_transfer_fail` | OSS 转存失败 |
| `material_db_insert_fail` | DB 写入异常 |
| `material_es_sync_fail` | ES 索引同步失败 |
| `material_process_success` | 单条素材入库成功 |
| `material_process_fail` | 单条素材入库失败（含原因） |
| `material_process_batch_complete` | 一批子任务处理完成 |

### 9.2 异常处理策略

| 异常场景 | 处理方式 |
|---------|---------|
| 子任务 result 解析失败 | log 警告 + 跳过该子任务（跳过标记避免重复报错） |
| 下载链接 403/404 | 记录 failedNodes → 继续下一条 |
| OSS 转存超时/异常 | 记录 failedNodes → 继续下一条 |
| DB 写入事务失败 | 整体异常抛给定时任务框架重试（QSchedule 自动重试） |
| ES 索引写入失败 | log + QMonitor 告警，不影响主流程 |
| 子任务部分成功/部分失败 | 设为 ANALYSIS_FAIL，明细写入 error_msg |
| dict.json 加载失败 | 前端回退默认值，不影响核心功能 |