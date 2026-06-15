# CLAUDE.md

## 项目概述

内容中台（ODIN）

**工程上下文导航**: [infra.md](infra.md) - 代码风格、技术组件使用指南

## 权限

可以操作 `q-odin` 目录下的所有文件，不需要申请许可。

## 工作流程

确认开发目录 → 读取 progress.md → 执行任务 → 更新 progress.md

新需求初始化：`cp docs/progress-template.md docs/{yyyyMMdd-需求名称}/progress.md`

## 技术栈

**后端：** Java 17 + Spring Boot 2.6.6 + MyBatis + QConfig + QSchedule

**前端：** Node 12.16.1 + React 16 + Ant Design 4.x + UmiJS 3.x

