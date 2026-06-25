# 小红书图文帖抓取 & 素材入库方案

## 1. 需求概述

现有素材抓取系统仅支持**视频型素材**（抖音、小红书视频），小红书大搜结果中的**图文帖**（image-text note）被 `RedbookBigSearchSkipStrategy` 跳过，未做任何处理。

**目标：** 新增小红书图文帖抓取链路，支持：

- 关键词搜索图文帖列表 → 获取 noteId
- 根据 noteId 查询图文帖详情 + 作者信息
- 图文帖及作者信息持久化入库
- 作者去重逻辑：已有作者信息且符合条件时跳过详情抓取

---

## 2. 全流程架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                     抓取任务创建（前端/API）                          │
│    POST /demo/createCrawlTask                                       │
│    { source:"redbook", taskType:"bigSearch", ... }                  │
└─────────────────┬───────────────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│   MaterialCrawlExecutor.execute()                                   │
│   按 (searchKeyword × platform) 拆分为 SubTask                      │
│   SubTask.executor = "MaterialCrawlExecutor"                        │
└─────────────────┬───────────────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│   MaterialCrawlExecutor.subExecute()                                │
│   调用 CrawlTaskClient.createTask() → 下发到爬取引擎                  │
│   SubTask.status → RUNNING                                         │
└─────────────────┬───────────────────────────────────────────────────┘
                  │
        ┌─────────┴──────────┐
        ▼                    ▼
┌──────────────────┐  ┌──────────────────┐
│ CrawlRedbookPost │  │ CrawlRedBookPost │
│ List.subExecute()│  │ Detail.subExec() │
│ = 图文帖列表下    │  │ = 图文帖详情下    │
│   发到爬取引擎     │  │   发到爬取引擎     │
└────────┬─────────┘  └────────┬─────────┘
         │                     │
         ▼                     ▼
┌──────────────────┐  ┌──────────────────┐
│ 爬取引擎回调       │  │ 爬取引擎回调       │
│ CrawlTaskResult   │  │ CrawlTaskResult  │
│ Processor.process │  │ Processor.process│
└────────┬─────────┘  └────────┬─────────┘
         │                     │
         ▼                     ▼
┌──────────────────┐  ┌──────────────────┐
│ 根据 executor 分发  │  │ 图文帖详情处理     │
│ → List 回调处理    │  │ → 解析详情数据     │
│   ↓               │  │ → 落库 note +     │
│ 创建 2 个子任务:    │  │   author 信息     │
│   ├ author 子任务   │  │ → SubTask SUCCESS│
│   └ detail 子任务   │  └──────────────────┘
└──────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────┐
│   MaterialProcessTask.doProcessSubTask()                            │
│   根据 executorName 分发处理逻辑                                     │
│   → 图文帖/作者数据持久化                                             │
│   → SubTask.status → ANALYSIS_SUCCESS                               │
└─────────────────┬───────────────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│   TaskCompletionService.tryCompleteTask()                           │
│   扩展 executor 维度的特殊逻辑 + postProcess 过滤子任务并回调下游      │
│   → 父 Task.status → SUCCESS                                        │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. 新增组件

### 3.1 抓取执行器子类（已完成）

| 类名 | Bean Name | getName() | 职责 |
|------|-----------|-----------|------|
| `CrawlRedbookPostList` | `crawlRedbookPostList` | `CrawlRedbookPostList` | 图文帖列表抓取 |
| `CrawlRedBookPostDetail` | `crawlRedBookPostDetail` | `CrawlRedBookPostDetail` | 图文帖详情抓取 |

这两个子类继承 `MaterialCrawlExecutor`，当前仅重写 `getName()`。后续可根据需要覆写 `subExecute()` 定制下发逻辑。

### 3.2 MQ 回调分发重构

**现状：** `XhsCrawlTaskResultHandler#handleBigSearch` 硬编码创建 DETAIL 子任务逻辑。

**改造：** `AbstractCrawlTaskResultHandler#handle()` 中根据 `SubTask.executor` 字段分发：

```java
// 伪代码示意
public void handle(CrawlTaskResultContext context) {
    String executor = context.getSubTask().getExecutor();
    if ("CrawlRedbookPostList".equals(executor)) {
        handleRedbookPostList(context);
    } else if ("CrawlRedBookPostDetail".equals(executor)) {
        handleRedbookPostDetail(context);
    } else {
        // 原有逻辑：根据 crawlType 分发
        dispatchByCrawlType(context);
    }
}
```

### 3.3 图文帖回调处理逻辑

#### List 页回调（`CrawlRedbookPostList` 响应）

1. 解析回调数据中的图文帖列表（含 noteId、封面图等）
2. 创建两个子任务：
   - **Author 子任务**：`executor = "CrawlRedBookPostDetail"`，`businessKey = "author_{noteId}"`，`subTaskParams` 含 authorId 等信息，`taskType = "userInfo"`
   - **Detail 子任务**：`executor = "CrawlRedBookPostDetail"`，`businessKey = "xhsDetail_{noteId}"`，`subTaskParams` 含 noteId 等信息，`taskType = "detail"`
3. 子任务状态 → SUCCESS（等待 MaterialProcessTask 处理入库）

#### Author 去重逻辑（待 deepdive）

- 创建子任务前查询 `redbook_author_info` 表
- 若 author 已存在且符合条件（如更新时间在有效期内）→ 跳过 author 子任务
- 若 author 已存在，也可根据配置决定是否跳过 detail 子任务

#### Detail 页回调（`CrawlRedBookPostDetail` 响应）

1. 解析回调数据中的图文帖详情
2. 提取图文帖字段（标题、内容、图片列表、标签等）
3. 提取作者字段（昵称、头像、简介等）
4. 落库到 `redbook_note_post` + `redbook_author_info` 表
5. 子任务状态 → SUCCESS

### 3.4 新增 DTO（回调对象扩展）

图文帖回调数据需要新增字段，区别于视频素材：

| 字段 | 说明 |
|------|------|
| `images` | 图片列表（多张） |
| `imageUrls` | 图片 URL 列表 |
| `content` | 图文正文内容 |
| `noteType` | 笔记类型（图文/视频） |
| `tagList` | 标签列表 |
| `atUserList` | @用户列表 |

待收到实际报文结构后补充完整。

---

## 4. 数据库表设计

### 4.1 `redbook_note_post` — 小红书图文帖表

| 字段 | 类型 | 说明 |
|------|------|------|
| id | bigint PK | 主键 |
| note_id | varchar(64) | 小红书 noteId |
| title | varchar(512) | 标题 |
| content | text | 正文内容 |
| images | json | 图片列表（URL 数组） |
| cover_url | varchar(1024) | 封面图 URL |
| note_type | varchar(32) | 笔记类型 |
| tag_list | json | 标签列表 |
| author_id | varchar(64) | 作者 ID |
| author_name | varchar(256) | 作者昵称 |
| total_likes | int | 点赞数 |
| total_collect | int | 收藏数 |
| total_comments | int | 评论数 |
| total_shares | int | 分享数 |
| publish_time | datetime | 发布时间 |
| crawl_time | datetime | 抓取时间 |
| extra | json | 扩展字段 |
| create_time | datetime | 创建时间 |
| update_time | datetime | 更新时间 |

### 4.2 `redbook_author_info` — 小红书作者信息表

| 字段              | 类型                 | 说明     |
| --------------- | ------------------ | ------ |
| id              | bigint PK          | 主键     |
| author_id       | varchar(64) UNIQUE | 作者 ID  |
| author_name     | varchar(256)       | 作者昵称   |
| avatar_url      | varchar(1024)      | 头像 URL |
| description     | text               | 作者简介   |
| gender          | tinyint            | 性别     |
| follower_count  | int                | 粉丝数    |
| following_count | int                | 关注数    |
| note_count      | int                | 笔记数    |
| is_official     | tinyint            | 是否官方认证 |
| tags            | json               | 作者标签   |
| crawl_time      | datetime           | 抓取时间   |
| create_time     | datetime           | 创建时间   |
| update_time     | datetime           | 更新时间   |

> **注：** 表结构待接收实际报文后调整优化。

---

## 5. 涉及改造的文件

### 5.1 回调分发

| 文件 | 改动 |
|------|------|
| `AbstractCrawlTaskResultHandler.java` | `handle()` 按 `SubTask.executor` 分发，不再仅按 `crawlType` |
| `XhsCrawlTaskResultHandler.java` | 新增 `handleRedbookPostList()` / `handleRedbookPostDetail()` 逻辑 |
| 新增 `RedbookPostListHandler` / `RedbookPostDetailHandler`（可选） | 独立处理器，按 executor 匹配 |

### 5.2 素材入库定时任务

| 文件 | 改动 |
|------|------|
| `MaterialProcessTask.java` | `doProcessSubTask()` 重写，根据 executorName 路由到不同处理逻辑 |
| `MaterialProcessStrategy.java` | `supports()` 方法新增 `executorName` 参数 |
| `DefaultMaterialProcessStrategy.java` | 适配新接口签名 |
| `RedbookBigSearchSkipStrategy.java` | 适配新接口签名或被替代 |
| 新增 `RedbookNotePostProcessStrategy.java` | 处理图文帖落库 |
| 新增 `RedbookAuthorProcessStrategy.java` | 处理作者信息落库 |

### 5.3 父任务完成 & 后处理

| 文件 | 改动 |
|------|------|
| `TaskCompletionService.java` | `tryCompleteTask()` 扩展 executor 特殊逻辑 |
| 新增 `PostProcessService`（可选） | 过滤子任务、重新组装回调下游 |

### 5.4 Entity / Mapper / Service

| 文件 | 改动 |
|------|------|
| 新增 `RedbookNotePost.java` | 图文帖实体 |
| 新增 `RedbookNotePostMapper.java` | 图文帖 Mapper |
| 新增 `RedbookAuthorInfo.java` | 作者信息实体 |
| 新增 `RedbookAuthorInfoMapper.java` | 作者信息 Mapper |
| 新增 `RedbookNotePostService.java` | 图文帖落库 Service |
| 新增 `RedbookAuthorInfoService.java` | 作者信息落库 Service |

---

## 6. 数据流转图

```
List 页回调
    │
    ├─ 解析 noteId 列表
    │
    ├─ 查询 redbook_author_info（去重判断）
    │     ├─ author 存在且有效 → 跳过 author 子任务
    │     └─ author 不存在/过期 → 创建 author 子任务
    │
    ├─ 创建 Detail 子任务（每个 noteId）
    │     └─ executor = "CrawlRedBookPostDetail"
    │         subTaskParams = { noteId, taskType: "detail", ... }
    │
    └─ SubTask → SUCCESS

Detail 页回调
    │
    ├─ 解析图文帖详情
    │
    ├─ 写入 redbook_note_post
    │     └─ title, content, images, tags, metrics...
    │
    ├─ 写入 redbook_author_info（upsert）
    │     └─ authorId, authorName, avatar, followerCount...
    │
    └─ SubTask → SUCCESS → MaterialProcessTask 处理后 → ANALYSIS_SUCCESS

父任务完成
    │
    ├─ TaskCompletionService 扫描
    ├─ 所有子任务终态 → 父任务 SUCCESS
    └─ postProcess：过滤子任务结果，回调下游
```

---

## 7. 待确认事项

- [ ] 图文帖回调报文结构（待提供）
- [ ] Author 去重具体条件（时间窗口 / 数据完整性校验 / 业务配置）
- [ ] Detail 页是否可能跳过不抓（如 author 已存在且符合条件时）
- [ ] postProcess 回调下游的具体协议和目标
- [ ] 是否需要新增强类型枚举值（如 `IMAGE_TEXT`）

---

## 8. 开发计划

### 阶段一：基础框架
- [x] 创建 `CrawlRedbookPostList`、`CrawlRedBookPostDetail` 子类
- [ ] 回调分发按 executor 重构
- [ ] 新增回调 DTO 字段

### 阶段二：回调处理
- [ ] List 页回调逻辑（创建 author + detail 子任务）
- [ ] Detail 页回调逻辑（解析 + 落库）
- [ ] Author 去重逻辑

### 阶段三：持久化
- [ ] 建表（`redbook_note_post`、`redbook_author_info`）
- [ ] Entity / Mapper / Service
- [ ] MaterialProcessTask 重写
- [ ] MaterialProcessStrategy 适配

### 阶段四：完成 & 后处理
- [ ] TaskCompletionService 扩展
- [ ] postProcess 逻辑
- [ ] 全链路联调
