# AiResultBackFillHandler 重构 — 新的 AI 标签打标回填逻辑

## Context

当前 `DefaultLabelBackfillHandler` 以 `"defaultLabelBackfillHandler"` 的 bean name 注册，解析 AI 结果 JSON 中的 `aiTags`/`tags`/`detail` 字段直接写入 `content_label`。新的 AI 结果结构变为 `{"labels":{"标签名":置信度,...}}`，需要：

1. 回写 `ai_detail`（原始结果的 detail/explanation）
2. 遍历 labels keySet，批量查询匹配的叶子标签及其父分类
3. 根据 `tagRule`（selectMode / threshold / required）做逻辑
4. 过滤已停用的标签
5. 过滤不存在的标签
6. 接口名改为 `AiResultBackFillHandler`

## 改动清单

### 1. `LabelBackfillHandler.java` → `AiResultBackFillHandler.java`（接口重命名）

| 路径 | `odin_server/.../service/task/media/label/` |
|---|---|

- 重命名接口为 `AiResultBackFillHandler`（注意大小写：`BackFill` 驼峰）
- 新增 `getResultClassType()` 默认方法，返回用于 JSON 反序列化的 Class 类型
- `backfill()` 签名不变

```java
public interface AiResultBackFillHandler {
    void backfill(Long baseId, String aiResult, String taskId);
    
    default Class<?> getResultClassType() {
        return AiLabelResult.class;
    }
}
```

### 2. `AiLabelResult.java`（新的结果 DTO）

| 路径 | `odin_server/.../domain/entity/task/media/` |
|---|---|

- 接收新的 AI 结果结构 `{"labels":{"学生":1,"周边游":0.95,...}}`
- 其中 `labels` 为 `Map<String, Double>`（标签名 → 置信度）

```java
public class AiLabelResult {
    private Map<String, Double> labels;
    private String detail;       // AI 解析说明
    // getters/setters
}
```

### 3. `DefaultLabelBackfillHandler.java` → `AiResultBackFillHandlerImpl.java`（实现重写）

| 路径 | `odin_server/.../service/task/media/label/` |
|---|---|

- bean name: `"aiResultBackFillHandler"`
- 注入 `TagLeafMapper`、`TagCategoryMapper`、`TagCategoryService`
- `backfill()` 流程：

```java
1. 查已有 ContentLabel（保留 city/poi）
2. 解析 aiResult → AiLabelResult
3. 写入 ContentLabel: aiTagDetail = aiResult（原始 JSON），taskId
4. 如果 AiLabelResult.labels 为空 → 跳过标签匹配
5. 遍历 labels keySet：
   a. 按标签名批量查询 TagLeaf（selectByNameList）
   b. 过滤 status=0（已停用）的标签
   c. 按 categoryId 分组
   d. 对每个分类，读取 TagRule（threshold/selectMode/required）
   e. 根据 threshold 过滤置信度不足的标签
   f. 根据 selectMode 限制标签数量
   g. 根据 required 确保必有标签
6. 最终匹配的标签名写入 aiTag
```

### 4. `TagLeafMapper.xml` — 新增按名称列表批量查询

```xml
<select id="selectByNameList" resultMap="BaseResultMap">
    SELECT <include refid="Base_Column_List"/>
    FROM tag_leaf
    WHERE name IN
    <foreach collection="names" item="name" open="(" separator="," close=")">
        #{name}
    </foreach>
    AND deleted = 0
</select>
```

### 5. `TagLeafMapper.java` — 新增接口方法

```java
List<TagLeaf> selectByNameList(@Param("names") List<String> names);
```

### 6. `ContentMediaProcessor.java` — 更新 bean name 引用

- `backfillLabels()` 中 `labelBackfillHandlers.get("defaultLabelBackfillHandler")` → `"aiResultBackFillHandler"`

## 不修改

- `ContentLabelMapper.xml` — ON DUPLICATE KEY UPDATE 逻辑不变
- `ContentLabel` — entity 不变
- `TagCategoryMapper` / `TagLeafMapper` — 已有方法不变
- `TagCategoryService` — `getTagRule()` 已有

## 验证

1. `mvn compile` 编译通过
2. AI 返回 `{"labels":{"学生":1,"周边游":0.95}}` → 匹配标签名 → 按 threshold 过滤 → 写入 aiTag
3. 标签不存在 → 自动过滤
4. 标签已停用 → 自动过滤