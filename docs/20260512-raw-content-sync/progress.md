# RawContentSyncTask 业务表同步

## 一、源数据 → 目标表映射总览

```
raw_content (RawContentInfo, ~40 字段)
    │
    ├──[1]── content_base      内容身份 + 发布 + 业务归属
    ├──[2]── content_text      正文内容 + 冗余标题/POI
    ├──[3]── content_image     contentUrl 按逗号拆分 → 图片行（仅图文类型）
    ├──[4]── content_video     视频URL + 封面 + 预处理占位（仅短视频类型）
    ├──[5]── content_metrics   曝光/点击/播放/转化/增长/归因/订单，全部指标
    └──[6]── content_label     city/POI + AI 标签占位
```

---

## 二、逐表字段映射

### 2.1 content_base（内容基础信息表）

| 目标字段 | 来源 | 映射 |
|---------|------|------|
| id | auto | 自增 |
| content_id | raw.contentId | 直接映射 |
| business_content_id | raw.businessContentId | 直接映射 |
| content_type | raw.contentType | "图文" / "短视频" |
| content_title | raw.contentTitle | 直接映射 |
| publish_platform | raw.publishPlatform | "小红书" / "抖音" |
| publish_time | raw.publishTime | 直接映射 |
| publish_url | raw.publishUrl | 直接映射 |
| business_line | raw.businessLine | 直接映射 |
| content_source | raw.contentSource | 直接映射 |
| production_team | raw.productionTeam | 直接映射 |
| operation_project | raw.operationProject | 直接映射 |
| placement_position | raw.placementPosition | 直接映射 |
| dt | raw.dt | Date → DATE |
| create_time / update_time | auto | CURRENT_TIMESTAMP |

**去重策略：** `UNIQUE KEY uniq_content_id (content_id)`
- 首次同步 → INSERT
- 再次同步同 content_id → ON DUPLICATE KEY UPDATE（覆盖业务字段 + update_time）

### 2.2 content_text（内容文本表）

| 目标字段 | 来源 | 映射 |
|---------|------|------|
| id | auto | 自增 |
| content_title（冗余） | raw.contentTitle | 直接映射 |
| content_text | raw.contentText | 直接映射 |
| poi（冗余） | raw.poi | 直接映射 |
| text_length | 计算 | raw.contentText.length() |
| ext_param | — | "{}"（预留扩展） |

**关联方式：** 通过 content_base.content_relations.text_ids 引用。
- contentText 不为空 → INSERT → textId 写入 text_ids = [textId]
- contentText 为空 → text_ids = []
- 再次同步时 INSERT 新行，旧 text 行成为孤儿（不清理）

### 2.3 content_image（内容图片表）

| 目标字段 | 来源 | 映射 |
|---------|------|------|
| id | auto | 自增 |
| image_type | 约定 | "正文图" / "封面图" |
| original_url | raw.contentUrl 拆分 | 逗号分割后逐个 |
| internal_url | — | ""（OSS 转存暂不做） |
| width/height/aspect_ratio/image_size | — | 0（raw_content 无此数据） |
| content_title（冗余） | raw.contentTitle | 直接映射 |
| poi（冗余） | raw.poi | 直接映射 |
| ext_param | — | "{}" |

**关联方式：** 通过 content_base.content_relations.image_ids 引用。
- `contentType == "图文"`: raw.contentUrl 按逗号分割 → 每个 URL 查/插 content_image → 收集 imageIds
- `contentType == "短视频"`: videoCoverUrl → 查/插 content_image → imageId
- URL 全局去重：`original_url` UNIQUE，共享同一 image_id

### 2.4 content_video（内容视频表）

| 目标字段 | 来源 | 映射 |
|---------|------|------|
| id | auto | 自增 |
| video_url | raw.contentUrl | 直接映射（短视频类型时） |
| internal_video_url | — | ""（OSS 转存暂不做） |
| video_cover_url | raw.videoCoverUrl | 直接映射 |
| duration | — | 0（raw_content 无此数据） |
| width/height/aspect_ratio/video_size | — | 0 |
| video_format | — | ""（raw_content 无此数据） |
| video_frame_param | — | `{"frame":[]}` |
| audio_url | — | "" |
| audio_text | — | null |
| preprocess_status | — | 0（预处理状态由后续流程更新） |
| content_title（冗余） | raw.contentTitle | 直接映射 |
| poi（冗余） | raw.poi | 直接映射 |
| ext_param | — | "{}" |

**关联方式：** 通过 content_base.content_relations.video_ids 引用。
- 仅当 `contentType == "短视频"` 时写此表
- 视频 URL 全局去重：`video_url` UNIQUE
- 再同步：命中已有 video 行 → UPDATE 字段，复用已有 videoId

### 2.5 content_metrics（内容指标表）

| 目标字段                      | 来源                         | 映射                        |
| ------------------------- | -------------------------- | ------------------------- |
| base_id                   | content_base.id            | INSERT base 后获取           |
| total_impressions         | raw.totalImpressions       | 直接映射                      |
| total_clicks              | raw.totalClicks            | 直接映射                      |
| total_reads               | raw.totalReads             | 直接映射                      |
| total_interactions        | raw.totalInteractions      | 直接映射                      |
| completion_rate           | raw.completionRate         | BigDecimal → DECIMAL(8,3) |
| three_sec_completion_rate | raw.threeSecCompletionRate | 同上                        |
| five_sec_completion_rate  | raw.fiveSecCompletionRate  | 同上                        |
| two_sec_bounce_rate       | raw.twoSecBounceRate       | 同上                        |
| cpm                       | raw.cpm                    | BigDecimal → DECIMAL(8,4) |
| ctr                       | raw.ctr                    | BigDecimal → DECIMAL(8,3) |
| cvr                       | raw.cvr                    | BigDecimal → DECIMAL(8,3) |
| app_downloads             | raw.appDownloads           | 直接映射                      |
| new_activations           | raw.newActivations         | 直接映射                      |
| new_registrations         | raw.newRegistrations       | 直接映射                      |
| drive_uv                  | raw.driveUv                | 直接映射                      |
| exposure_to_read_ratio    | raw.exposureToReadRatio    | BigDecimal → DECIMAL(8,3) |
| potential_new_uv          | raw.potentialNewUv         | 直接映射                      |
| potential_new_cac         | raw.potentialNewCac        | BigDecimal → DECIMAL(9,3) |
| attributed_new_customers  | raw.attributedNewCustomers | 直接映射                      |
| new_customer_cac          | raw.newCustomerCac         | BigDecimal → DECIMAL(9,3) |
| order_uv                  | raw.orderUv                | 直接映射                      |
| total_orders              | raw.totalOrders            | 直接映射                      |
| ext_param                 | —                          | "{}"                      |

**去重：** `UNIQUE KEY uniq_base_id (base_id)` — 与 content_base 一对一
- 首次同步 → INSERT
- 再次同步（数据更新）→ ON DUPLICATE KEY UPDATE（覆盖全部指标）

**注意：** raw_content 中的 INT/BigDecimal 字段可能为 null，插入时需处理默认值（MySQL 有 NOT NULL DEFAULT 0，MyBatis 用 IFNULL）。

### 2.6 content_label（内容标签表）

| 目标字段 | 来源 | 映射 |
|---------|------|------|
| base_id | content_base.id | INSERT base 后获取 |
| city | raw.city | 直接映射 |
| poi | raw.poi | 直接映射 |
| ai_tag | — | `'[]'`（空 JSON 数组） |
| ai_tag_detail | — | null |
| task_id | — | ""（AI 任务暂不关联） |
| ext_param | — | "{}" |

**去重：** `UNIQUE KEY uniq_base_id (base_id)`
- 首次同步 → INSERT
- 再次同步 → ON DUPLICATE KEY UPDATE（覆盖 city/poi）

**说明：** `ai_tag` 和 `ai_tag_detail` 由 AI 打标流程异步写入，本次同步仅写 city/poi。注意 DDL 中 `ai_tag` 是 `JSON NOT NULL`，所以必须写 `'[]'` 而不能留空。

---

## 三、同步流程设计

### 3.1 RawContentSyncService.sync() 核心流程

详见 [design/design.md](design/design.md) 第二节，核心步骤：

```
RawContentSyncService.sync(RawContentInfo raw):

  1. 查 content_base
     SELECT BY content_id
     ├── 首次 → baseId = null
     └── 已存在 → baseId（仅 metrics 更新场景走到这里）

  if baseId == null:
    2a. INSERT content_base → baseId, content_relations = {}
    3a. 写 content_text (INSERT) → textId → text_ids = [textId] 或 []
    4a. 按 contentType 分流写 image/video → 收集 ids
    5a. UPDATE content_base.content_relations = 最新 JSON

  2b. 写 content_label (ON DUPLICATE KEY UPDATE)
  6.  写 content_metrics (ON DUPLICATE KEY UPDATE)
```

| 条件 | 写入的表 |
|------|---------|
| 首次同步 | content_base + content_text + image/video + content_label + content_metrics |
| 二次同步 | content_metrics（+ content_label 兜底） |

**存量约束：** 二次同步只更新 content_metrics，业务字段不会变。

### 3.2 事务边界

整个 `sync()` 包在一个 `@Transactional` 中。
- 成功 → 6 张表全部提交，调用方更新 raw_content.syncStatus = SYNCED
- 失败 → 全部回滚，调用方更新 raw_content.syncStatus = SYNC_FAILED

### 3.3 幂等性

| 表 | 幂等键 | 操作 | 写时机 |
|----|--------|------|--------|
| content_base | content_id UNIQUE | SELECT then INSERT | 首次 |
| content_text | content_relations.text_ids[n] | INSERT new row | 首次 |
| content_image | original_url UNIQUE | SELECT by url → INSERT or 复用已有 id | 首次 |
| content_video | video_url UNIQUE | SELECT by url → INSERT or 复用已有 id | 首次 |
| content_metrics | base_id UNIQUE | INSERT ON DUPLICATE KEY UPDATE | 首次 + 二次 |
| content_label | base_id UNIQUE | INSERT ON DUPLICATE KEY UPDATE | 首次 + 二次（兜底） |

---

## 五、实现计划

### 5.1 架构调整

同步业务逻辑不放在 `RawContentServiceImpl.executeBusinessLogic()` 中，用独立的 `RawContentSyncService` 承接：

```
RawContentSyncTask / RawContentServiceImpl.triggerSync()
    │
    └── RawContentSyncService.sync(RawContentInfo)   ← @Transactional
            │
            ├── 1. 写 content_base (INSERT or UPDATE)
            ├── 2. 写 content_text (INSERT)
            ├── 3. 按 contentType 写 image / video
            ├── 4. UPDATE content_base.content_relations
            ├── 5. 写 content_metrics (ON DUPLICATE KEY UPDATE)
            └── 6. 写 content_label (ON DUPLICATE KEY UPDATE)
```

### 需要新建的文件

| 文件 | 说明 |
|------|------|
| `domain/entity/raw/ContentBase.java` | content_base 实体 |
| `domain/entity/raw/ContentText.java` | content_text 实体 |
| `domain/entity/raw/ContentImage.java` | content_image 实体 |
| `domain/entity/raw/ContentVideo.java` | content_video 实体 |
| `domain/entity/raw/ContentMetrics.java` | content_metrics 实体 |
| `domain/entity/raw/ContentLabel.java` | content_label 实体 |
| `infra/dao/ContentBaseMapper.java` | base 表 Mapper 接口 |
| `infra/dao/ContentTextMapper.java` | text 表 Mapper 接口 |
| `infra/dao/ContentImageMapper.java` | image 表 Mapper 接口 |
| `infra/dao/ContentVideoMapper.java` | video 表 Mapper 接口 |
| `infra/dao/ContentMetricsMapper.java` | metrics 表 Mapper 接口 |
| `infra/dao/ContentLabelMapper.java` | label 表 Mapper 接口 |
| `resources/mapper/ContentBaseMapper.xml` | base 表 SQL |
| `resources/mapper/ContentTextMapper.xml` | text 表 SQL |
| `resources/mapper/ContentImageMapper.xml` | image 表 SQL |
| `resources/mapper/ContentVideoMapper.xml` | video 表 SQL |
| `resources/mapper/ContentMetricsMapper.xml` | metrics 表 SQL |
| `resources/mapper/ContentLabelMapper.xml` | label 表 SQL |
| `service/raw/RawContentSyncService.java` | 同步服务接口 |
| `service/raw/impl/RawContentSyncServiceImpl.java` | 同步服务实现（@Transactional） |

### 需要修改的现有文件

| 文件 | 改动 |
|------|------|
| `task/RawContentSyncTask.java` | `executeBusinessLogic(data)` → `syncService.sync(data)` |
| `service/raw/impl/RawContentServiceImpl.java` | `triggerSync()` 中调用 `syncService.sync(data)`；移除 `executeBusinessLogic` |

### 5.2 RawContentSyncService 接口

```java
public interface RawContentSyncService {
    /**
     * 同步单条 raw_content → 6 张业务表
     */
    void sync(RawContentInfo raw);
}
```

---

## 当前状态

**阶段：** 设计文档 — 已完成

**阻塞项：** 无

**下一步：** 进入实现阶段