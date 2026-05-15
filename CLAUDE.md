# CLAUDE.md

## 项目概述

内容中台（ODIN）

**工程上下文导航**: [infra.md](infra.md) - 代码风格、技术组件使用指南

## 工作流程

确认开发目录 → 读取 progress.md → 执行任务 → 更新 progress.md

新需求初始化：`cp docs/progress-template.md docs/{yyyyMMdd-需求名称}/progress.md`

## 技术栈

**后端：** Java 8 + Spring Boot 2.6.6 + MyBatis + QConfig + QSchedule

**前端：** Node 12.16.1 + React 16 + Ant Design 4.x + UmiJS 3.x

## Git 提交规范

**仓库结构：**
- 外部仓库: `q-odin/`
- 后端仓库: `odin_server/`
- 前端仓库: `odin_node/`

**提交规则：**
- 格式：`<type>: AI <subject>`
- 类型：feat、fix、docs、refactor 等
- 标题使用英文

**提交流程：**
1. 小节点 → 子仓库提交
2. 阶段完成 → 外部仓库提交

**Git 命令要求：** 使用 `git -C <repo_path> <cmd>` 替代 `cd && git`

## 编码准则

### 1. 先思考再编码
- 明确假设，不确定就问
- 多种方案时呈现选项，不擅自决定
- 存在更简单方案时指出

### 2. 简单优先
- 只实现被要求的功能
- 单次使用不抽象
- 不添加未请求的灵活性/可配置性
- 200 行能写成 50 行就重写

### 3. 精准修改
- 只改必须改的
- 不重构无关代码，不改善邻近代码
- 匹配现有风格
- 改动产生的孤立代码需清理，预存的死代码不动

### 4. 目标驱动
- 将任务转化为可验证目标
- 多步骤任务先简述计划
- 定义成功标准，循环验证直到通过
