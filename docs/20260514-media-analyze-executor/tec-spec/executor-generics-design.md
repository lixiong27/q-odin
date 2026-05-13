# AbstractTaskExecutor 泛型化重构 — 技术方案

## 背景

当前 `AbstractTaskExecutor` 存在以下问题：

1. **结果用 Map 承接**：`completeSubTask` 将结果组装为 `Map<String, Object>`，类型不安全
2. **completeSubTask / updateParentTaskStats 在 AbstractMediaProcessor**：子任务完成和父任务统计属于通用流程，不属于媒体处理，应提升到 AbstractTaskExecutor
3. **多数据源类型未结构化映射**：一个 executor 可配置多个 dataSource type（如 `demo` + `mediaInfo`），但子任务 context 的 `params` 是 `Map<String, Object>`，缺乏类型约束
4. **params 和 dataSource 类型缺乏泛型约束**：子类通过 `getExtDataClass()` / `getExtParamsClass()` 返回 `Optional<Class<?>>`，使用时需强制转型
5. **Processor dispatch 过度设计**：executor 通过 `List<MediaProcessor>` 注入 + `supports/findFirst` runtime dispatch 选择 processor，但实际上每个 executor 只对应一个固定 processor，不需要 runtime dispatch

## 方案

### 核心思路

给 `AbstractTaskExecutor` 加两个泛型参数 `<P extends BaseTaskParams, D extends BaseTaskDataSource>`：
- **P** = ExecutorConfig.params 的具体 POJO 类型，必须继承 `BaseTaskParams`
- **D** = 数据源数据的具体 POJO 类型，必须继承 `BaseTaskDataSource`

基类可以是空类（无字段），仅作为类型约束的标记。子类具体 POJO 继承它们获得类型安全。

多数据源 type 场景下，通过模板方法 `convertToD` 将不同 type 的数据映射为统一的 D 类型。单 type 场景无需任何额外代码。

Processor 层去掉 `supports/findFirst` dispatch，executor 直接注入具体 processor。

### 基类定义

```java
/**
 * 执行器参数基类
 * 可以没有任何字段，仅作泛型类型约束
 * 子类按需添加具体参数字段
 */
public class BaseTaskParams {
}

/**
 * 数据源数据基类
 * 可以没有任何字段，仅作泛型类型约束
 * 子类按需添加具体数据字段
 */
public class BaseTaskDataSource {
}
```

继承示例：

```java
// MediaInfoParams — 继承基类，添加具体字段
public static class MediaInfoParams extends BaseTaskParams {
    private String asrProvider;
    private String asrFormat;
    private String prompt;
    // getter/setter...
}

// MediaInfoData — 继承基类，添加具体字段
public static class MediaInfoData extends BaseTaskDataSource {
    private List<MediaInfoItem> items;
    // getter/setter...
}

// 简单场景 — 无参数，直接用基类
class SimpleExecutor extends AbstractTaskExecutor<BaseTaskParams, BaseTaskDataSource> {
    // P 和 D 都是空基类，不需要额外字段
}
```

### 泛型定义

```java
public abstract class AbstractTaskExecutor<P extends BaseTaskParams, D extends BaseTaskDataSource> implements TaskExecutor {

    // P: params POJO（如 MediaInfoParams extends BaseTaskParams）
    // D: data POJO（如 MediaInfoData extends BaseTaskDataSource）
}
```

### 类结构变更

```
BaseTaskParams                                ← 新建，空基类，仅作类型约束
BaseTaskDataSource                            ← 新建，空基类，仅作类型约束

AbstractTaskExecutor<P extends BaseTaskParams, D extends BaseTaskDataSource>
├── buildContext()                            ← 保持不变
├── buildSubContext()                         ← 保持不变
├── parseExtData()                            ← 删除，泛型自动处理
├── parseExtParams()                          ← 删除，泛型自动处理
├── getExtDataClass()                         ← 删除，泛型替代
├── getExtParamsClass()                       ← 删除，泛型替代
├── initSubTask()                             ← 保持不变
├── completeSubTask(SubTaskContext, Object)   ← 委托 TaskCompletionHelper
├── updateParentTaskStats(Long)               ← 委托 TaskCompletionHelper
├── getParams(TaskContext) → P               ← 新增，类型安全的 params 获取
├── getData(TaskContext) → D                 ← 新增，类型安全的 data 获取
├── convertToD(Map, String) → D              ← 新增，模板方法，多 type 映射
├── getParamsClass() → Class<P>              ← 子类声明具体 Class
├── getDataClass() → Class<D>               ← 子类声明具体 Class
├── parseTaskParams()                         ← 保持不变
└── getConfigKeyFromTask()                    ← 保持不变

TaggingExecutor extends AbstractTaskExecutor<TaggingParams, DemoData>
  TaggingParams extends BaseTaskParams
  DemoData extends BaseTaskDataSource
  直接注入 VideoMediaProcessor（不再用 List<MediaProcessor> dispatch）

MediaInfoExecutor extends AbstractTaskExecutor<MediaInfoParams, MediaInfoData>
  MediaInfoParams extends BaseTaskParams
  MediaInfoData extends BaseTaskDataSource
  直接注入 MediaInfoProcessor（不再用 List<MediaProcessor> dispatch）
```

### 关键方法详细设计

#### 1. getParams — 类型安全获取 params

```java
protected P getParams(TaskContext context) {
    Object params = context.getExecutorConfig().getParams();
    if (params == null) {
        return null;
    }
    return JsonUtils.getObjectMapper().convertValue(params, getParamsClass());
}
```

由于 Java 泛型擦除，子类仍需声明一个方法返回具体 Class：

```java
// 父类
protected abstract Class<P> getParamsClass();
protected abstract Class<D> getDataClass();

// 子类
@Override
protected Class<MediaInfoParams> getParamsClass() { return MediaInfoParams.class; }
@Override
protected Class<MediaInfoData> getDataClass() { return MediaInfoData.class; }

// 无额外字段的简单场景
@Override
protected Class<BaseTaskParams> getParamsClass() { return BaseTaskParams.class; }
@Override
protected Class<BaseTaskDataSource> getDataClass() { return BaseTaskDataSource.class; }
```

这比原来的 `Optional<Class<?>>` + `parseExtData/parseExtParams` 更简洁，且类型安全。基类约束确保所有 P 和 D 都在同一个类型体系内。

#### 2. getData — 类型安全获取 data

```java
protected D getData(TaskContext context) {
    Map<String, Object> rawData = context.getData();
    if (rawData == null || rawData.isEmpty()) {
        return null;
    }
    String dataSourceType = context.getDataSource().get(0).getType();
    return convertToD(rawData, dataSourceType);
}
```

#### 3. convertToD — 模板方法，多数据源类型映射

**核心概念**：D 是子任务固定的数据对象类型，不同 dataSource type 的原始数据结构可能不同。通过模板方法 `convertToD`，子类 override 处理多 type 映射，无需额外接口或 Spring Bean。

**优势**：
- 无新增接口/文件，映射逻辑是 executor 内部行为
- 单 type 场景零代码——默认 Jackson convertValue
- 多 type 场景 override 一个方法，if/switch 即可

```java
/**
 * 将原始数据映射为 D 类型
 * 默认行为：直接 Jackson convertValue（单 type 场景零代码）
 * 多 type 场景：子类 override，根据 dataSourceType 做不同映射
 */
protected D convertToD(Map<String, Object> rawData, String dataSourceType) {
    return JsonUtils.getObjectMapper().convertValue(rawData, getDataClass());
}
```

**单 type executor — 无需 override，零代码**：

```java
@Component("MediaInfoExecutor")
public class MediaInfoExecutor extends AbstractTaskExecutor<MediaInfoParams, MediaInfoData> {
    // 不需要 override convertToD，默认 Jackson 反序列化即可
}
```

**多 type executor — override 处理不同 type**：

```java
@Component("TaggingExecutor")
public class TaggingExecutor extends AbstractTaskExecutor<TaggingParams, DemoData> {

    @Override
    protected DemoData convertToD(Map<String, Object> rawData, String dataSourceType) {
        if ("mediaInfo".equals(dataSourceType)) {
            // mediaInfo type → DemoData（映射：将音频+图片数据转为视频格式）
            MediaInfoData mediaData = JsonUtils.getObjectMapper()
                    .convertValue(rawData, MediaInfoData.class);
            DemoData demoData = new DemoData();
            demoData.setItems(mediaData.getItems().stream()
                    .map(item -> {
                        DemoItem demoItem = new DemoItem();
                        demoItem.setBusinessId(item.getBusinessId());
                        demoItem.setVideoUrl(item.getAudioUrl());
                        demoItem.setTitle("mediaInfo 转换数据");
                        return demoItem;
                    })
                    .collect(Collectors.toList()));
            return demoData;
        }
        // 默认 type 直接 Jackson
        return super.convertToD(rawData, dataSourceType);
    }
}
```

**调用处（`execute()` 中）**：

```java
D data = convertToD(context.getData(), dataSourceType);
```

**边界原则**：如果不同 type 的数据无法映射到同一个 D（结构差异太大），应创建新的 Executor，而不是强行映射。

#### 4. completeSubTask — 从 AbstractMediaProcessor 提升

```java
/**
 * 完成子任务
 * result 支持任意 Object（POJO / String / Map），自动序列化为 JSON
 */
protected void completeSubTask(SubTaskContext context, Object result, long startTime) {
    long duration = System.currentTimeMillis() - startTime;

    String resultJson = JsonUtils.toJson(result);
    subTaskService.completeSubTask(context.getSubTask().getId(), resultJson);

    // 更新父任务统计
    updateParentTaskStats(context.getSubTask().getParentTaskId());

    log.info("子任务完成: subTaskId={}, duration={}ms",
            context.getSubTask().getId(), duration);
}
```

**变更点**：
- 参数 `String analysisResult` → `Object result`，支持任意 POJO
- 不再硬塞 `durationMs` 和 `completedAt` 到结果 Map 中，结果就是纯粹的业务数据
- duration 由 `SubTask.durationMs` 和 `endTime - startTime` 记录，不混入业务结果

子类调用示例：

```java
// MediaInfoProcessor
MediaInfoResult result = new MediaInfoResult(asrText, analysisResult);
taskCompletionHelper.completeSubTask(context, result, startTime);

// VideoMediaProcessor
TaggingResult result = new TaggingResult(tags, asrText);
taskCompletionHelper.completeSubTask(context, result, startTime);

// 简单场景直接传 String
taskCompletionHelper.completeSubTask(context, "done", startTime);
```

#### 5. updateParentTaskStats — 从 AbstractMediaProcessor 提升

```java
protected void updateParentTaskStats(Long parentTaskId) {
    int success = subTaskService.countByStatus(parentTaskId, "SUCCESS");
    int failed = subTaskService.countByStatus(parentTaskId, "FAILED");
    int running = subTaskService.countByStatus(parentTaskId, "RUNNING");
    int pending = subTaskService.countByStatus(parentTaskId, "PENDING");

    taskService.updateSubTaskStats(parentTaskId, success, failed, running + pending);

    if (running + pending == 0) {
        String finalStatus = failed > 0 ? TaskStatus.FAILED.getCode() : TaskStatus.SUCCESS.getCode();
        Map<String, Integer> stats = new HashMap<>();
        stats.put("success", success);
        stats.put("failed", failed);
        taskService.updateTaskEndTime(parentTaskId, new Date(), finalStatus,
                JsonUtils.toJson(stats), "");
        log.info("父任务完成: taskId={}, status={}", parentTaskId, finalStatus);
    }
}
```

逻辑与原来完全一致，只是从 AbstractMediaProcessor 搬到 AbstractTaskExecutor。

### Processor 层优化

#### 当前问题

executor 的 `subExecute()` 通过 `List<MediaProcessor>` 注入 + stream `supports/findFirst` 选择 processor：

```java
// 当前 — runtime dispatch，实际关系固定
@Resource
private List<MediaProcessor> mediaProcessors;

public void subExecute(SubTaskContext context) {
    MediaProcessor processor = mediaProcessors.stream()
            .filter(mp -> mp.supports(context))
            .findFirst()
            .orElseThrow(...);
    processor.process(context);
}
```

实际上：
- MediaInfoExecutor **只用** MediaInfoProcessor
- TaggingExecutor **只用** VideoMediaProcessor

关系是编译期确定的，不需要 runtime dispatch。

#### 优化方案

**executor 直接注入具体 processor，去掉 supports/findFirst dispatch**：

```java
// MediaInfoExecutor — 直接注入
@Resource
private MediaInfoProcessor mediaInfoProcessor;

@Override
public void subExecute(SubTaskContext context) {
    mediaInfoProcessor.process(context);
}

// TaggingExecutor — 直接注入
@Resource
private VideoMediaProcessor videoMediaProcessor;

@Override
public void subExecute(SubTaskContext context) {
    videoMediaProcessor.process(context);
}
```

**MediaProcessor 接口简化**——删除 `supports()`，只保留 `process()`：

```java
// 优化后
public interface MediaProcessor {
    void process(SubTaskContext context);
}
```

**AbstractMediaProcessor 简化**——删除 `completeSubTask/updateParentTaskStats`（已提取到 TaskCompletionHelper），注入 TaskCompletionHelper：

```java
public abstract class AbstractMediaProcessor implements MediaProcessor {
    protected final Logger log = LoggerFactory.getLogger(getClass());

    @Resource
    protected TaskCompletionHelper taskCompletionHelper;

    @Resource
    protected SubTaskService subTaskService;

    // ========== 进度管理 ==========

    protected <T> T parseProgressFromJson(SubTask subTask, Class<T> type) {
        if (subTask.getProgress() != null && !subTask.getProgress().isEmpty()) {
            T progress = JsonUtils.jsonToObject(subTask.getProgress(), type);
            if (progress != null) {
                return progress;
            }
        }
        return null;
    }

    protected void saveProgress(Long subTaskId, Object progress) {
        subTaskService.updateSubTaskProgress(subTaskId, JsonUtils.toJson(progress));
    }
}
```

**Processor 复用逻辑不变**——`parseProgressFromJson` 和 `saveProgress` 仍在 AbstractMediaProcessor，子类继续继承使用。ASR 和图片理解虽然结构相似，但参数细节不同（provider/format vs 默认值、prompt 拼接逻辑），不值得进一步抽象。

#### 变更对比

| | 当前 | 优化后 |
|---|---|---|
| executor subExecute | `List<MediaProcessor>` + stream dispatch | 直接注入具体 processor |
| MediaProcessor 接口 | `supports()` + `process()` | 只保留 `process()` |
| AbstractMediaProcessor | `completeSubTask` + `updateParentTaskStats` + `parseProgressFromJson` + `saveProgress` | `parseProgressFromJson` + `saveProgress` + `TaskCompletionHelper` 注入 |
| MediaInfoProcessor | `supports()` 判断 executorName | 删除 `supports()` |
| VideoMediaProcessor | `supports()` 判断 videoUrl | 删除 `supports()` |

### SubTaskContext 变更

```java
@Data
public class SubTaskContext {
    private SubTask subTask;
    private Map<String, Object> params;       // 保持 Map，因为子任务参数结构各异
    private TaskContext parentContext;
    private ExecutorConfig executorConfig;
}
```

**params 保持 `Map<String, Object>` 不变**，原因是：
- 子任务参数来自 `subTaskParams` JSON，每个子任务的字段不同
- 父类在 `execute()` 中通过 `convertToD()` 已经将 D 映射为 Map 写入 subTaskParams
- 子类在 `subExecute()` 中从 Map 按需取值（`context.getParams().get("audioUrl")`）
- 如果要类型安全，子类可以自行从 params 中反序列化为 POJO

### TaskExecutor 接口变更

接口不变，泛型只影响 AbstractTaskExecutor 及其子类：

```java
public interface TaskExecutor {
    String getName();
    String getType();
    boolean hasSubExecutor();
    void execute(TaskContext context);
    void subExecute(SubTaskContext context);
}
```

### AbstractTaskExecutor 与 TaskCompletionHelper 的关系

`completeSubTask` 和 `updateParentTaskStats` 本身只依赖 `subTaskService` 和 `taskService`，不依赖 executor 的泛型参数。考虑到 MediaProcessor 和 AbstractTaskExecutor 不在同一继承链，提取为独立的 `TaskCompletionHelper`：

```java
@Component
public class TaskCompletionHelper {
    @Resource
    private SubTaskService subTaskService;
    @Resource
    private TaskService taskService;

    public void completeSubTask(SubTaskContext context, Object result, long startTime) { ... }
    public void updateParentTaskStats(Long parentTaskId) { ... }
}
```

AbstractTaskExecutor 也提供同名方法作为便捷入口（内部委托给 helper），子类 executor 在 `subExecute()` 中可直接 `completeSubTask(context, result, startTime)`。

## 变更文件清单

| 文件 | 变更 |
|------|------|
| `BaseTaskParams.java` | 新建，空基类，仅作 P 泛型约束 |
| `BaseTaskDataSource.java` | 新建，空基类，仅作 D 泛型约束 |
| `AbstractTaskExecutor.java` | 新增泛型 `<P, D>`，新增 `getParamsClass/getDataClass/getParams/getData/convertToD`，删除 `parseExtData/parseExtParams/getExtDataClass/getExtParamsClass`，新增 `completeSubTask/updateParentTaskStats`（委托 helper） |
| `TaskCompletionHelper.java` | 新建，提取 completeSubTask 和 updateParentTaskStats |
| `MediaProcessor.java` | 删除 `supports()` 方法，只保留 `process()` |
| `AbstractMediaProcessor.java` | 删除 `completeSubTask/updateParentTaskStats`，删除 `supports()`，注入 `TaskCompletionHelper`，保留 `parseProgressFromJson/saveProgress` |
| `MediaInfoExecutor.java` | 声明泛型 `<MediaInfoParams, MediaInfoData>`，POJO 继承基类，`List<MediaProcessor>` → 直接注入 `MediaInfoProcessor`，用 `convertToD/getData/getParams()` 替代手动转型 |
| `TaggingExecutor.java` | 声明泛型 `<TaggingParams, DemoData>`，POJO 继承基类，`List<MediaProcessor>` → 直接注入 `VideoMediaProcessor`，override `convertToD` 处理多 type |
| `MediaInfoProcessor.java` | 删除 `supports()`，`completeSubTask` → `taskCompletionHelper.completeSubTask(context, result, startTime)` |
| `VideoMediaProcessor.java` | 删除 `supports()`，`completeSubTask` → `taskCompletionHelper.completeSubTask(context, result, startTime)` |
| `SubTaskContext.java` | 不变 |
| `TaskExecutor.java` | 不变 |

## 结果 POJO 示例

```java
// MediaInfoExecutor 内部定义
public static class MediaInfoResult {
    private String asrText;
    private String analysisResult;

    public MediaInfoResult(String asrText, String analysisResult) {
        this.asrText = asrText;
        this.analysisResult = analysisResult;
    }
    // getter...
}

// TaggingExecutor 内部定义
public static class TaggingResult {
    private List<String> tags;
    private String asrText;
    private String analysisResult;

    public TaggingResult(List<String> tags, String asrText, String analysisResult) {
        this.tags = tags;
        this.asrText = asrText;
        this.analysisResult = analysisResult;
    }
    // getter...
}
```

## 风险与约束

1. **Java 泛型擦除**：子类仍需声明 `getParamsClass()` / `getDataClass()` 返回具体 Class，无法完全消除。但 `extends BaseTaskParams / BaseTaskDataSource` 约束确保类型体系统一
2. **基类可空**：`BaseTaskParams` 和 `BaseTaskDataSource` 没有字段，仅作泛型边界约束。简单 executor 直接用基类即可，不需要自定义 POJO
3. **MediaProcessor 继承链**：MediaProcessor 不继承 AbstractTaskExecutor，通过 TaskCompletionHelper 解耦。AbstractMediaProcessor 仍保留进度管理能力供 processor 子类复用
4. **向前兼容**：TaskExecutor 接口不变，TaskScheduler 注册逻辑不变
5. **Processor 固定绑定**：executor 与 processor 关系从 runtime dispatch 变为编译期确定。如果未来需要同一 executor 按条件选择不同 processor，需改为策略模式