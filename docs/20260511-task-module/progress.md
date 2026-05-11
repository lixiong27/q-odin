# 项目开发进度

## 项目概述

**项目名称**：任务模块（Task Module）

**目标**：实现任务管理模块，支持多种任务类型，其中 AI 打标任务结合抽帧、大模型识图、音频提取完成完整的视频内容分析流程。

---

## 设计文档

- [architecture.md](design/architecture.md) - 架构设计（执行器与数据源分离）
- [prototype.html](design/prototype.html) - 前端原型（可直接在浏览器打开）
- [任务表设计.md](design/任务表设计.md) - 数据库表结构

---

## 核心设计：执行器与数据源分离

### 概念说明

```
Task (主任务)
    │
    ├── dataSource: 数据源配置（数据从哪来）
    │     ├── RAW_CONTENT: 原始内容表筛选
    │     ├── TAGGED_CONTENT: 已打标内容重新打标
    │     ├── ID_LIST: 指定ID列表（Demo数据）
    │     └── ES_QUERY: ES查询结果
    │
    └── executor: 执行器配置（怎么处理）
          ├── AI_TAGGING: 抽帧→识图→ASR→合并
          ├── DATA_STATISTICS: 数据统计
          └── REPORT_SUMMARY: 报告汇总
```

### task_params JSON 示例

```json
{
  "dataSource": {
    "type": "RAW_CONTENT",
    "filter": { "status": "pending" },
    "limit": 100
  },
  "executor": {
    "frameInterval": 5,
    "maxFrames": 10,
    "model": "gpt-4o",
    "enableAsr": true
  }
}
```

---

## 开发阶段

### 阶段一：设计文档

| 任务 | 状态 | 说明 |
|------|------|------|
| 数据库表设计 | ✅ 已完成 | task / sub_task 两张表 |
| 架构设计 | ✅ 已完成 | 执行器与数据源分离架构 |
| 接口设计 | ✅ 已完成 | 任务CRUD、子任务查询 |
| 前端原型 | ✅ 已完成 | HTML原型（3个页面） |
| Deep Dive | 🔄 进行中 | 与用户确认细节 |

### 阶段二：后端开发

| 任务 | 状态 | 说明 |
|------|------|------|
| Entity/Mapper/Service | ✅ 已完成 | Task/SubTask 基础 CRUD |
| 数据源解析器 | ✅ 已完成 | DataSourceResolver (ID_LIST, DEMO_DATA) |
| 执行器工厂 | ✅ 已完成 | ExecutorFactory (工厂模式) |
| AI 打标执行器 | ✅ 已完成 | TaggingParentExecutor / TaggingChildExecutor |
| 定时任务调度 | ✅ 已完成 | QSchedule 集成 |

### 阶段三：前端开发

| 任务 | 状态 | 说明 |
|------|------|------|
| 任务列表页面 | ✅ 已完成 | 任务查询、筛选 |
| 新建任务页面 | ✅ 已完成 | 向导式创建 |
| 任务详情页面 | ✅ 已完成 | 进度、子任务、结果 |

### 阶段四：联调测试

| 任务 | 状态 | 说明 |
|------|------|------|
| 接口联调 | ❌ 待开始 | - |
| AI 打标流程测试 | ❌ 待开始 | 端到端测试 |

---

## 当前进度

**当前阶段：** 阶段四 - 联调测试

**已完成：**
- 架构设计文档
- 前端 HTML 原型
- 后端完整实现
  - Entity/Mapper/Service 基础代码
  - 数据源解析器
  - 执行器框架
  - AI 打标执行器（断点续传）
  - QSchedule 定时调度
- 前端完整实现
  - API 封装
  - 任务列表页面
  - 新建任务页面（向导式）
  - 任务详情页面

**待完成：**
- 接口联调
- AI 打标流程端到端测试

**下一步：**
- 启动前后端服务进行联调测试
