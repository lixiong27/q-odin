# 素材库需求文档

> 版本：v0.5
> 日期：2026-06-11
> 状态：草稿

---

## 1. 需求概述

### 1.1 背景

通过抓取调度系统（CrawlScheduler）从抖音、小红书抓取视频素材，经 QMQ 回调后将数据回传 ODIN，最终落地到素材库表中，支持前端素材模块的 ES 检索。

### 1.2 整体流程

```
┌──────────────────────────────────────────────────────────────────────┐
│ 阶段一：任务下发（已有）                                               │
│                                                                      │
│ MaterialCrawlExecutor                                                 │
│   → CrawlTaskClient.createBigSearchTask() / createDetailTask()        │
│   → CrawlScheduler 开始抓取                                           │
└──────────────────────────┬───────────────────────────────────────────┘
                           │ QMQ 回调
                           ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 阶段二：回调处理（增强已有 Handler）                                    │
│                                                                      │
│ CrawlTaskResultConsumer                                               │
│   → CrawlTaskResultProcessor                                          │
│     → XxxCrawlTaskResultHandler (Douyin / Xhs)                       │
│       → Step 1: 反序列化回调 data                                     │
│       → Step 2: 提取字段 → 组装 MaterialCrawlResult                   │
│       → Step 3: 持久化到 sub_task.result                              │
│       → Step 4: 更新子任务状态 → SUCCESS                              │
└──────────────────────────┬───────────────────────────────────────────┘
                           │ 定时任务轮询（@QSchedule）
                           ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 阶段三：MaterialProcessTask — 素材入库异步处理（新增）                  │
│                                                                      │
│ @QSchedule("mkt_odin_crawtask_material_process")                      │
│                                                                      │
│ scanAndProcess() 扫描 SUCCESS 状态的抓取子任务                         │
│   │                                                                  │
│   ├─ 1. 数据合法性校验                                                │
│   │   └─ 不合规 → log + continue                                     │
│   │                                                                  │
│   ├─ 2. 查重：SELECT FROM material_base WHERE material_id = ?         │
│   │   ├─ 已存在 → 更新 metrics，检查 OSS 链接是否已转存                │
│   │   │   └─ video_url 为空 → 走 OSS 转存后更新                      │
│   │   └─ 不存在 → 继续走全量入库流程                                  │
│   │                                                                  │
│   ├─ 3. 验证下载链接可访问性                                          │
│   │   ├─ HTTP HEAD videoUrl / coverUrl，超时 3s                       │
│   │   ├─ 不可访问 → log + QMonitor + continue                         │
│   │   └─ 可访问 → 继续                                               │
│   │                                                                  │
│   ├─ 4. OSS 转存（同步）                                              │
│   │   ├─ videoUrl → OssClient → internalVideoUrl                     │
│   │   ├─ coverUrl → OssClient → internalCoverUrl                     │
│   │   └─ OSS 失败 → log + QMonitor + continue                        │
│   │                                                                  │
│   ├─ 5. 写入素材库（事务内）                                          │
│   │   ├─ INSERT/UPDATE material_base                                 │
│   │   ├─ INSERT material_video                                       │
│   │   ├─ INSERT/UPDATE material_metrics                              │
│   │   └─ 事务提交                                                    │
│   │                                                                  │
│   ├─ 6. ES 索引同步 → material_search                                │
│   │   └─ 失败 → log + QMonitor 告警（不影响主流程）                   │
│   │                                                                  │
│   └─ 7. 更新子任务状态 → ANALYSIS_SUCCESS / ANALYSIS_FAIL            │
│       └─ 失败节点明细记录到 sub_task.error_msg                        │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 2. 表结构设计

### 2.1 material_base — 素材主表

素材的身份、来源、内部 OSS 链接、标签扩展。

> **注意**：本表的 `video_url` 存储的是 OSS 内部 URL（转存后回写），不是原始链接。原始链接在 `material_video` 表中。

```sql
-- ==================== 素材主表 ====================
CREATE TABLE IF NOT EXISTS material_base
(
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '自增主键',
    material_id         VARCHAR(64) NOT NULL DEFAULT '' COMMENT '素材唯一ID（幂等键，UNIQUE）',
    title               VARCHAR(500) NOT NULL DEFAULT '' COMMENT '素材标题/文案',
    material_type       VARCHAR(16) NOT NULL DEFAULT '' COMMENT '素材类型：video-视频，image-图片',
    origin              VARCHAR(32) NOT NULL DEFAULT 'crawl_task' COMMENT '来源方式：crawl_task-抓取任务，后续可扩展 process 等其他类型',
    source              VARCHAR(32) NOT NULL DEFAULT '' COMMENT '来源平台：douyin / redbook',
    source_id           VARCHAR(128) NOT NULL DEFAULT '' COMMENT '来源平台素材ID（抖音 aweme_id / 小红书 note_id）',
    publish_url         VARCHAR(1024) NOT NULL DEFAULT '' COMMENT '原始发布链接',
    publish_time        DATETIME NOT NULL DEFAULT '1970-01-01 00:00:00' COMMENT '原始发布时间',
    video_url           VARCHAR(520) NOT NULL DEFAULT '' COMMENT 'OSS内部视频URL（转存后回写）',
    material_label      VARCHAR(3000) NOT NULL DEFAULT '{}' COMMENT '素材标签JSON：{"common_tag":[],"poi":[],"city":[],"ai_tag":[]}',
    ext_param           VARCHAR(3000) NOT NULL DEFAULT '{}' COMMENT '扩展参数JSON',
    dt                  DATE NOT NULL DEFAULT '1970-01-01' COMMENT '数据日期',
    create_time         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    update_time         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (id),
    UNIQUE KEY uniq_material_id (material_id),
    KEY idx_source_source_id (source, source_id),
    KEY idx_create_time (create_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='素材主表';
```

### 2.2 material_video — 素材视频表

视频元数据、原始链接、封面图、预处理流水线。

```sql
-- ==================== 素材视频表 ====================
CREATE TABLE IF NOT EXISTS material_video
(
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '自增主键',
    material_id         VARCHAR(64) NOT NULL DEFAULT '' COMMENT '素材ID（关联 material_base）',
    video_url           VARCHAR(1024) NOT NULL DEFAULT '' COMMENT '原始视频下载链接',
    cover_url           VARCHAR(1024) NOT NULL DEFAULT '' COMMENT '封面图URL（原始）',
    internal_cover_url  VARCHAR(520) NOT NULL DEFAULT '' COMMENT '封面图OSS内部URL（转存后回写）',
    duration            INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '视频时长(秒)',
    width               INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '视频宽度(px)',
    height              INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '视频高度(px)',
    aspect_ratio        VARCHAR(16) NOT NULL DEFAULT '' COMMENT '画面比例，如 9:16 / 4:3 / 3:4 / 16:9',
    video_size          INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '视频文件大小(字节)',
    video_format        VARCHAR(16) NOT NULL DEFAULT '' COMMENT '视频格式(mp4/mov等)',
    frame_rate          DECIMAL(5,2) NOT NULL DEFAULT 0.00 COMMENT '帧率(fps)，暂无接口数据，后续通过 ffmpeg 获取',
    preprocess_status   TINYINT NOT NULL DEFAULT 0 COMMENT '预处理状态：0-未处理，1-已抽帧，2-已提取音频，3-已转文字，4-全部完成',
    video_frame_param   VARCHAR(6000) NOT NULL DEFAULT '{"frame":[]}' COMMENT '抽帧参数JSON',
    audio_url           VARCHAR(520) NOT NULL DEFAULT '' COMMENT '提取的音频文件链接',
    audio_text          TEXT NULL COMMENT '音频转文字内容',
    ext_param           VARCHAR(3000) NOT NULL DEFAULT '{}' COMMENT '扩展参数JSON',
    create_time         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    update_time         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (id),
    KEY idx_material_id (material_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='素材视频表';
```

### 2.3 material_metrics — 素材指标表

```sql
-- ==================== 素材指标表 ====================
CREATE TABLE IF NOT EXISTS material_metrics
(
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '自增主键',
    material_id         VARCHAR(64) NOT NULL DEFAULT '' COMMENT '素材ID（关联 material_base）',
    total_likes         INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '点赞量',
    total_favorites     INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '收藏量',
    total_views         INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '曝光量/播放量',
    total_comments      INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '评论量',
    total_shares        INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '分享量',
    ext_param           VARCHAR(3000) NOT NULL DEFAULT '{}' COMMENT '扩展参数JSON',
    create_time         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    update_time         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (id),
    UNIQUE KEY uniq_material_id (material_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='素材指标表';
```
>针对三张表的material_label、ext_param可以
---

## 3. 阶段二：回调处理增强

### 3.1 现状

当前 `DouyinCrawlTaskResultHandler` 和 `XhsCrawlTaskResultHandler` 的 `handleBigSearch()` / `handleDetail()` 只有 log，没有实质推进子任务状态。

### 3.2 改动要求

在每个 Handler 中补充完整逻辑：

1. **反序列化回调 data**（已有，`resolveParsedData()` 已完成）
2. **提取后续需要的字段**，组装成 `MaterialCrawlResult`
3. **写入 sub_task.result**（JSON 持久化）
4. **更新子任务状态为 SUCCESS**

### 3.3 MaterialCrawlResult 中间结构

```java
/**
 * 抓取回调结果 → sub_task.result 的中间结构
 * Handler 组装后持久化，MaterialProcessTask 读取处理
 */
public class MaterialCrawlResult {
    /** 来源平台 */
    private String source;
    /** 抓取类型 */
    private String crawlType;
    /** 搜索词（BIG_SEARCH 时） */
    private String keyword;
    /** 素材条目列表 */
    private List<MaterialCrawlItem> items;
}

public class MaterialCrawlItem {
    private String materialType;                // 素材类型：video / image
    private String sourceId;                    // 平台素材ID
    private String title;                       // 标题/文案
    private String authorId;                    // 作者ID
    private String authorName;                  // 作者昵称
    private String videoUrl;                    // 原始视频下载链接
    private String coverUrl;                    // 封面图链接
    private Integer duration;                   // 时长（秒）
    private Integer width;                      // 宽
    private Integer height;                     // 高
    private String videoFormat;                 // 格式
    private Long videoSize;                     // 大小（字节）
    private Double frameRate;                   // 帧率（可能为空）
    private String publishTime;                 // 发布时间
    private String publishUrl;                  // 发布链接
    private Integer totalLikes;                 // 点赞量
    private Integer totalFavorites;             // 收藏量
    private Integer totalViews;                 // 曝光量/播放量
    private Integer totalComments;              // 评论量
    private Integer totalShares;                // 分享量
    private MaterialLabel label;                // 标签（扩展结构）
    private Map<String, Object> extra;          // 扩展字段
}

/**
 * 标签结构，序列化为 JSON 存入 material_base.material_label
 */
public class MaterialLabel {
    private List<String> commonTag;   // 通用标签，如 ["有人脸","无文字"]
    private List<String> poi;         // POI 信息
    private List<String> city;        // 城市
    private List<String> aiTag;       // AI 分析标签
}
```

### 3.4 小红书两段式抓取说明

小红书素材需经过两段抓取才能获取完整数据：

| 阶段 | 类型 | 包含数据 | 不包含数据 |
|------|------|---------|-----------|
| 第一段 | BIG_SEARCH | 标题、视频链接、封面、作者、时长、尺寸等基本信息 | **指标数据**（点赞量、收藏量、曝光量等） |
| 第二段 | DETAIL | 标题、视频链接、封面、作者 + **指标数据**（点赞量、收藏量） | - |

**处理策略：**

```
BIG_SEARCH 回调（XhsHandler.handleBigSearch）
  → 提取基本字段到 MaterialCrawlItem（metrics 填 0）
  → 写 sub_task.result → SUCCESS

DETAIL 回调（XhsHandler.handleDetail）
  → 提取完整字段到 MaterialCrawlItem（含 totalLikes/totalFavorites）
  → 写 sub_task.result → SUCCESS

MaterialProcessTask 处理时：
  ├─ BIG_SEARCH 来的数据 → 正常入库，metrics 存 0
  └─ DETAIL 来的数据 → material_id 已存在 → 更新 metrics（覆盖点赞/收藏量）
```

> 抖音 BIG_SEARCH 当前按不包含指标处理，与小红书 BIG_SEARCH 走相同逻辑。

### 3.5 涉及修改的文件

| 文件 | 改动 |
|------|------|
| `DouyinCrawlTaskResultHandler` | handleBigSearch() → 提取字段 → 写 result → SUCCESS |
| `XhsCrawlTaskResultHandler` | handleDetail() + handleBigSearch() → 同上 |
| （新增）`MaterialCrawlResult.java` | 统一的中间结构 DTO |
| （新增）`MaterialCrawlItem.java` | 单条素材 DTO |
| （新增）`MaterialLabel.java` | 标签结构 DTO |

---

## 4. 阶段三：定时任务异步处理（新增）

### 4.1 MaterialProcessTask

通过 `@QSchedule("mkt_odin_crawtask_material_process")` 定时扫描已完成但未分析的抓取子任务，逐条处理入库。

### 4.2 查询待处理子任务

```
条件：
  status = 'SUCCESS'
  executor = 'materialCrawl'
  result IS NOT NULL
ORDER BY id ASC LIMIT #{batchSize}

处理完成后 status 更新为 ANALYSIS_SUCCESS / ANALYSIS_FAIL，避免被重复扫描。
```

### 4.3 子任务状态设计

| 状态 | 含义 | 说明 |
|------|------|------|
| `ANALYSIS_SUCCESS` | 素材入库成功 | 所有 items 都成功处理 |
| `ANALYSIS_FAIL` | 素材入库失败（部分或全部） | 通过 `error_msg` 记录失败节点明细 |

失败节点明细写入 `sub_task.error_msg`，结构为 JSON 数组：

```json
[
  {"id": "douyin_734567890123456", "msg": "下载链接不可达: videoUrl HEAD返回403"},
  {"id": "douyin_734567890123457", "msg": "OSS转存失败: timeout after 30s"}
]
```

### 4.4 处理流程详解

```
for each 子任务:
  MaterialCrawlResult result = parse(sub_task.result)
  List<FailedNode> failedNodes = new ArrayList<>()
  int successCount = 0, failCount = 0

  for each item in result.items:

    Step 1 — 数据合法性校验
      ├─ material_id = source + "_" + sourceId，非空校验
      ├─ source ∈ [douyin, redbook]
      ├─ title / videoUrl / coverUrl 非空
      └─ 不合法 →
          failCount++
          failedNodes.add({id: material_id, msg: "合法性校验失败: xxx"})
          continue

    Step 2 — 查重 + 更新/新增决策
      ├─ SELECT * FROM material_base WHERE material_id = ?
      ├─ 已存在 →
      │   ├─ UPDATE material_metrics（覆盖最新指标）
      │   ├─ 检查 base.video_url 是否为空（OSS内部URL）
      │   │   ├─ 空 → 需要走 OSS 转存（继续 Step 3）
      │   │   └─ 非空 → 已有 OSS 链接，跳过此条
      │   │       successCount++ + continue
      │   └─ 不重新写入 material_video（已有不变）
      └─ 不存在 → 继续走全量入库流程（Step 3）

    Step 3 — 下载链接验证（仅新入库或 OSS 链接为空时）
      ├─ HTTP HEAD videoUrl（超时 3s）
      │   ├─ 200 + Content-Length > 0 → 可访问
      │   └─ 其他 / 超时 →
      │       failCount++
      │       failedNodes.add({id: material_id, msg: "下载链接不可达: " + reason})
      │       QMonitor.recordOne("material_download_check_fail")
      │       continue
      └─ HTTP HEAD coverUrl（同逻辑）

    Step 4 — OSS 转存（同步）
      ├─ videoUrl → OssClient → internalVideoUrl
      ├─ coverUrl → OssClient → internalCoverUrl
      ├─ OSS 路径规则：mkt_odin_material/{materialId}/{filename}
      └─ 失败 →
          failCount++
          failedNodes.add({id: material_id, msg: "OSS转存失败: " + e.getMessage()})
          QMonitor.recordOne("material_oss_transfer_fail")
          continue

    Step 5 — 写入素材库（事务内）
      ├─ INSERT INTO material_base (material_id, title, material_type, origin,
      │     source, source_id, publish_url, publish_time,
      │     video_url(=internalVideoUrl), material_label, dt, ...)
      ├─ INSERT INTO material_video (material_id, video_url(=原始链接),
      │     cover_url, internal_cover_url, duration, width, height,
      │     aspect_ratio, video_size, video_format, frame_rate, ...)
      ├─ INSERT INTO material_metrics (material_id, total_likes, total_favorites,
      │     total_views, total_comments, total_shares)
      ├─ successCount++
      └─ 事务提交

    Step 6 — ES 索引同步（新入库才需全量索引）
      ├─ 组装 MaterialSearchDocument（含 material_label 展开）
      ├─ elasticsearchDataSource.indexDocument(index, doc)
      └─ 失败 → log + QMonitor（不影响主流程）

  Step 7 — 更新子任务状态
      ├─ failCount == 0 → status = ANALYSIS_SUCCESS
      ├─ failCount > 0  → status = ANALYSIS_FAIL
      └─ error_msg = JSON.toJson(failedNodes)
```

### 4.5 处理细节

#### 画面比例自动判断

```java
if (w == 0 || h == 0) return "";
double ratio = (double) w / h;
if (Math.abs(ratio - 9.0/16) < 0.01) return "9:16";
if (Math.abs(ratio - 4.0/3) < 0.01) return "4:3";
if (Math.abs(ratio - 3.0/4) < 0.01) return "3:4";
if (Math.abs(ratio - 16.0/9) < 0.01) return "16:9";
return "其他";
```

#### OSS 路径规则

```
bucket 路径格式: mkt_odin_material/{materialId}/{filename}
素材级别唯一，一个素材仅一个视频/图片。
```

### 4.6 涉及新增/修改的文件

| 文件 | 类型 | 说明 |
|------|------|----------|
| `MaterialProcessTask.java` | **新增** | @QSchedule 定时任务主类 |
| `MaterialProcessService.java` | **新增** | 核心处理逻辑（校验 + 查重 + 验证 + OSS + 写入 + ES） |
| `MaterialBaseMapper.java` | **新增** | MyBatis Mapper |
| `MaterialVideoMapper.java` | **新增** | MyBatis Mapper |
| `MaterialMetricsMapper.java` | **新增** | MyBatis Mapper |
| `MaterialBase.java` | **新增** | Entity |
| `MaterialVideo.java` | **新增** | Entity |
| `MaterialMetrics.java` | **新增** | Entity |
| `MaterialCrawlResult.java` | **新增** | 回调结果中间结构 |
| `MaterialCrawlItem.java` | **新增** | 回调单条素材 |
| `MaterialLabel.java` | **新增** | 标签结构 DTO |
| `MaterialOssService.java` | **新增** | OSS 转存服务（复用已有 OssClient） |
| `SubTaskStatus.java` | 修改 | 新增 ANALYSIS_SUCCESS / ANALYSIS_FAIL 枚举 |

---

## 5. 阶段四：ES 索引 + 前端素材模块

### 5.1 设计原则

- **ES 只存检索需要的字段**，不存 `video_url` / `cover_url` 等非检索字段
- ES 查询只返回素材 ID 列表，前端展示详情时从 DB 重新组装（参考内容模块 search 模式）
- **唯一标识用 DB 主键 `id`**

### 5.2 ES 索引：material_search

**索引名称**：`{prefix}_material_search`（如 `odin_material_search`）

**Document Mapping**：

| ES 字段 | 类型 | 对应 DB | 用途 |
|---------|------|---------|------|
| `id` | long | material_base.id | **唯一标识** |
| `material_id` | keyword | material_base.material_id | 业务标识 |
| `title` | text (ik_smart) | material_base.title | **素材名称模糊检索** |
| `source` | keyword | material_base.source | 平台筛选 |
| `duration` | integer | material_video.duration | **时长范围筛选** |
| `aspect_ratio` | keyword | material_video.aspect_ratio | **画面比例勾选** |
| `width` | integer | material_video.width | **分辨率计算** |
| `height` | integer | material_video.height | **分辨率计算** |
| `frame_rate` | float | material_video.frame_rate | **帧率勾选** |
| `material_label_common_tag` | keyword | material_label.common_tag | **通用标签筛选** |
| `material_label_poi` | keyword | material_label.poi | POI 筛选 |
| `material_label_city` | keyword | material_label.city | 城市筛选 |
| `material_label_ai_tag` | keyword | material_label.ai_tag | **AI 标签筛选** |
| `total_likes` | integer | material_metrics.total_likes | **点赞量范围筛选** |
| `total_favorites` | integer | material_metrics.total_favorites | **收藏量范围筛选** |
| `total_views` | integer | material_metrics.total_views | 曝光量范围筛选 |
| `total_comments` | integer | material_metrics.total_comments | 评论量筛选 |
| `publish_time` | date | material_base.publish_time | **发布时间范围 + 快捷筛选** |
| `create_time` | date | material_base.create_time | 入库时间 |

### 5.3 material_label ES 展开规则

```json
// DB material_base.material_label:
{"common_tag": ["有人脸", "无文字"], "poi": ["故宫"], "city": ["北京"], "ai_tag": ["风景", "古建筑"]}

// ES mapping 展开为独立 keyword 字段:
"material_label_common_tag": { "type": "keyword" },
"material_label_poi":        { "type": "keyword" },
"material_label_city":       { "type": "keyword" },
"material_label_ai_tag":     { "type": "keyword" }

// 查询示例:
{"term": {"material_label_common_tag": "有人脸"}}
{"term": {"material_label_poi": "故宫"}}
```

### 5.4 额外筛选转换逻辑

#### 分辨率映射

| 前端选项 | ES 查询条件 |
|---------|------------|
| 4K | width >= 3840 OR height >= 2160 |
| 2K | width >= 2560 OR height >= 1440 |
| 1080P | width >= 1920 OR height >= 1080 |
| 720P | width >= 1280 OR height >= 720 |
| 其他 | 不属于以上任何一档 |

#### 帧率映射

| 前端选项 | ES 查询条件 |
|---------|------------|
| >= 30fps | frame_rate >= 30 |
| >= 24fps | frame_rate >= 24 AND < 30 |
| 24fps 以下 | frame_rate > 0 AND frame_rate < 24 |

### 5.5 检索 API

| 接口 | 方法 | 说明 |
|------|------|------|
| `/api/material/search` | POST | ES 分页检索，返回 id 列表 + total |
| `/api/material/detail/{id}` | GET | DB 查询单个素材完整数据（含 video_url / cover_url） |

### 5.6 前端素材模块 Deepdive

#### 路由

```js
// config/config.js
routes: [
  { path: '/material', component: '@/pages/material/list' },
  { path: '/material/detail', component: '@/pages/material/detail' },
],
```

#### 新增文件清单

| 文件 | 用途 |
|------|------|
| `src/api/material.js` | API 封装（search / detail） |
| `src/pages/material/list.jsx` | 素材列表页 |
| `src/pages/material/list.less` | 列表页样式 |
| `src/pages/material/detail.jsx` | 素材详情页 |
| `src/pages/material/detail.less` | 详情页样式 |

#### 素材列表页 UI 设计

```
┌──────────────────────────────────────────────────────────────────────┐
│  素材库                                                               │
│  ┌──────────────────────────────────────────────────────────────────┐ │
│  │ 高级筛选                                                         │ │
│  │ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐            │ │
│  │ │ 素材名称   │ │ 素材时长  │ │ 发布时间  │ │ 画面比例  │            │ │
│  │ │ [ 输入框 ] │ │ [min~max]│ │ [选择器]  │ │ ☑9:16... │            │ │
│  │ └──────────┘ └──────────┘ └──────────┘ └──────────┘            │ │
│  │ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐            │ │
│  │ │ 点赞量    │ │ 收藏量    │ │ 分辨率    │ │ 帧率      │            │ │
│  │ │ [min~max]│ │ [min~max]│ │ ☑4K...   │ │ ☑>=30fps │            │ │
│  │ └──────────┘ └──────────┘ └──────────┘ └──────────┘            │ │
│  │                     [搜索] [重置]                                │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────────┐ │
│  │ 搜索结果 共 N 条                                                   │ │
│  │                                                                  │ │
│  │ ┌──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┐       │ │
│  │ │ ID   │封面  │名称   │时长   │比例  │点赞  │收藏  │来源  │       │ │
│  │ ├──────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┤       │ │
│  │ │ ...  │ img  │ xxx  │ 30s  │9:16  │ 1.2K │ 500  │抖音  │       │ │
│  │ └──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┘       │ │
│  │                                                                  │ │
│  │                        [页码翻页]                                 │ │
│  └──────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

**列表页核心交互逻辑（参照内容列表页）：**

1. **筛选条件状态管理** — 使用 `useReducer` 管理所有筛选条件 state
   - 文本类（`title`）：输入框，防抖触发检索
   - 范围类（`durationMin/Max`、`totalLikesMin/Max`、`totalFavoritesMin/Max`）：`InputNumber` 最小值/最大值
   - 勾选类（`aspectRatios[]`、`resolutions[]`、`frameRates[]`）：`Checkbox.Group`
   - 日期类（`publishTimeStart/End`）：`DatePicker.RangePicker` + 快捷选项（半年/1年/2年内）
   - 平台（`source`）：`Select`

2. **数据加载** — `loadData()` 从 state 构建请求 body → 调用 `/api/material/search` → 更新结果
   - 搜索参数格式参考：`{ title, durationMin, durationMax, aspectRatios, totalLikesMin, totalLikesMax, ... }`
   - 后端 MaterialSearchService 将筛选参数翻译为 ES query DSL
   - ES 返回 `id` 列表 → 后端从 DB JOIN 三表组装展示数据（含 `video_url`、`cover_url`）→ 返回前端

3. **表格列定义**（参考 content list 的 `renderCell` 模式）
   - `material_id`：文本
   - 封面：`<img>` 标签渲染 `cover_url`
   - `title`：文本
   - `duration`：整数，单位秒
   - `aspect_ratio`：Tag 标签显示
   - `total_likes` / `total_favorites`：数字，使用 `formatCompact` 千位缩写
   - `source`：中文标签映射（douyin → 抖音，redbook → 小红书）
   - 操作列：`详情` 按钮 → 跳转 `/material/detail?id=xxx`

4. **列配置**（可选）：参照内容模块的自定义列功能
   - 使用 localStorage 持久化用户列偏好
   - 提供列设置弹窗

5. **预设筛选**（可选）：参照内容模块将当前筛选条件保存为预设，方便快速切换

#### 素材详情页 UI 设计

```
┌──────────────────────────────────────────────────────────────────────┐
│  ← 返回素材列表                                                      │
│                                                                      │
│  ┌────────────────────┐  ┌─────────────────────────────────────────┐│
│  │  视频播放区域        │  │  基本信息                                ││
│  │                    │  │  ┌─────────────────────────────────────┐││
│  │   <video>          │  │  │ 素材名称: xxx                       │││
│  │   internal_video_url│  │  │ 素材ID: xxx                       │││
│  │                    │  │  │ 来源平台: 抖音                      │││
│  │                    │  │  │ 发布时间: 2026-06-01               │││
│  │                    │  │  │ 作者昵称: xxx                      │││
│  │                    │  │  │ 时长: 30s                          │││
│  │                    │  │  │ 画面比例: 9:16                     │││
│  │                    │  │  │ 分辨率: 720x1280                   │││
│  │                    │  │  └─────────────────────────────────────┘││
│  └────────────────────┘  │                                         ││
│                          │  ┌─────────────────────────────────────┐││
│                          │  │ 热度指标                              ││
│                          │  │ 点赞量: 1.2K  收藏量: 500           │││
│                          │  │ 曝光量: 50K   评论量: 200            │││
│                          │  │ 分享量: 30                           │││
│                          │  └─────────────────────────────────────┘││
│                          │                                         ││
│                          │  ┌─────────────────────────────────────┐││
│                          │  │ 标签                          [编辑] │││
│                          │  │ <Tag>有人脸</Tag> <Tag>风景</Tag>   │││
│                          │  └─────────────────────────────────────┘││
│                          └─────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────┘
```

**详情页核心交互：**

1. **数据加载** — 页面 mount 时调用 `/api/material/detail/{id}`，后端三表 JOIN 返回完整数据
2. **视频播放** — 使用 `<video>` 标签，`src` 指向 `material_base.video_url`（OSS 内部 URL）
3. **标签展示** — `material_label` JSON 解析，各标签以 `<Tag>` 组件渲染，不同类别的标签用不同颜色区分
4. **更多字段展示** — 使用 `Descriptions` 组件（参照 content detail）

### 5.7 涉及新增/修改的文件

| 文件 | 类型 | 说明 |
|------|------|------|
| `MaterialSearchDocument.java` | **新增** | ES Document POJO（Gson 序列化，仅检索字段） |
| `MaterialSearchSyncService.java` | **新增** | ES 同步 Service 接口 |
| `MaterialSearchSyncServiceImpl.java` | **新增** | ES 同步实现 |
| `MaterialSearchDocAssembler.java` | **新增** | Document 组装器（含 material_label 展开） |
| `MaterialSearchController.java` | **新增** | 素材检索 + 详情 API |
| `MaterialSearchService.java` | **新增** | 检索 Service（筛选参数 → ES query 构建） |
| `EsIndexConfig` | 修改 | 添加 `material_search` 索引名常量 |
| `src/api/material.js` | **新增** | 前端素材模块 API 封装 |
| `src/pages/material/list.jsx` | **新增** | 素材列表页 |
| `src/pages/material/list.less` | **新增** | 列表页样式 |
| `src/pages/material/detail.jsx` | **新增** | 素材详情页 |
| `src/pages/material/detail.less` | **新增** | 详情页样式 |
| `config/config.js` | 修改 | 添加 `/material` 和 `/material/detail` 路由 |

---

## 6. 完整新增/修改文件清单

### 新增文件

| 模块 | 文件路径（示意） |
|------|----------------|
| Entity | `domain/entity/material/MaterialBase.java` |
| Entity | `domain/entity/material/MaterialVideo.java` |
| Entity | `domain/entity/material/MaterialMetrics.java` |
| DTO | `domain/dto/crawl/MaterialCrawlResult.java` |
| DTO | `domain/dto/crawl/MaterialCrawlItem.java` |
| DTO | `domain/dto/crawl/MaterialLabel.java` |
| Mapper | `infra/dao/MaterialBaseMapper.java` |
| Mapper | `infra/dao/MaterialVideoMapper.java` |
| Mapper | `infra/dao/MaterialMetricsMapper.java` |
| Mapper XML | `infra/dao/mapper/MaterialBaseMapper.xml` |
| Mapper XML | `infra/dao/mapper/MaterialVideoMapper.xml` |
| Mapper XML | `infra/dao/mapper/MaterialMetricsMapper.xml` |
| Service | `service/material/MaterialOssService.java` |
| Service | `service/material/MaterialProcessService.java` |
| Task | `task/material/MaterialProcessTask.java` |
| ES Document | `domain/entity/es/MaterialSearchDocument.java` |
| ES Service | `service/es/MaterialSearchSyncService.java` |
| ES Service impl | `service/es/impl/MaterialSearchSyncServiceImpl.java` |
| ES Assembler | `service/es/MaterialSearchDocAssembler.java` |
| Controller | `web/MaterialSearchController.java` |
| Search Service | `service/material/MaterialSearchService.java` |
| 前端 API | `src/api/material.js` |
| 前端页面 | `src/pages/material/list.jsx` |
| 前端页面 | `src/pages/material/list.less` |
| 前端页面 | `src/pages/material/detail.jsx` |
| 前端页面 | `src/pages/material/detail.less` |

### 修改文件

| 文件 | 改动 |
|------|------|
| `DouyinCrawlTaskResultHandler.java` | handleBigSearch → 提取字段写 result + SUCCESS |
| `XhsCrawlTaskResultHandler.java` | handleDetail + handleBigSearch → 同上 |
| `EsIndexConfig.java` | 新增 `material_search` 索引常量 |
| `SubTaskStatus.java` | 新增 `ANALYSIS_SUCCESS` / `ANALYSIS_FAIL` 枚举 |
| `config/config.js` | 新增 `/material` 和 `/material/detail` 路由 |

---

## 7. 关键决策记录

| 决策项 | 结论 |
|--------|------|
| BIG_SEARCH 批量策略 | 全部入库 |
| material_label 来源 | 扩展字段，后续可由 AI 分析或其他数据源产出 |
| frame_rate 获取 | 调用方暂无此字段，后续通过 ffmpeg 分析视频文件获取 |
| OSS 转存 | 复用现有 OssClient，路径 `mkt_odin_material/{MD5(videoUrl)}/{filename}` |
| @QSchedule 任务名 | `mkt_odin_crawtask_material_process` |
| ES 唯一标识 | 使用 DB 主键 `id` |
| 查询组装 | ES 只返回 id 列表，详情数据从 DB 重新 JOIN 查询 |