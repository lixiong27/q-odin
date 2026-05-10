# 数仓宽表接入技术方案

## 1. 需求概述

接入数仓提供的 `raw_content_info` 宽表，提供基础CRUD能力，并实现定时任务处理未同步数据。

## 2. 数据模型设计

### 2.1 本地表设计

直接使用数仓宽表结构，本地建表：

```sql
CREATE TABLE `raw_content_info` (
    `id`                        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '自增主键',

    -- 日期与内容标识
    `dt`                        DATE NOT NULL DEFAULT '1970-01-01' COMMENT '数据日期',
    `content_id`                VARCHAR(64) NOT NULL DEFAULT '' COMMENT '内容ID',
    `business_content_id`       VARCHAR(64) NOT NULL DEFAULT '' COMMENT '业务内容ID',

    -- 内容维度
    `content_title`             VARCHAR(500) NOT NULL DEFAULT '' COMMENT '内容标题',
    `content_text`              LONGTEXT COMMENT '内容文案/正文',
    `content_url`               TEXT COMMENT '内容URL，多个用英文逗号分隔',
    `video_cover_url`           VARCHAR(1024) NOT NULL DEFAULT '' COMMENT '视频封面URL',
    `content_type`              VARCHAR(32) NOT NULL DEFAULT '' COMMENT '内容形式：图文、短视频',

    -- 发布与平台
    `publish_platform`          VARCHAR(32) NOT NULL DEFAULT '' COMMENT '发布平台：小红书、抖音',
    `publish_time`              DATETIME NOT NULL DEFAULT '1970-01-01 00:00:00' COMMENT '发布时间',
    `publish_url`               VARCHAR(1024) NOT NULL DEFAULT '' COMMENT '发布链接',

    -- 业务与归因维度
    `business_line`             VARCHAR(64) NOT NULL DEFAULT '' COMMENT '业务线：本地生活、电商',
    `content_source`            VARCHAR(64) NOT NULL DEFAULT '' COMMENT '内容来源/大业务方向划分',
    `production_team`           VARCHAR(128) NOT NULL DEFAULT '' COMMENT '生产归属团队/投放团队/代理名称',
    `operation_project`         VARCHAR(128) NOT NULL DEFAULT '' COMMENT '运营项目',
    `placement_position`        VARCHAR(128) NOT NULL DEFAULT '' COMMENT '投放版位',

    -- 地理位置
    `city`                      VARCHAR(100) NOT NULL DEFAULT '' COMMENT '城市，多个用逗号分隔',
    `poi`                       VARCHAR(200) NOT NULL DEFAULT '' COMMENT 'POI，多个用逗号分隔',

    -- 曝光与点击指标
    `total_impressions`         INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '累计曝光量',
    `total_clicks`              INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '累计点击量',
    `total_reads`               INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '累计阅读量',
    `total_interactions`        INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '累计互动数',

    -- 完播与跳出率
    `completion_rate`           DECIMAL(5,4) NOT NULL DEFAULT 0.0000 COMMENT '完播率',
    `three_sec_completion_rate` DECIMAL(5,4) NOT NULL DEFAULT 0.0000 COMMENT '3s完播率',
    `five_sec_completion_rate`  DECIMAL(5,4) NOT NULL DEFAULT 0.0000 COMMENT '5s完播率',
    `two_sec_bounce_rate`       DECIMAL(5,4) NOT NULL DEFAULT 0.0000 COMMENT '2s跳出率',

    -- 成本与转化指标
    `cpm`                       DECIMAL(12,4) NOT NULL DEFAULT 0.0000 COMMENT '千次曝光成本(CPM)',
    `ctr`                       DECIMAL(5,4) NOT NULL DEFAULT 0.0000 COMMENT '点击率(CTR)',
    `cvr`                       DECIMAL(5,4) NOT NULL DEFAULT 0.0000 COMMENT '转化率(CVR)',

    -- App与用户增长指标
    `app_downloads`             INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'App下载量',
    `new_activations`           INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '新激活UV',
    `new_registrations`         INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '新注册UV',

    -- 引流与归因指标
    `drive_uv`                  INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '引流UV',
    `exposure_to_read_ratio`    DECIMAL(10,4) NOT NULL DEFAULT 0.0000 COMMENT '曝光/阅读引流比',
    `potential_new_uv`          INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '潜新UV',
    `potential_new_cac`         DECIMAL(12,2) NOT NULL DEFAULT 0.00 COMMENT '潜新CAC',
    `attributed_new_customers`  INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '归一新客量',
    `new_customer_cac`          DECIMAL(12,2) NOT NULL DEFAULT 0.00 COMMENT '新客CAC',

    -- 订单指标
    `order_uv`                  INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '累计下单UV',
    `total_orders`              INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '累计订单量',

    -- 同步与治理
    `sync_status`               TINYINT NOT NULL DEFAULT 0 COMMENT '同步状态：0-未同步，1-已同步，2-同步失败',

    -- 审计字段
    `create_time`               DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`               DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',

    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_dt_content` (`dt`, `content_id`),
    KEY `idx_content_id` (`content_id`),
    KEY `idx_business_content_id` (`business_content_id`),
    KEY `idx_publish_time` (`publish_time`),
    KEY `idx_publish_platform` (`publish_platform`),
    KEY `idx_business_line` (`business_line`),
    KEY `idx_sync_status_create_time` (`sync_status`,`create_time`),
    KEY `idx_biz_city_time` (`business_line`, `city`, `publish_time`)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='原始内容信息宽表';
```

### 2.2 Redis Key设计

| Key | 类型 | 说明 | TTL |
|-----|------|------|-----|
| `odin:raw_content:last_processed_id` | String | 最新已处理的ID | 永久 |

## 3. 接口设计

### 3.1 CRUD接口

#### 创建内容
```
POST /api/raw-content/create
Request: RawContentInfo对象
Response: { code: 0, message: "success", data: { id: 123 } }
```

#### 更新内容
```
POST /api/raw-content/update
Request: RawContentInfo对象（必须包含id）
Response: { code: 0, message: "success", data: true }
```

#### 删除内容
```
POST /api/raw-content/delete
Request: { id: 123 }
Response: { code: 0, message: "success", data: true }
```

#### 根据ID查询
```
GET /api/raw-content/get?id=123
Response: { code: 0, message: "success", data: RawContentInfo }
```

#### 分页查询
```
POST /api/raw-content/list
Request: {
    pageNum: 1,
    pageSize: 20,
    contentId: "",
    businessLine: "",
    publishPlatform: "",
    syncStatus: null,
    startTime: "",
    endTime: ""
}
Response: { code: 0, message: "success", data: { list: [], total: 100 } }
```

### 3.2 业务接口

#### 查询最新N条未同步数据
```
GET /api/raw-content/unsynchronized?limit=100
Response: { code: 0, message: "success", data: [RawContentInfo] }
```

#### 根据ID和状态查询
```
GET /api/raw-content/getByIdAndStatus?id=123&status=0
Response: { code: 0, message: "success", data: RawContentInfo }
```

#### 更新同步状态
```
POST /api/raw-content/updateSyncStatus
Request: { id: 123, syncStatus: 1 }
Response: { code: 0, message: "success", data: true }
```

## 4. 定时任务设计

### 4.1 任务配置

```properties
# raw_content.properties
raw.content.sync.cron=0 */5 * * * ?
raw.content.sync.batchSize=100
raw.content.sync.enabled=true
```

### 4.2 任务逻辑

```java
/**
 * 同步处理定时任务
 * 每5分钟执行一次，处理未同步数据
 */
@Scheduled(cron = "${raw.content.sync.cron}")
public void processUnsynchronizedData() {
    // 1. 从Redis获取最新已处理ID
    Long lastProcessedId = getLastProcessedId();

    // 2. 查询未同步数据
    List<RawContentInfo> dataList = queryUnsynchronizedData(lastProcessedId, batchSize);

    // 3. 遍历处理
    for (RawContentInfo data : dataList) {
        try {
            // 执行业务逻辑（空函数占位）
            executeBusinessLogic(data);

            // 更新状态为已同步
            updateSyncStatus(data.getId(), 1);

            // 更新Redis中的最新ID
            updateLastProcessedId(data.getId());
        } catch (Exception e) {
            // 更新状态为同步失败
            updateSyncStatus(data.getId(), 2);
        }
    }
}

/**
 * 业务逻辑处理（待实现）
 */
private void executeBusinessLogic(RawContentInfo data) {
    // TODO: 待定业务逻辑
}
```

## 5. 代码结构

```
service/
├── RawContentService.java              # 内容服务接口
├── impl/
│   └── RawContentServiceImpl.java      # 内容服务实现
├── schedule/
│   └── RawContentSyncJob.java          # 同步定时任务

domain/
├── entity/
│   └── RawContentInfo.java             # 实体类
├── request/
│   └── RawContentRequest.java          # 请求对象
├── response/
│   └── RawContentResponse.java         # 响应对象

dao/
└── RawContentDao.java                  # DAO接口

web/
└── RawContentController.java           # 控制器
```

## 6. 同步状态枚举

| 值 | 含义 |
|----|------|
| 0 | 未同步 |
| 1 | 已同步 |
| 2 | 同步失败 |

## 7. QConfig配置

### 7.1 raw_content.properties

```properties
# 同步任务开关
raw.content.sync.enabled=true

# 批量处理大小
raw.content.sync.batchSize=100
```

### 7.2 QSchedule配置

在QSchedule平台配置定时任务 `mkt_odin_raw_content_sync`，支持动态调整执行频率。

## 8. 额外接口

### 8.1 批量创建内容
```
POST /api/raw-content/batchCreate
Request: [RawContentInfo对象数组]
Response: { code: 0, message: "success", data: 10 }
```

### 8.2 根据contentId查询
```
GET /api/raw-content/getByContentId?contentId=xxx
Response: { code: 0, message: "success", data: RawContentInfo }
```

### 8.3 批量更新同步状态
```
POST /api/raw-content/batchUpdateSyncStatus
Request: { ids: [1, 2, 3], syncStatus: 1 }
Response: { code: 0, message: "success", data: true }
```

### 8.4 手动触发同步任务
```
GET /api/raw-content/triggerSync?limit=100
Response: { code: 0, message: "success", data: "Process completed, total=100, success=98, fail=2" }
```

## 9. 文件清单

| 文件 | 说明 |
|------|------|
| `domain/entity/raw/RawContentInfo.java` | 实体类 |
| `domain/request/raw/RawContentRequest.java` | 请求对象 |
| `domain/request/raw/BatchUpdateStatusRequest.java` | 批量更新状态请求 |
| `service/raw/RawContentService.java` | 服务接口 |
| `service/raw/impl/RawContentServiceImpl.java` | 服务实现 |
| `service/raw/enums/SyncStatus.java` | 同步状态枚举 |
| `infra/dao/RawContentInfoMapper.java` | Mapper接口 |
| `infra/qconfig/RawContentQConfig.java` | QConfig配置类 |
| `infra/redis/RawContentRedisService.java` | Redis服务 |
| `task/RawContentSyncTask.java` | 定时任务 |
| `web/RawContentController.java` | 控制器 |
| `resources/mapper/RawContentInfoMapper.xml` | Mapper XML |
