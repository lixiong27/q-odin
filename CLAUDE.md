# CLAUDE.md

## 项目概述

内容中台（ODIN）- 支持 Query 词管理、内容生成、GEO 分析、多渠道发布。

**工程上下文导航**: [infra.md](infra.md) - 快速了解项目能力，避免重复造轮子

## 工作流程

```
确认开发目录 → 读取 progress.md → 确认当前阶段 → 执行任务 → 更新 progress.md
```

**第一步：确认开发目录**

查看 `docs/` 下有哪些开发需求文件夹，向用户确认当前开发哪个。

**第二步：读取进度文件**

```
docs/{需求目录}/progress.md
```

该文件记录：
- 当前所处阶段
- 已完成/待完成任务
- 下一步行动

**第三步：确认任务**

读取 progress.md 后，向用户确认要执行的任务，用户确认后再开始开发。

**第四步：更新进度**

任务完成后，更新 progress.md 中对应任务状态。

**新需求初始化**

创建新需求时，复制模板创建 progress.md：
```
cp docs/progress-template.md docs/{需求目录}/progress.md
```
模板路径：`docs/progress-template.md`

## 需求结构

**目录命名规范：** `yyyyMMdd-需求名称`，例如 `20260423-odin-init`

```
docs/{yyyyMMdd-需求目录}/
├── design/           # 模块设计文档
├── tech-spec/        # 技术方案
├── test/             # 测试用例
│   ├── backend-api-test.md      # 后端接口测试用例
│   └── frontend-page-test.md    # 前端页面测试用例
└── progress.md       # 进度追踪
```

## 技术栈

**后端：** Java 8 + Spring Boot 2.6.6 + MyBatis + QConfig + QSchedule + JdbcTemplate

**前端：** Node 12.16.1 + React 16 + Ant Design 4.x + UmiJS 3.x

## Git 提交规范

**仓库结构：**
- 外部仓库: `q-odin/`
- 后端仓库: `odin_server/`
- 前端仓库: `odin_node/`

**提交规则：**
- 类型：build、chore、ci、docs、feat、fix、perf、refactor、revert、style、test
- 格式：`<type>: AI <subject>`
- 标题使用英文

**提交流程：**
1. 小节点完成 → 子仓库内提交
2. 阶段完成 → 外部仓库提交（记录子仓库变更）

**命令分开执行：** 先 `git add` 再 `git commit`
