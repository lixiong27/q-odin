# 内容检索模块 — 开发进度

## 项目概述

**项目名称：** 内容检索模块（Content Retrieval）
**设计文档：** [design.md](design/design.md)

---

## 开发阶段

### 阶段一：设计文档

| 任务 | 状态 | 说明 |
|------|------|------|
| 设计文档初版 | ✅ 已完成 | 完整设计文档，含架构、接口、数据流 |
| 代码验证（设计 vs 实现差距分析） | ✅ 已完成 | 验证 EsDoc_Column_List、ContentSearchRequest 等 9 项差距 |
| 设计文档修正 | ✅ 已完成 | 确认 content_title/publish_url 不在 ES 索引，DataAggregator 回查 MySQL |
| 进度文档 | ✅ 已完成 | 本文件 |

### 阶段二：P0 代码修正

| 任务 | 状态 | 说明 |
|------|------|------|
| ContentSearchRequest 新增 5 个字段 | ✅ 已完成 | contentSource、productionTeam、operationProject、placementPosition、poi |
| ContentBaseMapper 新增单表查询/计数 | ✅ 已完成 | selectIdsByFilter / countByFilter |
| ContentTextMapper 新增 selectBatchByIds | ✅ 已完成 | 下载打包依赖（已有，无需新增） |
| ContentImageMapper 新增 selectBatchByIds | ✅ 已完成 | 下载打包依赖（已有，无需新增） |
| ContentVideoMapper 新增 selectBatchByIds | ✅ 已完成 | 下载打包依赖（已有，无需新增） |
| DataAggregator 回查 content_base 补标题/链接 | ✅ 已完成 | ContentDataAggregator.java |

### 阶段三：P1 代码修正

| 任务 | 状态 | 说明 |
|------|------|------|
| Controller 改为 BaseResponse 包装 | ✅ 已完成 | ContentSearchController.java 已使用 BaseResponse<T> |
| 新增 ESSearchService 用 filter() 替代 must() | ✅ 已完成 | ESSearchServiceImpl.java |

### 阶段四：检索模块核心开发

| 任务 | 状态 | 说明 |
|------|------|------|
| retrieve 包结构搭建 | ✅ 已完成 | controller / service / filter / config 完整结构 |
| ValidationFilter | ✅ 已完成 | ContentRetrieveValidationFilter（参数校验 + 方法校验） |
| ContentTrackService（埋点） | ✅ 已完成 | 异步记录用户行为，独立线程池 |
| SearchRouter（路由决策） | ✅ 已完成 | MySQL vs ES 路由 |
| SearchOrchestrator（编排核心） | ✅ 已完成 | track → route → aggregate → security → response |
| ContentDataAggregator（数据聚合） | ✅ 已完成 | 聚合 ES/MySQL 结果 + 回查 title/url |
| ContentSecurityFilter（安全过滤） | ✅ 已完成 | URL 安全校验 |
| ContentResponseAssembler（响应组装） | ✅ 已完成 | 组装最终响应 + fieldMeta |

### 阶段五：内容下载打包（ContentDownload）

| 任务 | 状态 | 说明 |
|------|------|------|
| ContentDownloadService | ✅ 已完成 | 下载打包核心逻辑 |
| DownloadController | ✅ 已完成 | 下载端点 |
| DownloadSecurityFilter | ✅ 已完成 | 内网域名校验 |
| InternalDomainConfig | ✅ 已完成 | QConfig 内网域名配置 |
| DownloadResult | ✅ 已完成 | 下载结果 DTO |
| WebFilterConfig | ✅ 已完成 | Filter 注册配置 |

### 阶段六：联调测试

| 任务 | 状态 | 说明 |
|------|------|------|
| 单元测试 | ❌ 待开始 | - |
| 集成测试 | ❌ 待开始 | - |
| 功能验证 | ❌ 待开始 | - |

---

## 当前进度

**当前阶段：** 阶段四/五 - 核心开发 ✅

**已完成：**
- 内容检索模块设计文档定稿
- 代码验证（EsDoc_Column_List、ContentSearchRequest、EsDocResultMap 等 9 项差距分析）
- 确认 content_title/publish_url 归属：ES 不存，DataAggregator 回查 MySQL
- 确认完整 P0/P1/P2 改动清单
- **P0 代码修正全部完成**（ContentSearchRequest 字段补充、Mapper 查询方法、DataAggregator）
- **P1 代码修正全部完成**（Controller 包装、ESSearchService）
- **检索模块核心开发全部完成**（12 个文件：Orchestrator、Router、Aggregator、Security、Track、Assembler、Controller、ValidationFilter、Config）
- **内容下载打包全部完成**（5 个文件：DownloadService、Controller、SecurityFilter、DomainConfig、DownloadResult + WebFilterConfig）

**已完成：**
- 内容库列表页（搜索、筛选、排序、分页、自定义列、预设、高级筛选）
- 内容详情页（基本信息、内容预览、标签编辑、数据指标）
- **TagTreeSelector 组件** — 动态标签树选择器，替代硬编码 AI_TAG_OPTIONS
- **后端字典系统** — ContentDictConfig + ContentDictService(QConfig) + /api/content/dict 端点
- **ContentResponseAssembler 重构** — 静态 FIELD_META 替换为字典驱动
- **list.jsx 字典集成** — 所有硬编码常量替换为 dict 驱动（内容类型、平台、业务线、排序、指标筛选、列配置、建议字段 AutoComplete）
- **detail.jsx 字典集成** — FIELD_LABEL/METRIC_GROUPS 替换为 dict 驱动，AI标签编辑改用 TagTreeSelector

**待开始：**
- 联调测试

**下一步：** 联调测试

---

## 技术栈

### 后端
- Java 8
- Spring Boot 2.6.6
- MyBatis 3.x
- QConfig（配置中心）
- QSchedule（定时任务）

### 前端
- Node.js 12.16.1
- React 16.14.0
- Ant Design 4.x
- UmiJS 3.x

---

## 关键约定

### 接口规范
- 统一前缀：`/api`
- 统一响应格式：`{ code: 0, message: "success", data: {} }`

### 架构原则
- ES 索引只存搜索字段，展示字段由 DataAggregator 回查 MySQL content_base 补全
- 路由层单向下游依赖：Router → Service → Mapper，不产生循环依赖
- 埋点异步执行，失败不阻塞主流程