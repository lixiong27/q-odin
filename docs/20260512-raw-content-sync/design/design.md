# RawContentSyncTask 业务表同步 — 设计方案

## 核心设计决策

### 存量约束：仅指标会再次同步

存量数据中，同 content_id 再次同步 **只更新 content_metrics**，业务字段（标题、正文、图片URL、视频URL、city/poi 等）不会变。

这意味着：
- 对某个 content_id 的首次同步 = 全量写 6 张表
- 后续再次同步 = **SELECT content_base**（复用 baseId）→ **写 content_metrics**（INSERT ON DUPLICATE KEY UPDATE），其他表不写

### 子表去掉 base_id，关系由 content_base 统一维护

```
之前:  content_text.base_id → content_base.id
       content_image.base_id → content_base.id
       content_video.base_id → content_base.id

之后:  content_base.content_relations = {
         "text_ids": [123],
         "image_ids": [1, 2, 3],
         "video_ids": [456]
       }
```

**为什么这样更好：**

1. **解决图片/视频跨 content 共享问题** — 同一 URL 在两个 content 中出现，各自的 content_relations 都指向同一个 image_id，image 表 UNIQUE 保证不重复
2. **text/video 统一用数组** — text_ids 和 video_ids 都是数组，即使只有一条数据也是 `[123]`，结构统一

---

## 一、DDL 变更

### content_base 新增字段

```sql
ALTER TABLE content_base
    ADD COLUMN `content_relations` JSON NOT NULL COMMENT '关联关系：{text_ids:[], image_ids:[], video_ids:[]}';
```

### content_text / content_image / content_video 去掉 base_id

```sql
ALTER TABLE content_text DROP COLUMN base_id;
ALTER TABLE content_image DROP COLUMN base_id;
ALTER TABLE content_video DROP COLUMN base_id;
```

### content_metrics / content_label 不变

这两个表仍然是 1:1 关系，保留 `base_id` + UNIQUE 约束。

---

## 二、同步流程

```
RawContentSyncService.sync(RawContentInfo raw):

  1. 查 content_base
     SELECT BY content_id
     ├── 首次 → baseId = null
     └── 已存在 → baseId（仅 metrics 更新场景走到这里）

  if baseId == null:

    2a. INSERT content_base → baseId, content_relations = {}

    3a. 写 content_text
        contentText 不为空 → INSERT content_text → textId
        → content_relations.text_ids = [textId]
        contentText 为空 → content_relations.text_ids = []

    4a. 按 contentType 分流:

        【图文】
        contentUrl 按逗号拆分 → 逐个:
          SELECT content_image BY original_url
          ├── 命中 → 已有 imageId
          └── 未命中 → INSERT → 新 imageId
        → 收集所有 imageId → content_relations.image_ids

        【短视频】
          contentUrl → SELECT content_video BY video_url
          ├── 命中 → videoId
          └── 未命中 → INSERT → videoId
          → content_relations.video_ids = [videoId]

          videoCoverUrl → SELECT content_image BY original_url
          ├── 命中 → coverImageId
          └── 未命中 → INSERT → coverImageId
          → 追加到 content_relations.image_ids

        【其他类型】
          不写 image/video，跳过

    5a. UPDATE content_base.content_relations = 最新 JSON

  ─────────────────────────────────────────
  if baseId != null: (首次同步后，baseId 一定非空)

    2b. 写 content_label
        INSERT ... ON DUPLICATE KEY UPDATE (base_id)
        ai_tag = '[]'（首次），后续 AI 流程覆盖

    6. 写 content_metrics
       INSERT ... ON DUPLICATE KEY UPDATE (base_id)
```

### 流程说明

| 条件 | 写入的表 |
|------|---------|
| 首次同步 (baseId == null) | content_base + content_text + content_image/video + content_label + content_metrics |
| 二次同步 (baseId != null) | content_metrics（+ content_label 兜底） |

- content_label 在首次/二次都执行 `ON DUPLICATE KEY UPDATE`，保证兜底
- content_metrics 始终执行 `INSERT ON DUPLICATE KEY UPDATE`，这是唯一会真正 UPDATE 的表

---

## 三、content_relations JSON 结构

```json
{
  "text_ids": [1001],
  "image_ids": [2001, 2002, 2003],
  "video_ids": [3001]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| text_ids | [Long] | content_text.id 列表，可为空数组 |
| image_ids | [Long] | content_image.id 列表，可为空数组 |
| video_ids | [Long] | content_video.id 列表，可为空数组 |

---

## 四、幂等性保证

| 表 | 幂等键 | 操作 | 写时机 |
|----|--------|------|--------|
| content_base | content_id UNIQUE | SELECT then INSERT | 首次 |
| content_text | content_relations.text_ids[n] | INSERT new row | 首次 |
| content_image | original_url UNIQUE | SELECT by url → INSERT or 复用已有 id | 首次 |
| content_video | video_url UNIQUE | SELECT by url → INSERT or 复用已有 id | 首次 |
| content_metrics | base_id UNIQUE | INSERT ON DUPLICATE KEY UPDATE | 首次 + 二次 |
| content_label | base_id UNIQUE | INSERT ON DUPLICATE KEY UPDATE | 首次 + 二次（兜底） |

---

## 五、边界处理

| 场景 | 处理 |
|------|------|
| contentUrl 为空 | 跳过图片/视频处理，image_ids = [], video_ids = [] |
| contentText 为空 | 跳过 text 处理，text_ids = [] |
| contentType 非图文也非短视频 | 仅写 base + text + metrics + label，不写 image/video |
| BigDecimal 为 null | MyBatis IFNULL 设默认值 0 |
| 视频类型无 videoCoverUrl | 不写 content_image |
| 二次同步时 contentUrl/Text 与首次不同 | 按约束不会发生，不做特殊处理 |

## 六、事务边界

整个 `sync()` 在一个 `@Transactional` 中：
- 成功：全部提交，调用方更新 raw_content.syncStatus = SYNCED
- 失败：全部回滚，调用方更新 raw_content.syncStatus = SYNC_FAILED