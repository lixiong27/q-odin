# Redis 使用指南

## 客户端类型

本项目使用 `RedisAsyncClient`（qclient-redis），详见 [tec-components.md](tec-components.md#3-redis-操作)

## Redis Key 命名规范

| 模块 | Key 格式 | 说明 |
|------|---------|------|
| 通用 | `odin:common:xxx` | 通用缓存 |
| 原始内容 | `odin:raw_content:xxx` | 数据同步相关 |

## 现有服务

| 服务 | 说明 |
|------|------|
| `RedisUtil` | 通用 Redis 工具类 |
| `RawContentRedisService` | 原始内容同步 Redis 服务 |

## 注意事项

1. 使用 `RedisAsyncClient`，所有操作需调用 `.get()` 等待结果
2. 必须处理 `InterruptedException` 和 `ExecutionException`
3. 记录监控指标 `QMonitor.recordOne()`
