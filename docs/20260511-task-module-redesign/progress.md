# 任务模块重构开发进度

## 项目概述

**项目名称**：任务模块重构

**目标**：将原有的 ParentExecutor/ChildExecutor 父子执行器模式，重构为统一 TaskExecutor 接口 + QConfig JSON 配置管理

---

## 开发阶段

### 阶段一：设计文档

| 任务 | 状态 | 说明 |
|------|------|------|
| 设计文档 | ✅ 完成 | `design/design.md` 已输出 |

### 阶段二：后端开发

| 任务 | 状态 | 说明 |
|------|------|------|
| QConfig 配置类 (TaskQConfig) | ❌ 待开始 | `task_executor_config.json` JSON 配置 |
| TaskExecutor 接口 + 抽象类 | ❌ 待开始 | 统一执行器接口 |
| TaskContext / SubTaskContext | ❌ 待开始 | 上下文传递 |
| ExecutorFactory 改造 | ❌ 待开始 | 利用 Spring Map 注入 |
| TaskType 枚举重构 | ❌ 待开始 | type/executorName 分离 |
| TaggingExecutor 实现 | ✅ 完成 | AI打标执行器（含 subExecute 重构） |
| TaskScheduler 适配 | ❌ 待开始 | 适配新模型 |
| TaskController 新增接口 | ❌ 待开始 | executor/types, executor/datasources |
| TaskCreateRequest 调整 | ❌ 待开始 | dataSourceName + params |

### 阶段二-B：MediaProcessor 抽取（subExecute 重构）

| 任务 | 状态 | 说明 |
|------|------|------|
| 设计文档 | ✅ 完成 | `design/executor-refactor.md` |
| MediaProcessor 接口 | ✅ 完成 | `service/task/media/MediaProcessor.java` |
| AbstractMediaProcessor 抽象类 | ✅ 完成 | 进度管理 + 任务完成共用逻辑 |
| VideoMediaProcessor | ✅ 完成 | 视频 6 步骤流水线抽取 |
| TaggingExecutor 委托 + JsonUtils 迁移 | ✅ 完成 | subExecute 委托 + ObjectMapper → JsonUtils |
| AbstractTaskExecutor JsonUtils 迁移 | ✅ 完成 | 所有 objectMapper 替换为 JsonUtils |
| 编译验证 | ✅ 完成 | mvn compile 通过 |

### 阶段三：前端开发

| 任务 | 状态 | 说明 |
|------|------|------|
| 创建任务页适配 | ❌ 待开始 | 支持选择执行器类型、数据源 |
| 前端 API 适配 | ❌ 待开始 | 适配新接口 |

### 阶段四：联调测试

| 任务 | 状态 | 说明 |
|------|------|------|
| 后端编译验证 | ❌ 待开始 | mvn compile |
| 接口联调 | ❌ 待开始 | 任务创建/执行/查看 |

---

## 当前进度

**当前阶段：** 阶段一 - 设计文档（已完成）

**已完成：**
- 架构设计文档 `design/design.md`
  - params 类型从 `Map<String, Object>` 改为 `Object`
  - `getExtParamsClass()` / `parseExtParams()` 泛型继承机制
  - `extensionExample` → `dataSourceExample` 字段重命名
  - Type-Safe params 解析设计（如 TaggingParams POJO）
- 所有 `>` 注释已处理完毕

**待开始：**
- 后端编码（阶段二）

**下一步：**
- 确认设计文档后开始后端编码

---

## 设计要点

### 关键变更
- **统一 TaskExecutor**：废弃 ParentExecutor/ChildExecutor，统一接口
- **QConfig 配置**：`task.json` 管理所有 executor/dataSource 配置
- **type/executorName 分离**：TaskType 枚举只定义业务类型
- **灵活参数**：所有阶段使用 JSON params，不限定具体字段
- **配置快照落库**：创建任务时快照 ExecutorConfig 到 task_params.executorSnapshot，避免 QConfig 变更影响历史任务
- **dataSource 泛型继承**：AbstractTaskExecutor 提供 getExtDataClass() + parseExtData()，子类声明 POJO 类型安全访问用户数据

### 数据流
```
前端创建 → DB 初始化 → QSchedule 调度 → TaskExecutor.execute()
  → hasSubExecutor=true: 解析数据源 → 创建子任务 → subExecute()
  → hasSubExecutor=false: 直接执行业务
```