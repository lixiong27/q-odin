# 素材库实现 — 2026/06/09 ~ 06/12

> 对应设计文档：[20260527-material-library](../20260527-material-library/design.md)

## 概述

基于 5 月 27 日的设计，完成了素材库一期完整实现。涵盖**抓取管道接入**、**回调数据处理**、**ES 搜索**、**前端页面**四条链路。

---

## 后端（odin_server）— 分支 `20260609-build_library-FD-414958`

### 贡献者：zhaojia.xu

| 日期 | Commit | 内容 |
|------|--------|------|
| 06/09 | `c2027b6` | **抓取内容接口 & QMQ 回调接入** — 定义回调 DTO、任务类型枚举、三种请求/响应类、HTTP Client `CrawlContentTaskClient`，各 profile 配置回调 topic |
| 06/09 | `a88b3df` | **命名修正** — `CrawlContent*` → `Crawl*`，去冗余中缀 |
| 06/11 | `cea7363` | **回调处理框架 + 任务下发** — 策略模式 `CrawlTaskResultHandler` + 模板方法 `AbstractCrawlTaskResultHandler` + `CrawlTaskResultProcessor` 分发器；抖音 7 个自定义 DTO 和 6 个反序列化器处理非标准 JSON；小红书大搜/详情双模式解析；`MaterialCrawlExecutor` 按搜索词拆分子任务、子任务按类型下发 |
| 06/11 | `3ee1ffb` | **优化抓取调用** — 删除 `CrawlBigSearchTaskRequest`，统一用 `CrawlTaskRequest` 携带类型字段；简化 `MaterialCrawlExecutor` 调用链路 |

### 贡献者：qixiong.li (AI 辅助)

| 日期 | Commit | 内容 |
|------|--------|------|
| 06/11 | `042d8e4` | **回调数据持久化 + ES 搜索 + 前端 API** — 3 张表（`material_base`/`material_metrics`/`material_video`）的 Mapper 和实体；`MaterialProcessService` 含 URL 可用性检测、OSS 上传、事务落库、视频分集处理、自动打标；`MaterialSearchSyncService` 同步到 ES；`MaterialSearchService` 提供标题模糊搜索、多标签 AND/OR 过滤、指标排序、分页；`MaterialSearchController` 暴露 `POST /search`、`GET /detail/{id}`、`GET /dict` |
| 06/11 | `8cc88cc` | 素材 ES 索引名称接入 QConfig 动态配置 |
| 06/12 | `fd496f3` | 各 profile 的 `mq.properties` 添加回调 topic 配置（`push_content_crawl_mkt_odin_res_topic`） |

**后端新增/修改：67 个文件，+5,561 / -4 行**

---

## 前端（odin_node）— master 分支

| 日期 | Commit | 内容 |
|------|--------|------|
| 06/11 | `e5a4b42` | **素材库前端** — 列表页 8 维筛选（标题/时长/分辨率/帧率/日期/宽高比/点赞数/收藏数）、列配置弹窗（localStorage 持久化）、详情页（视频播放器 + 指标卡片 + AI 标签 + OSS 预览下载） |

**前端新增：6 个文件，+708 行**

---

## 架构总览

```
素材抓取平台 (外部)
     │ QMQ 回调 push_content_crawl_mkt_odin_res_topic
     ▼
CrawlTaskResultConsumer         ← 消费 QMQ 消息
     │
     ▼
CrawlTaskResultProcessor        ← 按 source 分发（策略模式）
     ├── DouyinCrawlTaskResultHandler  ← 抖音：自定义反序列化器
     └── XhsCrawlTaskResultHandler     ← 小红书：大搜+详情双模式
     │
     ▼
MaterialProcessService          ← 解析、URL 检测、OSS 转存、事务落库
     ├── MaterialBaseMapper         → material_base 表
     ├── MaterialMetricsMapper      → material_metrics 表
     └── MaterialVideoMapper        → material_video 表
     │
     ▼
MaterialSearchSyncService       ← 同步到 ES
     │
     ▼
MaterialSearchService           ← 标题搜索 + 标签过滤 + 指标排序 + 分页
     │
     ▼
MaterialSearchController        ← REST API (/api/material/*)
     │
     ▼
前端 (List + Detail)            ← 8 维筛选 + 列配置 + 详情预览
```

## 关键设计决策

1. **抓取管道方向**: zhaojia.xu 负责上游（抓取协议/HTTP 调用/QMQ 回调/任务下发），qixiong.li 负责下游（结果落地/ES 搜索/API/前端），在 `DouyinCrawlTaskResultHandler`/`XhsCrawlTaskResultHandler` 中通过调用 `MaterialProcessService` 完成衔接
2. **抖音 JSON 处理**: 抖音回调数据结构不规则，通过 6 个自定义 Jackson 反序列化器处理复杂的嵌套可空字段
3. **搜索方案**: 使用独立 ES 索引 `material_search`，索引名通过 QConfig 动态配置
4. **持久化**: 4 张表（含子任务关联），视频支持分集多行写入，URL 入库前做可用性检测

## 待完成

- [ ] 抓取链路端到端联调（QMQ topic 已配置，需验证回调通路）
- [ ] 素材标签体系复用已有 tag 模块 vs 独立管理
- [ ] 素材导出/打包（复用 ContentDownloadService）
- [ ] AI 画面干净度评估的接入
- [ ] 前端代码 → odin_node 子仓库 master 已合并，外部仓库需更新 submodule 引用

## SQL 变更

`docs/sql/full_schema.sql` 已包含新增的三张表结构（`material_base`、`material_metrics`、`material_video`）。