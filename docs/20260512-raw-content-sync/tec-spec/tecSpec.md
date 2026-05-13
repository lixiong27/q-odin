# RawContentSync 业务表同步 — 技术规格

## 一、整体流程

```
RawContentSyncService.sync(RawContentInfo raw):
                    │
        ┌───────────┴───────────┐
        │                       │
  首次同步                 二次同步
  (base == null)           (base != null)
        │                       │
  ┌ 事务内 (DB写入，无 OSS) ─┐  │
  │                         │  │
  │ 1. INSERT content_base  │  │
  │ 2. buildText()→text_ids │  │
  │ 3. contentType 分流:     │  │
  │    ├─ "图文帖"           │  │
  │    │  buildImages()     │  │
  │    │  → image_ids       │  │
  │    └─ "短视频"           │  │
  │       buildVideo()      │  │
  │       → video_ids       │  │
  │       buildVideoCover() │  │
  │       → image_ids       │  │
  │ 4. UPDATE               │  │
  │    content_relations    │  │
  │                         │  │
  │ 5. buildLabel()(upsert)◄┼──┘
  │ 6. buildMetrics()(upsert)│
  └─────────────────────────┘
        │
  ┌ 事务外 (OSS 转存) ───────┐
  │                         │
  │ 7. transferImages()     │
  │    (正文图 + 封面图)     │
  │ 8. transferVideos()     │
  │    (原视频文件)          │
  └─────────────────────────┘
```

---

## 二、字段映射规格

### 2.1 空值兜底策略

所有字段不允许数据库 NULL，统一遵循以下规则：

| 数据类型 | Java null 时的兜底值 |
|---------|-------------------|
| String | `""`（空字符串） |
| Integer / Long | 0 |
| BigDecimal | `BigDecimal.ZERO` |
| Date | `new Date(0)` → "1970-01-01 00:00:00" |

```java
// 辅助方法，统一空值兜底
private String defaultIfBlank(String str) {
    return str != null ? str : "";
}

private <T> T defaultIfNull(T value, T defaultValue) {
    return value != null ? value : defaultValue;
}
```

### 2.2 RawContentInfo → content_base

| 目标字段 | 来源 | 空值处理 | 备注 |
|---------|------|---------|------|
| id | 自增 | — | useGeneratedKeys 回写 |
| content_id | raw.contentId | defaultIfBlank | UNIQUE 幂等键 |
| business_content_id | raw.businessContentId | defaultIfBlank | |
| content_type | raw.contentType | defaultIfBlank | "图文帖" / "短视频" |
| content_title | raw.contentTitle | defaultIfBlank | |
| publish_platform | raw.publishPlatform | defaultIfBlank | |
| publish_time | raw.publishTime | DEFAULT_DATE | Date→DATETIME |
| publish_url | raw.publishUrl | defaultIfBlank | |
| business_line | raw.businessLine | defaultIfBlank | |
| content_source | raw.contentSource | defaultIfBlank | |
| production_team | raw.productionTeam | defaultIfBlank | |
| operation_project | raw.operationProject | defaultIfBlank | |
| placement_position | raw.placementPosition | defaultIfBlank | |
| dt | raw.dt | DEFAULT_DATE | Date→DATE |
| content_relations | 构建 | "{}" | JSON |

```java
private ContentBase buildContentBase(RawContentInfo raw) {
    ContentBase base = new ContentBase();
    base.setContentId(defaultIfBlank(raw.getContentId()));
    base.setBusinessContentId(defaultIfBlank(raw.getBusinessContentId()));
    base.setContentType(defaultIfBlank(raw.getContentType()));
    base.setContentTitle(defaultIfBlank(raw.getContentTitle()));
    base.setPublishPlatform(defaultIfBlank(raw.getPublishPlatform()));
    base.setPublishTime(defaultIfNull(raw.getPublishTime(), DEFAULT_DATE));
    base.setPublishUrl(defaultIfBlank(raw.getPublishUrl()));
    base.setBusinessLine(defaultIfBlank(raw.getBusinessLine()));
    base.setContentSource(defaultIfBlank(raw.getContentSource()));
    base.setProductionTeam(defaultIfBlank(raw.getProductionTeam()));
    base.setOperationProject(defaultIfBlank(raw.getOperationProject()));
    base.setPlacementPosition(defaultIfBlank(raw.getPlacementPosition()));
    base.setDt(defaultIfNull(raw.getDt(), DEFAULT_DATE));
    base.setContentRelations("{}");
    return base;
}
```

### 2.3 RawContentInfo → content_text

| 目标字段 | 来源 | 空值处理 | 备注 |
|---------|------|---------|------|
| id | 自增 | — | useGeneratedKeys |
| content_title | raw.contentTitle | defaultIfBlank | 冗余 |
| content_text | raw.contentText | 原值 | 可为 null |
| poi | raw.poi | defaultIfBlank | 冗余 |
| text_length | raw.contentText.length() | 0 | 计算 |
| ext_param | 常量 | "{}" | |

### 2.4 RawContentInfo → content_image

| 目标字段 | 来源 | 空值处理 | 备注 |
|---------|------|---------|------|
| id | 自增 | — | useGeneratedKeys |
| image_type | 约定值 | "正文图"/"封面图" | 根据上下文设定 |
| original_url | contentUrl 拆分 / videoCoverUrl | defaultIfBlank | UNIQUE 去重 |
| internal_url | 常量 | "" | OSS 转存后异步更新 |
| width | raw 无此数据 | 0 | 数仓宽表未提供 |
| height | raw 无此数据 | 0 | |
| aspect_ratio | raw 无此数据 | BigDecimal.ZERO | |
| image_size | raw 无此数据 | 0L | |
| content_title | raw.contentTitle | defaultIfBlank | 冗余 |
| poi | raw.poi | defaultIfBlank | 冗余 |
| ext_param | 常量 | "{}" | |

### 2.5 RawContentInfo → content_video

| 目标字段 | 来源 | 空值处理 | 备注 |
|---------|------|---------|------|
| id | 自增 | — | useGeneratedKeys |
| video_url | raw.contentUrl | defaultIfBlank | UNIQUE 去重 |
| internal_video_url | 常量 | "" | OSS 转存后异步更新 |
| video_cover_url | raw.videoCoverUrl | defaultIfBlank | |
| duration | raw 无此数据 | 0 | |
| width/height | raw 无此数据 | 0 | |
| aspect_ratio | raw 无此数据 | BigDecimal.ZERO | |
| video_size | raw 无此数据 | 0L | |
| video_format | raw 无此数据 | "" | |
| video_frame_param | 常量 | "{\"frame\":[]}" | 抽帧后更新 |
| audio_url | 常量 | "" | 音频提取后更新 |
| audio_text | 常量 | null | ASR 后更新 |
| preprocess_status | 常量 | 0 | 预处理管线驱动 |
| content_title | raw.contentTitle | defaultIfBlank | 冗余 |
| poi | raw.poi | defaultIfBlank | 冗余 |
| ext_param | 常量 | "{}" | |

### 2.6 RawContentInfo → content_metrics

| 目标字段 | 来源 | SQL 空值处理 |
|---------|------|-------------|
| base_id | content_base.id | 回写 |
| total_impressions | raw.totalImpressions | IFNULL(#{totalImpressions}, 0) |
| total_clicks | raw.totalClicks | IFNULL(#{totalClicks}, 0) |
| total_reads | raw.totalReads | IFNULL(#{totalReads}, 0) |
| total_interactions | raw.totalInteractions | IFNULL(#{totalInteractions}, 0) |
| completion_rate | raw.completionRate | IFNULL(#{completionRate}, 0) |
| three_sec_completion_rate | raw.threeSecCompletionRate | IFNULL 0 |
| five_sec_completion_rate | raw.fiveSecCompletionRate | IFNULL 0 |
| two_sec_bounce_rate | raw.twoSecBounceRate | IFNULL 0 |
| cpm | raw.cpm | IFNULL(#{cpm}, 0) |
| ctr | raw.ctr | IFNULL 0 |
| cvr | raw.cvr | IFNULL 0 |
| app_downloads | raw.appDownloads | IFNULL 0 |
| new_activations | raw.newActivations | IFNULL 0 |
| new_registrations | raw.newRegistrations | IFNULL 0 |
| drive_uv | raw.driveUv | IFNULL 0 |
| exposure_to_read_ratio | raw.exposureToReadRatio | IFNULL 0 |
| potential_new_uv | raw.potentialNewUv | IFNULL 0 |
| potential_new_cac | raw.potentialNewCac | IFNULL 0 |
| attributed_new_customers | raw.attributedNewCustomers | IFNULL 0 |
| new_customer_cac | raw.newCustomerCac | IFNULL 0 |
| order_uv | raw.orderUv | IFNULL 0 |
| total_orders | raw.totalOrders | IFNULL 0 |
| ext_param | 常量 "{}" | — |

### 2.7 RawContentInfo → content_label

| 目标字段 | 来源 | 空值处理 | 备注 |
|---------|------|---------|------|
| base_id | content_base.id | 回写 | |
| city | raw.city | defaultIfBlank | 直接映射 |
| poi | raw.poi | defaultIfBlank | 直接映射 |
| ai_tag | 常量 | "[]" | AI 打标后异步更新 |
| ai_tag_detail | 常量 | null | AI 打标后异步更新 |
| task_id | 常量 | "" | 关联 AI 任务 |
| ext_param | 常量 | "{}" | |

---

## 三、子流程伪代码

### 3.1 buildContentBase

```java
private ContentBase buildContentBase(RawContentInfo raw) {
    ContentBase base = new ContentBase();
    base.setContentId(defaultIfBlank(raw.getContentId()));
    base.setBusinessContentId(defaultIfBlank(raw.getBusinessContentId()));
    base.setContentType(defaultIfBlank(raw.getContentType()));
    base.setContentTitle(defaultIfBlank(raw.getContentTitle()));
    base.setPublishPlatform(defaultIfBlank(raw.getPublishPlatform()));
    base.setPublishTime(defaultIfNull(raw.getPublishTime(), DEFAULT_DATE));
    base.setPublishUrl(defaultIfBlank(raw.getPublishUrl()));
    base.setBusinessLine(defaultIfBlank(raw.getBusinessLine()));
    base.setContentSource(defaultIfBlank(raw.getContentSource()));
    base.setProductionTeam(defaultIfBlank(raw.getProductionTeam()));
    base.setOperationProject(defaultIfBlank(raw.getOperationProject()));
    base.setPlacementPosition(defaultIfBlank(raw.getPlacementPosition()));
    base.setDt(defaultIfNull(raw.getDt(), DEFAULT_DATE));
    base.setContentRelations("{}");
    return base;
}
```

### 3.2 buildText

```java
private List<Long> buildText(RawContentInfo raw) {
    if (StringUtils.isBlank(raw.getContentText())) {
        return Collections.emptyList();
    }
    ContentText entity = new ContentText();
    entity.setContentTitle(defaultIfBlank(raw.getContentTitle()));
    entity.setContentText(raw.getContentText());
    entity.setPoi(defaultIfBlank(raw.getPoi()));
    entity.setTextLength(raw.getContentText().length());
    entity.setExtParam("{}");
    contentTextMapper.insert(entity);
    return Collections.singletonList(entity.getId());
}
```

### 3.3 buildImages（图文帖）

```java
private List<Long> buildImages(RawContentInfo raw) {
    if (StringUtils.isBlank(raw.getContentUrl())) {
        return Collections.emptyList();
    }
    List<Long> imageIds = new ArrayList<>();
    String[] urls = raw.getContentUrl().split(",");
    for (String url : urls) {
        url = url.trim();
        if (StringUtils.isBlank(url)) continue;

        // URL 全局去重
        ContentImage existing = contentImageMapper.selectByOriginalUrl(url);
        if (existing != null) {
            imageIds.add(existing.getId());
            continue;
        }

        ContentImage image = new ContentImage();
        image.setImageType("正文图");
        image.setOriginalUrl(url);
        image.setInternalUrl("");
        image.setWidth(0);
        image.setHeight(0);
        image.setAspectRatio(BigDecimal.ZERO);
        image.setImageSize(0L);
        image.setContentTitle(defaultIfBlank(raw.getContentTitle()));
        image.setPoi(defaultIfBlank(raw.getPoi()));
        image.setExtParam("{}");
        contentImageMapper.insert(image);
        imageIds.add(image.getId());
    }
    return imageIds;
}
```

### 3.4 buildVideo（短视频）

```java
private List<Long> buildVideo(RawContentInfo raw) {
    if (StringUtils.isBlank(raw.getContentUrl())) {
        return Collections.emptyList();
    }
    // URL 全局去重
    ContentVideo existing = contentVideoMapper.selectByVideoUrl(raw.getContentUrl());
    if (existing != null) {
        return Collections.singletonList(existing.getId());
    }

    ContentVideo video = new ContentVideo();
    video.setVideoUrl(raw.getContentUrl());
    video.setInternalVideoUrl("");
    video.setVideoCoverUrl(defaultIfBlank(raw.getVideoCoverUrl()));
    video.setDuration(0);
    video.setWidth(0);
    video.setHeight(0);
    video.setAspectRatio(BigDecimal.ZERO);
    video.setVideoSize(0L);
    video.setVideoFormat("");
    video.setVideoFrameParam("{\"frame\":[]}");
    video.setAudioUrl("");
    video.setAudioText(null);
    video.setPreprocessStatus(PreprocessStatus.PENDING);
    video.setContentTitle(defaultIfBlank(raw.getContentTitle()));
    video.setPoi(defaultIfBlank(raw.getPoi()));
    video.setExtParam("{}");
    contentVideoMapper.insert(video);
    return Collections.singletonList(video.getId());
}
```

### 3.5 buildVideoCover（短视频封面图 → content_image）

```java
private List<Long> buildVideoCover(RawContentInfo raw) {
    if (StringUtils.isBlank(raw.getVideoCoverUrl())) {
        return Collections.emptyList();
    }
    // URL 全局去重
    ContentImage existing = contentImageMapper.selectByOriginalUrl(raw.getVideoCoverUrl());
    if (existing != null) {
        return Collections.singletonList(existing.getId());
    }

    ContentImage cover = new ContentImage();
    cover.setImageType("封面图");
    cover.setOriginalUrl(raw.getVideoCoverUrl());
    cover.setInternalUrl("");
    cover.setWidth(0);
    cover.setHeight(0);
    cover.setAspectRatio(BigDecimal.ZERO);
    cover.setImageSize(0L);
    cover.setContentTitle(defaultIfBlank(raw.getContentTitle()));
    cover.setPoi(defaultIfBlank(raw.getPoi()));
    cover.setExtParam("{}");
    contentImageMapper.insert(cover);
    return Collections.singletonList(cover.getId());
}
```

### 3.6 buildLabel

```java
private void buildLabel(RawContentInfo raw, Long baseId) {
    ContentLabel label = new ContentLabel();
    label.setBaseId(baseId);
    label.setCity(defaultIfBlank(raw.getCity()));
    label.setPoi(defaultIfBlank(raw.getPoi()));
    label.setAiTag("[]");
    label.setAiTagDetail(null);
    label.setTaskId("");
    label.setExtParam("{}");
    contentLabelMapper.insertOrUpdate(label);
}
```

```xml
<!-- ContentLabelMapper.xml: INSERT ON DUPLICATE KEY UPDATE -->
<insert id="insertOrUpdate">
    INSERT INTO content_label (base_id, city, poi, ai_tag, ai_tag_detail, task_id, ext_param)
    VALUES (#{baseId}, #{city}, #{poi}, #{aiTag}, #{aiTagDetail}, #{taskId}, #{extParam})
    ON DUPLICATE KEY UPDATE
        city = VALUES(city),
        poi = VALUES(poi)
</insert>
```

### 3.7 buildMetrics

```java
private void buildMetrics(RawContentInfo raw, Long baseId) {
    ContentMetrics metrics = new ContentMetrics();
    metrics.setBaseId(baseId);
    metrics.setTotalImpressions(raw.getTotalImpressions());
    metrics.setTotalClicks(raw.getTotalClicks());
    metrics.setTotalReads(raw.getTotalReads());
    metrics.setTotalInteractions(raw.getTotalInteractions());
    metrics.setCompletionRate(raw.getCompletionRate());
    metrics.setThreeSecCompletionRate(raw.getThreeSecCompletionRate());
    metrics.setFiveSecCompletionRate(raw.getFiveSecCompletionRate());
    metrics.setTwoSecBounceRate(raw.getTwoSecBounceRate());
    metrics.setCpm(raw.getCpm());
    metrics.setCtr(raw.getCtr());
    metrics.setCvr(raw.getCvr());
    metrics.setAppDownloads(raw.getAppDownloads());
    metrics.setNewActivations(raw.getNewActivations());
    metrics.setNewRegistrations(raw.getNewRegistrations());
    metrics.setDriveUv(raw.getDriveUv());
    metrics.setExposureToReadRatio(raw.getExposureToReadRatio());
    metrics.setPotentialNewUv(raw.getPotentialNewUv());
    metrics.setPotentialNewCac(raw.getPotentialNewCac());
    metrics.setAttributedNewCustomers(raw.getAttributedNewCustomers());
    metrics.setNewCustomerCac(raw.getNewCustomerCac());
    metrics.setOrderUv(raw.getOrderUv());
    metrics.setTotalOrders(raw.getTotalOrders());
    metrics.setExtParam("{}");
    contentMetricsMapper.insertOrUpdate(metrics);
}
```

```xml
<!-- ContentMetricsMapper.xml -->
<insert id="insertOrUpdate">
    INSERT INTO content_metrics (
        base_id, total_impressions, total_clicks, total_reads, total_interactions,
        completion_rate, three_sec_completion_rate, five_sec_completion_rate, two_sec_bounce_rate,
        cpm, ctr, cvr,
        app_downloads, new_activations, new_registrations,
        drive_uv, exposure_to_read_ratio,
        potential_new_uv, potential_new_cac,
        attributed_new_customers, new_customer_cac,
        order_uv, total_orders, ext_param
    ) VALUES (
        #{baseId},
        IFNULL(#{totalImpressions}, 0), IFNULL(#{totalClicks}, 0),
        IFNULL(#{totalReads}, 0), IFNULL(#{totalInteractions}, 0),
        IFNULL(#{completionRate}, 0), IFNULL(#{threeSecCompletionRate}, 0),
        IFNULL(#{fiveSecCompletionRate}, 0), IFNULL(#{twoSecBounceRate}, 0),
        IFNULL(#{cpm}, 0), IFNULL(#{ctr}, 0), IFNULL(#{cvr}, 0),
        IFNULL(#{appDownloads}, 0), IFNULL(#{newActivations}, 0), IFNULL(#{newRegistrations}, 0),
        IFNULL(#{driveUv}, 0), IFNULL(#{exposureToReadRatio}, 0),
        IFNULL(#{potentialNewUv}, 0), IFNULL(#{potentialNewCac}, 0),
        IFNULL(#{attributedNewCustomers}, 0), IFNULL(#{newCustomerCac}, 0),
        IFNULL(#{orderUv}, 0), IFNULL(#{totalOrders}, 0),
        #{extParam}
    )
    ON DUPLICATE KEY UPDATE
        total_impressions = VALUES(total_impressions),
        total_clicks = VALUES(total_clicks),
        total_reads = VALUES(total_reads),
        total_interactions = VALUES(total_interactions),
        completion_rate = VALUES(completion_rate),
        three_sec_completion_rate = VALUES(three_sec_completion_rate),
        five_sec_completion_rate = VALUES(five_sec_completion_rate),
        two_sec_bounce_rate = VALUES(two_sec_bounce_rate),
        cpm = VALUES(cpm),
        ctr = VALUES(ctr),
        cvr = VALUES(cvr),
        app_downloads = VALUES(app_downloads),
        new_activations = VALUES(new_activations),
        new_registrations = VALUES(new_registrations),
        drive_uv = VALUES(drive_uv),
        exposure_to_read_ratio = VALUES(exposure_to_read_ratio),
        potential_new_uv = VALUES(potential_new_uv),
        potential_new_cac = VALUES(potential_new_cac),
        attributed_new_customers = VALUES(attributed_new_customers),
        new_customer_cac = VALUES(new_customer_cac),
        order_uv = VALUES(order_uv),
        total_orders = VALUES(total_orders)
</insert>
```

---

## 四、素材处理（同步阶段）

### 4.1 范围说明

**同步阶段只做 OSS 转存**，不做抽帧、ASR、多模态分析。视频的 ffmpeg 抽帧、音频提取、ASR 转写、多模态分析属于后续 AI 打标流程，不在当前同步范围内。

```
sync() 本次同步范围:
    │
    ├── content_type == "图文帖"
    │     └── 图片 URL → OSS 转存 → 回写 content_image.internal_url
    │
    └── content_type == "短视频"
          ├── 封面图 URL → OSS 转存 → 回写 content_image.internal_url
          └── 视频文件 → OSS 转存 → 回写 content_video.internal_video_url
```

### 4.2 现有能力复用

| 所需能力 | 现有服务 | 复用方式 |
|---------|---------|---------|
| URL→OSS 转存 | `OssTransferService.transferFromUrl(String)` | 直接注入调用 |

### 4.3 图片/封面 OSS 转存

图文帖和短视频的封面图都存储在 `content_image`，统一处理：

```
触发时机: syncDb() 事务提交后，同线程串行执行（见 §6 事务边界）
扫描范围: content_relations.image_ids 中 internal_url == "" 的记录
幂等保证: internal_url 不为空则跳过

OssTransferService.transferFromUrl(String) 返回 OSS 公网 URL
  ├── 成功 → 回写 content_image.internal_url
  └── 失败 → 记录 QMonitor，下次重试（不抛异常）
```

```java
@Resource
private OssTransferService ossTransferService;

public void transferImages(ContentBase base) {
    List<Long> imageIds = parseImageIds(base.getContentRelations());
    for (Long imageId : imageIds) {
        ContentImage image = contentImageMapper.selectById(imageId);
        if (image == null || StringUtils.isNotBlank(image.getInternalUrl())) {
            continue;
        }
        try {
            String ossUrl = ossTransferService.transferFromUrl(image.getOriginalUrl());
            if (StringUtils.isNotBlank(ossUrl)) {
                image.setInternalUrl(ossUrl);
                contentImageMapper.updateInternalUrl(image);
                QMonitor.recordOne("content_image_oss_success");
            }
        } catch (Exception e) {
            QMonitor.recordOne("content_image_oss_fail");
            log.warn("Image OSS transfer failed, imageId={}", imageId, e);
        }
    }
}
```

### 4.4 视频文件 OSS 转存

短视频的原始视频文件同样需要转存到 OSS：

```
触发时机: syncDb() 事务提交后，同线程串行执行（见 §6 事务边界）
扫描范围: content_relations.video_ids 中 internal_video_url == "" 的记录
幂等保证: internal_video_url 不为空则跳过
```

```java
public void transferVideos(ContentBase base) {
    List<Long> videoIds = parseVideoIds(base.getContentRelations());
    for (Long videoId : videoIds) {
        ContentVideo video = contentVideoMapper.selectById(videoId);
        if (video == null || StringUtils.isNotBlank(video.getInternalVideoUrl())) {
            continue;
        }
        try {
            String ossUrl = ossTransferService.transferFromUrl(video.getVideoUrl());
            if (StringUtils.isNotBlank(ossUrl)) {
                video.setInternalVideoUrl(ossUrl);
                contentVideoMapper.updateInternalVideoUrl(video);
                QMonitor.recordOne("content_video_oss_success");
            }
        } catch (Exception e) {
            QMonitor.recordOne("content_video_oss_fail");
            log.warn("Video OSS transfer failed, videoId={}", videoId, e);
        }
    }
}
```

### 4.5 content_video.preprocess_status 说明

`content_video.preprocess_status` 在同步阶段固定为 `0`（未处理），后续由独立的 AI 打标流程推进状态机。以下为未来扩展的完整状态定义，**本阶段不实现**：

```
preprocess_status 定义（预留，本阶段不实现）:
  0 = 未处理（PENDING）          ← 同步阶段固定为此值
  1 = 已抽帧（FRAMES_EXTRACTED）
  2 = 已提取音频（AUDIO_EXTRACTED）
  3 = 已转文字（ASR_DONE）
  4 = 全部完成（ALL_DONE）

后续 AI 打标流程：
  QSchedule 独立定时任务扫描 content_video WHERE preprocess_status < 4
  → 按 status 分发: 抽帧 → 提取音频 → ASR → 多模态分析
  → 结果写入 content_label.ai_tag
```

---

## 五、content_relations JSON 结构

```json
{"text_ids":[1],"image_ids":[1,2,3],"video_ids":[4]}
```

### 辅助对象

```java
@Data
public class ContentRelations {
    private List<Long> textIds = new ArrayList<>();
    private List<Long> imageIds = new ArrayList<>();
    private List<Long> videoIds = new ArrayList<>();
}
```

### 构建步骤

```
1. ContentRelations relations = new ContentRelations()
   (三字段默认为空列表)

2. buildText → relations.setTextIds(result)
3. buildImages → relations.setImageIds(result)          // 图文帖图片
4. buildVideo → relations.setVideoIds(result)
5. buildVideoCover → relations.getImageIds().addAll()   // 封面图追加到 image_ids

6. base.setContentRelations(JsonUtils.toJson(relations))
7. UPDATE content_base SET content_relations = ? WHERE id = ?
```

### 读取（素材处理时反查）

```java
private List<Long> parseImageIds(String contentRelationsJson) {
    ContentRelations relations = JsonUtils.jsonToObject(
        contentRelationsJson, ContentRelations.class);
    return relations != null ? relations.getImageIds() : Collections.emptyList();
}
```

---

## 六、事务边界与执行顺序

### 6.1 两阶段原则

```
每个 item 的执行严格按两阶段进行：
  阶段一 (事务内): DB 写入 → 事务提交
  阶段二 (事务外): OSS 转存

不允许在事务内调用 OssTransferService（网络 IO 会延长事务锁时间）。
DB 写入全部成功后才开始 OSS 转存，两者在同线程串行执行。
```

### 6.2 伪代码

```java
@Override
@Transactional(rollbackFor = Exception.class)
public void syncDb(RawContentInfo raw) {
    // 阶段一：仅 DB 写入，无 OSS
    // 失败抛异常 → 全部回滚，调用方更新 SYNC_FAILED
}

// 阶段二：OSS 转存在 @Transactional 外调用，同线程执行
// 失败记录 QMonitor，下次重试，不影响 sync 状态
public void sync(RawContentInfo raw) {
    syncDb(raw);              // 事务内：DB 写入
    doPostSync(raw);          // 事务外：OSS 转存
}
```

### 6.3 执行顺序细节

```
sync(RawContentInfo raw):
  │
  ├── 阶段一: @Transactional syncDb()
  │     ├── 首次同步 → 写入 content_base / text / image / video / label / metrics
  │     ├── 二次同步 → upsert label + metrics
  │     ├── 更新 content_relations
  │     └── 事务提交（此时 DB 完整可见）
  │
  └── 阶段二: doPostSync() (同线程，事务外)
        ├── contentType == "图文帖"
        │     └── transferImages()  → 回写 content_image.internal_url
        ├── contentType == "短视频"
        │     ├── transferImages()  → 回写封面图 internal_url
        │     └── transferVideos()  → 回写 content_video.internal_video_url
        └── 任何 OSS 失败 → 记录 QMonitor，不抛异常
```

---

## 七、幂等保证矩阵

| 表 | 幂等键 | 操作 | 写时机 |
|----|--------|------|--------|
| content_base | content_id UNIQUE | SELECT then INSERT | 首次 |
| content_text | — | INSERT new row | 首次 |
| content_image | original_url UNIQUE | SELECT → INSERT or 复用 | 首次 |
| content_video | video_url UNIQUE | SELECT → INSERT or 复用 | 首次 |
| content_metrics | base_id UNIQUE | INSERT ON DUPLICATE KEY UPDATE | 首次 + 二次 |
| content_label | base_id UNIQUE | INSERT ON DUPLICATE KEY UPDATE | 首次 + 二次 |
| video 抽帧 | video_frame_param != "" | 判空跳过 | 异步 |
| 图片 OSS 转存 | internal_url != "" | 判空跳过 | 异步 |

---

## 八、边界处理

| 场景 | 处理 |
|------|------|
| contentUrl 为空 | buildImages/buildVideo 返回 [] |
| contentText 为空 | buildText 返回 [] |
| contentType 非图文非短视频 | 跳过 image/video 分流 |
| videoCoverUrl 为空 | buildVideoCover 返回 [] |
| 指标字段为 null | SQL 层 IFNULL 兜底 |
| 二次同步（content_id 已存在） | 只走 metrics + label |
| 图片 URL 跨内容共享 | selectByOriginalUrl 命中，复用 id |
| 事务中抛异常 | @Transactional 全部回滚 |
| 图片 OSS 转存失败 | 记录 QMonitor + 日志，下次重试 |
| ASR 失败 | preprocess_status 不更新，下次重试 |
| 视频无法解码（抽帧结果为空） | 标记 ALL_DONE，跳过管线 |
| content_text 二次同步时变更 | 按存量约束不会发生（不做处理） |

---

## 九、常量定义

```java
// ContentType — 替代散落字符串字面量
public interface ContentType {
    String IMAGE_TEXT = "图文帖";
    String SHORT_VIDEO = "短视频";
}

// PreprocessStatus — 视频预处理状态机
public interface PreprocessStatus {
    int PENDING = 0;
    int FRAMES_EXTRACTED = 1;
    int AUDIO_EXTRACTED = 2;
    int ASR_DONE = 3;
    int ALL_DONE = 4;
}

// ImageType — content_image.image_type 取值
public interface ImageType {
    String BODY = "正文图";
    String COVER = "封面图";
}
```

---

## 十、并发同步任务设计

### 10.1 设计原则与执行顺序

```
单个 item 的执行顺序（关键）:

  processItem(raw)
    │
    ├── 第一步: syncDb(raw)            → @Transactional，仅 DB 写入
    │       ├── INSERT content_base
    │       ├── INSERT content_text
    │       ├── INSERT content_image    (original_url, internal_url = "")
    │       ├── INSERT content_video    (video_url, internal_video_url = "")
    │       ├── UPSERT content_label
    │       ├── UPSERT content_metrics
    │       ├── UPDATE content_relations
    │       └── 事务提交
    │
    └── 第二步: doPostSync(raw, base)  → 事务外，同线程串行
            ├── contentType == "图文帖" → transferImages()
            ├── contentType == "短视频" → transferImages() + transferVideos()
            └── OSS 失败只记 QMonitor，不抛异常
```

**为什么要先 DB 后 OSS？**
- OSS 转存是网络 IO，放在事务内会长时间持有 DB 连接和锁
- DB 写入先完成提交，即使 OSS 失败，基础数据已落库，可重试补偿
- 同线程串行保证二者有序，不需要额外的协调机制

```
task 层面多个内容的 processItem() 通过线程池并行  → 并发控制
```

- **单条内容的三步（syncDb → commit → OSS）**：同线程串行，无并发困扰
- **Task 批量处理**：多个内容的 `processItem` 通过线程池并行，互不影响
- **动态并发控制**：一次执行多少条通过 QConfig 可调

### 10.2 线程池配置

参考 `ThreadPoolTaskExecutor` 模式（`corePoolSize`、`maxPoolSize` 绑定，拒绝策略直接取消）：

```java
@Configuration
public class RawContentSyncExecutorConfig {

    @Bean("rawContentSyncExecutor")
    public TaskExecutor rawContentSyncExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(16);
        executor.setMaxPoolSize(16);
        executor.setQueueCapacity(1024);
        executor.setKeepAliveSeconds(60);
        executor.setThreadNamePrefix("rawContentSync-");
        // 拒绝策略：直接取消任务
        executor.setRejectedExecutionHandler((r, exe) -> {
            QMonitor.recordOne("rawContentSync-reject");
            if (r instanceof FutureTask) {
                ((FutureTask<?>) r).cancel(true);
            } else {
                throw new RejectedExecutionException("rawContentSyncExecutor 拒绝任务");
            }
        });
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.initialize();
        executor.getThreadPoolExecutor().prestartCoreThreads();
        return executor;
    }
}
```

### 10.3 QConfig 动态并发数

```java
// RawContentQConfig 新增
public int getMaxConcurrency() {
    return hotFileQConfig.getInt("raw.content.sync.maxConcurrency", 8);
}
```

```properties
# hotfile.properties
raw.content.sync.maxConcurrency=8
```

### 10.4 两种运行模式

支持测试和正式两种模式，通过 QConfig 动态切换：

| 模式 | 配置 | 行为 |
|------|------|------|
| 测试模式 | `testMode=true` | 只取一批数据（默认 10 条），处理完后退出 |
| 正式模式 | `testMode=false` | `while(true)` 循环处理，直至全部数据同步完成 |

```
QSchedule 触发
    │
    ├── isSyncEnabled? → 否 → return
    │
    ├── testMode? → 是 → doSyncTest()
    │       │
    │       ├── 取 testBatchSize 条
    │       ├── 按 maxConcurrency 分批并行执行
    │       ├── 记录监控
    │       └── 退出
    │
    └── testMode? → 否 → doSyncProduction()
            │
            ├── while(true)
            │   ├── isSyncEnabled? → 否 → break（退出开关）
            │   ├── getUnsynchronized(batchSize) → 空 → break（全部完成）
            │   │
            │   ├── 按 maxConcurrency 分批
            │   │       │
            │   │       └── 每批:
            │   │               ├── processItem(item) -- 同线程串行:
            │   │               │     第一步: syncDb()  → @Transactional DB写入
            │   │               │     第二步: doPostSync() → OSS 转存
            │   │               │     第三步: updateSyncStatus(SYNCED)
            │   │               ├── ... (每批并行数 = maxConcurrency)
            │   │               └── CompletableFuture.allOf(futures).get(timeout)
            │   │
            │   └── 累计 totalSuccess / totalFail / updateProgress
            │
            └── 记录最终监控
```

### 10.5 QConfig 新增配置

```java
// RawContentQConfig 新增
public boolean isTestMode() {
    return hotFileQConfig.getBoolean("raw.content.sync.testMode", false);
}

public int getTestBatchSize() {
    return hotFileQConfig.getInt("raw.content.sync.testBatchSize", 10);
}
```

```properties
# hotfile.properties
raw.content.sync.testMode=false
raw.content.sync.testBatchSize=10
```

### 10.6 Task 实现

```java
@Service
public class RawContentSyncTask {

    private static final Logger LOG = LoggerFactory.getLogger(RawContentSyncTask.class);

    @Resource(name = "rawContentSyncExecutor")
    private TaskExecutor rawContentSyncExecutor;

    @Resource
    private RawContentService rawContentService;

    @Resource
    private RawContentQConfig rawContentQConfig;

    @Resource
    private RawContentRedisService rawContentRedisService;

    @QSchedule("mkt_odin_raw_content_sync")
    public void syncTask(Parameter param) {
        LOG.info("Raw content sync task start");
        final TaskMonitor monitor = TaskHolder.getKeeper();

        if (!rawContentQConfig.isSyncEnabled()) {
            monitor.getLogger().info("Sync task is disabled by config");
            return;
        }

        monitor.autoAck(false);
        try {
            doSyncTask(monitor);
        } catch (Exception e) {
            LOG.error("Sync task error", e);
        } finally {
            if (!monitor.isStopped()) {
                monitor.finish();
            }
        }
    }

    private void doSyncTask(TaskMonitor monitor) {
        if (rawContentQConfig.isTestMode()) {
            doSyncTest(monitor);
        } else {
            doSyncProduction(monitor);
        }
    }

    /** 测试模式：处理一批数据后退出 */
    private void doSyncTest(TaskMonitor monitor) {
        int batchSize = rawContentQConfig.getTestBatchSize();
        int maxConcurrency = rawContentQConfig.getMaxConcurrency();

        List<RawContentInfo> dataList = rawContentService.getUnsynchronized(batchSize);
        if (CollectionUtils.isEmpty(dataList)) {
            monitor.getLogger().info("Test mode: no unsynchronized data found");
            return;
        }
        monitor.setRateCapacity(dataList.size());

        BatchResult result = executeBatch(dataList, maxConcurrency);
        updateProgress(dataList, monitor);

        monitor.getLogger().info("Test mode done, total={}, success={}, fail={}",
                dataList.size(), result.success, result.fail);
    }

    /** 正式模式：while(true) 直至全部完成 */
    private void doSyncProduction(TaskMonitor monitor) {
        int batchSize = rawContentQConfig.getBatchSize();
        int maxConcurrency = rawContentQConfig.getMaxConcurrency();
        int totalSuccess = 0;
        int totalFail = 0;
        int totalProcessed = 0;

        while (true) {
            if (!rawContentQConfig.isSyncEnabled()) {
                monitor.getLogger().info("Sync disabled by config, exiting loop");
                break;
            }

            List<RawContentInfo> dataList = rawContentService.getUnsynchronized(batchSize);
            if (CollectionUtils.isEmpty(dataList)) {
                monitor.getLogger().info("All data synced");
                break;
            }

            monitor.setRateCapacity(dataList.size());

            List<List<RawContentInfo>> batches = Lists.partition(dataList, maxConcurrency);
            for (List<RawContentInfo> batch : batches) {
                if (!rawContentQConfig.isSyncEnabled()) {
                    monitor.getLogger().info("Sync disabled mid-batch, exiting");
                    break;
                }
                BatchResult result = executeBatch(batch, maxConcurrency);
                totalSuccess += result.success;
                totalFail += result.fail;
                totalProcessed += batch.size();
                updateProgress(batch, monitor);
            }
        }

        monitor.getLogger().info("Production done, totalProcessed={}, success={}, fail={}",
                totalProcessed, totalSuccess, totalFail);
        QMonitor.recordMany("raw_content_sync_success", totalSuccess, 0);
        QMonitor.recordMany("raw_content_sync_fail", totalFail, 0);
    }

    /** 并行执行一批 */
    private BatchResult executeBatch(List<RawContentInfo> batch, int maxConcurrency) {
        List<CompletableFuture<Void>> futures = new ArrayList<>(batch.size());
        for (RawContentInfo data : batch) {
            futures.add(CompletableFuture.runAsync(() -> processItem(data), rawContentSyncExecutor)
                    .exceptionally(e -> {
                        LOG.error("Failed to process, id={}", data.getId(), e);
                        QMonitor.recordOne("raw_content_sync_process_fail");
                        return null;
                    }));
        }
        try {
            CompletableFuture.allOf(futures.toArray(new CompletableFuture[0]))
                    .get(5, TimeUnit.MINUTES);
        } catch (Exception e) {
            LOG.warn("Batch timeout/interrupted", e);
        }
        return countResults(batch);
    }

    private void processItem(RawContentInfo data) {
        // 第一步：DB 写入（事务内，无 OSS）
        rawContentService.syncDb(data);
        // 第二步：OSS 转存（事务外，同线程串行）
        rawContentService.doPostSync(data);
        rawContentService.updateSyncStatus(data.getId(), SyncStatus.SYNCED.getCode());
    }

    private BatchResult countResults(List<RawContentInfo> batch) {
        int success = 0, fail = 0;
        for (RawContentInfo data : batch) {
            try {
                RawContentInfo refreshed = rawContentService.getById(data.getId());
                if (refreshed != null && SyncStatus.SYNCED.getCode() == refreshed.getSyncStatus()) {
                    success++;
                } else {
                    fail++;
                }
            } catch (Exception e) {
                LOG.warn("Failed to check status for id={}", data.getId(), e);
                fail++;
            }
        }
        return new BatchResult(success, fail);
    }

    private void updateProgress(List<RawContentInfo> batch, TaskMonitor monitor) {
        for (RawContentInfo data : batch) {
            rawContentRedisService.updateLastProcessedId(data.getId());
            monitor.addRate(1);
        }
    }

    private static class BatchResult {
        final int success;
        final int fail;
        BatchResult(int success, int fail) {
            this.success = success;
            this.fail = fail;
        }
    }
}
```

### 10.7 关键要点

| 要点 | 说明 |
|------|------|
| 执行顺序 | 每个 item 严格两阶段：`syncDb()`(事务内DB) → 事务提交 → `doPostSync()`(事务外OSS) |
| OSS 放在事务外 | 避免网络 IO 长时间占用 DB 连接和锁 |
| OSS 失败不阻塞 | 失败只记 QMonitor，基础数据已落库可重试 |
| 单条失败不影响批量 | `CompletableFuture.exceptionally()` 吞异常返回 null |
| 超时兜底 | `allOf().get(5min)` 避免极端情况卡死，超时后进入下一批 |
| 状态反查 | 批完成后重新查询 DB 确认状态，而非依赖内存变量 |
| 拒绝策略 | 线程池满时 FutureTask.cancel(true)，不会阻塞提交线程 |
| 并发数可调 | `raw.content.sync.maxConcurrency` 上线后根据 DB 负载动态调整 |