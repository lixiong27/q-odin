# 小红书图文帖抓取 & 素材入库 - 开发进度

## 项目概述

**项目名称**：小红书图文帖抓取 & 素材入库

新增小红书图文帖抓取链路，支持两条抓取路径：
- **关键词发现（preCrawl）：** bigSearch → 作者过滤 + 首日数据 → detail+userInfo 抓取 → 入库
- **NoteId 刷新（postCrawl）：** noteId 列表 → 查 DB 确认数据 → detail 抓取 → 定时刷新互动数据 → 回调下游

---

## 开发阶段

### 阶段一：设计文档 ✅

| 任务 | 状态 | 说明 |
|------|------|------|
| 设计文档 | ✅ 已完成 | design.md + field-mapping.md — 全流程、架构图、表设计、改造清单 |
| 报文结构确认 | ✅ 已完成 | origin-message.md — bigSearch / detail / userInfo 完整报文 |
| DDL 建表脚本 | ✅ 已完成 | odin_server/docs/sql/redbook_note_schema.sql |
| Deepdive 代码对照 | ✅ 已完成 | 发现 10 项差异（USER_INFO 缺失、DTO 缺字段、executor 传播、策略签名等），已在 design.md 中详细记录 |

### 阶段二：Handler 策略体系搭建 + 对外 API ✅

| 任务 | 状态 | 说明 |
|------|------|------|
| ExecutorHandler 接口 + AbstractExecutorHandler 抽象基类 | ✅ 已完成 | supports(executor) + handle(context, parsedData) |
| RedbookExecutorHandler 平台抽象 | ✅ 已完成 | 按 crawlType 路由：handleRedbookDetail / handleRedbookBigSearch / handleRedbookUserInfo（空实现） |
| DouyinExecutorHandler 平台抽象 | ✅ 已完成 | 预留 |
| HotPredictRedbookPreCrawlHandler | ✅ 已完成 | 重写 handleRedbookBigSearch() — 图文帖过滤 + author 去重 + 提取首日数据 + 创建子任务 |
| HotPredictRedbookPostCrawlHandler | ✅ 已完成 | 重写 handleRedbookDetail()（解析 NoteCard + 合并首日数据）+ handleRedbookUserInfo() |
| DefaultExecutorHandler | ✅ 已完成 | 原有视频逻辑兜底（executor=MaterialCrawlExecutor） |
| XhsCrawlTaskResultHandler.handle() 改为 override | ✅ 已完成 | 遍历 ExecutorHandler 列表按 executor 路由，未匹配回退 super.handle() |
| 新增 DTO | ✅ 已完成 | NotePostCrawlResult / NotePostData / AuthorInfoData |
| XhsCrawlDetailTaskResultData.NoteCard 补字段 | ✅ 已完成 | 新增 ipLocation + atUserList + AtUserItem 内部类 |
| AssignTaskController | ✅ 已完成 | POST /api/assignTask/，configKey 校验 + taskType 路由 + 参数校验结构 |
| 重命名 executor 子类 | ✅ 已完成 | CrawlRedbookPostList → HotPredictRedbookPreCrawl, CrawlRedBookPostDetail → HotPredictRedbookPostCrawl |

### 阶段三：回调处理 ✅

| 任务 | 状态 | 说明 |
|------|------|------|
| PreCrawl BigSearch 回调 | ✅ 已完成 | 过滤 normal 图文帖 + author 去重（查 RedbookAuthorInfo，满足条件跳过）+ 提取首日数据入 extra + 创建 detail+userInfo 子任务 |
| PostCrawl Detail 回调 | ✅ 已完成 | 解析 note_card 构造 NotePostData（含 ipLocation/atUserList/tagList/首日数据）→ 存入 SubTask.result |
| PostCrawl UserInfo 回调 | ✅ 已完成 | 解析 userInfo 嵌套结构 → 构造 AuthorInfoData → 存入 SubTask.result |
| PostCrawl subExecute | ✅ 已完成 | 接收 noteId 列表 → 遍历查 redbook_note_post 获 xsec_token → 部分有效下发 detail、全部无效 FAILED |
| Author 去重逻辑 | ✅ 已完成 | 查询 RedbookAuthorInfoService.getByAuthorId()，判断 updateTime + isSeller + followerCount |

### 阶段四：持久化 + 图片缓存 ✅

| 任务 | 状态 | 说明 |
|------|------|------|
| Entity / Mapper | ✅ 已完成 | RedbookNotePost / RedbookAuthorInfo + Mapper |
| Service 层 | ✅ 已完成 | RedbookNotePostService / RedbookAuthorInfoService |
| MaterialProcessTask 重写 | ✅ 已完成 | 多 executor 扫描（MaterialCrawlExecutor + hotPredictRedbookPreCrawl + hotPredictRedbookPostCrawl）|
| MaterialProcessStrategy 适配 | ✅ 已完成 | supports(source, crawlType) → supports(source, crawlType, executorName) |
| 新增策略实现 | ✅ 已完成 | RedbookNotePostProcessStrategy（解析 + 标签提取 + 入库）+ RedbookAuthorProcessStrategy（upsert） |
| 现有策略适配 | ✅ 已完成 | DefaultMaterialProcessStrategy / RedbookBigSearchSkipStrategy 适配新签名 |

### 阶段五：完成 & 后处理 ✅

| 任务 | 状态 | 说明 |
|------|------|------|
| TaskCompletionService 扩展 | ✅ 已完成 | postProcess HTTP 回调触发点 |
| postProcess HTTP 回调 | ✅ 已完成 | PostProcessService — 组装 dataList → HTTP POST 下游（QConfig: hotpredict.callback.url） |
| QSchedule 定时刷新 stats | ✅ 已完成 | RedbookStatsRefreshTask — 每 6h 扫描 stale notes → 下发 detail 爬取 |
| 全链路联调 | ❌ 待开始 | 端到端验证 |

---

## 当前进度

**当前阶段：** 全部开发完成，待联调

**已完成（全部阶段）：**
- [x] 设计文档 + 全流程方案
- [x] Handler 策略体系（接口 → 抽象 → 平台层 → 具体 Handler）
- [x] 回调处理（Filter → BigSearch → Detail → UserInfo）
- [x] 对外 API（POST /api/assignTask/，含 createPreCrawlTask/createPostCrawlTask）
- [x] Entity/Mapper/Service + 持久化策略（入库 + 标签提取 + upsert）
- [x] MaterialProcessTask 多 executor 扫描 + 策略接口适配
- [x] PostProcessService HTTP 回调下游
- [x] QSchedule 定时刷新互动数据

**待开始：**
- 全链路联调

---

## 技术栈

### 后端
- Java 17
- Spring Boot 2.6.6
- MyBatis 3.x
- QConfig（配置中心）
- QSchedule（定时任务）
- QMQ（消息消费）
- MaterialCrawlExecutor 体系
