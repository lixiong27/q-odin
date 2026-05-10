# CLAUDE.md

## 项目概述

内容中台（ODIN）

**工程上下文导航**: [infra.md](infra.md) - 代码风格、技术组件使用指南

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

## 编码准则

1. **先思考再编码** - 明确假设，多种方案呈现选项
2. **简单优先** - 只实现被要求的功能，不添加未请求的灵活性
3. **精准修改** - 只改必须改的，匹配现有风格
4. **目标驱动** - 定义成功标准，循环验证直到通过
