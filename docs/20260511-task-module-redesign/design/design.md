# 任务模块重构设计文档

## 一、概述

### 1.1 设计目标

重构任务模块，将原有的 ParentExecutor/ChildExecutor 父子执行器模式，改为统一的 TaskExecutor 模型，并通过 QConfig 管理所有配置。

### 1.2 核心变化

| 变化项    | 原设计                               | 新设计                       |
| ------ | --------------------------------- | ------------------------- |
| 执行器模型  | ParentExecutor + ChildExecutor 接口 | 统一 TaskExecutor 接口        |
| 配置管理   | 硬编码 / 局部配置                        | QConfig JSON 统一管理         |
| 数据源    | 代码内解析                             | QConfig 配置数据源列表           |
| 参数格式   | 固定字段                              | JSON params 灵活结构          |
| 类型与执行器 | TaskType 硬编码绑定                    | type 枚举 + executorName 分离 |

---

## 二、QConfig 配置设计

### 2.1 QConfig JSON 文件结构

**文件：** `task_executor_config.json`（QConfig 管理）

**文件：** `task_executor_config.json`（QConfig 管理），根节点为 `Map<String, ExecutorConfig>`

```json
{
  "ai1": {
    "type": "aiTag",
    "executorName": "TaggingExecutor",
    "desc": "AI打标-默认",
    "hasSubExecutor": true,
    "dataSource": [
      {
        "type": "demo",
        "desc": "示例数据源",
        "dataSourceExample": "{\"items\":[{\"businessId\":\"001\",\"videoUrl\":\"https://...\",\"title\":\"测试视频1\"}]}"
      }
    ],
    "params": {
      "frameInterval": 5,
      "maxFrames": 10,
      "enableAsr": true,
      "prompts": {
        "system": "你是一个视频内容分析专家...",
        "analyze": "请分析这个视频内容，提取关键信息。\n视频标题：{title}\n语音内容：{asrText}"
      }
    }
  },
  "ai2": {
    "type": "aiTag",
    "executorName": "TaggingExecutor",
    "desc": "AI打标-高帧率",
    "hasSubExecutor": true,
    "dataSource": [
      {
        "type": "idList",
        "desc": "ID列表数据源",
        "dataSourceExample": "{\"ids\":[\"1001\",\"1002\",\"1003\"]}"
      }
    ],
    "params": {
      "frameInterval": 2,
      "maxFrames": 30,
      "enableAsr": true,
      "prompts": {
        "system": "你是一个视频内容分析专家...",
        "analyze": "请分析这个视频内容，提取关键信息。\n视频标题：{title}\n语音内容：{asrText}"
      }
    }
  },
  "stats1": {
    "type": "stats",
    "executorName": "StatsExecutor",
    "desc": "数据统计",
    "hasSubExecutor": false,
    "dataSource": [
      {
        "type": "idList",
        "desc": "素材ID列表",
        "dataSourceExample": "{\"ids\":[\"M1001\",\"M1002\"]}"
      }
    ],
    "params": {
      "statTypes": ["view", "like", "share"]
    }
  }
}
```

 
### 2.2 配置类设计

```java
/**
 * 任务 QConfig
 * 监听 task_executor_config.json，热加载配置
 * 根节点为 Map<String, ExecutorConfig>，每个 config 包含完整信息
 */
@Component
public class TaskQConfig {

    private volatile Map<String, ExecutorConfig> executorConfigs = Collections.emptyMap();

    @QConfig("task_executor_config.json")
    private void onChanged(String json) {
        TaskConfig config = JsonUtils.jsonToObject(json, TaskConfig.class);
        if (config != null) {
            this.executorConfigs = new ConcurrentHashMap<>(config);
        }
    }

    /** 根据 key 获取执行器配置 */
    public ExecutorConfig getConfig(String key) {
        ExecutorConfig config = executorConfigs.get(key);
        if (config == null) {
            throw new IllegalArgumentException("未找到执行器配置: " + key);
        }
        return config;
    }

    /** 获取所有执行器 type 去重列表（供前端分组筛选） */
    public List<String> getExecutorTypes() {
        return executorConfigs.values().stream()
                .map(ExecutorConfig::getType)
                .distinct()
                .collect(Collectors.toList());
    }

    /** 获取同一 type 下的所有 config key 列表（供前端选择执行器） */
    public List<String> getConfigKeysByType(String type) {
        return executorConfigs.entrySet().stream()
                .filter(e -> type.equals(e.getValue().getType()))
                .map(Map.Entry::getKey)
                .collect(Collectors.toList());
    }

    /** 所有执行器配置 */
    public Map<String, ExecutorConfig> getAllConfigs() {
        return Collections.unmodifiableMap(executorConfigs);
    }

    /** task_executor_config.json 根节点直接是 Map<String, ExecutorConfig> */
    @Data
    public static class TaskConfig extends HashMap<String, ExecutorConfig> {
    }
}
```

### 2.3 配置 POJO

```java
/**
 * 执行器配置
 */
@Data
public class ExecutorConfig {
    /** 业务类型枚举值：aiTag / stats */
    private String type;

    /** Spring Bean 名称 */
    private String executorName;

    /** 描述 */
    private String desc;

    /** 是否需要子任务 */
    private Boolean hasSubExecutor = false;

    /** 数据源配置列表（每个元素包含 type + dataSourceExample） */
    private List<DataSourceConfig> dataSource;

    /** 
     * 执行参数（Object 类型，各执行器按需定义具体 POJO）
     * 子类通过 getExtParamsClass() 声明具体类型，框架自动转换
     */
    private Object params;
}

/**
 * 数据源配置
 */
@Data
public class DataSourceConfig {
    /** 数据源类型：demo / idList */
    private String type;

    /** 数据源描述，前端下拉展示 */
    private String desc;

    /** JSON 示例，用户按此格式输入数据 */
    private String dataSourceExample;
}
```

---

## 三、TaskExecutor 接口设计

### 3.1 统一接口

```java
/**
 * 任务执行器接口
 * 不再区分父子执行器，统一由一个执行器处理
 */
public interface TaskExecutor {

    /** 执行器名称，与 Spring Bean name 一致 */
    String getName();

    /** 业务类型枚举值，如 aiTag / stats */
    String getType();

    /** 是否需要子任务（批量处理时为 true） */
    boolean hasSubExecutor();

    /** 主执行逻辑 - 由 QSchedule 调度 */
    void execute(TaskContext context);

    /** 子任务执行逻辑 - 由 QSchedule 调度 */
    void subExecute(SubTaskContext context);
}
```


### 3.2 上下文类

上下文只负责传递数据，**不执行任何业务逻辑**：

```java
/**
 * 任务执行上下文 - 传递数据，不执行业务
 */
@Data
public class TaskContext {
    /** 当前任务实体 */
    private Task task;

    /** 执行器配置（来自 QConfig 快照，params 保持 Object 类型，子类通过 parseExtParams() 按需解析） */
    private ExecutorConfig executorConfig;

    /** 数据源配置列表 */
    private List<DataSourceConfig> dataSource;

    /** 用户按 dataSourceExample 输入的实际数据 */
    private Map<String, Object> data;

    /** 选中的数据源索引（前端选择第几个数据源） */
    private Integer dataSourceIndex;

    /** 临时数据传递 */
    private Map<String, Object> tempData = new HashMap<>();
}

/**
 * 子任务执行上下文 - 传递数据，不执行业务
 */
@Data
public class SubTaskContext {
    /** 当前子任务实体 */
    private SubTask subTask;

    /** 子任务参数（来自 subTaskParams，携带 configKey 和业务数据） */
    private Map<String, Object> params;

    /** 父任务上下文 */
    private TaskContext parentContext;

    /** 执行器配置 */
    private ExecutorConfig executorConfig;
}
```

### 3.3 抽象模板类

抽象类提供通用能力，不执行业务逻辑：

```java
/**
 * 执行器抽象模板
 * 提供：上下文构建、状态管理、异常处理、日志监控等通用能力
 * 子类只需实现 execute/subExecute 具体业务
 */
public abstract class AbstractTaskExecutor implements TaskExecutor {

    @Resource
    protected TaskQConfig taskQConfig;

    @Resource
    protected TaskService taskService;

    @Resource
    protected SubTaskService subTaskService;

    @Resource
    protected DataSourceResolver dataSourceResolver;

    @Resource
    protected ObjectMapper objectMapper;

    /**
     * 构建 TaskContext（模板方法）
     * 优先使用 task_params 中的 executorSnapshot（快照），
     * 不存在时从 QConfig 实时加载
     * 
     * params 保持 Object 类型，不在此处合并解析。
     * 子类在 execute/subExecute 中通过 parseExtParams() 按需解析为具体 POJO。
     */
    public TaskContext buildContext(Task task) {
        Map<String, Object> taskParams = parseTaskParams(task.getTaskParams());
        
        // 1. 优先从快照获取 ExecutorConfig，不存在则从 QConfig 加载
        ExecutorConfig executorConfig = getExecutorConfig(taskParams);
        
        // 2. 组装 TaskContext
        //    params 保持 executorConfig 中的 Object 类型，
        //    业务层通过 parseExtParams() 按需解析，不做提前合并
        TaskContext context = new TaskContext();
        context.setTask(task);
        context.setExecutorConfig(executorConfig);
        context.setDataSource(executorConfig.getDataSource());
        context.setData((Map<String, Object>) taskParams.get("data"));
        return context;
    }

    /**
     * 获取 ExecutorConfig：优先快照，回退 QConfig
     */
    private ExecutorConfig getExecutorConfig(Map<String, Object> taskParams) {
        // 优先使用快照
        Map<String, Object> snapshot = (Map<String, Object>) taskParams.get("executorSnapshot");
        if (snapshot != null) {
            return objectMapper.convertValue(snapshot, ExecutorConfig.class);
        }
        // 回退 QConfig 实时加载
        String configKey = (String) taskParams.get("configKey");
        return taskQConfig.getConfig(configKey);
    }

    /**
     * 构建 SubTaskContext（模板方法）
     */
    public SubTaskContext buildSubContext(SubTask subTask, TaskContext parentContext) {
        Map<String, Object> subParams = parseTaskParams(subTask.getSubTaskParams());
        // 子任务携带 configKey 和 params，从父上下文复用 executorConfig
        ExecutorConfig executorConfig = parentContext != null ?
            parentContext.getExecutorConfig() : taskQConfig.getConfig((String) subParams.get("configKey"));

        SubTaskContext context = new SubTaskContext();
        context.setSubTask(subTask);
        context.setParams(subParams);
        context.setParentContext(parentContext);
        context.setExecutorConfig(executorConfig);
        return context;
    }

    // ========== 数据源泛型继承机制 ==========

    /**
     * 获取指定 dataSource type 对应的具体 POJO 类型
     * 子类可重写，实现类型安全的数据访问
     * 
     * 示例：
     *   public Optional<Class<?>> getExtDataClass(String dataSourceType) {
     *       if ("demo".equals(dataSourceType)) return Optional.of(DemoData.class);
     *       if ("idList".equals(dataSourceType)) return Optional.of(IdListData.class);
     *       return Optional.empty();
     *   }
     */
    public Optional<Class<?>> getExtDataClass(String dataSourceType) {
        return Optional.empty();
    }

    /**
     * 将用户输入 data 反序列化为具体类型实例
     * 子类在 execute/subExecute 中调用，获得类型安全的 POJO
     *
     * @param data            用户输入数据（来自 task_params.data）
     * @param dataSourceType  数据源类型（如 "demo"、"idList"）
     * @return 反序列化后的具体 POJO 实例，无匹配类型时返回原始 Map
     */
    protected Object parseExtData(Map<String, Object> data, String dataSourceType) {
        Optional<Class<?>> extDataClass = getExtDataClass(dataSourceType);
        if (extDataClass.isPresent() && data != null && !data.isEmpty()) {
            return objectMapper.convertValue(data, extDataClass.get());
        }
        return data;
    }

    // ========== params 泛型继承机制 ==========

    /**
     * 获取 ExecutorConfig.params 对应的具体 POJO 类型
     * 子类可重写，实现类型安全的参数访问
     * 
     * 示例：
     *   public Optional<Class<?>> getExtParamsClass() {
     *       return Optional.of(TaggingParams.class);
     *   }
     */
    public Optional<Class<?>> getExtParamsClass() {
        return Optional.empty();
    }

    /**
     * 将 executorConfig.params（Object）反序列化为具体类型实例
     * 子类在 execute/subExecute 中调用，获得类型安全的 POJO
     *
     * @param params  executorConfig 的 params 字段（Object）
     * @return 反序列化后的具体 POJO 实例，无匹配类型时返回原始 Map
     */
    protected Object parseExtParams(Object params) {
        if (params == null) {
            return null;
        }
        Optional<Class<?>> extParamsClass = getExtParamsClass();
        if (extParamsClass.isPresent()) {
            return objectMapper.convertValue(params, extParamsClass.get());
        }
        return params;
    }

    // ========== 任务状态管理 ==========

    /**
     * 执行任务（带状态管理）
     */
    public void executeWithTracking(Task task) {
        try {
            TaskContext context = buildContext(task);
            taskService.updateTaskStartTime(task.getId(), new Date());
            execute(context);
        } catch (Exception e) {
            taskService.updateTaskEndTime(task.getId(), new Date(),
                    TaskStatus.FAILED.getCode(), "", e.getMessage());
        }
    }

    /**
     * 执行子任务（带状态管理）
     */
    public void subExecuteWithTracking(SubTask subTask, TaskContext parentContext) {
        try {
            SubTaskContext context = buildSubContext(subTask, parentContext);
            subTaskService.startSubTask(subTask.getId());
            subExecute(context);
        } catch (Exception e) {
            subTaskService.failSubTask(subTask.getId(), e.getMessage());
        }
    }

    /**
     * 解析 task_params JSON
     */
    private Map<String, Object> parseTaskParams(String taskParams) {
        if (StringUtils.isBlank(taskParams)) {
            return new HashMap<>();
        }
        try {
            return objectMapper.readValue(taskParams,
                new TypeReference<HashMap<String, Object>>() {});
        } catch (Exception e) {
            throw new RuntimeException("解析 task_params 失败", e);
        }
    }
}
```

---

## 四、TaskType 重构

type 和 executorName 分离，type 是枚举标识，executorName 是 Spring Bean 名称。

```java
/**
 * 任务类型枚举
 * 只定义业务类型，不绑定执行器
 */
public enum TaskType {
    AI_TAG("aiTag", "AI打标"),
    STATS("stats", "数据统计");

    private final String code;
    private final String desc;

    // getter...
    public static TaskType fromCode(String code) { ... }
}
```

**映射关系**（通过 QConfig + TaskQConfig 完成）：

```
Task.task_params.configKey = "ai1"
                │
                ▼
TaskQConfig.getConfig("ai1")
                │
                ▼
ExecutorConfig.executorName = "TaggingExecutor"
                │
                ▼
Spring Context.getBean("TaggingExecutor") → TaskExecutor
```

---

## 五、调度器改造

原有的 `TaskScheduler` 适配新的执行器模型：

```java
@Service
public class TaskScheduler {

    @Resource
    private TaskService taskService;

    @Resource
    private SubTaskService subTaskService;

    @Resource
    private TaskQConfig taskQConfig;

    @Resource
    private Map<String, TaskExecutor> executorMap; // Spring 自动注入所有 TaskExecutor

    @QSchedule("mkt_odin_task_schedule")
    public void scheduleTask(Parameter param) {
        List<Task> pendingTasks = taskService.getPendingTasks(TASK_BATCH_SIZE);
        for (Task task : pendingTasks) {
            // 1. 解析 task_params 获取 configKey
            Map<String, Object> taskParams = parseTaskParams(task.getTaskParams());
            String configKey = (String) taskParams.get("configKey");

            // 2. 从 QConfig 获取执行器配置
            ExecutorConfig config = taskQConfig.getConfig(configKey);
            TaskExecutor executor = executorMap.get(config.getExecutorName());

            if (executor == null) {
                taskService.updateTaskEndTime(...);
                continue;
            }

            if (executor.hasSubExecutor()) {
                // 解析数据源 → 创建子任务
                executor.execute(executor.buildContext(task));
            } else {
                // 直接执行
                executor.executeWithTracking(task);
            }
        }
    }

    @QSchedule("mkt_odin_subtask_schedule")
    public void scheduleSubTask(Parameter param) {
        List<SubTask> pendingSubTasks = subTaskService.getPendingSubTasks(SUBTASK_BATCH_SIZE);
        for (SubTask subTask : pendingSubTasks) {
            Task parentTask = taskService.getTask(subTask.getParentTaskId());
            // 从子任务参数中获取 configKey 重建上下文
            Map<String, Object> subParams = parseTaskParams(subTask.getSubTaskParams());
            String configKey = (String) subParams.get("configKey");
            ExecutorConfig config = taskQConfig.getConfig(configKey);
            TaskExecutor executor = executorMap.get(config.getExecutorName());
            executor.subExecuteWithTracking(subTask, /* parentContext */);
        }
    }
}
```

---

## 六、API 接口变更

### 6.1 执行器管理接口（新增）

前端选择流程：先按 type 分组浏览 → 选择具体的 configKey → 查看数据源示例。type 仅用于分组，前端展示的是 `desc` 描述文本，后端传对应标识：

| 接口 | 方法 | 说明 |
|------|------|------|
| `/api/executor/types` | GET | 获取所有执行器 type 列表（展示 desc，传 type） |
| `/api/executor/configs` | GET | 根据 type 获取 config key 列表（展示 desc，传 configKey） |
| `/api/executor/datasources` | GET | 根据 configKey 获取数据源配置 |

**返回示例**：

```json
// GET /api/executor/types
{
  "code": 0,
  "data": [
    { "type": "aiTag", "desc": "AI打标" },      // 前端展示 "AI打标"，选中后传 aiTag
    { "type": "stats", "desc": "数据统计" }
  ]
}

// GET /api/executor/configs?type=aiTag
{
  "code": 0,
  "data": [
    { "configKey": "ai1", "desc": "AI打标-默认" },   // 前端展示 "AI打标-默认"，选中后传 ai1
    { "configKey": "ai2", "desc": "AI打标-高帧率" }
  ]
}

// GET /api/executor/datasources?configKey=ai1
{
  "code": 0,
  "data": [
    { "type": "demo", "desc": "示例数据源", "dataSourceExample": "{\"items\":[{\"businessId\":\"001\",\"videoUrl\":\"https://...\",\"title\":\"测试视频1\"}]}" }
  ]
}
```

### 6.2 创建任务接口调整

```json
// POST /api/task/create
{
  "taskName": "AI打标测试任务",
  "configKey": "ai1",                  // 对应 QConfig 的 key
  "dataSourceType": "demo",            // 选中的数据源 type
  "data": {                            // 用户按 dataSourceExample 格式输入的实际数据
    "items": [{ "businessId": "001", "videoUrl": "https://example.com/v1.mp4", "title": "测试视频1" }]
  },
  "params": {                          // 灵活 JSON 参数
    "frameInterval": 3,
    "customTags": ["旅游", "美食"]
  },
  "executeTime": "2026-05-11 14:00:00",
  "createBy": "admin"
}
```

对应的 `TaskCreateRequest`：

```java
@Data
public class TaskCreateRequest {
    private String taskName;
    private String configKey;            // QConfig key，如 ai1
    private String dataSourceType;       // 选中的 dataSource type，如 demo / idList
    private Map<String, Object> data;    // 用户按 dataSourceExample 格式输入的实际数据
    private Map<String, Object> params;  // 灵活参数
    private Date executeTime;
    private String createBy;
}
```

`TaskService.createTask()` 创建任务时，自动从 QConfig 快照 `ExecutorConfig` 写入 `task_params`：

```java
@Transactional(rollbackFor = Exception.class)
public Long createTask(TaskCreateRequest request) {
    // 1. 从 QConfig 获取执行器配置
    ExecutorConfig executorConfig = taskQConfig.getConfig(request.getConfigKey());

    // 2. 构建 task_params（含配置快照）
    Map<String, Object> taskParams = new HashMap<>();
    taskParams.put("configKey", request.getConfigKey());
    taskParams.put("dataSourceType", request.getDataSourceType());
    taskParams.put("data", request.getData());
    taskParams.put("params", request.getParams());
    taskParams.put("executorSnapshot", executorConfig);  // ← 配置快照：创建时完整拷贝 QConfig 配置

    // 3. 创建任务
    Task task = new Task();
    task.setTaskCode(generateTaskCode());
    task.setTaskName(request.getTaskName());
    task.setTaskType(executorConfig.getType());
    task.setExecutor(executorConfig.getExecutorName());
    task.setTaskParams(objectMapper.writeValueAsString(taskParams));
    // ... 其余字段
    taskMapper.insert(task);
    return task.getId();
}
```

落库后的 `task_params` 结构：

```json
{
  "configKey": "ai1",
  "dataSourceType": "demo",
  "data": {
    "items": [{ "businessId": "001", "videoUrl": "https://...", "title": "测试视频1" }]
  },
  "params": { "frameInterval": 3, "customTags": ["旅游", "美食"] },
  "executorSnapshot": {
    "type": "aiTag",
    "executorName": "TaggingExecutor",
    "hasSubExecutor": true,
    "dataSource": [
      { "type": "demo", "dataSourceExample": "{\"items\":[...]}" }
    ],
    "params": { "frameInterval": 5, "maxFrames": 10, "enableAsr": true, "prompts": { "analyze": "请分析这个视频内容..." } }
    }
  }
}
```

---

## 七、Executor 示例：AI 打标（TaggingExecutor）

```java
@Component("TaggingExecutor")
public class TaggingExecutor extends AbstractTaskExecutor {

    @Override
    public String getName() { return "TaggingExecutor"; }

    @Override
    public boolean hasSubExecutor() { return true; }

    @Override
    public Optional<Class<?>> getExtParamsClass() {
        return Optional.of(TaggingParams.class);
    }

    @Override
    public Optional<Class<?>> getExtDataClass(String dataSourceType) {
        if ("demo".equals(dataSourceType)) {
            return Optional.of(DemoData.class);
        }
        return Optional.empty();
    }
     * 示例：dataSource type = "demo" 时，用户输入格式为：
     *   { "items": [{ "businessId": "...", "videoUrl": "...", "title": "..." }] }
     */
    @Data
    public static class DemoData {
        /** 业务标识列表 */
        private List<DemoItem> items;
    }

    @Data
    public static class DemoItem {
        private String businessId;
        private String videoUrl;
        private String title;
    }

    /**
     * params 对应的具体 POJO
     * 框架自动将 executorConfig.params（Object）转换为该类型
     * 包含所有执行器配置参数，包括原本独立的 prompts
     */
    @Data
    public static class TaggingParams {
        private Integer frameInterval;
        private Integer maxFrames;
        private Boolean enableAsr;
        private Map<String, String> prompts;
    }

    /**
     * 主执行逻辑：解析数据源 → 创建子任务
     */
    @Override
    public void execute(TaskContext context) {
        // 1. 从上下文获取数据源配置和用户输入数据
        List<DataSourceConfig> dataSourceConfigs = context.getDataSource();
        Map<String, Object> rawData = context.getData();

        // 2. 利用 AbstractTaskExecutor 的泛型机制，转换为类型安全的 POJO
        //    根据 dataSource[0].type = "demo" 自动找到 DemoData.class
        String dataSourceType = dataSourceConfigs.get(0).getType();
        DemoData demoData = (DemoData) parseExtData(rawData, dataSourceType);

        // 3. 解析 params 为类型安全的 TaggingParams POJO
        //    获取执行参数，包括 frameInterval、prompts 等
        TaggingParams params = (TaggingParams) parseExtParams(context.getExecutorConfig().getParams());

        // 4. 解析数据源，获取业务标识列表
        List<SubTask> subTasks = new ArrayList<>();
        for (DemoItem item : demoData.getItems()) {
            SubTask subTask = new SubTask();
            subTask.setParentTaskId(context.getTask().getId());
            subTask.setExecutor(getName());
            subTask.setBusinessKey(item.getBusinessId());

            // 子任务参数传递业务数据和上下文
            // 注意：不传递整个 params（子任务从快照重建 executorConfig），
            // 只传递业务相关字段
            Map<String, Object> subParams = new HashMap<>();
            subParams.put("videoUrl", item.getVideoUrl());
            subParams.put("title", item.getTitle());
            subParams.put("configKey", getConfigKeyFromTask(context.getTask()));
            subTask.setSubTaskParams(objectMapper.writeValueAsString(subParams));
            subTasks.add(subTask);
        }
        subTaskService.batchCreateSubTasks(subTasks);
    }

    /**
     * 子任务执行逻辑：下载视频 → 抽帧 → 提取音频 → ASR → 大模型分析
     */
    @Override
    public void subExecute(SubTaskContext context) {
        // 1. 解析 params 为类型安全的 TaggingParams POJO
        TaggingParams params = (TaggingParams) parseExtParams(
            context.getExecutorConfig().getParams());
        
        // 2. 获取业务数据
        String videoUrl = (String) context.getParams().get("videoUrl");
        String title = (String) context.getParams().get("title");
        
        // 3. 使用 params 获取配置
        Integer frameInterval = params.getFrameInterval();
        Integer maxFrames = params.getMaxFrames();
        Boolean enableAsr = params.getEnableAsr();
        String prompt = params.getPrompts() != null ?
            params.getPrompts().get("analyze") : "";
        // ...
    }

    /**
     * 辅助方法：从 task.task_params 中获取 configKey
     */
    private String getConfigKeyFromTask(Task task) {
        try {
            Map<String, Object> taskParams = objectMapper.readValue(
                task.getTaskParams(), HashMap.class);
            return (String) taskParams.get("configKey");
        } catch (Exception e) {
            throw new RuntimeException("解析 task_params 获取 configKey 失败", e);
        }
    }
}
```

---

## 八、当前代码适配总结

### 8.1 保留的文件

| 文件 | 处理方式 |
|------|---------|
| `Task.java` / `SubTask.java` | 实体类基本保留 |
| `TaskStatus.java` / `SubTaskStatus.java` | 枚举保留 |
| `TaskService.java` / `SubTaskService.java` | 服务层保留 |
| `TaskController.java` | Controller 保留，新增 executor 接口 |
| `TaskScheduler.java` | 适配新的 TaskExecutor 模型 |
| `DataSourceResolver.java` | 保留，数据源解析逻辑复用 |
| `VideoUtil.java` / `AsrService.java` / `ImageUnderstandingService.java` | 保留，业务能力复用 |

### 8.2 需要修改的文件

| 文件 | 变更内容 |
|------|---------|
| `TaskType.java` | 移除 executor 硬编码绑定，type/executorName 分离 |
| `ParentExecutor.java` / `ChildExecutor.java` | 废弃，替换为 TaskExecutor 接口 |
| `ExecutorFactory.java` | 废弃，利用 Spring 自动注入 `Map<String, TaskExecutor>` |
| `ExecutorConfig.java` | 重构为 QConfig 数据模型 |
| `DataSourceConfig.java` | 精简为 type + dataSourceExample 结构 |
| `DataSourceResolver.java` | 增强：支持按 dataSource type 选择 POJO 解析策略 |
| `TaggingParentExecutor.java` | 重构为 TaggingExecutor，实现 TaskExecutor 接口 |
| `TaggingChildExecutor.java` | 逻辑合并到 TaggingExecutor.subExecute() |
| `TaskService.java` | createTask 新增 executorSnapshot 快照落库逻辑 |
| `TaskCreateRequest.java` | dataSourceName + params 灵活结构 |
| `TaskScheduler.java` | 适配新模型，优先使用快照 |
| `TaskController.java` | 新增 executor/types、executor/datasources 接口 |

### 8.3 新增的文件

| 文件 | 说明 |
|------|------|
| `TaskExecutor.java` | 统一执行器接口 |
| `AbstractTaskExecutor.java` | 抽象模板类（含配置快照解析 + dataSource 泛型机制） |
| `TaskContext.java` | 任务上下文 |
| `SubTaskContext.java` | 子任务上下文 |
| `TaskQConfig.java` | QConfig 配置管理 |
| `executor/data/*.java` | 各 dataSource type 对应的具体 POJO 类（如 DemoData、IdListData） |

---

## 九、数据流转全流程

### 9.1 三类数据定义

| 类别 | 来源 | 存储位置 | 说明 |
|------|------|---------|------|
| **QConfig 配置** | 运维配置 `task_executor_config.json` | QConfig 热加载，**创建时快照落 DB** | executorName、hasSubExecutor、dataSource[] 定义、params 默认值（含 prompts） |
| **用户输入** | 前端表单提交 | **落 DB**（task_params） | configKey、data（业务数据）、params（覆盖 QConfig 默认值） |
| **运行时派生** | AbstractTaskExecutor 构建 | **不落 DB**，仅上下文传递 | TaskContext、SubTaskContext、解析后的 POJO 实例 |


### 9.2 全流程数据分类明细

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  步骤1: 前端初始化表单                                                       │
│                                                                             │
│  GET /api/executor/types                    ← QConfig: 各 config 的 type    │
│  → 前端展示 desc 文本（如 "AI打标"），选中后传 type 值                    │
│                                                                             │
│  GET /api/executor/configs?type=aiTag       ← QConfig: 该 type 下的 config  │
│  → 前端展示 desc 文本（如 "AI打标-默认"），选中后传 configKey              │
│                                                                             │
│  GET /api/executor/datasources?configKey=ai1  ← QConfig: dataSource[]       │
│  → 前端展示 desc 文本（如 "示例数据源"），选中后传 dataSourceType 值       │
│  → 前端展示 dataSource[].dataSourceExample    示例 JSON                      │
│  → 用户按示例格式输入 data                                                  │
│                                                                             │
│  → 用户可选输入 params 覆盖默认值            ← QConfig: params 默认值        │
└─────────────────────────────────────────────────────────────────────────────┘
                                        ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│  步骤2: 提交创建任务 (POST /api/task/create)                                 │
│                                                                             │
│  请求体：                                                                   │
│  {                                                                          │
│    "taskName": "AI打标测试",             ← 用户输入 → 落 DB                 │
│    "configKey": "ai1",                   ← 用户输入 → 落 DB                 │
│    "dataSourceType": "demo",             ← 用户输入 → 落 DB                 │
│    "data": {                              ← 用户输入 → 落 DB                 │
│      "items": [{"businessId":"001","videoUrl":"...","title":"测试视频1"}]    │
│    },                                                                       │
│    "params": { "frameInterval": 3 },      ← 用户输入 → 落 DB                │
│    "executeTime": "2026-05-11 14:00:00",  ← 用户输入 → 落 DB                │
│    "createBy": "admin"                    ← 用户输入 → 落 DB                │
│  }                                                                          │
│                                                                             │
│  DB task 表：                                                               │
│  ┌──────────────┬──────────────────────────────────────────────────┐        │
│  │ task_type    │ "aiTag"                 (从 configKey 反查)       │        │
│  │ executor     │ "TaggingExecutor"        (从 QConfig 反查)       │        │
│  │ task_params  │ JSON {                                            │        │
│  │              │   "configKey": "ai1",                  ← 用户输入 │        │
│  │              │   "dataSourceType": "demo",            ← 用户输入 │        │
│  │              │   "data": {"items":[...]},              ← 用户输入 │        │
│  │              │   "params": {"frameInterval":3},        ← 用户输入 │        │
│  │              │   "executorSnapshot": {                  ← 配置快照 │        │
│  │              │     "type":"aiTag",                                 │        │
│  │              │     "executorName":"TaggingExecutor",               │        │
│  │              │     "hasSubExecutor":true,                          │        │
│  │              │     "dataSource":[{type:"demo",...}],               │        │
│  │              │     "params":{                                       │        │
    │  │              │       "frameInterval":5,                            │        │
    │  │              │       "maxFrames":10,                               │        │
    │  │              │       "enableAsr":true,                             │        │
    │  │              │       "prompts":{analyze:"请分析..."}               │        │
    │  │              │     }                                               │        │
│  │              │   }                                                 │        │
│  │              │ }                                                    │     │
│  │ status       │ "PENDING"                                          │        │
│  │ execute_time │ 2026-05-11 14:00:00                                 │        │
│  └──────────────┴──────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────────────────────┘
                                        ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│  步骤3: QSchedule 调度执行 (TaskScheduler.scheduleTask)                      │
│                                                                             │
│  ① 查询 PENDING 任务                                                         │
│                                                                             │
│  ② 解析 task_params → 获取 configKey + executorSnapshot                    │
│     task_params = {                                 ← DB 持久化数据          │
│       "configKey": "ai1",                                                   │
│       "data": {"items":[...]},                                              │
│       "params": {"frameInterval":3},                                        │
│       "executorSnapshot": {                    ← 创建时快照（首选）          │
│         type:"aiTag", executorName:"TaggingExecutor",                       │
│         hasSubExecutor:true, dataSource:[...],                              │
│         params:{frameInterval:5,maxFrames:10,enableAsr:true,prompts:{analyze:"请分析..."}}│
│       }                                                                     │
│     }                                                                       │
│                                                                             │
│  ③ buildContext: 优先用 executorSnapshot 重建 ExecutorConfig                │
│     getExecutorConfig(taskParams) →                                         │
│       snapshot 存在 → 反序列化快照 ← 配置冻结，不受 QConfig 变更影响         │
│       snapshot 不存在 → taskQConfig.getConfig("ai1") ← 回退 QConfig 实时    │
│     ExecutorConfig {                                                        │
│       type: "aiTag",                                                        │
│       executorName: "TaggingExecutor",              ← QConfig               │
│       hasSubExecutor: true,                         ← QConfig               │
│       dataSource: [{ type:"demo", dataSourceExample }] ← QConfig             │
│       params: { frameInterval:5, maxFrames:10, enableAsr:true, prompts:{analyze:"请分析..."} }│
│                                                                              │
│     }                                                                       │
│                                                                             │
│  ④ Spring getBean("TaggingExecutor") → TaskExecutor                         │
│                                                                             │
│  ⑤ buildContext(task):  params 不合并，保持 Object 类型                    │
│     TaskContext {                                                           │
│       task:                    ← DB 实体                                    │
│       params:                  ← 不设置，业务层通过 parseExtParams() 按需解析│
│       executorConfig:           ← 快照反序列化的 ExecutorConfig              │
│       dataSource:               ← QConfig dataSource[] 引用                  │
│       data:                     ← DB 用户输入 data                           │
│     }                                                                       │
│                                                                             │
│  ⑥ executor.execute(context)                                                │
└─────────────────────────────────────────────────────────────────────────────┘
                                        ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│  步骤4: 创建子任务 (TaggingExecutor.execute)                                 │
│                                                                             │
│  execute(context) {                                                         │
│    dataSourceConfigs = context.getDataSource()   ← QConfig 快照/引用         │
│    rawData = context.getData()                    ← DB 用户输入 data         │
│                                                                             │
│    // 利用泛型机制：dataSource[0].type="demo" → DemoData.class              │
│    DemoData demoData = (DemoData) parseExtData(rawData, "demo")             │
│    // 现在 demoData 是类型安全的 POJO：demoData.getItems()                  │
│    // 每个 dataSource type 可对应独立 POJO，在子类 getExtDataClass() 中声明  │
│                                                                             │
│    for (DemoItem item in demoData.getItems()) {                             │
│      SubTask {                                                              │
│        parentTaskId: task.id,                  ← DB                         │
│        executor: "TaggingExecutor",            ← QConfig 快照               │
│        businessKey: item.businessId,           ← POJO 字段                  │
│        subTaskParams: {                        ← 落 DB（JSON 序列化）       │
│          "videoUrl": item.videoUrl,            ← POJO 字段                  │
│          "title": item.title,                  ← POJO 字段                  │
│          "configKey": "ai1"                    ← 用于子任务重建上下文        │
│        }                                                                     │
│      }                                                                       │
│    }                                                                         │
│  }                                                                           │
└─────────────────────────────────────────────────────────────────────────────┘
                                        ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│  步骤5: QSchedule 执行子任务 (TaskScheduler.scheduleSubTask)                  │
│                                                                             │
│  ① 查询 PENDING 子任务                                                       │
│                                                                             │
│  ② buildSubContext(subTask, parentContext):                                 │
│     SubTaskContext {                                                        │
│       subTask:                      ← DB 实体                               │
│       params: subTask.subTaskParams 解析                                    │
│       parentContext:                 ← 需要从 parentTaskId 重建 parentContext│
│       executorConfig:                ← 从 subTaskParams 中 configKey 查     │
│                                        QConfig 重建                          │
│     }                                                                       │
│                                                                             │
│  ③ executor.subExecute(context) → 执行业务逻辑                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 9.3 关键设计要点

**QConfig 不落 DB + 配置快照**：所有 `ExecutorConfig`（executorName、hasSubExecutor、dataSource 定义、params 默认值）只存在于 QConfig 热加载内存中。但创建任务时 `TaskService.createTask()` 自动将当前 `ExecutorConfig` 完整快照写入 `task_params.executorSnapshot`，确保后续 QConfig 配置变更或删除不影响历史任务。调度执行时优先使用快照，快照不存在才回退 QConfig 实时加载。

**params 类型安全解析**：`executorConfig.params` 为 `Object` 类型，不在此处做 Map 合并。子类通过 `getExtParamsClass()` 声明具体 POJO 类型，执行时调用 `parseExtParams()` 将 `params` 转换为类型安全的 POJO（如 `TaggingParams`），按需访问字段（包括 `prompts`、`frameInterval` 等）。
- QConfig 定义 `params` 默认值（如 `{ "frameInterval": 5, "maxFrames": 10, "prompts": {...} }`）
- 用户创建任务时传入的 `params` 覆盖值存储在 `task_params.params`，但 **不做自动合并**
- 子类在业务代码中按需自行处理默认值与用户输入的关系，灵活度更高

**子任务上下文重建**：子任务不直接引用 parentContext（避免跨线程/跨调度周期序列化问题），而是在 `subTaskParams` 中携带 `configKey`，执行时从快照或 QConfig 查找 `ExecutorConfig`，通过 `parseExtParams()` 重新解析 params。

**dataSource 泛型继承机制**：
1. QConfig 定义 `dataSource[]`，每项包含 `type` + `dataSourceExample`（示例 JSON）
2. 用户按示例格式输入实际 `data`，落库到 `task_params.data`
3. 执行器子类通过 `getExtDataClass(type)` 声明每个 dataSource type 对应的具体 POJO
4. `AbstractTaskExecutor.parseExtData(data, type)` 自动将 `Map` 转换为 POJO
5. 业务代码直接操作类型安全的 POJO（如 `DemoData.getItems()`），无需手动解析 JSON

**dataSource 解析流程**：
1. QConfig 定义 `dataSource[]`，每项包含 `type` + `dataSourceExample`（示例 JSON）
2. 用户按示例格式输入实际 `data`
3. 执行时 `DataSourceResolver.resolve(dataSourceConfigs, userData)` 根据 `type` 选择解析策略
4. 返回 `List<BusinessKeyItem>` 用于创建子任务

---

## 十、QConfig JSON 完整示例

```json
{
  "ai1": {
    "type": "aiTag",
    "executorName": "TaggingExecutor",
    "desc": "AI打标-默认",
    "hasSubExecutor": true,
    "dataSource": [
      {
        "type": "demo",
        "desc": "示例数据源",
        "dataSourceExample": "{\"items\":[{\"businessId\":\"001\",\"videoUrl\":\"https://example.com/v1.mp4\",\"title\":\"测试视频1\"},{\"businessId\":\"002\",\"videoUrl\":\"https://example.com/v2.mp4\",\"title\":\"测试视频2\"}]}"
      }
    ],
    "params": {
      "frameInterval": 5,
      "maxFrames": 10,
      "enableAsr": true,
      "prompts": {
        "system": "你是一个视频内容分析专家...",
        "analyze": "请分析视频内容..."
      }
    }
  },
  "stats1": {
    "type": "stats",
    "executorName": "StatsExecutor",
    "desc": "数据统计",
    "hasSubExecutor": false,
    "dataSource": [
      {
        "type": "idList",
        "desc": "素材ID列表",
        "dataSourceExample": "{\"ids\":[\"M1001\",\"M1002\"]}"
      }
    ],
    "params": {}
  }
}
```

---

## 十一、落库数据示例

### 字段来源说明

| 字段 | 来源 | 说明 |
|------|------|------|
| `task_type` | QConfig `ExecutorConfig.type` | 创建时从 configKey 反查写入 |
| `executor` | QConfig `ExecutorConfig.executorName` | 创建时从 configKey 反查写入 |
| `task_params.configKey` | 用户输入 | 前端选中的 configKey |
| `task_params.data` | 用户输入 | 按 dataSourceExample 格式填写 |
| `task_params.dataSourceType` | 用户输入 | 选中的数据源 type，如 demo / idList |
| `task_params.params` | 用户输入 | 覆盖 QConfig 默认值的可选参数 |
| `task_params.executorSnapshot` | QConfig 快照 | 创建时自动完整拷贝，冻结配置 |
| `sub_task_params.configKey` | 父任务传递 | 子任务通过它重建上下文 |
| `sub_task_params.videoUrl/title` | 父任务 execute() 注入 | 从 dataSource POJO 中提取的业务数据 |

### 11.1 task 表 — AI打标任务（有子任务）

**创建时（INSERT）：**

```sql
INSERT INTO `task` (
    `task_code`, `task_name`, `task_type`, `executor`,
    `task_params`,
    `status`, `execute_time`, `create_by`
) VALUES (
    'TASK_1715385600000_A1B2C3D4',
    '新品宣传片AI打标',
    'aiTag',
    'TaggingExecutor',
    '{
        "configKey": "ai1",
        "dataSourceType": "demo",
        "data": {
            "items": [
                { "businessId": "P20240501", "videoUrl": "https://oss.example.com/videos/p20240501.mp4", "title": "春季新品宣传片" },
                { "businessId": "P20240502", "videoUrl": "https://oss.example.com/videos/p20240502.mp4", "title": "夏季新品预告" }
            ]
        },
        "params": {
            "frameInterval": 3,
            "customTags": ["时尚", "新品"]
        },
        "executorSnapshot": {
            "type": "aiTag",
            "executorName": "TaggingExecutor",
            "desc": "AI打标-默认",
            "hasSubExecutor": true,
            "dataSource": [
                { "type": "demo", "dataSourceExample": "{\"items\":[...]}" }
            ],
            "params": {
                "frameInterval": 5,
                "maxFrames": 10,
                "enableAsr": true,
                "prompts": {
                    "system": "你是一个视频内容分析专家...",
                    "analyze": "请分析视频内容..."
                }
            }
        }
    }',
    'PENDING',
    '2026-05-11 14:00:00',
    'admin'
);
```

**执行中（UPDATE）：**

```sql
UPDATE `task` SET
    `status` = 'RUNNING',
    `start_time` = '2026-05-11 14:00:05',
    `sub_task_count` = 2,
    `sub_task_processing` = 2
WHERE `id` = 1;
```

**执行完成（UPDATE）：**

```sql
UPDATE `task` SET
    `status` = 'SUCCESS',
    `end_time` = '2026-05-11 14:05:30',
    `sub_task_success` = 2,
    `sub_task_processing` = 0,
    `result` = '{"success":2,"failed":0}'
WHERE `id` = 1;
```

### 11.2 task 表 — 数据统计任务（无子任务）

```sql
INSERT INTO `task` (
    `task_code`, `task_name`, `task_type`, `executor`,
    `task_params`,
    `status`, `execute_time`, `create_by`
) VALUES (
    'TASK_1715392800000_E5F6G7H8',
    '5月视频播放量统计',
    'stats',
    'StatsExecutor',
    '{
        "configKey": "stats1",
        "dataSourceType": "idList",
        "data": {
            "ids": ["M1001", "M1002", "M1003"]
        },
        "params": {},
        "executorSnapshot": {
            "type": "stats",
            "executorName": "StatsExecutor",
            "desc": "数据统计",
            "hasSubExecutor": false,
            "dataSource": [
                { "type": "idList", "dataSourceExample": "{\"ids\":[\"M1001\",\"M1002\"]}" }
            ],
            "params": { "statTypes": ["view", "like", "share"] }
        }
    }',
    'PENDING',
    '2026-05-11 16:00:00',
    'admin'
);
```

### 11.3 sub_task 表 — 子任务数据

```sql
INSERT INTO `sub_task` (
    `sub_task_code`, `parent_task_id`, `executor`, `business_key`,
    `sub_task_params`,
    `status`, `priority`
) VALUES
(
    'SUB_1715385601000_P001',
    1,
    'TaggingExecutor',
    'P20240501',
    '{
        "videoUrl": "https://oss.example.com/videos/p20240501.mp4",
        "title": "春季新品宣传片",
        "configKey": "ai1"
    }',
    'PENDING',
    5
),
(
    'SUB_1715385601000_P002',
    1,
    'TaggingExecutor',
    'P20240502',
    '{
        "videoUrl": "https://oss.example.com/videos/p20240502.mp4",
        "title": "夏季新品预告",
        "configKey": "ai1"
    }',
    'PENDING',
    5
);
```

**子任务执行完成（UPDATE）：**

```sql
UPDATE `sub_task` SET
    `status` = 'SUCCESS',
    `start_time` = '2026-05-11 14:00:10',
    `end_time` = '2026-05-11 14:05:20',
    `duration_ms` = 310000,
    `result` = '{"analysisResult":"{\"theme\":\"春季新品发布\",\"tags\":[\"时尚\",\"新品\",\"春季\"],\"sentiment\":\"positive\"}","durationMs":310000,"completedAt":"2026-05-11T14:05:20"}'
WHERE `id` = 1;
```