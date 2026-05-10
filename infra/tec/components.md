# 技术组件使用指南

## 1. QConfig 动态配置

### 配置类模板

```java
@Slf4j
@Service
public class XxxQConfig {

    private volatile int batchSize = 100;
    private volatile boolean enabled = true;

    @QConfig("xxx.properties")
    private void onChanged(Map<String, String> map) {
        if (map == null) {
            return;
        }
        try {
            String batchSizeStr = map.get("xxx.batch.size");
            if (StringUtils.isNotBlank(batchSizeStr)) {
                batchSize = Integer.parseInt(batchSizeStr);
            }
            String enabledStr = map.get("xxx.enabled");
            if (StringUtils.isNotBlank(enabledStr)) {
                enabled = Boolean.parseBoolean(enabledStr);
            }
        } catch (Exception e) {
            log.error("Failed to parse qconfig", e);
        }
    }

    public int getBatchSize() {
        return batchSize;
    }

    public boolean isEnabled() {
        return enabled;
    }
}
```

### properties 文件示例

```properties
# xxx.properties
xxx.batch.size=100
xxx.enabled=true
```

### 使用 HotFileQConfig（通用配置读取）

```java
@Resource
private HotFileQConfig hotFileQConfig;

// 读取配置
int shards = hotFileQConfig.getInt("es.index.shards", 3);  // 默认值 3
String value = hotFileQConfig.getString("key", "default");
```

## 2. QSchedule 定时任务

### 任务类模板

```java
@Service
public class XxxSyncTask {

    private static final Logger LOG = LoggerFactory.getLogger(XxxSyncTask.class);

    // 单线程执行器
    private static final int N_THREADS = 1;
    private static final ExecutorService EXECUTOR = new ThreadPoolExecutor(
            N_THREADS, Integer.MAX_VALUE, 0L, TimeUnit.MILLISECONDS,
            new LinkedBlockingQueue<>(),
            new ThreadFactoryBuilder().setDaemon(true).setNameFormat("Xxx-Sync-%d").build());

    @Resource
    private XxxService xxxService;

    @Resource
    private XxxQConfig xxxQConfig;

    /**
     * 定时任务入口
     */
    @QSchedule("task_name")
    public void syncTask(Parameter param) {
        LOG.info("Task start");
        final TaskMonitor monitor = TaskHolder.getKeeper();

        // 检查是否启用
        if (!xxxQConfig.isEnabled()) {
            monitor.getLogger().info("Task is disabled");
            return;
        }

        // 关闭自动确认
        monitor.autoAck(false);

        // 异步执行
        EXECUTOR.submit(() -> {
            try {
                doTask(monitor);
            } catch (Exception e) {
                LOG.error("Task error", e);
            } finally {
                if (!monitor.isStopped()) {
                    monitor.finish();
                }
            }
        });
    }

    private void doTask(TaskMonitor monitor) {
        int batchSize = xxxQConfig.getBatchSize();

        // 设置处理总量
        monitor.setRateCapacity(batchSize);

        // 业务处理...
        for (Item item : items) {
            try {
                process(item);
                monitor.addRate(1);  // 进度+1
            } catch (Exception e) {
                LOG.error("Process error", e);
                QMonitor.recordOne("task_process_fail");
            }
        }
    }
}
```

### 关键点

1. 使用 `@QSchedule("task_name")` 注解
2. 通过 `TaskHolder.getKeeper()` 获取 monitor
3. 调用 `monitor.autoAck(false)` 关闭自动确认
4. 在 finally 中调用 `monitor.finish()`
5. 使用 `monitor.setRateCapacity()` 和 `monitor.addRate()` 跟踪进度

## 3. Redis 操作

### RedisAsyncClient 模板

```java
@Slf4j
@Component
public class XxxRedisService {

    private static final String KEY_PREFIX = "odin:xxx:";

    @Resource
    private RedisAsyncClient redisAsyncClient;

    /**
     * 获取值
     */
    public String get(String key) {
        long startTime = System.nanoTime();
        try {
            return (String) redisAsyncClient.get(key).get();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            QMonitor.recordOne("redis_get_error");
        } catch (ExecutionException e) {
            QMonitor.recordOne("redis_get_error");
        } finally {
            QMonitor.recordOne("redis_get", System.nanoTime() - startTime);
        }
        return null;
    }

    /**
     * 设置值（永久）
     */
    public void set(String key, String value) {
        long startTime = System.nanoTime();
        try {
            redisAsyncClient.set(key, value).get();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            QMonitor.recordOne("redis_set_error");
        } catch (ExecutionException e) {
            QMonitor.recordOne("redis_set_error");
        } finally {
            QMonitor.recordOne("redis_set", System.nanoTime() - startTime);
        }
    }

    /**
     * 设置值（带过期时间）
     */
    public void setex(String key, int seconds, String value) {
        try {
            redisAsyncClient.setex(key, seconds, value).get();
        } catch (Exception e) {
            log.warn("Redis setex error", e);
        }
    }

    /**
     * 删除
     */
    public void del(String key) {
        try {
            redisAsyncClient.del(key).get();
        } catch (Exception e) {
            log.warn("Redis del error", e);
        }
    }

    /**
     * 判断存在
     */
    public boolean exists(String key) {
        try {
            return redisAsyncClient.exists(key).get();
        } catch (Exception e) {
            log.warn("Redis exists error", e);
        }
        return false;
    }
}
```

### 关键点

1. 使用 `RedisAsyncClient`，调用 `.get()` 等待结果
2. 处理 `InterruptedException` 时调用 `Thread.currentThread().interrupt()`
3. 使用 `QMonitor` 记录监控指标
4. 记录耗时用于性能分析

## 4. MyBatis Mapper

### Mapper 接口

```java
@Mapper
public interface XxxMapper {

    int insert(XxxEntity entity);

    int update(XxxEntity entity);

    int deleteById(@Param("id") Long id);

    XxxEntity selectById(@Param("id") Long id);

    List<XxxEntity> selectByCondition(@Param("field1") String field1,
                                       @Param("field2") Integer field2);

    int countByCondition(@Param("field1") String field1);
}
```

### Mapper XML 位置

```
resources/mapper/XxxMapper.xml
```

## 5. QMonitor 监控

```java
// 计数
QMonitor.recordOne("metric_name");
QMonitor.recordMany("metric_name", count, 0);

// 耗时
long startTime = System.nanoTime();
// ... 操作
QMonitor.recordOne("metric_name", System.nanoTime() - startTime);
```

## 6. Elasticsearch

```java
@Resource
private RestHighLevelClient restHighLevelClient;

@Resource
private ElasticsearchDataSource elasticsearchDataSource;

// 批量插入
elasticsearchDataSource.batchInsert(index, dataList);

// 检查索引存在
elasticsearchDataSource.existIndex(index);

// 创建索引
elasticsearchDataSource.create(index, settings, mapping);
```
