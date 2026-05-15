# 打标回填模块 — 设计文档

## 1. 背景

ContentTagExecutor 完成 AI 分析后，需要将分析结果持久化到 `content_label` 表。该表以 `base_id` 为幂等键（UNIQUE），存储 AI 标签结果。

打标回填模块是 ContentTagExecutor 流程的最后一环，需满足以下要求：

- **扩展性**：不同的业务方可能对 AI 结果有不同的解析和回填逻辑
- **幂等性**：同一内容重复执行不会产生重复标签
- **可追溯**：记录 taskId，可追踪每个标签的来源任务

## 2. 架构

```
AI 分析结果 (JSON String)
        │
        ▼
LabelBackfillHandler.backfill(baseId, aiResult, taskId)
        │
        ├── parseAiResult(aiResult) → AiLabelData
        │       ├── aiTag: JSON Array  (["景点", "美食"])
        │       ├── aiTagDetail: JSON Object  ({...})
        │       └── city / poi: 可选字段
        │
        ├── ContentLabel record = new ContentLabel()
        │       ├── baseId = baseId
        │       ├── aiTag = aiTag
        │       ├── aiTagDetail = aiTagDetail
        │       ├── taskId = taskId
        │       └── city / poi = 从 aiResult 中提取 或 ContentBase 中获取
        │
        └── contentLabelMapper.insertOrUpdate(record)
```

## 3. 接口定义

```java
public interface LabelBackfillHandler {
    /**
     * 打标回填
     *
     * @param baseId   content_base 主键
     * @param aiResult AI 分析结果 JSON
     * @param taskId   任务 ID（用于追溯）
     */
    void backfill(Long baseId, String aiResult, String taskId);
}
```

### 默认实现：DefaultLabelBackfillHandler

默认实现解析 AI 结果 JSON，提取以下字段：

| content_label 字段 | 来源 | 说明 |
|---|---|---|
| `base_id` | 参数 baseId | 幂等键（UNIQUE） |
| `ai_tag` | aiResult 中的 `aiTags` / `tags` 数组 | JSON 数组字符串，如 `["景点","美食"]` |
| `ai_tag_detail` | aiResult 中的 `detail` / 完整结果 | 完整分析结果 JSON |
| `task_id` | 参数 taskId | 来源任务追溯 |
| `city` | aiResult 中的 `city` 或 ContentBase | 可选 |
| `poi` | aiResult 中的 `poi` 或 ContentBase | 可选 |

#### AI 结果 JSON 格式约定（建议）

默认实现期望 AI 返回的 JSON 包含以下结构：

```json
{
  "aiTags": ["景点", "美食", "打卡"],
  "detail": {
    "主题": "城市美食探索",
    "关键元素": ["街头小吃", "网红餐厅"],
    "情感倾向": "正面"
  },
  "city": "北京",
  "poi": "三里屯"
}
```

若 AI 结果不包含 `aiTags` / `detail` 字段，则直接将整个 `aiResult` 存入 `ai_tag_detail`，`ai_tag` 留空（由业务方自行解析）。

## 4. 扩展点

通过 Spring `@Resource` + `Map<String, LabelBackfillHandler>` 注入，ContentMediaProcessor 按需选择 handler：

```java
@Component
public class ContentMediaProcessor extends AbstractMediaProcessor {

    @Resource
    private Map<String, LabelBackfillHandler> labelBackfillHandlers;

    private void backfillLabels(Long baseId, String aiResult, String taskId) {
        // 默认使用 defaultLabelBackfillHandler
        LabelBackfillHandler handler = labelBackfillHandlers.get("defaultLabelBackfillHandler");
        if (handler != null) {
            handler.backfill(baseId, aiResult, taskId);
        }
    }
}
```

### 如何扩展

1. 实现 `LabelBackfillHandler` 接口
2. 注册为 Spring Component（如 `@Component("customLabelBackfillHandler")`）
3. 在 QConfig executor params 中指定 `labelBackfillHandler: "customLabelBackfillHandler"`
4. ContentMediaProcessor 根据配置选择 handler

## 5. 数据库设计

### content_label 表

```sql
CREATE TABLE content_label (
    id           BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '自增主键',
    base_id      BIGINT       NOT NULL COMMENT 'content_base主键（幂等键，UNIQUE）',
    city         VARCHAR(100) DEFAULT '' COMMENT '城市',
    poi          VARCHAR(500) DEFAULT '' COMMENT 'POI',
    ai_tag       TEXT         COMMENT 'AI标签JSON数组',
    ai_tag_detail MEDIUMTEXT  COMMENT 'AI标签详情',
    task_id      VARCHAR(64)  DEFAULT '' COMMENT 'AI任务ID',
    ext_param    VARCHAR(500) DEFAULT '' COMMENT '扩展参数JSON',
    create_time  DATETIME     DEFAULT CURRENT_TIMESTAMP,
    update_time  DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_base_id (base_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='内容标签表';
```

### MyBatis insertOrUpdate

当前 SQL 使用 `ON DUPLICATE KEY UPDATE`，仅更新 `city` / `poi`：

```xml
<insert id="insertOrUpdate" parameterType="com.qunar.ug.flight.contact.odin.server.domain.entity.raw.ContentLabel">
    INSERT INTO content_label (base_id, city, poi, ai_tag, ai_tag_detail, task_id, ext_param)
    VALUES (#{baseId}, #{city}, #{poi}, #{aiTag}, #{aiTagDetail}, #{taskId}, #{extParam})
    ON DUPLICATE KEY UPDATE
        city = VALUES(city),
        poi = VALUES(poi)
</insert>
```

> 注意：ai_tag / ai_tag_detail / task_id 在重复执行时**不覆盖**，因为同一 base_id 的 AI 标签理论上应保持不变。如果业务方需要覆盖，可以在自定义 LabelBackfillHandler 中直接调用 ContentLabelMapper 的扩展方法。

## 6. 错误处理

| 场景 | 处理方式 |
|---|---|
| AI 结果为 null 或空 | 跳过回填，记录 WARN 日志 |
| AI 结果 JSON 解析失败 | 跳过 aiTag 解析，将原始结果存入 ai_tag_detail |
| insertOrUpdate 抛异常 | 抛出运行时异常，触发子任务 fail 和重试 |
| 重复执行（幂等） | base_id UNIQUE 约束保证无重复记录 |

## 7. 与现有 MediaInfoExecutor 对比

| 维度 | MediaInfoExecutor | ContentTagExecutor |
|---|---|---|
| 结果存储 | 无持久化，仅作为任务结果返回 | 持久化到 content_label 表 |
| 解析逻辑 | 无解析，原始结果返回 | 解析 AI 结果 JSON，提取结构化标签 |
| 幂等 | 不涉及 | base_id UNIQUE 保证幂等 |
| 可追溯 | 不涉及 | taskId 记录来源 |

## 8. 未来优化方向

1. **多 Handler 链**: 支持多个 LabelBackfillHandler 串行执行，如一个提取标签、一个发送通知
2. **AI 结果 Schema 注册**: 各业务方注册自己的 AI 结果 JSON Schema，自动解析
3. **回填补偿**: 子任务成功后异步验证 content_label 是否写入，缺失则补偿
4. **标签版本管理**: 同一 base_id 支持多次打标，保留历史版本