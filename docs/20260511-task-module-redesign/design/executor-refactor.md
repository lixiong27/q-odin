# subExecute 重构：MediaProcessor 抽象设计

## 一、现状分析

### 1.1 当前问题

`TaggingExecutor.subExecute()` 目前是一个**单体 6 步骤流水线**，直接内联在 Executor 中：

```
subExecute()
  ├── ① 解析 params (TaggingParams)
  ├── ② 获取 videoUrl / title
  ├── ③ 创建临时目录
  ├── ④ downloadVideo()       ← 视频特有
  ├── ⑤ extractFrames()       ← 视频特有
  ├── ⑥ extractAudio()        ← 视频特有
  ├── ⑦ transcribeAudio()     ← 视频特有
  ├── ⑧ analyzeImages()       ← 通用（未来图文也需要）
  └── ⑨ completeSubTask()     ← 通用
```

**问题**：
- 视频处理全流程耦合在 Executor 中，无法复用
- 后续需要支持**图文类型**（无下载/抽帧/音频/ASR，直接分析图片），当前结构难以扩展
- 进度管理（getProgress/saveProgress）与业务逻辑混合
- 使用 `objectMapper` 而非 `JsonUtils`

### 1.2 未来数据类型

| 媒体类型 | 处理流程 | 复用组件 |
|---------|---------|---------|
| 视频 (video) | 下载 → 抽帧 → 音频 → ASR → 分析 → 完成 | 分析、完成 |
| 图文 (imageText) | 下载图片 → 分析 → 完成 | 分析、完成 |
| 后续更多类型 | ... | ... |

---

## 二、重构方案

### 2.1 架构设计

引入 `MediaProcessor` 接口层，将媒体处理从 Executor 中分离：

```
TaggingExecutor.execute()       ← 主执行不变：解析数据源 → 创建子任务
TaggingExecutor.subExecute()    ← 扁平化：判断媒体类型 → 委托 MediaProcessor

MediaProcessor (接口)
  ├── supports(String dataSourceType)   ← 是否支持该类型
  └── process(SubTaskContext)           ← 统一处理入口

VideoMediaProcessor (实现)
  ├── download → extractFrames → extractAudio → ASR → AI analyze → complete
  └── 持有 VideoUtil, AsrService, ImageUnderstandingService 等

ImageTextMediaProcessor (未来实现)
  ├── downloadImages → AI analyze → complete
  └── 复用 ImageUnderstandingService
```

### 2.2 复用逻辑抽取

**AbstractMediaProcessor**（可选抽象层）：
- `saveProgress(subTaskId, progress)` — 进度持久化
- `complete(context, result, startTime)` — 子任务完成 + 父任务统计更新
- `cleanup(tempDir)` — 临时目录清理

**分析服务复用**：`ImageUnderstandingService` 是视频和图文共用的组件，保持独立。

### 2.3 JsonUtils 迁移

`ObjectMapper` → `JsonUtils` 替换清单：

| 位置 | 原代码 | 新代码 |
|------|--------|--------|
| getProgress | `objectMapper.readValue(progress, TaggingProgress.class)` | `JsonUtils.jsonToObject(progress, TaggingProgress.class)` |
| saveProgress | `objectMapper.writeValueAsString(progress)` | `JsonUtils.toJson(progress)` |
| getConfigKeyFromTask | `objectMapper.readValue(taskParams, HashMap.class)` | `JsonUtils.stringToObjectMap(taskParams)` |
| safeWriteValue | `objectMapper.writeValueAsString(obj)` | `JsonUtils.toJson(obj)` |
| updateParentTaskStats | `objectMapper.writeValueAsString(stats)` | `JsonUtils.toJson(stats)` |

---

## 三、文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `service/task/media/MediaProcessor.java` | **新增** | 媒体处理器接口 |
| `service/task/media/AbstractMediaProcessor.java` | **新增** | 处理器抽象类（通用逻辑） |
| `service/task/media/VideoMediaProcessor.java` | **新增** | 视频处理器实现 |
| `TaggingExecutor.java` | **修改** | subExecute 委托给 MediaProcessor，ObjectMapper → JsonUtils |

### 3.1 MediaProcessor 接口

```java
public interface MediaProcessor {
    /** 是否支持该数据源类型 */
    boolean supports(String dataSourceType);

    /** 处理媒体 */
    void process(SubTaskContext context);
}
```

### 3.2 AbstractMediaProcessor 抽象类

提供通用能力：
- 进度管理（getProgress / saveProgress）
- 任务完成（completeSubTask + updateParentTaskStats）
- 临时目录清理

### 3.3 VideoMediaProcessor

从 TaggingExecutor 迁移：
- downloadVideo / downloadFromUrl
- extractFrames
- extractAudio
- transcribeAudio
- analyzeImages / buildPrompt

### 3.4 TaggingExecutor 变更

```java
@Resource
private List<MediaProcessor> mediaProcessors;  // Spring 自动注入所有处理器

@Override
public void subExecute(SubTaskContext context) {
    // 1. 解析 params
    // 2. 获取 dataSourceType
    // 3. 查找匹配的 MediaProcessor
    // 4. 委托处理
}
```

---

## 四、数据处理统一抽象

### 4.1 数据一致性

无论 dataSource 是什么类型（demo、idList...），到达 `subExecute` 时 `subTaskParams` 中的业务数据格式是一致的：

```json
// demo 数据源创建的子任务 params
{ "videoUrl": "...", "title": "...", "configKey": "ai1" }

// idList 数据源创建的子任务 params（未来）
{ "videoUrl": "...", "title": "...", "configKey": "ai1" }
```

因此 `execute()` 中按 dataSource 类型解析 POJO，但 `subExecute()` 收到的数据是统一的。

### 4.2 MediaProcessor 工厂选择

由于 `supports()` 方法存在，无需独立的工厂类。Spring 自动注入 `List<MediaProcessor>`，在 `subExecute()` 中遍历找到匹配的处理器：

```java
MediaProcessor processor = mediaProcessors.stream()
    .filter(mp -> mp.supports(dataSourceType))
    .findFirst()
    .orElseThrow(() -> new IllegalArgumentException("不支持的媒体类型: " + dataSourceType));
```

---

## 五、实施计划

| 步骤 | 内容 | 文件 |
|------|------|------|
| 1 | 创建设计文档 | `executor-refactor.md` |
| 2 | 新建 `service/task/media/` 包 | `MediaProcessor.java`, `AbstractMediaProcessor.java`, `VideoMediaProcessor.java` |
| 3 | 从 TaggingExecutor 迁移视频逻辑到 VideoMediaProcessor | 6 步骤方法 |
| 4 | TaggingExecutor 改为委托模式 + JsonUtils 迁移 | `TaggingExecutor.java` |
| 5 | 编译验证 | `mvn compile` |