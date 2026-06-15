# 最近三次代码改动分析（后端）

> 分析日期：2026-06-11
> 分析范围：odin_server，2026-06-09 ～ 2026-06-11

---

## 目录

1. [改动一：抓取内容接口实现 & QMQ 回调接入](#改动一抓取内容接口实现--qmq-回调接入)
2. [改动二：抓取功能命名重构](#改动二抓取功能命名重构)
3. [改动三：素材库 QMQ 回调 & 任务下发实现](#改动三素材库-qmq-回调--任务下发实现)
4. [三次改动的演进关系](#三次改动的演进关系)

---

## 改动一：抓取内容接口实现 & QMQ 回调接入

- **Commit**：`c2027b6`（2026-06-09 11:59）
- **消息**：feat: 抓取内容接口实现&qmq回调功能接入
- **规模**：13 个文件，633 行新增

### 改动内容

抓取功能的首次落地，实现了两个核心流程：

#### 流程一：任务下发（ODIN → 抓取调度系统）

```
MaterialCrawlExecutor
  → CrawlContentTaskClient.createBigSearchTask()  /  createDetailTask()
    → HTTP POST 到 crawl.content.task.url
      → CrawlContentTaskResponse (成功/失败)
```

| 文件 | 职责 |
|------|------|
| `CrawlContentBigSearchTaskRequest` | 关键词大搜请求参数（source / businessType / keyword / crawlCount / ...） |
| `CrawlContentDetailTaskRequest` | 帖子详情请求参数（source / noteId / xsecToken / ...） |
| `CrawlContentTaskRequest` | 通用任务请求参数（taskType / priority / expireAt / ext 扩展字段） |
| `CrawlContentTaskResponse` | 下发结果（code / msg / success / taskId / ext） |
| `CrawlContentTaskClient` | HTTP 客户端，validate → serialize → POST → parse 完整链路 |

#### 流程二：QMQ 回调消费（抓取调度系统 → ODIN）

```
CrawlTaskResultConsumer (@QmqConsumer)
  → message.getStringProperty("body") → JSON → CrawlTaskResultCallback
    → （后续处理由改动三补充）
```

| 文件 | 职责 |
|------|------|
| `CrawlTaskResultConsumer` | QMQ 消息消费者，提取 body → JSON 反序列化 |
| `CrawlTaskResultCallback` | 回调通用结构（taskId / source / failReason / data） |

#### 基础设施

| 文件 | 职责 |
|------|------|
| `CrawlTaskTypeEnum` | 抓取类型枚举：BIG_SEARCH / DETAIL |
| `pom.xml` | 新增 QMQ 依赖 |
| `mq.properties` × 4 环境 | 各环境 QMQ consumer 主题配置 |

### 关键设计决策

1. **回调 data 先用 String**：不确定下游 data 结构前，先保留原始字符串，后续按需反序列化
2. **Request 中保留 ext 扩展字段**：`LinkedHashMap` 类型，支持未来扩展无需改接口
3. **QMonitor 全链路埋点**：每个异常/失败路径都有 `QMonitor.recordOne()`，可监控

---

## 改动二：抓取功能命名重构

- **Commit**：`a88b3df`（2026-06-09 14:32）
- **消息**：refactor: 修正抓取功能命名问题
- **规模**：5 个文件 rename

### 改动内容

| 原名称 | 新名称 | 说明 |
|--------|--------|------|
| `CrawlContentBigSearchTaskRequest` | `CrawlBigSearchTaskRequest` | 去掉 Content |
| `CrawlContentDetailTaskRequest` | `CrawlDetailTaskRequest` | 去掉 Content |
| `CrawlContentTaskRequest` | `CrawlTaskRequest` | 去掉 Content |
| `CrawlContentTaskResponse` | `CrawlTaskResponse` | 去掉 Content |
| `CrawlContentTaskClient` | `CrawlTaskClient` | 去掉 Content |

连带变化：
- 内部字段 `crawlContentTaskUrl` → `crawlTaskUrl`
- 内部字段 `crawlContentTaskTimeout` → `crawlTaskTimeout`
- 所有 QMonitor 埋点 Key：`CrawlContentTaskClient_*` → `CrawlTaskClient_*`
- 所有 log 信息同步更新

### 原因

抓取功能不再只抓"内容"（Content），后续要支持素材库（Material）等多种来源，原命名域过窄。

### 对后续开发的启示

- 命名域要与功能边界匹配，初期宽命名可避免后续 rename
- QMonitor 埋点 + log 需要同步改名，漏改会导致监控断点

---

## 改动三：素材库 QMQ 回调 & 任务下发实现

- **Commit**：`cea7363`（2026-06-11 10:59）
- **消息**：feat: 素材库qmq回调功能实现&任务下发功能实现
- **规模**：29 个文件，3401 行新增，9 行修改

### 整体架构

```
┌──────────────────────────────────────────────────┐
│                   QMQ Message                      │
│             (CrawlTaskResultCallback)               │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│              CrawlTaskResultConsumer               │
│   @QmqConsumer 消费抓取结果回调消息                  │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│              CrawlTaskResultProcessor              │
│   1. resolveRunningSubTask — 校验子任务状态         │
│   2. findHandler — 按 source 查找处理器             │
│   3. buildContext — 从 subTaskParams 解析上下文      │
│      (crawlType / keyword)                         │
│   4. handler.handle(context)                       │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│          AbstractCrawlTaskResultHandler             │
│   Template Method 模式 — handle() 骨架流程：        │
│   1. 校验 context → 解析 crawlType                │
│   2. resolveParsedData() — 反序列化回调 data       │
│   3. 按 crawlType 分发：                           │
│      ├── handleDetail(context, parsedData)        │
│      └── handleBigSearch(context, parsedData)      │
└──────────────────┬───────────────────────────────┘
                   │
         ┌─────────┴──────────┐
         ▼                    ▼
┌──────────────────┐  ┌──────────────────┐
│ DouyinHandler    │  │ XhsHandler       │
│ source="douyin"  │  │ source="redbook" │
│ BIG_SEARCH → ✅  │  │ DETAIL → ✅      │
│ DETAIL → ❌ TODO │  │ BIG_SEARCH → ✅  │
└──────────────────┘  └──────────────────┘
```

### 核心设计模式：Template Method

`AbstractCrawlTaskResultHandler` 定义处理骨架，子类只覆写 3-4 个抽象方法：

| 方法 | 类型 | 职责 |
|------|------|------|
| `getSource()` | abstract | 声明支持的 source |
| `getParsedDataClass(crawlTaskType)` | 可选 override | 指定反序列化目标类型 |
| `handleDetail(context, parsedData)` | abstract | 处理详情回调 |
| `handleBigSearch(context, parsedData)` | abstract | 处理大搜回调 |

模板类自动处理：
- 上下文空值校验
- `callback.data` 按指定类型反序列化（支持 String → POJO 或 Object → POJO）
- 按 `crawlType` 分发到对应分支

### 回调数据反序列化体系

#### 通用回调 DTO

| 类 | 职责 |
|----|------|
| `CrawlTaskResultCallback` | data 从 `String` 改为 `Object`，由各 Handler 按需反序列化 |

#### 抖音 DTO

| 类 | 行数 | 说明 |
|----|------|------|
| `DouyinCrawlBigSearchTaskResultData` | 795 | 大搜 data 根结构，含分页信息 + BigSearchPage 列表 |
| `DouyinCrawlBigSearchTaskResultDataDeserializer` | 68 | 自定义反序列化（数据是数组字符串，需逐层解嵌套） |
| `DouyinMiscDownloadAddrs` | 47 | 下载地址信息 |
| `DouyinMiscDownloadAddrsDeserializer` | 30 | 自定义反序列化 |
| `DouyinUfqInfo` | 89 | UFQ 加密信息 |
| `DouyinUfqInfoDeserializer` | 30 | 自定义反序列化 |
| `DouyinVideoExtra` | 85 | 视频附加信息 |
| `DouyinVideoExtraDeserializer` | 62 | 自定义反序列化 |
| `DouyinVolumeInfo` | 118 | 音量信息 |
| `DouyinVolumeInfoDeserializer` | 30 | 自定义反序列化 |
| `DouyinVqsItem` | 43 | VQS 查询参数 |
| `DouyinVqsDeserializer` | 34 | 自定义反序列化 |

#### 小红书 DTO

| 类 | 行数 | 说明 |
|----|------|------|
| `XhsCrawlBigSearchTaskResultData` | 354 | 大搜回调 data |
| `XhsCrawlDetailTaskResultData` | 743 | 详情回调 data |

### 任务下发逻辑增强

改动一中的 `MaterialCrawlExecutor` 在这次提交中完成：

```
主任务 execute():
  1. 读取 searchKeywords + platformParams
  2. 笛卡尔积拆分子任务（每个 keyword × 每个 platform）
  3. 每批 100 条批量写入 sub_task
  4. 更新主任务子任务统计

子任务 subExecute():
  1. 解析 MaterialCrawlSubTaskParams
  2. 按 crawlType 构建请求参数
     → BIG_SEARCH: buildBigSearchRequest()
     → DETAIL: buildDetailRequest()
  3. 通过 CrawlTaskClient 下发
  4. 将进度快照写入 subTaskProgress
```

新增辅助类：

| 类 | 职责 |
|----|------|
| `ExecutorConfig` | QConfig 执行器配置模型 |
| `JoinerUtils` | 字符串拼接工具（逗号/分号/下划线等分隔符） |

### 与改动一的差异

| 维度 | 改动一（c2027b6） | 改动三（cea7363） |
|------|-------------------|-------------------|
| 回调处理 | 只有 Consumer | Consumer → Processor → Handler 完整链路 |
| DTO | 通用回调 + 请求参数 | 平台特定反序列化 DTO |
| Executor | 只有骨架类名 | 完整的 execute + subExecute |
| 进度追踪 | 无 | 每次下发写入 subTaskProgress |

### 当前 TODO 项

| 位置 | TODO |
|------|------|
| `DouyinCrawlTaskResultHandler.handleDetail()` | 抛出 `UnsupportedOperationException`，抖音详情处理未实现 |
| `DouyinCrawlTaskResultHandler.handleBigSearch()` | "获取到具体视频素材，子任务状态推进到完成" — 只有 log，未落地 |
| `XhsCrawlTaskResultHandler.handleDetail()` | "获取到具体视频素材，子任务状态推进到完成" — 只有 log，未落地 |
| `XhsCrawlTaskResultHandler.handleBigSearch()` | "获取详情的帖子 id + xsec_token，关闭当前子任务，派发查看详情页子任务" — 需要分派新子任务 |

---

## 三次改动的演进关系

```
c2027b6 (06-09 11:59)           a88b3df (06-09 14:32)          cea7363 (06-11 10:59)
┌─────────────────────┐         ┌─────────────────────┐        ┌─────────────────────┐
│ 抓取接口实现          │ ──rename──→ │ 命名重构             │ ──build──→ │ 素材库回调+下发      │
│                     │         │                     │        │                     │
│ CrawlContent*       │         │ CrawlTask*          │        │ MaterialCrawlExecutor│
│ CrawlTaskResultCons.│         │ (same files renamed)│        │ Handler 完整链路     │
│ 基础 Request/Resp.  │         │                     │        │ 平台特定 DTO         │
└─────────────────────┘         └─────────────────────┘        │ 进度快照             │
                                                                └─────────────────────┘
```

- **改动一** 搭建骨架：任务下发 HTTP 客户端 + QMQ 回调消费者入口
- **改动二** 修正命名：将 Content 限定去掉，为素材库铺路
- **改动三** 填充血肉：完整的回调处理链路（Processor → Handler）、平台特定 DTO、Executor 全流程

**当前状态**：素材抓取的"下发 → 回调"链路已跑通，但回调后的数据落地和子任务状态推进还是 TODO。任何需要素材抓取结果入库的新逻辑，都需要先补全这些 Handler。

### 新增逻辑的关键注意事项

1. **扩展新平台**：新增 `XxxCrawlTaskResultHandler extends AbstractCrawlTaskResultHandler`，实现 getSource / handleDetail / handleBigSearch 即可自动被 Processor 发现
2. **扩展新 crawlType**：`CrawlTaskTypeEnum` 加枚举 → AbstractCrawlTaskResultHandler 加分支持 → MaterialCrawlExecutor 加 dispatch / buildRequest 分支
3. **回调 data 反序列化**：如果新增平台返回结构特殊，需要编写自定义 Jackson Deserializer（参考抖音各 Deserializer 的写法）
4. **子任务状态推进**：所有 Handler 的 handleDetail / handleBigSearch 当前都未推进子任务状态，新逻辑需要依赖 `SubTaskService` 更新子任务到 SUCCESS/FAILED