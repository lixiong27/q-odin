# ES 索引加速查询 — 项目开发进度

## 项目概述

**项目名称**：ES 索引加速查询

**背景**：raw-content-sync 已将数仓数据同步到 6 张 MySQL 业务表，在此基础上构建 ES 索引实现内容检索加速。

---

## 开发阶段

### 阶段一：设计文档

| 任务 | 状态 | 说明 |
|------|------|------|
| 原始设计（origin-design） | ✅ 已完成 | ES mapping + 三种场景策略 + 异常方案 |
| Deepdive 设计（design.md） | ✅ 已完成 | 对齐 ES 7.10.2、QSchedule、QConfig、ElasticsearchDataSource |

### 阶段二：后端开发

| 任务 | 状态 | 说明 |
|------|------|------|
| ElasticsearchDataSource 增强 | ❌ 待开始 | 新增 update / bulkUpdate / search 方法 |
| ContentSearchDocument 实体 | ❌ 待开始 | ES 文档 POJO |
| ContentSearchDocAssembler | ❌ 待开始 | MySQL 6 表 JOIN 组装文档 |
| ContentSearchIndexService | ❌ 待开始 | ES 写入服务（首次索引/指标更新/标签更新） |
| ContentSearchService | ❌ 待开始 | ES 搜索查询服务 |
| IndexQConfig | ❌ 待开始 | 动态配置 |
| RawContentSyncServiceImpl 集成 | ❌ 待开始 | sync 成功后调用 ES 索引 |
| 搜索 API Controller | ❌ 待开始 | GET /api/content/search |

### 阶段三：定时任务

| 任务 | 状态 | 说明 |
|------|------|------|
| EsRepairTask | ❌ 待开始 | 不完整文档修复（每 30 分钟） |
| EsReconcileTask | ❌ 待开始 | 全量对账（每日凌晨） |
| EsFullRebuildTask | ❌ 待开始 | 全量重建（手动触发） |

### 阶段四：测试

| 任务 | 状态 | 说明 |
|------|------|------|
| 单元测试 | ❌ 待开始 | Service / Assembler 层 |
| 集成测试 | ❌ 待开始 | ES 写入 + 查询验证 |

---

## 当前进度

**当前阶段：** 阶段一 - 设计文档 ✅

**已完成：**
- origin-design.md：ES mapping、写入策略、异常方案
- design.md：deepdive，对齐工程模式（ES 7.10.2 HLRC、QSchedule、QConfig），新增查询 API、服务层设计、文件清单、监控指标

**待开始：**
- ElasticsearchDataSource 增强（update / bulkUpdate / search）
- 写入/查询/组装三组服务
- 定时修复/对账/重建任务
- 搜索 API 接入

**下一步：**
- 实现 ElasticsearchDataSource 增强
- 按文件清单逐步开发

---

## 技术栈

### 后端
- Java 8
- Spring Boot 2.6.6
- MyBatis 3.x
- QConfig（配置中心）
- QSchedule（定时任务）
- Elasticsearch 7.10.2（RestHighLevelClient）
- Gson（ES 层序列化）

---

## 关键约定

### 接口规范
- 统一前缀：`/api`
- 统一响应格式：`{ code: 0, message: "success", data: {} }`

### 本地开发
- 后端：IDEA Tomcat 部署，端口 8080
- ES 连接：通过 K8s 集群内地址（已有配置）