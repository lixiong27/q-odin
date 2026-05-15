# 业务模块

## 标签管理（Tag Module）

**用途：** 标签分类 + 叶子标签 CRUD，内容中台基础元数据模块。支持多级树形分类、AI 标签配置、脑图可视化编辑。

**核心能力：**
- 分类管理：多级树形结构，path + parent_id 实现子树查询，递归 CTE（MySQL 8.0+）
- 叶子标签：必须挂载到叶子分类，软删除 valid 标记，级联停用
- 脑图可视化：拖拽编辑分类关系

**关键文件：**
- `domain/entity/TagCategory.java`、`TagLeaf.java`
- `service/TagCategoryService.java`、`TagLeafService.java`
- `web/TagCategoryController.java`、`TagLeafController.java`
- 表：`tag_category`、`tag_leaf`

**API：** `POST /api/tag/category/create|update|delete|toggle`、`GET /api/tag/category/list|tree`、`POST /api/tag/leaf/create|update|delete|toggle`、`GET /api/tag/leaf/list`

**前端：** `src/pages/tag/category.jsx`（分类管理）、`list.jsx`（叶子标签管理）、`visual.jsx`（脑图可视化）

---

## 原始内容同步（Raw Content Sync）

**用途：** 数仓宽表 `raw_content_info` → 6 张标准化业务表（content_base/text/image/video/metrics/label）。支持首次全量同步和指标重同步。

**核心能力：**
- 两阶段设计：Phase1 `@Transactional` 写 DB → Phase2 `doPostSync` 异步 OSS 转存
- content_relations JSON：`{"text_ids":[],"image_ids":[],"video_ids":[]}` 集中存储引用关系
- 幂等写入：每张表独立幂等键和写入策略（SELECT-then-INSERT / ON DUPLICATE KEY UPDATE）
- 并发控制：ThreadPoolTaskExecutor（16 线程），QConfig 动态调节
- 断点续传：Redis 记录 last_processed_id，QSchedule 定时轮询

**关键文件：**
- `service/raw/RawContentSyncService.java` + `impl/RawContentSyncServiceImpl.java`
- `domain/entity/raw/` — ContentBase, ContentText, ContentImage, ContentVideo, ContentMetrics, ContentLabel
- `infra/dao/Content*Mapper.java`（6 个 Mapper）
- `task/RawContentSyncTask.java` — QSchedule 定时任务
- `infra/redis/RawContentRedisService.java` — 同步断点记录

**API：** `POST /api/raw-content/triggerSync`、`POST /api/raw-content/list`（分页查询）

---

## ES 内容搜索（ES Content Search）

**用途：** 将 6 张业务表索引到 Elasticsearch，提供搜索/筛选/排序/分页。含修复、对账、全量重建三个维护任务。

**核心能力：**
- 索引即缓存：ES 只存搜索字段，展示字段由 DataAggregator 回查 MySQL
- 后置同步钩子：DB 同步后自动触发 ES 索引更新
- 三个维护任务：Repair（修复不完整文档，30min）、Reconcile（交叉校验，hourly）、FullRebuild（全量重建，手动）

**关键文件：**
- `domain/entity/es/ContentSearchDocument.java` — ES 文档模型
- `service/es/ContentSearchIndexService.java` — 索引写入
- `service/es/ContentSearchService.java` — 搜索服务
- `service/es/ContentSearchDocAssembler.java` — 6 表 JOIN → Document 组装
- `task/es/ContentRepairTask.java`、`ContentReconcileTask.java`、`ContentFullRebuildTask.java`
- `infra/qconfig/IndexQConfig.java`

**API：** `POST /api/content/search`（全文搜索）、`GET /api/content/filter`（筛选查询）

---

## 内容检索（Content Retrieval）

**用途：** 内容库前端检索服务，提供搜索/筛选/排序/分页/自定义列/预设/高级筛选。含内容详情页（媒体预览、标签编辑、指标看板）和下载打包。

**核心能力：**
- Orchestrator 编排：SearchOrchestrator 协调完整检索管道（埋点 → 路由 → 聚合 → 安全 → 组装）
- Router 路由：根据查询复杂度决定 MySQL 还是 ES
- Aggregator 回查：ES 只存搜索字段，展示字段从 MySQL 回查补全
- 字典驱动渲染：ContentDictService 加载 QConfig JSON，前端所有枚举/列配置/指标分组动态渲染
- 异步埋点：独立线程池，失败不阻塞主流程
- 安全过滤链：参数校验 → URL 安全校验 → 响应

**关键文件：**
- `service/retrieve/service/SearchOrchestrator.java` — 编排核心
- `service/retrieve/service/SearchRouter.java` — 路由决策
- `service/retrieve/service/ContentDataAggregator.java` — 数据聚合回查
- `service/retrieve/service/ContentTrackService.java` — 异步埋点
- `service/retrieve/filter/ContentRetrieveValidationFilter.java` — 参数校验
- `service/retrieve/filter/ContentSecurityFilter.java` — URL 安全校验
- `service/retrieve/service/ContentResponseAssembler.java` — 字典驱动 fieldMeta 组装
- `service/download/ContentDownloadService.java` + `DownloadController.java`

**API：** `GET/POST /api/content/retrieve/search`、`GET /api/content/retrieve/detail/{id}`、`GET /api/content/download`

**前端：** `src/pages/content/list.jsx`（列表页）、`detail.jsx`（详情页）、`src/components/TagTreeSelector/`（标签树选择器）

---

## 内容字典（Content Dict）

**用途：** QConfig 驱动的动态字典系统，提供内容模块前端所有下拉选项、列配置、指标分组、建议字段、渲染元数据。

**核心能力：**
- QConfig JSON 热加载，修改配置即时生效，无需重启
- 8 个配置段：contentTypes、publishPlatforms、businessLines、sortOptions、suggestionFields、metricFilters、metricGroups、columns
- renderType 取值：text / tag / tagList / link / integer（千分位）/ decimal（两位小数）/ percent（×100 + %）

**关键文件：**
- `service/dict/ContentDictConfig.java` — 字典 POJO
- `service/dict/ContentDictService.java` — QConfig 热加载
- `web/ContentDictController.java` — `/api/content/dict` 端点

**API：** `GET /api/content/dict`

**文档：** [docs/20260515-content-dict/content-dict-example.md](../docs/20260515-content-dict/content-dict-example.md)

---

## 任务模块（Task Module）

**用途：** 通用任务管理模块，支持多种任务类型。核心场景是 AI 打标管线：按 content_base 逐条处理，经 `ContentMediaProcessor` 按内容类型分发到 `ContentAnalyzer`（视频/图文分析），最终回写到 `content_label` 表。

**核心接口与抽象类：**
- `TaskExecutor` — 执行器接口：`getName()` / `getType()` / `hasSubExecutor()` / `execute(TaskContext)` / `subExecute(SubTaskContext)`
- `AbstractTaskExecutor<P, D>` — 模板方法基类，提供类型安全的 `getParams()` / `getData()`，子类只需声明泛型参数 + 实现 execute/subExecute
- `AbstractSubTaskExecutor<P, D>` — 创建子任务的执行器基类（hasSubExecutor=true），结果自动包装 SubTaskResult 信封
- `AbstractSimpleExecutor<P, D>` — 不创建子任务的执行器基类
- `ContentAnalyzer` — 分析器接口：`supportedContentType()` / `analyze(context, base, videos, images, text)`，按内容类型扩展
- `LabelBackfillHandler` — 标签回写策略接口：`backfill(baseId, aiResult, taskId)`
- `MediaProcessor` — 媒体处理器接口：`process(SubTaskContext)`

**扩展点：**
- 新增执行器：实现 `TaskExecutor` 或继承 `AbstractTaskExecutor<P, D>`，声明为 Spring `@Component` 即可自动注册
- 新增内容类型分析：实现 `ContentAnalyzer` 接口，Spring 自动注入到 `ContentMediaProcessor` 的分发 Map
- 新增标签回写策略：实现 `LabelBackfillHandler`，在 QConfig 中配置即可切换

**关键模式：**
- **模板方法**：`AbstractTaskExecutor` 定义骨架（buildContext → execute/subExecute → completeSubTask），子类只实现业务逻辑
- **策略模式（Spring DI）**：`Map<String, ContentAnalyzer>` 按内容类型分发，`Map<String, LabelBackfillHandler>` 按 bean 名选择
- **快照配置**：创建任务时将 `ExecutorConfig` 序列化到 `task_params.executorSnapshot`，执行时优先使用快照而非实时 QConfig，确保任务与创建时配置一致
- **父子任务状态机**：Task（PENDING→RUNNING→SUCCESS/FAILED/CANCELLED）+ SubTask（PENDING→RUNNING→SUCCESS/FAILED/SKIPPED），子任务全部完成后自动完结父任务
- **Checkpoint/Resume**：Progress POJO 存储在 sub_task.progress JSON 字段，支持断点续跑
- **多数据源**：`convertToD()` 可重写处理不同输入格式

**关键文件：**
- `service/task/executor/TaskExecutor.java` — 执行器接口
- `service/task/executor/AbstractTaskExecutor.java` — 模板方法基类
- `service/task/executor/AbstractSubTaskExecutor.java` — 子任务执行器基类
- `service/task/executor/AbstractSimpleExecutor.java` — 简单执行器基类
- `service/task/executor/content/ContentTagExecutor.java` — AI 打标执行器
- `service/task/media/ContentMediaProcessor.java` — 媒体处理分发
- `service/task/media/ContentVideoPreprocessor.java` — 视频预处理（幂等）
- `service/task/media/analyzer/ContentAnalyzer.java` — 分析器接口
- `service/task/media/analyzer/VideoContentAnalyzer.java` — 短视频分析器
- `service/task/media/analyzer/ImageContentAnalyzer.java` — 图文帖分析器
- `service/task/label/LabelBackfillHandler.java` — 标签回写接口
- `service/task/label/DefaultLabelBackfillHandler.java` — 默认回写实现
- `service/task/helper/TaskCompletionHelper.java` — 子任务完成 + 父任务自动完结
- `infra/qconfig/TaskQConfig.java` — `task_executor_config.json` 热加载
- `domain/entity/task/Task.java`、`SubTask.java`、`TaskParamBO.java`、`TaskContext.java`、`SubTaskContext.java`
- `service/task/TaskService.java` + `SubTaskService.java`
- `web/TaskController.java`

**API：** `GET /api/executor/types|configs|datasources`（元数据查询）、`POST /api/task/create|cancel|retry|delete`、`GET /api/task/list|detail/{id}`、`GET /api/task/subtask/list|detail/{id}`

**表：** `task`、`sub_task`

**QConfig：** `task_executor_config.json`（执行器定义和参数）

---

## OSS 转存（OSS Transfer）

**用途：** 公网图片/视频 URL 转存到内部 OSS，含 SSRF 防护和文件校验。

**核心能力：** 下载到临时文件 → 校验文件类型/大小 → 上传 OSS → 清理临时文件。SSRF 黑名单过滤内网 IP。

**关键文件：**
- `service/oss/OssTransferService.java`
- `web/OssController.java`

**API：** `POST /api/oss/transfer`