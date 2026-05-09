# 后端 ES 能力接入设计

## 一、需求概述

**目标**：实现 Elasticsearch 基础能力，支持批量插入、查询等操作。

**输入**：实体对象列表
**输出**：操作结果

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
│    - 生成文档ID   │
│    - 序列化为JSON │
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
├── config/
│   └── ElasticsearchConfig.java           # ES Client 配置
├── infra/
│   └── elasticsearch/
│       └── ElasticsearchDataSource.java   # ES 通用操作封装
├── service/
│   └── es/
│       └── EsDemoService.java             # Demo 服务
├── domain/
│   ├── entity/es/
│   │   └── DemoEntity.java                # Demo 实体
│   ├── request/es/
│   │   └── EsBatchInsertRequest.java      # 批量插入请求
│   └── response/es/
│       └── EsBatchInsertResponse.java     # 批量插入响应
└── web/
    └── EsDemoController.java              # Demo 控制器
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

```java
package com.qunar.ug.flight.contact.odin.server.infra.config;

import com.qunar.ug.flight.contact.odin.server.infra.qconfig.HotFileQConfig;
import lombok.extern.slf4j.Slf4j;
import org.apache.http.HttpHost;
import org.apache.http.auth.AuthScope;
import org.apache.http.auth.UsernamePasswordCredentials;
import org.apache.http.impl.client.BasicCredentialsProvider;
import org.elasticsearch.client.RestClient;
import org.elasticsearch.client.RestClientBuilder;
import org.elasticsearch.client.RestHighLevelClient;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import javax.annotation.Resource;
import java.net.URI;

/**
 * ES 配置类
 */
@Slf4j
@Configuration
public class ElasticsearchConfig {

    @Resource
    private HotFileQConfig hotFileQConfig;

    @Bean
    public RestHighLevelClient restHighLevelClient() {
        String uris = hotFileQConfig.getString("spring.elasticsearch.rest.uris", "http://localhost:9200");
        String username = hotFileQConfig.getString("spring.elasticsearch.rest.username", "");
        String password = hotFileQConfig.getString("spring.elasticsearch.rest.password", "");

        URI uri = URI.create(uris);
        HttpHost httpHost = new HttpHost(uri.getHost(), uri.getPort(), uri.getScheme());

        RestClientBuilder builder = RestClient.builder(httpHost);

        // 配置认证
        if (!username.isEmpty()) {
            BasicCredentialsProvider credentialsProvider = new BasicCredentialsProvider();
            credentialsProvider.setCredentials(AuthScope.ANY,
                    new UsernamePasswordCredentials(username, password));

            builder.setHttpClientConfigCallback(httpClientBuilder ->
                    httpClientBuilder.setDefaultCredentialsProvider(credentialsProvider));
        }

        log.info("Initializing RestHighLevelClient with uri: {}", uris);
        return new RestHighLevelClient(builder);
    }
}
```

#### 3.3.2 ElasticsearchDataSource.java

```java
package com.qunar.ug.flight.contact.odin.server.infra.elasticsearch;

import com.qunar.flight.qmonitor.QMonitor;
import lombok.extern.slf4j.Slf4j;
import org.elasticsearch.action.admin.indices.create.CreateIndexRequest;
import org.elasticsearch.action.admin.indices.create.CreateIndexResponse;
import org.elasticsearch.action.admin.indices.get.GetIndexRequest;
import org.elasticsearch.client.RequestOptions;
import org.elasticsearch.client.RestHighLevelClient;
import org.elasticsearch.common.settings.Settings;
import org.elasticsearch.common.xcontent.XContentType;
import org.springframework.stereotype.Component;

import javax.annotation.Resource;
import java.io.IOException;

/**
 * ES 数据源通用操作
 */
@Slf4j
@Component
public class ElasticsearchDataSource {

    @Resource
    private RestHighLevelClient restHighLevelClient;

    /**
     * 检查索引是否存在
     */
    public boolean existIndex(String indexName) {
        try {
            GetIndexRequest request = new GetIndexRequest(indexName);
            return restHighLevelClient.indices().exists(request, RequestOptions.DEFAULT);
        } catch (IOException e) {
            log.error("检查索引存在失败: {}", indexName, e);
            return false;
        }
    }

    /**
     * 创建索引
     */
    public boolean createIndex(String indexName, String settings, String mappings) {
        try {
            CreateIndexRequest request = new CreateIndexRequest(indexName);

            if (settings != null && !settings.isEmpty()) {
                request.settings(settings, XContentType.JSON);
            }
            if (mappings != null && !mappings.isEmpty()) {
                request.mapping(mappings, XContentType.JSON);
            }

            CreateIndexResponse response = restHighLevelClient.indices()
                    .create(request, RequestOptions.DEFAULT);
            log.info("创建索引成功: {}", indexName);
            return response.isAcknowledged();
        } catch (IOException e) {
            QMonitor.recordOne("es_create_index_error");
            log.error("创建索引失败: {}", indexName, e);
            return false;
        }
    }
}
```

#### 3.3.3 EsDemoService.java

```java
package com.qunar.ug.flight.contact.odin.server.service.es;

import com.qunar.flight.qmonitor.QMonitor;
import com.qunar.ug.flight.contact.odin.server.infra.elasticsearch.ElasticsearchDataSource;
import com.qunar.ug.flight.contact.odin.server.infra.qconfig.HotFileQConfig;
import com.qunar.ug.flight.contact.odin.server.infra.util.JsonUtils;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.collections4.CollectionUtils;
import org.elasticsearch.action.bulk.BulkRequest;
import org.elasticsearch.action.bulk.BulkResponse;
import org.elasticsearch.action.index.IndexRequest;
import org.elasticsearch.client.RequestOptions;
import org.elasticsearch.client.RestHighLevelClient;
import org.elasticsearch.common.xcontent.XContentType;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * ES Demo 服务
 */
@Slf4j
@Service
public class EsDemoService {

    @Resource
    private RestHighLevelClient restHighLevelClient;

    @Resource
    private ElasticsearchDataSource elasticsearchDataSource;

    @Resource
    private HotFileQConfig hotFileQConfig;

    private static final DateTimeFormatter DATE_FORMATTER = DateTimeFormatter.ofPattern("yyyyMMdd");

    /**
     * 批量插入数据
     */
    public void batchInsert(String indexPrefix, List<?> dataList) {
        if (CollectionUtils.isEmpty(dataList)) {
            log.info("批量插入数据为空");
            return;
        }

        // 按类型分组处理
        Map<Class<?>, List<?>> groupedData = dataList.stream()
                .collect(Collectors.groupingBy(Object::getClass));

        for (Map.Entry<Class<?>, List<?>> entry : groupedData.entrySet()) {
            doBatchInsert(indexPrefix, entry.getValue());
        }
    }

    private void doBatchInsert(String indexPrefix, List<?> dataList) {
        // 构建索引名（按日期分片）
        String indexName = buildIndexName(indexPrefix);

        // 检查并创建索引
        ensureIndexExists(indexName);

        // 构建批量请求
        BulkRequest bulkRequest = new BulkRequest();
        for (Object data : dataList) {
            if (data == null) {
                continue;
            }
            String id = UUID.randomUUID().toString();
            String json = JsonUtils.toJson(data);
            IndexRequest request = new IndexRequest(indexName)
                    .id(id)
                    .source(json, XContentType.JSON);
            bulkRequest.add(request);
        }

        if (bulkRequest.requests().isEmpty()) {
            log.warn("批量插入数据为空");
            return;
        }

        // 执行批量插入
        try {
            BulkResponse response = restHighLevelClient.bulk(bulkRequest, RequestOptions.DEFAULT);
            log.info("批量插入完成, index: {}, size: {}", indexName, dataList.size());

            if (response.hasFailures()) {
                QMonitor.recordOne("es_batch_insert_fail");
                log.error("批量插入失败: {}", response.buildFailureMessage());
            } else {
                QMonitor.recordMany("es_batch_insert_success", dataList.size(), 0);
            }
        } catch (Exception e) {
            QMonitor.recordOne("es_batch_insert_exception");
            log.error("批量插入异常", e);
            throw new RuntimeException("批量插入失败: " + e.getMessage(), e);
        }
    }

    private String buildIndexName(String indexPrefix) {
        String dateSuffix = LocalDate.now().format(DATE_FORMATTER);
        return indexPrefix + "_" + dateSuffix;
    }

    private void ensureIndexExists(String indexName) {
        if (!elasticsearchDataSource.existIndex(indexName)) {
            String settings = buildDefaultSettings();
            String mappings = buildDefaultMappings();
            boolean created = elasticsearchDataSource.createIndex(indexName, settings, mappings);
            if (!created) {
                throw new RuntimeException("创建索引失败: " + indexName);
            }
        }
    }

    private String buildDefaultSettings() {
        int shards = hotFileQConfig.getInt("es.index.shards", 3);
        int replicas = hotFileQConfig.getInt("es.index.replicas", 1);
        return String.format("{\"number_of_shards\": %d, \"number_of_replicas\": %d}", shards, replicas);
    }

    private String buildDefaultMappings() {
        return "{\"properties\": {" +
                "\"createTime\": {\"type\": \"date\", \"format\": \"yyyy-MM-dd HH:mm:ss\"}," +
                "\"updateTime\": {\"type\": \"date\", \"format\": \"yyyy-MM-dd HH:mm:ss\"}" +
                "}}";
    }
}
```

---

## 四、监控指标

| 指标名 | 说明 |
|--------|------|
| es_create_index_error | 创建索引失败次数 |
| es_batch_insert_success | 批量插入成功次数 |
| es_batch_insert_fail | 批量插入失败次数 |
| es_batch_insert_exception | 批量插入异常次数 |

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
