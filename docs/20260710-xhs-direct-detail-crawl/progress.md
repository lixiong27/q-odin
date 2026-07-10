## 项目概述

**项目名称**：小红书图文帖直接抓取 (DirectCrawl) + Excel 导出

**目标**：
1. 新增 DirectCrawl 抓取链路：外部传入 noteId 列表，直接下发 detail 爬取后落库，不走 bigSearch/userInfo
2. 新增 Excel 导出接口：传入 noteIdList，从 `redbook_note_post` 查全量数据返回 .xlsx

---

## 开发阶段

### 阶段一：设计文档 ✅

| 任务 | 状态 | 说明 |
|------|------|------|
| 设计文档 | ✅ 已完成 | design.md — 全流程、组件说明、数据流图 |
| Deep Dive | ✅ 已完成 | deepdive.md — 代码对照分析 |
| progress.md | ✅ 已完成 | 开发进度 |

### 阶段二：后端开发 — DirectCrawl

| 任务 | 状态 | 说明 |
|------|------|------|
| DirectCrawlExecutor | ❌ 待开始 | TaskExecutor，继承 MaterialCrawlExecutor |
| DirectCrawlHandler | ❌ 待开始 | 回调处理器，继承 RedbookExecutorHandler |
| HotPredictProcessStrategy.supports() | ❌ 待开始 | 新增 directCrawl |
| QConfig task_executor_config.json | ❌ 待开始 | 新增 hotpredict-redbook-direct-crawl |
| QConfig material.process.source | ❌ 待开始 | 追加 directCrawl |

### 阶段三：后端开发 — Excel 导出

| 任务 | 状态 | 说明 |
|------|------|------|
| RedbookNoteExportVO | ❌ 待开始 | 23 字段 Excel VO |
| RedbookNoteExportService | ❌ 待开始 | 查询 + EasyExcel 写入 |
| RedbookNoteExportController | ❌ 待开始 | GET /api/redbook/note/export |
| Mapper + XML SQL | ❌ 待开始 | selectByNoteIdList |

### 阶段四：联调测试

| 任务 | 状态 | 说明 |
|------|------|------|
| 编译验证 | ❌ 待开始 | mvn compile |
| 接口联调 | ❌ 待开始 | 端到端测试 |

---

## 当前进度

**当前阶段：** 阶段一 - 设计文档 ✅

**已完成：**
- [x] 设计文档（design.md）
- [x] Deep Dive 代码对照（deepdive.md）
- [x] 开发进度（progress.md）

**待开发：**
- DirectCrawlExecutor
- DirectCrawlHandler
- HotPredictProcessStrategy.supports()
- RedbookNoteExportVO + Service + Controller
- Mapper selectByNoteIdList
- QConfig 配置
- 全链路联调

**下一步：**
- 阶段二：后端代码开发