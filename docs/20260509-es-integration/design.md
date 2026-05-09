# 后端 ES 能力接入设计

## 一、需求概述

**目标**：实现 Elasticsearch 基础能力，支持批量插入、查询等操作。

**输入**：实体对象列表
**输出**：操作结果

**参考项目**：poseidon-superman

---

## 二、技术方案

### 2.1 核心依赖

```xml
<!-- Elasticsearch -->
<dependency>
    <groupId>org.elasticsearch.client</groupId>
    <artifactId>elasticsearch-rest-high-level-client</artifactId>
    <version>7.10.2</version>
</dependency>
<dependency>
    <groupId>org.elasticsearch</groupId>
    <artifactId>elasticsearch</artifactId>
    <version>7.10.2</version>
</dependency>
<!-- Gson -->
<dependency>
    <groupId>com.google.code.gson</groupId>
    <artifactId>gson</artifactId>
    <version>2.8.9</version>
</dependency>
```

### 2.2 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                         Controller                          │
│  POST /api/es/demo/batchInsert                              │
│  请求: { "items": [...] }                                   │
│  响应: { "code": 0, "msg": "success" }                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                         Service                             │
│  EsDemoService                                              │
│  1. 构建索引名（按日期分片）                                 │
│  2. 检查/创建索引                                           │
│  3. 批量插入数据                                            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Infrastructure                         │
│  RestHighLevelClient (ES Client)                           │
│  ElasticsearchDataSource (通用 ES 操作封装)                  │
│  HotFileQConfig (配置项)                                    │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 核心流程

```
数据输入
    │
    ▼
┌──────────────────┐
│ 1. 构建索引名     │
│    - 按日期分片   │
│    - prefix_date │
└──────────────────┘
    │
    ▼
┌──────────────────┐
│ 2. 检查索引存在   │
│    - 存在则跳过   │
│    - 不存在则创建 │
└──────────────────┘
    │
    ▼
┌──────────────────┐
│ 3. 构建 BulkRequest│
│    - Gson序列化   │
│    - 无文档ID     │
└──────────────────┘
    │
    ▼
┌──────────────────┐
│ 4. 执行批量插入   │
│    - 调用 ES API │
│    - 处理响应结果 │
└──────────────────┘
    │
    ▼
返回结果
```

---

## 三、实现细节

### 3.1 文件结构

```
odin_server/mkt_odin_server_web/src/main/java/com/qunar/ug/flight/contact/odin/server/
├── infra/
│   ├── config/
│   │   └── ElasticsearchConfig.java        # ES Client 配置
│   └── elasticsearch/
│       └── ElasticsearchDataSource.java    # ES 通用操作封装
├── service/
│   └── es/
│       └── EsDemoService.java              # Demo 服务
├── domain/
│   ├── entity/es/
│   │   └── DemoEntity.java                 # Demo 实体
│   ├── request/es/
│   │   └── EsBatchInsertRequest.java       # 批量插入请求
│   └── response/es/
│       └── EsBatchInsertResponse.java      # 批量插入响应
└── web/
    └── EsDemoController.java               # Demo 控制器
```

### 3.2 配置项 (hotfile.properties)

```properties
# ES 连接配置
spring.elasticsearch.rest.uris=http://your-es-endpoint:9200/
spring.elasticsearch.rest.username=your_username
spring.elasticsearch.rest.password=your_password

# ES 索引配置
es.index.prefix=odin
es.index.shards=3
es.index.replicas=1
```

### 3.3 核心代码

#### 3.3.1 ElasticsearchConfig.java

参考 superman `ElasticsearchRestClientConfigurations` 实现：

- 使用 `RestClientBuilderCustomizer` 扩展配置
- 使用 `ElasticsearchRestClientProperties` 读取配置
- 添加失败监听器

```java
@Configuration
public class ElasticsearchConfig {

    @Bean
    public RestClientBuilderCustomizer selfRestClientBuilderCustomizer() {
        return new RestClientBuilderCustomizer() {
            @Override
            public void customize(RestClientBuilder builder) {
                builder.setFailureListener(new RestClient.FailureListener() {
                    @Override
                    public void onFailure(Node node) {
                        log.warn("ES 节点发生异常 node={}", node);
                        QMonitor.recordOne("es_node_error_" + node.getHost().getHostName());
                    }
                });
            }
        };
    }

    @Bean
    RestClientBuilder elasticsearchRestClientBuilder(
            ElasticsearchRestClientProperties properties,
            ObjectProvider<RestClientBuilderCustomizer> builderCustomizers) {
        // ...
    }
}
```

#### 3.3.2 ElasticsearchDataSource.java

参考 superman `ElasticsearchDataSourceImpl` 实现：

```java
@Component
public class ElasticsearchDataSource {

    private static final Gson GSON = new Gson();

    @Resource
    private RestHighLevelClient restHighLevelClient;

    public boolean create(String index, String settings, String mapping) {
        // 创建索引
    }

    public boolean existIndex(String index) {
        // 检查索引是否存在
    }

    public <T> boolean batchInsert(String index, List<T> dataLists) {
        // 批量插入，使用 Gson 序列化
        BulkRequest request = new BulkRequest();
        transform(index, dataLists).forEach(request::add);
        // ...
    }

    private <T> List<IndexRequest> transform(String index, List<T> dataLists) {
        return dataLists.stream()
                .map(data -> new IndexRequest(index)
                        .source(GSON.toJson(data), XContentType.JSON))
                .filter(Objects::nonNull)
                .collect(Collectors.toList());
    }
}
```

#### 3.3.3 EsDemoService.java

参考 superman `ErrorLocateService` 实现：

```java
@Service
public class EsDemoService {

    @Resource
    private ElasticsearchDataSource elasticsearchDataSource;

    public void batchInsert(String indexPrefix, List<?> dataList) {
        // 按类型分组
        Map<Class<?>, List<?>> groupedData = dataList.stream()
                .collect(Collectors.groupingBy(Object::getClass));

        for (Map.Entry<Class<?>, List<?>> entry : groupedData.entrySet()) {
            doBatchInsert(indexPrefix, entry.getValue());
        }
    }

    private void doBatchInsert(String indexPrefix, List<?> dataList) {
        String index = buildIndexName(indexPrefix);
        ensureIndexExists(index);
        elasticsearchDataSource.batchInsert(index, dataList);
    }
}
```

---

## 四、监控指标

| 指标名 | 说明 |
|--------|------|
| es_create_index | 创建索引次数 |
| es_create_index_error | 创建索引失败次数 |
| es_exist_index_error | 检查索引存在失败次数 |
| es_batch_insert | 批量插入次数 |
| es_batch_insert_error | 批量插入异常次数 |
| es_batch_insert_failure | 批量插入失败次数 |
| es_demo_batch_insert_success | Demo 批量插入成功次数 |
| es_demo_batch_insert_fail | Demo 批量插入失败次数 |

---

## 五、配置示例

### hotfile.properties

```properties
# ==================== ES Connection Config ====================
# ES endpoint URL
spring.elasticsearch.rest.uris=http://your-es-endpoint:9200/

# ES credentials
spring.elasticsearch.rest.username=your_username
spring.elasticsearch.rest.password=your_password

# ==================== ES Index Config ====================
# Index name prefix
es.index.prefix=odin

# Number of shards
es.index.shards=3

# Number of replicas
es.index.replicas=1
```

---

## 六、后续扩展

1. **查询能力**：支持复杂查询、聚合查询
2. **删除能力**：支持按条件删除
3. **更新能力**：支持部分更新
4. **索引模板**：支持动态索引模板
5. **异步批量插入**：大容量数据异步处理
