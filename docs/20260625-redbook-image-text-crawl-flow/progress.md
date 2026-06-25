# 小红书图文帖抓取 & 素材入库 - 开发进度

## 项目概述

**项目名称**：小红书图文帖抓取 & 素材入库

新增小红书图文帖抓取链路，支持关键词搜索图文帖列表 → 获取 noteId → 查询图文帖详情 + 作者信息 → 持久化入库。

---

## 开发阶段

### 阶段一：设计文档

| 任务 | 状态 | 说明 |
|------|------|------|
| 设计文档 | ✅ 已完成 | design.md — 全流程、架构图、表设计、改造清单 |

### 阶段二：基础框架

| 任务 | 状态 | 说明 |
|------|------|------|
| CrawlRedbookPostList | ✅ 已完成 | MaterialCrawlExecutor 子类，重写 getName() |
| CrawlRedBookPostDetail | ✅ 已完成 | MaterialCrawlExecutor 子类，重写 getName() |
| 回调分发按 executor 重构 | ❌ 待开始 | AbstractCrawlTaskResultHandler 改造 |
| 新增回调 DTO 字段 | ❌ 待开始 | 图文帖特有字段扩展 |

### 阶段三：回调处理

| 任务 | 状态 | 说明 |
|------|------|------|
| List 页回调逻辑 | ❌ 待开始 | 创建 author + detail 子任务 |
| Detail 页回调逻辑 | ❌ 待开始 | 解析 + 落库 |
| Author 去重逻辑 | ❌ 待开始 | 条件判断，配置化 |

### 阶段四：持久化

| 任务 | 状态 | 说明 |
|------|------|------|
| 建表（redbook_note_post） | ❌ 待开始 | DDL |
| 建表（redbook_author_info） | ❌ 待开始 | DDL |
| Entity / Mapper / Service | ❌ 待开始 | 基础 CRUD |
| MaterialProcessTask 重写 | ❌ 待开始 | executor 分发 |
| MaterialProcessStrategy 适配 | ❌ 待开始 | supports 加 executorName 参数 |

### 阶段五：完成 & 后处理

| 任务 | 状态 | 说明 |
|------|------|------|
| TaskCompletionService 扩展 | ❌ 待开始 | executor 维度的特殊逻辑 |
| postProcess 逻辑 | ❌ 待开始 | 过滤子任务、回调下游 |
| 全链路联调 | ❌ 待开始 | 端到端验证 |

---

## 当前进度

**当前阶段：** 阶段一 - 设计文档

**已完成：**
- [x] 设计文档（design.md）：全流程、架构图、表设计、组件清单、改造范围

**待开始：**
- 阶段二 ~ 阶段五开发

**下一步：** 阶段二 - 基础框架开发

---

## 技术栈

### 后端
- Java 17
- Spring Boot 2.6.6
- MyBatis 3.x
- QConfig（配置中心）
- QSchedule（定时任务）
- QMQ（消息消费）
- MaterialCrawlExecutor 体系
