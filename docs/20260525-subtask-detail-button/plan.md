# 子任务操作栏新增"内容详情"按钮

## 需求

任务详情页的子任务列表，操作栏增加"内容详情"按钮，点击新标签页跳转至当前子任务关联的内容详情页。该按钮仅在执行器的 `bizContentIdSource = odinBaseContent` 时显示。

## 方案

后端子任务列表已返回 `SubTask.executor`（Spring Bean 名），前端可通过新增的通用接口获取全量执行器配置，按 `executorName` 匹配后判断 `bizContentIdSource`。

## 改动文件

### 后端

| 文件 | 改动 |
|------|------|
| `ExecutorConfig.java` | 新增字段 `bizContentIdSource` |
| `TaskController.java` | 新增 `GET /api/executor/config` 返回全部配置 |

#### ExecutorConfig 新增字段

```java
/**
 * 业务内容 ID 来源标识
 * odinBaseContent — businessKey 指向内容中台 baseId，可跳转内容详情
 */
private String bizContentIdSource;
```

#### 新增接口

```
GET /api/executor/config
→ BaseResponse<Map<String, ExecutorConfig>>
```

返回 `task_executor_config.json` 全量配置，前端按 `executorName` 索引。

### 前端

| 文件 | 改动 |
|------|------|
| `src/api/task.js` | 新增 `getExecutorConfig()` API |
| `src/pages/task/detail/index.js` | 加载配置 → 操作栏条件渲染"内容详情"按钮 |

#### 逻辑流程

1. `useEffect` 加载全部执行器配置，构建 `executorName → ExecutorConfig` 映射
2. 操作栏渲染时：`executorConfigMap[record.executor]?.bizContentIdSource === 'odinBaseContent'` → 展示按钮
3. 按钮点击：`window.open('/content/detail?baseId=' + record.businessKey)` 新标签页打开

#### task_executor_config.json 配置示例

```json
{
  "contentTag_config": {
    "type": "aiTag",
    "executorName": "ContentTagExecutor",
    "desc": "内容标签标注",
    "bizContentIdSource": "odinBaseContent",
    ...
  }
}
```

## 不做的事

- 不改子任务列表接口：`SubTask.executor` 已返回 executorName，可直接匹配
- 不改子任务实体：`businessKey` 即 baseId

## 验证

1. 在 QConfig `task_executor_config.json` 中为 ContentTagExecutor 设置 `bizContentIdSource: "odinBaseContent"`
2. 打开含 contentTag 子任务的任务详情页，验证"内容详情"按钮出现
3. 点击按钮，验证新标签页打开正确的 `/content/detail?baseId=xxx`
4. 验证未设置 `bizContentIdSource` 的执行器不显示该按钮