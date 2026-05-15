# 工程上下文导航

## 技术组件

| 组件 | 说明 | 文档 |
|------|------|------|
| 代码规范 | 响应对象、请求对象、Controller 模式、包结构 | [tec-coding-style.md](infra/tec-coding-style.md) |
| QConfig | 动态配置中心（properties + JSON） | [tec-components.md](infra/tec-components.md#1-qconfig-动态配置) |
| QSchedule | 定时任务调度 | [tec-components.md](infra/tec-components.md#2-qschedule-定时任务) |
| Redis | 缓存、分布式锁、同步断点 | [tec-redis.md](infra/tec-redis.md) |
| MyBatis | ORM 框架 | [tec-components.md](infra/tec-components.md#4-mybatis-mapper) |
| JsonUtils | Jackson 封装（FAIL_ON_UNKNOWN_PROPERTIES=false） | [tec-components.md](infra/tec-components.md#5-jsonutils-工具类) |
| HttpUtils | HTTP 客户端（QunarAsyncClient） | [tec-components.md](infra/tec-components.md#8-httputils-http客户端) |
| Elasticsearch | 搜索引擎 7.10.2 | [tec-components.md](infra/tec-components.md#7-elasticsearch) |
| OSS | 对象存储（qunar-oss-sdk） | [tec-components.md](infra/tec-components.md#9-oss-对象存储) |
| QMonitor | 监控打点 | [tec-components.md](infra/tec-components.md#6-qmonitor-监控) |

## 业务模块

各业务模块的详细说明（核心能力、关键文件、API、设计模式）见 [biz-modules.md](infra/biz-modules.md)。

| 模块 | 用途 | 关键入口 |
|------|------|---------|
| 标签管理 | 标签分类 + 叶子标签 CRUD，多级树形结构 | `TagCategoryController`、`TagLeafController` |
| 原始内容同步 | 数仓宽表 → 6 张标准化业务表，QSchedule 定时同步 | `RawContentSyncService`、`RawContentSyncTask` |
| ES 内容搜索 | 6 表索引到 ES，搜索/筛选/排序/分页 + 修复对账 | `ContentSearchService`、`ContentSearchIndexService` |
| 内容检索 | 内容库前端检索服务，Orchestrator 编排 + 字典驱动渲染 | `SearchOrchestrator`、`ContentResponseAssembler` |
| 内容字典 | QConfig JSON 热加载，前端枚举/列配置/指标分组动态渲染 | `ContentDictService`、`/api/content/dict` |
| 任务模块 | 通用任务管理，AI 打标管线，模板方法 + 策略模式扩展 | `AbstractTaskExecutor<P,D>`、`ContentAnalyzer` 接口 |
| OSS 转存 | 公网 URL 转存内部 OSS，SSRF 防护 | `OssTransferService` |

---

## 基础设施全景

```
QConfig（配置中心）
├── raw_content.properties          — 同步批大小、启停、测试模式、并发数
├── es-index.properties             — ES 分片数、副本数、修复/同步启停
├── content_dict.json               — 前端字典配置（JSON 热加载）
├── task_executor_config.json       — 执行器定义和参数
├── hotfile.properties              — ES 连接、OSS 配置、通用键值
└── 各模块 QConfig 类               — RawContentQConfig, IndexQConfig, AigcQConfig 等

QSchedule（定时任务）
├── mkt_odin_raw_content_sync       — 原始内容同步（5min）
├── mkt_odin_es_repair              — ES 不完整文档修复（30min）
├── mkt_odin_es_reconcile           — ES/MySQL 对账（hourly）
├── mkt_odin_es_full_rebuild        — ES 全量重建（手动）
└── 各执行器 QSchedule 任务         — 任务模块子任务调度

Redis（qclient-redis）
├── odin:common:*                   — 通用缓存
└── odin:raw_content:*              — 同步断点记录

Elasticsearch 7.10.2
├── ElasticsearchDataSource         — 通用操作封装
├── ContentSearchDocument           — 内容搜索文档模型
└── 索引: odin_content_*            — 按日期分片

OSS（qunar-oss-sdk）
└── OssTransferService              — URL 转存 + SSRF 防护

MySQL + MyBatis
├── raw_content_info                — 数仓宽表（40 字段）
├── content_base                    — 标准化基础表（content_relations JSON）
├── content_text/image/video        — 内容详情表
├── content_metrics                 — 指标表（1:1）
├── content_label                   — AI 标签表（1:1）
├── tag_category / tag_leaf         — 标签分类树
└── task / sub_task                 — 任务状态机
```

## 新业务接入快速定位

| 场景            | 已有能力        | 接入方式                                                                                                                                                                       |
| ------------- | ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 新增 CRUD 接口    | 标签管理        | 参考 [biz-modules.md](infra/biz-modules.md#标签管理tag-module) + [tec-coding-style.md](infra/tec-coding-style.md)                                                                |
| 新增 QConfig 配置 | 内容字典、原始内容同步 | properties 用 `@QConfig("xxx.properties")` + `Map` 回调；JSON 用 `@QConfig("xxx.json")` + `JsonUtils.jsonToObject()`，参考 [biz-modules.md](infra/biz-modules.md#内容字典content-dict) |
| 新增定时任务        | 原始内容同步      | `@QSchedule("task_name")` + `TaskHolder.getKeeper()`，参考 [tec-components.md](infra/tec-components.md#2-qschedule-定时任务)                                                      |
| 新增 ES 索引      | ES 内容搜索     | `ElasticsearchDataSource` 通用操作封装，参考 [biz-modules.md](infra/biz-modules.md#es-内容搜索es-content-search)                                                                        |
| 新增 AI 处理管线    | 任务模块        | 继承 `AbstractTaskExecutor<P, D>` 实现 execute/subExecute，Spring 自动注册，参考 [biz-modules.md](infra/biz-modules.md#任务模块task-module)                                                |
| 新增内容类型分析      | 任务模块        | 实现 `ContentAnalyzer` 接口，Spring 自动注入到分发 Map                                                                                                                                 |
| 新增标签回写策略      | 任务模块        | 实现 `LabelBackfillHandler` 接口，QConfig 配置切换                                                                                                                                  |
| 新增前端字典驱动页面    | 内容检索        | `getContentDict()` + `dict?.xxx` 替换硬编码，参考 [biz-modules.md](infra/biz-modules.md#内容检索content-retrieval)                                                                     |
| 新增 OSS 转存     | OSS 转存      | `OssTransferService.transfer(url)`，含 SSRF 防护                                                                                                                               |
| 新增 Redis 缓存   | 原始内容同步      | `RedisAsyncClient` + `odin:module:xxx` 命名，参考 [tec-redis.md](infra/tec-redis.md)                                                                                            |
| 新增 HTTP 调用    | AI 服务       | `HttpUtils.postHttp()`，超时时间走 QConfig 配置，参考 [tec-components.md](infra/tec-components.md#8-httputils-http客户端)                                                                |
| 新增监控打点        | 全模块         | `QMonitor.recordOne("metric_name")`，参考 [tec-components.md](infra/tec-components.md#6-qmonitor-监控)                                                                          |