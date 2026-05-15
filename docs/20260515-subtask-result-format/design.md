# 子任务结构化结果格式设计

## 背景

当前子任务 `result` 字段存储的是原始 AI 响应字符串（非结构化），前端无法可靠解析展示。同时所有 Executor 共用 `AbstractTaskExecutor`，没有区分"有子任务"和"无子任务"的抽象层。

## 目标

1. 定义统一的结果信封 `SubTaskResult`，包含 `trace` / `params` / `result` 三层结构
2. 抽象 `AbstractSubTaskExecutor` / `AbstractSimpleExecutor` 分层
3. 各 Executor 定义具体结果 POJO，Processor 返回 POJO 而非直接调用 `completeSubTask()`

## 架构

### 类层次

```
TaskExecutor (interface)
  └── AbstractTaskExecutor<P, D> (不变)
        ├── AbstractSubTaskExecutor<P, D> (新增, hasSubExecutor=true)
        │     ├── ContentTagExecutor
        │     ├── TaggingExecutor (@Deprecated)
        │     └── MediaInfoExecutor (@Deprecated)
        └── AbstractSimpleExecutor<P, D> (新增, hasSubExecutor=false)
              └── (预留)
```

### 结果信封

```json
{
  "trace": "SUB_1715000000000_ABCD1234",
  "params": {"contentBaseId": 1001, "configKey": "xxx"},
  "result": {
    "contentType": "短视频",
    "contentTitle": "xxx",
    "aiResult": { ... }
  }
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `trace` | String | 子任务编码，用于追踪 |
| `params` | Map | 子任务参数快照 |
| `result` | Object | 具体结果 POJO，由各 Executor 定义 |

### 各 Executor 结果 POJO

| Executor | Result POJO | 字段 |
|----------|-------------|------|
| ContentTagExecutor | `ContentTagSubTaskResult` | contentType, contentTitle, aiResult |
| TaggingExecutor | `TaggingSubTaskResult` | title, aiResult |
| MediaInfoExecutor | `MediaInfoResult` (已有) | asrText, analysisResult |

## 数据流

### 重构前

```
Processor.process(context)
  → analyzer.analyze() 返回原始 String (AI 响应)
  → taskCompletionHelper.completeSubTask(context, rawString, startTime)
    → JsonUtils.toJson(rawString) → 带引号的字符串
    → subTask.setResult(resultJson) → 存入 DB
```

### 重构后

```
Executor.subExecute()
  → Processor.process() 返回 Result POJO
  → AbstractSubTaskExecutor.completeSubTask() 包装 SubTaskResult 信封
    → taskCompletionHelper.completeSubTask(context, envelope, startTime)
      → JsonUtils.toJson(envelope) → 结构化 JSON
      → subTask.setResult(resultJson) → 存入 DB
```

## 关键设计点

### 1. aiResult 序列化

AI 返回的 JSON 字符串需先解析为 `Map<String, Object>` 再设入 POJO，避免 `JsonUtils.toJson()` 产生双重转义：

```
原始: "{\"tags\":[\"景点\"]}"
  → JsonUtils.toJson(原始) → "\"{\\\"tags\\\":[\\\"景点\\\"]}\""  ❌ 双重转义

解析后: Map {"tags": ["景点"]}
  → JsonUtils.toJson(解析后) → "{\"tags\":[\"景点\"]}"  ✅ 正确嵌套
```

`ContentMediaProcessor.parseAiResult()` 和 `VideoMediaProcessor.parseAiResult()` 处理此逻辑。

### 2. 错误处理

Processor 不再 catch 异常，直接 throw，由 `AbstractTaskExecutor.subExecuteWithTracking()` 统一处理 `failSubTask()`。

### 3. 兼容性

`SubTaskResult` 信封是 additive 变更，DB 字段不变，旧数据仍可读。前端通过 `result.trace` / `result.params` / `result.result` 访问结构化字段。

## 文件清单

### 新建
| 文件 | 说明 |
|------|------|
| `domain/entity/task/SubTaskResult.java` | 结果信封 POJO |
| `service/task/executor/AbstractSubTaskExecutor.java` | 有子任务抽象基类 |
| `service/task/executor/AbstractSimpleExecutor.java` | 无子任务抽象基类 |
| `service/task/executor/content/ContentTagSubTaskResult.java` | ContentTag 结果 POJO |
| `service/task/executor/tag/TaggingSubTaskResult.java` | Tagging 结果 POJO |

### 修改
| 文件 | 变更 |
|------|------|
| `service/task/media/MediaProcessor.java` | process() 返回类型 void → Object |
| `service/task/media/ContentMediaProcessor.java` | 返回 ContentTagSubTaskResult，移除 completeSubTask() |
| `service/task/media/VideoMediaProcessor.java` | 返回 TaggingSubTaskResult，移除 completeSubTask() |
| `service/task/media/MediaInfoProcessor.java` | 返回 MediaInfoResult，移除 completeSubTask() |
| `service/task/executor/content/ContentTagExecutor.java` | 改继承 AbstractSubTaskExecutor，更新 subExecute() |
| `service/task/executor/tag/TaggingExecutor.java` | 改继承 AbstractSubTaskExecutor，更新 subExecute() |
| `service/task/executor/mediainfo/MediaInfoExecutor.java` | 改继承 AbstractSubTaskExecutor，更新 subExecute() |

## 前端消费

前端通过 `getSubTaskDetail(id)` 获取子任务详情，`result` 字段为 JSON 字符串：

```javascript
// 解析后结构
{
  trace: "SUB_xxx",
  params: { contentBaseId: 1001, configKey: "xxx" },
  result: {
    contentType: "短视频",
    contentTitle: "xxx",
    aiResult: { tags: [...], detail: {...} }
  }
}
```

前端 detail 页 Modal 中展示：
- Descriptions 区域：trace、params 摘要
- JSON 渲染区域：result.result 格式化展示