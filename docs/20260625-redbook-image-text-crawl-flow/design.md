# 小红书图文帖抓取 & 素材入库方案

## 1. 需求概述

现有素材抓取系统仅支持**视频型素材**（抖音、小红书视频），小红书大搜结果中的**图文帖**（image-text note）被 `RedbookBigSearchSkipStrategy` 跳过，未做任何处理。

**目标：** 新增小红书图文帖抓取链路，支持两条抓取路径：

**路径 A — 关键词发现（preCrawl）：**
- 关键词搜索图文帖列表（bigSearch）→ 获取 noteId
- 作者去重（已有作者且符合条件时跳过）
- 图文帖详情 + 作者信息抓取
- **首日互动数据**（点赞/收藏/评论）落 extra 字段

**路径 B — NoteId 驱动刷新（postCrawl）：**
- 外部传入 noteId 列表 → 查 `redbook_note_post` 表确认数据 + xsec_token
- 无数据则直接失败，有数据则下发 detail 页抓取任务
- 定时任务定期刷新点赞/收藏/评论数据
- 回调推送下游

---

## 2. 全流程架构

```
                            ┌──────────────────────────────────┐
                            │  POST /api/assignTask/           │
                            │  { configKey, taskType, data }   │
                            └────────────┬─────────────────────┘
                                         │
                                    ┌────┴────┐
                                    │ 校验     │
                                    │ configKey│
                                    └────┬────┘
                                         │
                            ┌────────────┴────────────┐
                            │                         │
                    taskType=PreCrawl          taskType=PostCrawl
                            │                         │
                            ▼                         ▼
            ┌──────────────────────────┐  ┌──────────────────────────┐
            │ 创建 CrawlTask           │  │ 创建 CrawlTask           │
            │ source=redbook           │  │ executor=               │
            │ taskType=bigSearch       │  │ hotPredictRedbookPost-  │
            │ executor=               │  │ Crawl                   │
            │ hotPredictRedbookPreCrawl│  │ param.noteIds=[...]     │
            └────────┬─────────────────┘  └────────┬─────────────────┘
                     │                             │
                     ▼                             ▼
            ┌──────────────────┐         ┌──────────────────┐
            │ MaterialCrawl    │         │ hotPredictRedbook│
            │ Executor         │         │ PostCrawl        │
            │ .execute()       │         │ .subExecute()    │
            │ 拆分为 SubTask   │         │ = 查 DB 获取     │
            │ (per keyword)    │         │   noteId+token   │
            └────────┬─────────┘         │ → 失败/下发 detail│
                     │                   └────────┬─────────┘
                     ▼                            │
            ┌──────────────────┐                   │
            │ MaterialCrawl    │                   │
            │ Executor         │                   │
            │ .subExecute()    │                   │
            │ bigSearch 下发   │                   │
            └────────┬─────────┘                   │
                     │                             │
                     └─────────┬───────────────────┘
                               ▼
            ┌────────────────────────────────────────┐
            │          爬取引擎回调                    │
            │   CrawlTaskResultProcessor.process()    │
            └────────────────┬───────────────────────┘
                             │
                             ▼
            ┌────────────────────────────────────────┐
            │    XhsCrawlTaskResultHandler.handle()    │
            │    → 按 executor 分发                    │
            └────────┬───────────────────┬────────────┘
                     │                   │
                     ▼                   ▼
            ┌──────────────────┐  ┌──────────────────┐
            │ PreCrawlHandler  │  │ PostCrawlHandler │
            │ executor=preCrawl│  │ executor=post-   │
            │ bigSearch 回调   │  │ Crawl            │
            │ → 过滤 + 拆子任务  │  │ → 解析详情/作者   │
            │ → 首日数据 extra  │  │ → 合并首日数据   │
            └────────┬─────────┘  └────────┬─────────┘
                     │                     │
                     ▼                     ▼
            ┌────────────────────────────────────────┐
            │   MaterialProcessTask 持久化             │
            │   → 下载图片 + 缓存 (noteId_index)       │
            │   → 入库 redbook_note_post              │
            │   → upsert redbook_author_info          │
            └────────────────┬───────────────────────┘
                             │
                             ▼
            ┌────────────────────────────────────────┐
            │   TaskCompletionService                │
            │   → postProcess HTTP 回调下游 python    │
            │   → 父 Task → SUCCESS                  │
            └────────────────────────────────────────┘
```
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

### 3.1 抓取执行器子类

| 类名                           | Bean Name                    | getName()                    | 职责                                                 |
| ---------------------------- | ---------------------------- | ---------------------------- | -------------------------------------------------- |
| `HotPredictRedbookPreCrawl`  | `hotPredictRedbookPreCrawl`  | `hotPredictRedbookPreCrawl`  | bigSearch 下发 + 回调过滤、拆分子任务、首日数据落 extra              |
| `HotPredictRedbookPostCrawl` | `hotPredictRedbookPostCrawl` | `hotPredictRedbookPostCrawl` | noteId 驱动：查 DB 确认数据 → 失败/下发 detail 任务 → 定时刷新 stats |

`HotPredictRedbookPreCrawl` 覆写 `subExecute()` 定制 bigSearch 下发参数；
`HotPredictRedbookPostCrawl` 覆写 `subExecute()` 实现 noteId 查 DB + 失败/下发逻辑。

### 3.2 MQ 回调分发 — `ExecutorHandler` 策略体系

**设计原则：**
1. **路由只按 `executor` 名称匹配**，不区分 `taskType`
2. 每个 executor 对应一个 `ExecutorHandler`，内部自行处理所有 taskType 的路由
3. 引入平台层抽象（小红书/抖音），各平台有公开的空方法，子类按需重写
4. `XhsCrawlTaskResultHandler` 改为按 executor 分发到 `ExecutorHandler`

#### 类层次结构

```
ExecutorHandler (接口)
  supports(String executor)
  handle(context, parsedData)
    │
    └── AbstractExecutorHandler (抽象基类，空实现 handle())
            │
            ├── RedbookExecutorHandler (小红书平台抽象)
            │     ├── handleRedbookDetail()     ← 空，子类重写
            │     ├── handleRedbookBigSearch()   ← 空，子类重写
            │     └── handleRedbookUserInfo()    ← 空，子类重写
            │     │
            │     ├── HotPredictRedbookPreCrawlHandler  (绑定 executor="hotPredictRedbookPreCrawl")
            │     │     └── 重写 handleRedbookBigSearch()  → 作者过滤 + 拆分子任务
            │     │
            │     └── HotPredictRedbookPostCrawlHandler     (绑定 executor="hotPredictRedbookPostCrawl")
            │           ├── 重写 handleRedbookDetail()      → 解析图文帖
            │           └── 重写 handleRedbookUserInfo()    → 解析作者信息
            │
            ├── DouyinExecutorHandler (抖音平台抽象，预留)
            │     └── ...
            │
            └── DefaultExecutorHandler (绑定 executor="MaterialCrawlExecutor")
                  └── 原有视频处理逻辑（bigSearch 拆分子任务 + detail 提取素材）
```

#### 接口定义

```java
/** 策略接口：按 executor 匹配，统一入口 */
public interface ExecutorHandler {
    /** 是否支持该 executor */
    boolean supports(String executor);

    /** 统一处理入口，内部按 context.crawlType 路由到平台方法 */
    void handle(CrawlTaskResultContext context, Object parsedData);
}

/** 抽象基类：默认空实现 */
public abstract class AbstractExecutorHandler implements ExecutorHandler {
    @Override
    public void handle(CrawlTaskResultContext context, Object parsedData) {
        // 空实现 - 子类按需重写
    }
}
```

#### 小红书平台抽象层

```java
/** 小红书平台抽象层 */
public abstract class RedbookExecutorHandler extends AbstractExecutorHandler {

    /** 子类在构造时绑定 executor 名称 */
    protected abstract String getExecutorName();

    @Override
    public boolean supports(String executor) {
        return getExecutorName().equals(executor);
    }

    /** 统一入口：按 crawlType 分派到平台方法 */
    @Override
    public void handle(CrawlTaskResultContext context, Object parsedData) {
        String crawlType = context.getCrawlType();
        switch (crawlType) {
            case "detail" ->    handleRedbookDetail(context, parsedData);
            case "bigSearch" -> handleRedbookBigSearch(context, parsedData);
            case "userInfo" ->  handleRedbookUserInfo(context, parsedData);
            default -> log.warn("unknown crawlType={} for executor={}", crawlType, getExecutorName());
        }
    }

    // ===== 以下是公开的空方法，子类按需重写 =====

    public void handleRedbookDetail(CrawlTaskResultContext context, Object parsedData) {}
    public void handleRedbookBigSearch(CrawlTaskResultContext context, Object parsedData) {}
    public void handleRedbookUserInfo(CrawlTaskResultContext context, Object parsedData) {}
}
```

#### 路由矩阵（按 executor 匹配）

| executor | Handler 类 | 处理的 crawlType |
|----------|-----------|----------------|
| `hotPredictRedbookPreCrawl` | `HotPredictRedbookPreCrawlHandler` | bigSearch |
| `hotPredictRedbookPostCrawl` | `HotPredictRedbookPostCrawlHandler` | detail + userInfo |
| `MaterialCrawlExecutor` | `DefaultExecutorHandler` | detail + bigSearch（原有视频逻辑） |

#### `XhsCrawlTaskResultHandler` 改造

```java
@Slf4j
@Service
public class XhsCrawlTaskResultHandler extends AbstractCrawlTaskResultHandler {

    @Resource
    private List<ExecutorHandler> executorHandlers;

    @Override
    protected String getSource() { return "redbook"; }

    @Override
    public void handle(CrawlTaskResultContext context) {
        // 1. 解析回调数据（复用父类逻辑）
        CrawlTaskTypeEnum crawlTaskType = CrawlTaskTypeEnum.fromCode(context.getCrawlType());
        Object parsedData = resolveParsedData(context, crawlTaskType);

        // 2. 按 executor 查找匹配的 Handler
        String executor = context.getSubTask().getExecutor();
        ExecutorHandler handler = executorHandlers.stream()
                .filter(h -> h.supports(executor))
                .findFirst().orElse(null);

        if (handler == null) {
            log.warn("no handler for executor={}, subTaskId={}, fallback to default dispatch",
                    executor, context.getSubTask().getId());
            super.handle(context);  // 回退到原有按 crawlType 分发
            return;
        }

        // 3. 委托给 Handler
        handler.handle(context, parsedData);
        subTaskService.completeSubTask(context.getSubTask().getId(), ...);
    }
}
```

#### 调用流程

```
XhsCrawlTaskResultHandler.handle(context)
  │
  ├─ resolveParsedData()  →  解析回调 data
  │
  ├─ subTask.executor  →  "hotPredictRedbookPreCrawl"
  │     └─ 匹配 → HotPredictRedbookPreCrawlHandler
  │           └─ handle(context, data)
  │                └─ crawlType="bigSearch" → handleRedbookBigSearch()
  │                     → 作者过滤 + 创建子任务
  │
  ├─ subTask.executor  →  "hotPredictRedbookPostCrawl"
  │     └─ 匹配 → HotPredictRedbookPostCrawlHandler
  │           └─ handle(context, data)
  │                ├─ crawlType="detail"    → handleRedbookDetail()
  │                │     → 解析 detail → NotePostCrawlResult
  │                └─ crawlType="userInfo"   → handleRedbookUserInfo()
  │                      → 解析 userInfo → AuthorInfoData
  │
  └─ 未匹配 → super.handle() 原有逻辑兜底
```

### 3.3 图文帖回调处理逻辑

#### 3.3.1 PreCrawl 回调 — bigSearch 列表处理（`executor = "hotPredictRedbookPreCrawl"`）

`HotPredictRedbookPreCrawlHandler.handleRedbookBigSearch()` 的逻辑：

1. 解析回调 `data.data.data.items[]`，过滤 `note_card.type == "normal" && model_type == "note"` 的图文帖
2. 对每条图文帖：
   - 查询 `redbook_author_info` 表（by `note_card.user.user_id`）
   - **作者过滤条件（满足以下所有条件则跳过本条笔记）**：
     - `redbook_author_info` 中该 author 记录**存在**
     - **且** `update_time` > 当前时间 - 7 天（数据在有效期内）
     - **且** `is_seller = 1`（有店铺）
     - **且** `follower_count > 10000`（粉丝数大于一万）
     - → **跳过本条**，不下发任何子任务（已知的高质量作者，无需重复抓取）
   - **不满足以上任一条件时**：
     - 提取 BigSearch 返回的互动数据作为**首日数据**（preCrawl 只抓一天内帖子，此时数据即为 D0 值）：
       - `firstDayLikes` ← `note_card.interact_info.liked_count`
       - `firstDayCollects` ← `note_card.interact_info.collected_count`
       - `firstDayComments` ← `note_card.interact_info.comment_count`
     - 将首日数据存入 extra JSON（与图文帖数据一同持久化）：`{"firstDayLikes":84,"firstDayCollects":52,"firstDayComments":21}`
     - 创建两个子任务：
       - **Detail 子任务**（executor = `"hotPredictRedbookPostCrawl"`）：
         - `businessKey = "detail_{parentSubTaskId}_{noteId}"`
         - `subTaskParams` = `{ source, businessType, taskType:"detail", crawlType:"detail", noteId, xsecToken, keyword, priority, expireAt }`
         - 必须包含 `crawlType:"detail"`，供 `CrawlTaskResultProcessor.buildContext()` 路由
       - **UserInfo 子任务**（executor = `"hotPredictRedbookPostCrawl"`）：
         - `businessKey = "author_{parentSubTaskId}_{authorId}"`
         - `subTaskParams` = `{ source, businessType, taskType:"userInfo", crawlType:"userInfo", userId, keyword, priority, expireAt }`
         - 使用 `crawlTaskIdCodec.encode(subTaskId)` 生成 taskId 下发爬取引擎
3. 当前子任务状态 → SUCCESS（result 中存储 `NotePostCrawlResult`，含 keyword、来源信息和首日数据 extra）
4. 调用 `taskCompletionHelper.updateParentTaskStats()` 更新父任务统计

#### 3.3.2 PostCrawl 子任务下发 — subExecute（`executor = "hotPredictRedbookPostCrawl"`）

`HotPredictRedbookPostCrawl` 覆写 `subExecute()`，执行 noteId 驱动逻辑：

1. 从任务参数中获取 noteId 列表（`param.noteIds`）
2. 遍历 noteIds，查询 `redbook_note_post` 表：
   - **记录存在且有 xsec_token** → 加入下发队列
   - **记录不存在或无 xsec_token** → 日志警告该 noteId 不可用，**跳过**（不终止整体任务）
3. 部分成功场景：
   - **部分 noteId 有效** → 只为有效的 noteId 调用 `CrawlTaskClient.createTask()` 下发 detail 页爬取任务
   - **全部 noteId 均无效** → 子任务直接 FAILED，不下发任何爬取任务
4. 子任务状态 → RUNNING（等待爬取引擎回调）

#### 3.3.3 PostCrawl 回调 — Detail + UserInfo 处理（`executor = "hotPredictRedbookPostCrawl"`）

`HotPredictRedbookPostCrawlHandler.handleRedbookDetail()`：

1. 解析回调 `data.data.data.cards[0].note_card`
2. 提取图文帖数据 → 构造 `NotePostCrawlResult`（存于 `SubTask.result`）
   - 合并首日数据（preCrawl 大搜阶段提取的 `firstDayLikes/Collects/Comments`）到 extra 字段
3. 子任务状态 → SUCCESS
4. 数据落库由 `MaterialProcessTask` + `RedbookNotePostProcessStrategy` 异步处理：
   - 读取 `SubTask.result` 中的 `NotePostData`（含首日数据 extra）
   - 写入 `redbook_note_post` 表（insert 或更新）
   - 同时从 detail 响应提取 author 信息（user_id, nick_name, avatar）
   - upsert `redbook_author_info`（基础信息）

`HotPredictRedbookPostCrawlHandler.handleRedbookUserInfo()`：

1. 解析回调 `data.data.data`
2. 提取作者信息 → 构造 `AuthorInfoData`（存于 `SubTask.result`）
3. 子任务状态 → SUCCESS
4. 数据落库由 `MaterialProcessTask` + `RedbookAuthorProcessStrategy` 异步处理：
   - 读取 `SubTask.result` 中的 `AuthorInfoData`
   - upsert `redbook_author_info`（完整信息）

#### 3.3.4 定时任务 — 互动数据刷新

**目的：** 定期更新 `redbook_note_post` 表中的 `total_likes` / `total_collect` / `total_comments` / `total_shares`，因为小红书帖子发布后互动数据会持续增长。

**方案（QSchedule）：**

1. 定时扫描 `redbook_note_post` 表，按 `last_update_time` 筛选需刷新的帖子
2. 对每条笔记，调用 detail 页爬取获取最新互动数据
3. 更新 `total_likes / total_collect / total_comments / total_shares` 字段
4. 同时更新 `last_update_time`
5. 配置化执行周期（key: `hotpredict.redbook.stats.refresh.interval`，默认每 6 小时）

> 首日数据（`firstDayLikes/Collects/Comments` 存于 extra）与当前互动数据（`total_likes/Collects/Comments` 为表字段）分离：
> - 首日数据由 **preCrawl** 在 bigSearch 阶段捕获，写入 extra 后不再变更
> - 当前数据由 **定时任务** 定期刷新，反映最新互动情况

#### 3.4 新增 DTO（回调对象扩展）

图文帖回调需要新增两个 DTO 反序列化结构，区别于视频素材。

**中间传输结构 `NotePostCrawlResult`**（类比 `MaterialCrawlResult`，存于 SubTask.result）：

| 字段 | 类型 | 说明 |
|------|------|------|
| source | String | 来源 `redbook` |
| crawlType | String | `bigSearch` / `detail` / `userInfo` |
| keyword | String | 搜索关键词 |
| subTaskId | Long | 子任务 ID |
| notePost | NotePostData | 图文帖数据（detail回调时） |
| authorInfo | AuthorInfoData | 作者数据（userInfo回调时） |

**`NotePostData`** — 图文帖数据，直接映射 `redbook_note_post` 表字段。
`label` 字段参考 `MaterialLabel` 结构（`material_base.material_label`）：
```java
@Data
public class NotePostLabel {
    @JsonProperty("common_tag")
    private List<String> commonTag;
    private List<String> poi;
    private List<String> city;
    @JsonProperty("ai_tag")
    private List<String> aiTag;
}
```
`extra` 字段中额外存储首日互动数据：
```json
{
  "firstDayLikes": 84,
  "firstDayCollects": 52,
  "firstDayComments": 21
}
```
由 preCrawl 在 bigSearch 回调阶段写入，持久化后不再变更。

**`AuthorInfoData`** — 作者数据，直接映射 `redbook_author_info` 表字段。

> **⚠️ 现有 DTO 缺失字段（需新增）**
>
> `XhsCrawlDetailTaskResultData.NoteCard` 当前缺少两个字段，需补充：
> | 字段名 | 类型 | 对应回调路径 | 表字段 |
> |--------|------|-------------|--------|
> | `ipLocation` | `String` | `cards[0].note_card.ip_location` | `redbook_note_post.ip_location` |
> | `atUserList` | `List<AtUserItem>` | `cards[0].note_card.at_user_list` | `redbook_note_post.at_user_list` |
>
> 另外需新增 `AtUserItem` 内部类：
> ```java
> @Data
> public static class AtUserItem {
>     private String userId;
>     private String nickName;
> }
> ```

---

## 3.5 对外 API 设计

### 3.5.1 接口定义

**说明：** 新增独立 Controller（不复用现有 `addTask` 入口），供外部系统触发小红书图文帖抓取任务。调用方需提供 `configKey` 进行鉴权。

**Endpoint：** `POST /api/assignTask/`

**Request Body：**

```json
{
    "configKey": "xxx",
    "taskType": "HotPredictRedbookPreCrawl | HotPredictRedbookPostCrawl",
    "dataSourceType": "batch",
    "data": {
        "searchKeywords": ["搜索词1", "搜索词2"]
    }
}
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `configKey` | String | 是 | 调用方鉴权 Key，与 QConfig 配置值比对 |
| `taskType` | String | 是 | `HotPredictRedbookPreCrawl`（关键词发现）/ `HotPredictRedbookPostCrawl`（noteId 刷新） |
| `dataSourceType` | String | 是 | 固定 `"batch"`（批量任务） |
| `data.searchKeywords` | String[] | 是 | PreCrawl 时 = 搜索关键词列表；PostCrawl 时 = 笔记 ID 列表 |

> `searchKeywords` 名称对齐 `MaterialCrawlData.searchKeywords`，PreCrawl 时可直接构造 `MaterialCrawlData` 传入 `MaterialCrawlExecutor.execute()` 复用其 SubTask 拆分逻辑。

**Response：**

```json
{
    "code": 0,
    "msg": "msg_1a85e32faa0f",
    "data": {
        "taskId": 214
    }
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `code` | int | `0` 成功，非 `0` 失败 |
| `msg` | String | 成功时为 `"msg_{uuid}"`，失败时为错误描述 |
| `data.taskId` | Long | 创建的父任务 ID |

### 3.5.2 校验规则

| 校验项 | 失败处理 |
|--------|----------|
| `configKey` 为空或不匹配 QConfig 配置值 | 返回 `code: 401, msg: "invalid configKey"` |
| `taskType` 不在枚举中 | 返回 `code: 400, msg: "invalid taskType"` |
| `dataSourceType` 不为 `"batch"` | 返回 `code: 400, msg: "invalid dataSourceType"` |
| `searchKeywords` 为空 | 返回 `code: 400, msg: "searchKeywords required"` |

### 3.5.3 内部流程（适配 `MaterialCrawlExecutor.execute()`）

PreCrawl 复用 `MaterialCrawlExecutor.execute()` 的 SubTask 拆分逻辑，Controller 做适配层：

```
POST /api/assignTask/  (PreCrawl)
  │
  ├─ 1. 校验 configKey / taskType / searchKeywords
  │
  ├─ 2. 从 QConfig 加载 ExecutorConfig（taskQConfig.getConfig(configKey)）
  │       └─ 包含：platforms、crawlCount、priority、expireAt 等参数
  │
  ├─ 3. 创建 Task 记录（taskService.createTask）
  │     ├─ executor = "hotPredictRedbookPreCrawl"
  │     ├─ configKey → 写入 taskParams.configKey
  │     └─ 从 QConfig ExecutorConfig 中提取：
  │           dataSourceType: "batch",
  │           data: { searchKeywords: [...] },
  │           params: { platforms: [...] },          ← QConfig 配置的平台参数
  │           executorSnapshot: { ... }               ← QConfig 完整快照
  │
  ├─ 4. hotPredictRedbookPreCrawl.executeWithTracking(task)
  │     │
  │     ├─ buildContext(task) → TaskContext
  │     │     ├─ task, taskParamBO, executorConfig
  │     │     └─ data = { searchKeywords: [...] }
  │     │
  │     ├─ MaterialCrawlExecutor.execute(context)  ← 继承复用
  │     │     │
  │     │     ├─ getData(context)
  │     │     │     └─ Jackson convertValue → MaterialCrawlData(searchKeywords)
  │     │     │
  │     │     ├─ getParams(context)
  │     │     │     └─ Jackson convertValue → MaterialCrawlParams(platforms)
  │     │     │
  │     │     └─ 按 (searchKeyword × platform) 拆分 SubTask
  │     │           └─ subTask.executor = "hotPredictRedbookPreCrawl"（getName()）
  │     │
  │     └─ 各 SubTask.subExecute() → bigSearch 下发爬取引擎
  │
  └─ 5. 返回 { code:0, data:{ taskId } }

---

POST /api/assignTask/  (PostCrawl)
  │
  ├─ 1. 校验 configKey / taskType / searchKeywords
  │
  ├─ 2. 创建 Task 记录 + 单个 SubTask
  │     ├─ executor = "hotPredictRedbookPostCrawl"
  │     └─ subTaskParams = { noteIds: searchKeywords }
  │
  ├─ 3. hotPredictRedbookPostCrawl.subExecuteWithTracking(subTask, null)
  │     │
  │     └─ subExecute() → 遍历 noteIds 查 DB
  │           ├─ 有数据 + xsec_token → 下发 detail 爬取
  │           └─ 无数据 → 日志跳过
  │
  └─ 4. 返回 { code:0, data:{ taskId } }
```

---

## 4. 数据库表设计

### 4.1 `redbook_note_post` — 小红书图文帖表

来源：detail 回调 `cards[0].note_card`，字段映射见 `field-mapping.md`

| 字段 | 类型 | 报文来源 | 说明 |
|------|------|----------|------|
| id | bigint PK | - | 自增主键 |
| note_id | varchar(64) UNIQUE | `cards[0].note_card.note_id` / `cards[0].id` | 小红书 noteId |
| title | varchar(1024) | `cards[0].note_card.title` | 笔记标题 |
| note_desc | text | `cards[0].note_card.desc` | 笔记正文/简介 |
| note_type | varchar(16) | `cards[0].note_card.type` | normal(图文) / video(视频) |
| cover_url | varchar(1024) | `cards[0].note_card.image_list[0].url_default` | 封面图(首图 URL) |
| image_list | json | `cards[0].note_card.image_list[]` → url_default | 多张图片 URL 列表 |
| tag_list | json | `cards[0].note_card.tag_list[]` | `[{name,id,type}]` |
| ip_location | varchar(64) | `cards[0].note_card.ip_location` | IP 属地 |
| author_id | varchar(64) | `cards[0].note_card.user.user_id` | 作者 ID |
| author_name | varchar(256) | `cards[0].note_card.user.nick_name` | 作者昵称 |
| author_avatar | varchar(1024) | `cards[0].note_card.user.avatar` | 作者头像 |
| total_likes | int | `cards[0].note_card.interact_info.liked_count` | 点赞数 |
| total_collect | int | `cards[0].note_card.interact_info.collected_count` | 收藏数 |
| total_comments | int | `cards[0].note_card.interact_info.comment_count` | 评论数 |
| total_shares | int | `cards[0].note_card.interact_info.share_count` | 分享数 |
| publish_time | datetime | `cards[0].note_card.time`（毫秒 → datetime） | 发布时间 |
| last_update_time | datetime | `cards[0].note_card.last_update_time` | 最后更新时间 |
| xsec_token | varchar(256) | `cards[0].xsec_token` | 透传 token |
| at_user_list | json | `cards[0].note_card.at_user_list` | @用户列表 |
| keyword | varchar(256) | 从 subTaskParams 提取 | 来源搜索关键词 |
| label | json | - | 标签JSON：`{"common_tag":[],"poi":[],"city":[],"ai_tag":[]}`，参考 `material_base.material_label`，由 `RedbookNotePostProcessStrategy` 从标题/正文 + keyword 提取 |

> **label 生成逻辑（参考 `MaterialProcessService.processItem()`）：**
> 1. `common_tag` 来源：搜索关键词 `keyword` + 标题/正文中的 `#tag`（去重合并）
> 2. `keyword` 一定存在（preCrawl 必有搜索词，postCrawl 从数据库已有记录中读取）
> 3. poi/city/ai_tag 当前暂不填充，保留空数组。

| extra | json | - | 扩展字段（含首日数据：`{"firstDayLikes":84,"firstDayCollects":52,"firstDayComments":21}`） |
| crawl_time | datetime | 当前时间 | 抓取时间 |
| create_time | datetime | - | 创建时间 |
| update_time | datetime | - | 更新时间 |

### 4.2 `redbook_author_info` — 小红书作者信息表

来源：userInfo 回调 `data.data.data`，字段映射见 `field-mapping.md`

| 字段                  | 类型                 | 报文来源                                      | 说明                       |
| ------------------- | ------------------ | ----------------------------------------- | ------------------------ |
| id                  | bigint PK          | -                                         | 自增主键                     |
| author_id           | varchar(64) UNIQUE | `data.data.data.userid`                   | 作者 ID                    |
| nickname            | varchar(256)       | `data.data.data.nickname`                 | 作者昵称                     |
| avatar_url          | varchar(1024)      | `data.data.data.images`                   | 头像 URL                   |
| description         | text               | `data.data.data.desc`                     | 作者简介                     |
| gender              | tinyint            | `data.data.data.gender`                   | 0-未知 / 1-男 / 2-女         |
| follower_count      | int                | `data.data.data.fans`                     | 粉丝数                      |
| following_count     | int                | `data.data.data.follows`                  | 关注数                      |
| note_count          | int                | `data.data.data.note_num_stat.posted`     | 笔记数                      |
| total_liked         | int                | `data.data.data.liked`                    | 获赞数                      |
| total_collected     | int                | `data.data.data.collected`                | 收藏数                      |
| location            | varchar(256)       | `data.data.data.location`                 | 位置信息                     |
| ip_location         | varchar(64)        | `data.data.data.ip_location`              | IP 属地                    |
| red_id              | varchar(64)        | `data.data.data.red_id`                   | 小红书号                     |
| red_official_verify | tinyint            | `data.data.data.red_official_verify_type` | 0-未认证 / 1-认证             |
| tags                | json               | `data.data.data.tags[]`                   | 作者标签 `[{name,tag_type}]` |
| is_seller           | tinyint            | `data.data.data.seller_info != null`      | 0-无店铺 / 1-有店铺            |
| is_buyer            | tinyint            | `data.data.data.buyer_info != null`       | 0-无橱窗 / 1-有橱窗            |
| share_link          | varchar(1024)      | `data.data.data.share_link`               | 用户主页分享链接                |
| extra               | json               | -                                         | 扩展字段                     |
| crawl_time          | datetime           | 当前时间                                      | 抓取时间                     |
| create_time         | datetime           | -                                         | 创建时间                     |
| update_time         | datetime           | -                                         | 更新时间                     |

---

## 5. 涉及改造的文件

### 5.1 回调分发（`ExecutorHandler` 策略体系）

| 文件 | 改动 |
|------|------|
| 新增 `ExecutorHandler` 接口 | `supports(executor)` + `handle(context, parsedData)` 统一入口 |
| 新增 `AbstractExecutorHandler` | 实现 `ExecutorHandler`，空实现 |
| 新增 `RedbookExecutorHandler` | 小红书平台抽象层，handle() → 按 crawlType 路由到 `handleRedbookDetail()`/`handleRedbookBigSearch()`/`handleRedbookUserInfo()` |
| 新增 `DouyinExecutorHandler`（预留） | 抖音平台抽象层，结构同 Redbook |
| 新增 `HotPredictRedbookPreCrawlHandler` | bigSearch 回调处理：作者过滤 + 拆分子任务；绑定 executor=`hotPredictRedbookPreCrawl` |
| 新增 `HotPredictRedbookPostCrawlHandler` | detail + userInfo 回调处理：解析存储结果；绑定 executor=`hotPredictRedbookPostCrawl` |
| 新增 `DefaultExecutorHandler` | 原有视频逻辑合并（bigSearch 拆子任务 + detail 提取素材）；绑定 executor=`MaterialCrawlExecutor` |
| `XhsCrawlTaskResultHandler.java` | 重写 `handle()`：按 executor 查找 `ExecutorHandler` 并委托；未匹配时回退 `super.handle()` |

### 5.2 素材入库定时任务

| 文件 | 改动 |
|------|------|
| `MaterialProcessTask.java` | `doProcessSubTask()` 重写，根据 executorName 路由到不同处理逻辑 |
| `MaterialProcessStrategy.java` | `supports(source, crawlType)` → `supports(source, crawlType, executorName)` |
| `DefaultMaterialProcessStrategy.java` | 适配新接口签名；改为 `!(redbook + bigSearch)` + 排除 `hotPredictRedbookPostCrawl` |
| `RedbookBigSearchSkipStrategy.java` | 适配新接口签名；`supports` 增加 executorName 维度 |
| 新增 `RedbookNotePostProcessStrategy.java` | 处理图文帖落库（含图片缓存 + 标签提取 + 首日数据 extra 合并） |
| 新增 `RedbookAuthorProcessStrategy.java` | 处理作者信息落库 |

### 5.3 父任务完成 & 后处理

| 文件 | 改动 |
|------|------|
| `TaskCompletionService.java` | `tryCompleteTask()` 扩展 executor 特殊逻辑；postProcess HTTP 回调下游 |
| 新增 `PostProcessService` | 过滤子任务、组装回调结果 → HTTP POST 到下游 python 服务 |

### 5.4 Entity / Mapper / Service

| 文件 | 改动 |
|------|------|
| 新增 `RedbookNotePost.java` | 图文帖实体（含 extra JSON 中 firstDayLikes/Collects/Comments 解析） |
| 新增 `RedbookNotePostMapper.java` | 图文帖 Mapper |
| 新增 `RedbookAuthorInfo.java` | 作者信息实体 |
| 新增 `RedbookAuthorInfoMapper.java` | 作者信息 Mapper |
| 新增 `RedbookNotePostService.java` | 图文帖落库 Service |
| 新增 `RedbookAuthorInfoService.java` | 作者信息落库 Service |

### 5.5 对外 API

| 文件 | 改动 |
|------|------|
| 新增 `AssignTaskController.java` | `POST /api/assignTask/`，校验 configKey + 参数合法性 + 路由到 PreCrawl/PostCrawl |
| 新增 `AssignTaskRequest.java` | 请求体 DTO（configKey, taskType, dataSourceType, data） |
| 新增 `AssignTaskResponse.java` | 响应体 DTO（code, msg, data.taskId） |

---

## 6. 数据流转图（基于实际报文）

### 6.1 PreCrawl 回调（bigSearch）→ 拆分子任务

```
BigSearch 回调 (executor = "hotPredictRedbookPreCrawl")
  body.data = {
    data: {  data: { items: [ ... ] }  },   ← ×2 JSON 嵌套
    pageNum, reachedBottom
  }
  │
  ├─ 解析为 XhsCrawlBigSearchTaskResultData
  │     → BigSearchPageData.items[]
  │
  ├─ 遍历 items，过滤 note_card.type == "normal" && model_type == "note"
  │
  ├─ 查询 redbook_author_info（by note_card.user.user_id）
  │
  ├─ 作者过滤（同时满足则跳过本条）：
  │     ├─ author 记录存在
  │     ├─ update_time > 当前时间 - 7天（数据新鲜）
  │     ├─ is_seller = 1（有店铺）
  │     └─ follower_count > 10000（高粉丝）
  │     → 跳过，不下发任何子任务
  │
  ├─ 不满足过滤条件时：
  │   ├─ 提取首日数据（preCrawl 只抓一天内帖子，此时为 D0 值）
  │   │     ├─ firstDayLikes   ← interact_info.liked_count
  │   │     ├─ firstDayCollects ← interact_info.collected_count
  │   │     └─ firstDayComments ← interact_info.comment_count
  │   │     → 存入 extra JSON: {"firstDayLikes":84,"firstDayCollects":52,"firstDayComments":21}
  │   │
  │   ├─ Detail 子任务（executor = "hotPredictRedbookPostCrawl"）
  │   │     businessKey = "detail_{parentSubTaskId}_{noteId}"
  │   │     subTaskParams = {
  │   │       source:"redbook", businessType:"mkt_odin",
  │   │       taskType:"detail", crawlType:"detail",
  │   │       noteId, xsecToken, keyword, priority, expireAt,
  │   │       extra: {firstDayLikes, firstDayCollects, firstDayComments}
  │   │     }
  │   │
  │   └─ UserInfo 子任务（executor = "hotPredictRedbookPostCrawl"）
  │         businessKey = "author_{parentSubTaskId}_{authorId}"
  │         subTaskParams = {
  │           source:"redbook", businessType:"mkt_odin",
  │           taskType:"userInfo", crawlType:"userInfo",
  │           userId, keyword, priority, expireAt
  │         }
  │
  └─ 当前 SubTask → SUCCESS（result 中 extra 字段携带首日数据）
```

### 6.2 PostCrawl 回调 — Detail 处理 → 存 SubTask.result

```
Detail 回调 (executor = "hotPredictRedbookPostCrawl", crawlType = "detail")
  body.data = {
    data: {  data: { cards: [{
      note_card: {
        note_id, title, desc, type:"normal",
        image_list[], tag_list[], user, interact_info,
        ip_location, time, last_update_time, xsec_token,
        at_user_list, share_info
      },
      id, xsec_token, model_type:"note"
    }] }  },
    pageNum, reachedBottom
  }
  │
  ├─ 解析为 XhsCrawlDetailTaskResultData
  │     → DetailPageData.cards[0].note_card
  │
  ├─ 构造 NotePostCrawlResult → 存入 SubTask.result
  │     ├─ note_id, title, desc, note_type:"normal"
  │     ├─ cover_url = image_list[0].url_default
  │     ├─ image_list = [image_list[].url_default]  (JSON)
  │     ├─ tag_list = tag_list[]  (JSON)
  │     ├─ ip_location, xsec_token, at_user_list
  │     ├─ author_id, author_name, author_avatar (from user)
  │     ├─ total_likes, total_collect, total_comments, total_shares
  │     ├─ publish_time = time (毫秒转datetime)
  │     ├─ last_update_time, keyword
  │     └─ crawl_time = now()
  │
  ├─ MaterialProcessTask 异步处理（后续）：
  │     ├─ 读取 SubTask.result → 写入 redbook_note_post
  │     └─ upsert redbook_author_info（基础信息：author_id, nickname, avatar_url）
  │
  └─ SubTask → SUCCESS
```

### 6.3 PostCrawl 回调 — UserInfo 处理 → 存 SubTask.result

```
UserInfo 回调 (executor = "hotPredictRedbookPostCrawl", crawlType = "userInfo")
  body.data = {
    data: {  data: {
      userid, nickname, images, desc, gender, fans,
      follows, note_num_stat:{posted,liked,collected},
      liked, collected, location, ip_location, red_id,
      red_official_verify_type, tags[], seller_info, ...
    }  }
  }
  │
  ├─ 构造 AuthorInfoData → 存入 SubTask.result
  │     ├─ author_id, nickname, avatar_url, description
  │     ├─ gender, follower_count, following_count, note_count
  │     ├─ total_liked, total_collected
  │     ├─ location, ip_location, red_id
  │     ├─ red_official_verify, tags, is_seller, is_buyer
  │     └─ share_link, crawl_time = now()
  │
  ├─ MaterialProcessTask 异步处理（后续）：
  │     └─ 读取 SubTask.result → upsert redbook_author_info
  │
  └─ SubTask → SUCCESS
```

### 6.4 PostCrawl subExecute — NoteId 驱动查 DB + 下发 Detail

```
hotPredictRedbookPostCrawl.subExecute(taskParam)
  param = { noteIds: ["noteId1", "noteId2", ...] }
  │
  ├─ 遍历 noteIds
  │   ├─ 查询 redbook_note_post（by note_id）
  │   │   ├─ 记录存在 && xsec_token 非空 → 加入下发队列
  │   │   └─ 记录不存在或 xsec_token 为空 → 日志警告，跳过
  │   │
  │   ├─ 有有效 noteId → 批量下发 detail 页爬取任务
  │   ├─ 全部无效 → 整个子任务 FAILED
  │   └─ 部分有效 → 下发有效部分，无效部分记录日志
  │
  └─ 有成功下发的任务 → SubTask → RUNNING（等待爬取引擎回调）
```

Detail 回调到达后走 6.2 / 6.3 流程。

### 6.5 素材入库（`MaterialProcessTask`）

> **⚠️ 关键约束：扫描范围需扩展**
>
> 当前 `MaterialProcessTask.doProcess()` 只扫描 executor = `"MaterialCrawlExecutor"` 的 SUCCESS 子任务：
> ```java
> subTaskService.getSuccessTasks(
>     hotFileQConfig.getString("material.process.source", "MaterialCrawlExecutor"), getBatchSize());
> ```
> 新流程的 executor 为 `"hotPredictRedbookPreCrawl"` 和 `"hotPredictRedbookPostCrawl"`，不会被扫描到。
>
> **改造方案：** `getSuccessTasks()` 改为接收多 executor：
> ```java
> // 方案 A: 扩展 getSuccessTasks 为 list 参数
> List<SubTask> subTasks = subTaskService.getSuccessTasks(
>     List.of("MaterialCrawlExecutor", "hotPredictRedbookPreCrawl", "hotPredictRedbookPostCrawl"),
>     getBatchSize());
>
> // 方案 B（推荐）: 保持原有扫描，额外扫描新 executor
> List<SubTask> legacyTasks = subTaskService.getSuccessTasks("MaterialCrawlExecutor", batchSize);
> List<SubTask> noteTasks = subTaskService.getSuccessTasks("hotPredictRedbookPostCrawl", batchSize);
> ```

```
SubTask → SUCCESS
  │
  ├─ MaterialProcessTask 扫描 SUCCESS 子任务
  │   （扫描 executor IN ("hotPredictRedbookPreCrawl","hotPredictRedbookPostCrawl","MaterialCrawlExecutor")）
  │
  ├─ 查找匹配策略（`supports(source, crawlType, executorName)`）
  │     ├─ hotPredictRedbookPreCrawl / bigSearch → RedbookBigSearchSkipStrategy（跳过）
  │     ├─ hotPredictRedbookPostCrawl / detail  → RedbookNotePostProcessStrategy
  │     │     → 解析 SubTask.result 中 NotePostData
  │     │     → 提取标签（参考 MaterialProcessService.processItem()）：
  │     │       ├─ 来源：keyword（搜索词）+ title/desc 中 #tag
  │     │       ├─ 合并到 label.common_tag（去重）
  │     │       └─ label 结构：{"common_tag":["搜索词","tag1"],"poi":[],"city":[],"ai_tag":[]}
  │     │     → 下载图片并缓存至 Qunar CDN：
  │     │       ├─ 遍历 image_list，下标 i
  │     │       ├─ 下载原图 → 上传至 CDN
  │     │       └─ 文件名: {noteId}_{i}（如 6a366131..._0.jpg）
  │     │       ├─ cover_url ← cached_url[0]
  │     │       └─ image_list ← 替换为 cached_url 列表
  │     │     → insert/update redbook_note_post（含首日数据 extra）
  │     │     → upsert redbook_author_info（基础信息）
  │     ├─ hotPredictRedbookPostCrawl / userInfo → RedbookAuthorProcessStrategy
  │     │     → 解析 SubTask.result 中 AuthorInfoData
  │     │     → upsert redbook_author_info（完整信息）
  │     └─ MaterialCrawlExecutor / detail  → DefaultMaterialProcessStrategy（原有视频逻辑）
  │
  └─ SubTask → ANALYSIS_SUCCESS / ANALYSIS_FAIL
```

### 6.6 父任务完成（`TaskCompletionService`）+ postProcess 回调

```
父任务 → 所有子任务终态
  │
  ├─ tryCompleteTask() 扩展
  │     ├─ 如果父任务下包含 hotPredictRedbookPostCrawl 子任务
  │     │   → 统计 detail + userInfo 子任务的完成情况
  │     │   → 只有 author 或 detail 失败时才标记父任务 FAILED
  │     └─ postProcess
  │           → 过滤出成功的 detail 子任务
  │           → 组装回调结果 → HTTP POST 下游 python 服务
  │
  └─ 父 Task → SUCCESS / FAILED
```

**回调协议：**

| 项 | 说明 |
|----|------|
| 协议 | HTTP |
| 方法 | POST |
| Content-Type | application/json |
| 目标 | 下游 python 服务（URL 由业务方提供，QConfig 配置化，key: `hotpredict.callback.url`） |
| 触发时机 | 父任务所有子任务达到终态，`tryCompleteTask()` 中调用 |

**回调 Request Body：**

```json
{
    "taskId": 214,
    "taskType": "HotPredictRedbookPreCrawl | HotPredictRedbookPostCrawl",
    "dataList": [
        {
            "keyword": "搜索词",
            "noteId": "6a366131000000002101aa61",
            "title": "三亚3天2晚旅游攻略🌴",
            "content": "笔记正文全文 desc",
            "imageUrls": ["https://qunar.cdn.com/noteId_0.jpg", "..."],
            "userId": "5e15586000000000010012c9",
            "userName": "小小小提米。",
            "userLink": "https://www.xiaohongshu.com/user/profile/5e1558...",
            "tags": [{"name":"三亚旅游攻略","type":"topic"}],
            "publishTime": "2025-03-15 10:00:00",
            "shareLink": "https://www.xiaohongshu.com/...",
            "totalLikes": 84,
            "totalCollects": 52,
            "totalShares": 1,
            "totalComments": 21,
            "firstDayLikes": 80,
            "firstDayCollects": 50,
            "firstDayComments": 20
        }
    ]
}
```

| 字段 | preCrawl | postCrawl | 来源 |
|------|----------|-----------|------|
| keyword | ✅ 返回 | ❌ 不返回 | subTaskParams / 数据库 keyword |
| noteId | ✅ | ✅ | `redbook_note_post.note_id` |
| title | ✅ | ✅ | `redbook_note_post.title` |
| content | ✅ | ✅ | `redbook_note_post.note_desc` |
| imageUrls | ✅ | ✅ | `redbook_note_post.image_list`（已缓存 URL） |
| userId | ✅ | ✅ | `redbook_note_post.author_id` |
| userName | ✅ | ✅ | `redbook_note_post.author_name` |
| userLink | ✅ | ✅ | 拼接 `https://www.xiaohongshu.com/user/profile/{author_id}` |
| tags | ✅ | ✅ | `redbook_note_post.tag_list` |
| publishTime | ✅ | ✅ | `redbook_note_post.publish_time` |
| shareLink | ✅ | ✅ | `redbook_author_info.share_link` |
| totalLikes | ✅ | ✅ | `redbook_note_post.total_likes` |
| totalCollects | ✅ | ✅ | `redbook_note_post.total_collect` |
| totalShares | ✅ | ✅ | `redbook_note_post.total_shares` |
| totalComments | ✅ | ✅ | `redbook_note_post.total_comments` |
| firstDayLikes | ✅ | ✅ | `redbook_note_post.extra.firstDayLikes` |
| firstDayCollects | ✅ | ✅ | `redbook_note_post.extra.firstDayCollects` |
| firstDayComments | ✅ | ✅ | `redbook_note_post.extra.firstDayComments` |

> **字段差异说明：** preCrawl 由关键词搜索触发，包含 `keyword` 来源信息；postCrawl 由 noteId 驱动刷新，不返回 `keyword`。

### 6.7 定时任务 — 互动数据刷新

```
QSchedule 定时任务 (每 6h)
  │
  ├─ 扫描 redbook_note_post
  │     └─ last_update_time < 当前时间 - 6h → 需刷新
  │
  ├─ 对每条需刷新的笔记，下发 detail 页爬取任务
  │
  ├─ detail 回调到达 → 更新互动数据（不覆盖 extra 中首日数据）
  │     ├─ total_likes    ← interact_info.liked_count
  │     ├─ total_collect  ← interact_info.collected_count
  │     ├─ total_comments ← interact_info.comment_count
  │     ├─ total_shares   ← interact_info.share_count
  │     └─ last_update_time = now()
  │
  └─ 更新 redbook_note_post 表
```


---

## 7. Deepdive 发现与代码对照

### 7.1 新架构解决的关键问题

新架构（`XhsCrawlTaskResultHandler` 重写 `handle()` + 按 executor 路由到 `ExecutorHandler`）解决了旧架构中的三大问题：

| 旧问题 | 旧方案 | 新方案 |
|--------|--------|--------|
| `switch` 不处理 USER_INFO | 需在 `AbstractCrawlTaskResultHandler` 加分支 | `XhsCrawlTaskResultHandler.handle()` 直接按 executor 路由，不依赖 crawlType 分支 |
| 多个策略共享同一 executor 时需组合 taskType | `supports(executor, taskType)` 双重匹配 | 每个 executor 绑定唯一 handler，handler 内部分发 |
| 现有逻辑与新逻辑耦合在同一个 handler 类中 | 大量 if/else | 独立 Handler 类，通过 Spring 注入 |

### 7.2 回调 Data 路径确认

实际报文嵌套层次（已通过 origin-message 确认）：

| 回调类型 | 完整路径（从 callback.attrs.body.data 开始） |
|---------|-------------------------------------------|
| BigSearch | `data.data.data.items[].note_card` (×3 嵌套) |
| Detail | `data.data.data.cards[].note_card` (×3 嵌套) |
| UserInfo | `data.data.data` (×3 嵌套) |

`XhsCrawlBigSearchTaskResultData` / `XhsCrawlDetailTaskResultData` 均有自定义 `Deserializer` 处理 JSON 字符串嵌套展开。这些 DTO 可直接复用，**无需新增反序列化逻辑**。

### 7.3 现有 DTO 缺失字段

`XhsCrawlDetailTaskResultData.NoteCard` 缺少 `ipLocation` 和 `atUserList`，需补充（见 3.4 节）。

### 7.4 Callback Handler vs MaterialProcessTask 的职责划分

| 维度 | Callback Handler | MaterialProcessTask |
|------|-----------------|-------------------|
| 时机 | MQ 回调实时触发 | 定时任务批量扫描 |
| 操作 | 解析报文 → 构造 DTO → 存 `SubTask.result` | 读 `SubTask.result` → 写入业务表 |
| 异常影响 | 子任务标记 FAILED | 子任务标记 ANALYSIS_FAIL |

**原则：** Callback Handler 不直接操作 DB 业务表，遵循现有 `MaterialCrawlResult` 模式。

### 7.5 `MaterialProcessTask` 扫描范围需扩展

当前只扫描 `executor = "MaterialCrawlExecutor"`（通过 QConfig 配置 `material.process.source`）。
新 executor `"hotPredictRedbookPreCrawl"` 和 `"hotPredictRedbookPostCrawl"` 不会被扫描到。

**改造方案：** 将 `getSuccessTasks` 从单 executor 改为多 executor 查询（见 6.4 节）。

### 7.6 `MaterialProcessStrategy.supports()` 接口签名

当前：
```java
boolean supports(String source, String crawlType);
```

新图文帖 detail 和原有视频 detail 的 `source=redbook, crawlType=detail` 完全相同。
需要增加 `executorName` 维度区分：
```java
boolean supports(String source, String crawlType, String executorName);
```

### 7.7 作者过滤条件所需的 DB 字段

`HotPredictRedbookPreCrawlHandler` 的过滤逻辑需要读取 `redbook_author_info` 的三个字段：
- `update_time` — 判断数据是否在 7 天有效期内
- `is_seller` — 判断是否有店铺
- `follower_count` — 判断粉丝数是否 > 10000

**前置条件：** `redbook_author_info` 表已包含这些字段，DDL 已确认。

### 7.8 BigSearch 分页

回调有 `has_more: true`，但当前设计 V1 不做分页处理。
每次 bigSearch 只抓取 `crawlCount` 指定数量，由爬取引擎控制单页返回条数。

### 7.9 BigSearch vs Detail 的 `image_list` 差异

| 回调 | image_list 内容 | cover 来源 |
|------|----------------|-----------|
| BigSearch | 可能只有首图 | `note_card.cover.url_default` |
| Detail | 完整图片列表 | `image_list[0].url_default` |

`redbook_note_post.cover_url` 映射的是 Detail 回调中 `image_list[0].url_default`。

### 7.10 `subTaskParams` 反序列化兼容性

`CrawlTaskResultProcessor.buildContext()` 使用 `MaterialCrawlSubTaskParams` 解析 subTaskParams。
新子任务的 `subTaskParams` 包含 `crawlType` 等标准字段即可兼容，多出的 `noteId`/`xsecToken`/`userId` 等字段被 Jackson 忽略。

---

## 8. 已确认 & 待确认事项

### ✅ 已确认
- [x] 报文结构已收到：见 `origin-message.md`
  - BigSearch 列表回调：`items[].note_card` + `items[].id` (noteId) + `items[].xsec_token`
  - Detail 帖子回调：`cards[0].note_card`（含 title/desc/image_list/tag_list/user/interact_info/time）
  - UserInfo 作者回调：`data.data.data`（含 userid/nickname/fans/follows/gender/location/is_seller 等）
- [x] executor 命名：`hotPredictRedbookPreCrawl`（bigSearch 关键词发现）+ `hotPredictRedbookPostCrawl`（noteId 驱动刷新）
- [x] 路由规则：按 executor 匹配，`XhsCrawlTaskResultHandler.handle()` 重写，不再走 crawlType 分支
- [x] 作者过滤条件：author 存在 + 7 天内更新 + is_seller=1 + follower_count>10000 → 跳过该笔记
- [x] 作者过滤时间窗口 QConfig 配置化（key: `hotpredict.redbook.author.refresh.days`）
- [x] postCrawl subExecute：接收 noteId 列表 → 查 `redbook_note_post` 表确认数据 + xsec_token → 部分成功下发有效 noteId
- [x] postCrawl xsec_token 过期不考虑（3天内不会过期）
- [x] 首日数据方案：preCrawl bigSearch 阶段提取 `firstDayLikes/Collects/Comments` → 存入 extra JSON 字段
- [x] 定时任务：QSchedule 定期刷新 `total_likes/collect/comments/shares`（key: `hotpredict.redbook.stats.refresh.interval`，默认 6h）
- [x] 子任务 subTaskParams 必须含 `crawlType` 字段（供 `CrawlTaskResultProcessor.buildContext()` 使用）
- [x] 对外 API：`POST /api/assignTask/`，校验 configKey，支持 PreCrawl/PostCrawl 两种 taskType
- [x] postProcess 回调：HTTP POST 到下游 python 服务，字段列表已确认（§6.6）
- [x] postProcess 回调失败 → 标记 `PARTIAL_SUCCESS`，不下发重试
- [x] 图片缓存：MaterialProcessTask 入库时处理，文件名 `{noteId}_{index}`
- [x] `label.common_tag` 来源：keyword（搜索词）+ title/desc 中的 `#tag`
- [x] `businessType`：`mkt_odin`
- [x] configKey：同时用于 API 鉴权（`hotpredict.api.configKey`）+ 加载 QConfig executor 配置
- [x] crawlCount 等平台参数走 QConfig 配置
- [x] 多 keyword 去重：暂不做，依赖 `redbook_note_post.uniq_note_id` 唯一键幂等（接受一次额外爬取开销）

### 🔲 待确认
- [ ] `DefaultExecutorHandler` 中原有视频 bigSearch 逻辑（`MaterialCrawlExecutor` 的 detail 子任务）是否已有现成实现代码？
- [ ] 下游 python 服务回调域名（QConfig key: `hotpredict.callback.url`，待业务方提供）

---

## 9. 开发计划

### 阶段一：基础框架 ✅
- [x] 创建 `hotPredictRedbookPreCrawl`、`hotPredictRedbookPostCrawl` 子类（原 `CrawlRedbookPostList` / `CrawlRedBookPostDetail`）
- [x] 设计文档（design.md + field-mapping.md + origin-message.md）
- [x] 建表 DDL（redbook_note_schema.sql）

### 阶段二：Handler 策略体系搭建 + 对外 API
- [ ] `ExecutorHandler` 接口（+ `supports(executor)` / `handle(context, parsedData)`）
- [ ] `AbstractExecutorHandler` 抽象基类（空实现 handle）
- [ ] `RedbookExecutorHandler` 平台抽象（红书路由：crawlType → handleRedbookDetail / handleRedbookBigSearch / handleRedbookUserInfo，均为空实现）
- [ ] `DouyinExecutorHandler` 平台抽象（预留）
- [ ] `HotPredictRedbookPreCrawlHandler`（重写 handleRedbookBigSearch）
- [ ] `HotPredictRedbookPostCrawlHandler`（重写 handleRedbookDetail + handleRedbookUserInfo）
- [ ] `DefaultExecutorHandler`（原有视频逻辑迁移，executor=MaterialCrawlExecutor）
- [ ] `XhsCrawlTaskResultHandler.handle()` 改为 override，遍历 ExecutorHandler 列表按 executor 路由
- [ ] 新增 DTO：`NotePostCrawlResult` / `NotePostData` / `AuthorInfoData`
- [ ] `XhsCrawlDetailTaskResultData.NoteCard` 补字段：`ipLocation`(String) + `atUserList`(List\<AtUserItem\>)
- [ ] 新增 Controller：`POST /api/assignTask/`，含 configKey 校验 + taskType 路由 + 参数校验

### 阶段三：回调处理逻辑
- [ ] **PreCrawlHandler.handleRedbookBigSearch()**：过滤 normal 图文帖 + author 去重 + 提取首日数据入 extra（firstDayLikes/Collects/Comments）+ 创建 detail + userInfo 子任务（executor=hotPredictRedbookPostCrawl）
- [ ] **PostCrawlHandler.handleRedbookDetail()**：解析 note_card 构造 `NotePostCrawlResult`（合并首日数据 extra）→ 存入 `SubTask.result`
- [ ] **PostCrawlHandler.handleRedbookUserInfo()**：解析 userInfo 构造 `AuthorInfoData` → 存入 `SubTask.result`
- [ ] **PostCrawl.subExecute()**：接收 noteId 列表 → 遍历查 `redbook_note_post` 获取 xsec_token → 部分有效则下发、全部无效则 FAILED
- [ ] Author 去重时间窗口 QConfig 配置化（key: `hotpredict.redbook.author.refresh.days`）

### 阶段四：持久化 + 图片缓存
- [ ] Entity / Mapper（`RedbookNotePost`、`RedbookAuthorInfo`）
- [ ] Service 层（落库 + 查重，含 extra 中首日数据解析）
- [ ] `MaterialProcessTask` 重写 — 扫描新增 executor（`hotPredictRedbookPreCrawl`, `hotPredictRedbookPostCrawl`）+ 扩展 `getSuccessTasks` 支持多 executor
- [ ] `MaterialProcessStrategy.supports(source, crawlType)` → `supports(source, crawlType, executorName)`
- [ ] 新增 `RedbookNotePostProcessStrategy`、`RedbookAuthorProcessStrategy`
- [ ] `RedbookBigSearchSkipStrategy` / `DefaultMaterialProcessStrategy` 适配新接口签名
- [ ] **图片缓存逻辑**：入库时遍历 image_list，下载原图 → 上传 CDN → 文件名 `{noteId}_{index}` → 替换 URL
- [ ] **标签提取逻辑**：入库时从 title/desc 提取 `#tag` 合并到 `label.common_tag`（参考 MaterialProcessService.processItem）

### 阶段五：完成 & 后处理
- [ ] `TaskCompletionService.tryCompleteTask()` — executor 维度的特殊完成逻辑
- [ ] postProcess — 过滤子任务结果、组装回调下游
- [ ] QSchedule 定时任务 — 每 6h 刷新 `redbook_note_post` 互动数据（total_likes/collect/comments/shares）
- [ ] 全链路联调
