# 工程上下文导航

## 技术组件

| 组件            | 说明                      | 文档                                                            |
| ------------- | ----------------------- | ------------------------------------------------------------- |
| 代码规范          | 响应对象、请求对象、Controller 模式 | [tec/coding-style.md](infra/tec/coding-style.md)              |
| QConfig       | 动态配置中心                  | [tec/components.md](infra/tec/components.md#1-qconfig-动态配置)   |
| QSchedule     | 定时任务调度                  | [tec/components.md](infra/tec/components.md#2-qschedule-定时任务) |
| Redis         | 缓存、分布式锁                 | [tec/redis.md](infra/tec/redis.md)                            |
| MyBatis       | ORM 框架                  | [tec/components.md](infra/tec/components.md#4-mybatis-mapper) |
| JsonUtils     | JSON 工具类                | [tec/components.md](infra/tec/components.md#5-jsonutils-工具类)  |
| HttpUtils     | HTTP 客户端(QunarAsyncClient) | [tec/components.md](infra/tec/components.md#8-httputils-http客户端) |
| Elasticsearch | 搜索引擎                    | [tec/components.md](infra/tec/components.md#7-elasticsearch)  |

## 业务模块

| 模块    | 说明               |
| ----- | ---------------- |
| 标签管理  | 标签分类 + 叶子标签 CRUD |
| 原始内容  | 数仓宽表同步 + CRUD    |
| AI 服务 | ASR 转写 + 图像理解    |
