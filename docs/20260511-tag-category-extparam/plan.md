# 标签分类打标规则扩展实现计划

## 需求背景

末级分类下的叶子标签需要支持打标规则配置：
- 单选/多选（AiTagSelectMode）
- 是否必填
- 匹配度阈值

后续可扩展，本次只接入 tagRule。

---

## 实现方案

### 1. 数据库变更

文件：`odin_server/docs/sql/tag_schema.sql`

```sql
ALTER TABLE tag_category 
ADD COLUMN select_mode VARCHAR(16) DEFAULT 'MULTIPLE' COMMENT '打标选择模式：SINGLE-单选，MULTIPLE-多选',
ADD COLUMN required TINYINT(1) DEFAULT 0 COMMENT '打标是否必填：0-否，1-是',
ADD COLUMN threshold DECIMAL(5,4) DEFAULT 0.7000 COMMENT '匹配度阈值，默认0.7',
ADD COLUMN ext_param TEXT DEFAULT NULL COMMENT '扩展参数JSON，存储tagRule等扩展配置';
```

### 2. 枚举类

路径：`odin_server/mkt_odin_server_web/src/main/java/com/qunar/ug/flight/contact/odin/server/domain/enums/AiTagSelectMode.java`

```java
public enum AiTagSelectMode {
    SINGLE("单选"),
    MULTIPLE("多选");

    private final String desc;
    AiTagSelectMode(String desc) { this.desc = desc; }
    public String getDesc() { return desc; }
}
```

### 3. TagRule 领域对象

路径：`odin_server/mkt_odin_server_web/src/main/java/com/qunar/ug/flight/contact/odin/server/domain/dto/tag/TagRule.java`

```java
@Data
public class TagRule {
    /** 单选/多选 */
    private AiTagSelectMode selectMode;
    
    /** 是否必填：0-否，1-是 */
    private Integer required;
    
    /** 匹配度阈值，默认0.7 */
    private BigDecimal threshold;
}
```

### 4. Entity 变更

文件：`TagCategory.java`

新增字段：
```java
/** 打标选择模式：SINGLE/MULTIPLE */
private String selectMode;

/** 打标是否必填：0-否，1-是 */
private Integer required;

/** 匹配度阈值 */
private BigDecimal threshold;

/** 扩展参数JSON */
private String extParam;
```

### 5. Request 变更

文件：`CategoryCreateRequest.java` 和 `CategoryUpdateRequest.java`

新增字段：
```java
/** 打标选择模式：SINGLE/MULTIPLE */
private String selectMode;

/** 打标是否必填：0-否，1-是 */
private Integer required;

/** 匹配度阈值 */
private BigDecimal threshold;
```

### 6. Service 层

文件：`TagCategoryService.java`

#### 6.1 创建/更新时组装 extParam

```java
public Long createCategory(CategoryCreateRequest request) {
    // ... 现有逻辑 ...
    
    // 组装 extParam
    TagRule tagRule = new TagRule();
    tagRule.setSelectMode(StringUtils.isBlank(request.getSelectMode()) 
        ? AiTagSelectMode.MULTIPLE 
        : AiTagSelectMode.valueOf(request.getSelectMode()));
    tagRule.setRequired(request.getRequired() != null ? request.getRequired() : 0);
    tagRule.setThreshold(request.getThreshold() != null ? request.getThreshold() : new BigDecimal("0.70"));
    
    Map<String, Object> extParamMap = new HashMap<>();
    extParamMap.put("tagRule", tagRule);
    category.setExtParam(JsonUtils.objectToJson(extParamMap));
    
    // ... 保存逻辑 ...
}
```

#### 6.2 获取 TagRule

```java
public TagRule getTagRule(Long categoryId) {
    TagCategory category = tagCategoryMapper.selectById(categoryId);
    if (category == null || StringUtils.isBlank(category.getExtParam())) {
        return null;
    }
    
    Map<String, Object> extParamMap = JsonUtils.jsonToObject(category.getExtParam(), Map.class);
    if (extParamMap == null || !extParamMap.containsKey("tagRule")) {
        return null;
    }
    
    return JsonUtils.mapToObject((Map<String, Object>) extParamMap.get("tagRule"), TagRule.class);
}
```

### 7. Mapper 层

文件：`TagCategoryMapper.xml`

更新 resultMap，新增字段映射：
```xml
<result column="select_mode" property="selectMode"/>
<result column="required" property="required"/>
<result column="threshold" property="threshold"/>
<result column="ext_param" property="extParam"/>
```

### 8. QConfig 配置

文件：`hotfile.properties`

```properties
# 打标多选模式下的最大标签数
tagging.max.multiple.tags=10
```

### 9. Controller 层

文件：`TagCategoryController.java`

新增接口：
```java
@GetMapping("/{id}/tagRule")
public ResponseEntity<TagRule> getTagRule(@PathVariable Long id) {
    TagRule tagRule = tagCategoryService.getTagRule(id);
    return ResponseEntity.ok(tagRule);
}

@PutMapping("/{id}/tagRule")
public ResponseEntity<Void> updateTagRule(@PathVariable Long id, @RequestBody TagRule tagRule) {
    tagCategoryService.updateTagRule(id, tagRule);
    return ResponseEntity.ok().build();
}
```

### 10. 打标结果校验（Task 模块）

路径：`odin_server/mkt_odin_server_web/src/main/java/com/qunar/ug/flight/contact/odin/server/service/task/validator/TagRuleValidator.java`

```java
@Component
public class TagRuleValidator {
    
    @Resource
    private TagCategoryService tagCategoryService;
    
    @Resource
    private HotFileQConfig hotFileQConfig;
    
    public boolean isValid(List<String> selectedTagCodes, Long categoryId) {
        TagRule rule = tagCategoryService.getTagRule(categoryId);
        if (rule == null) {
            return true; // 无规则，默认通过
        }
        
        // 必填校验
        if (Integer.valueOf(1).equals(rule.getRequired()) && (selectedTagCodes == null || selectedTagCodes.isEmpty())) {
            return false;
        }
        
        // 单选/多选校验
        int maxMultiple = hotFileQConfig.getInt("tagging.max.multiple.tags", 10);
        if (AiTagSelectMode.SINGLE == rule.getSelectMode()) {
            return selectedTagCodes != null && selectedTagCodes.size() <= 1;
        } else {
            return selectedTagCodes == null || selectedTagCodes.size() <= maxMultiple;
        }
    }
}
```

### 11. 前端 - 分类管理页面

文件：`odin_node/src/pages/tag/category.jsx`

修改点：编辑弹窗中，当 `isLeaf` 为 true 时，显示"打标规则"配置区域

```jsx
// 新增字段
const [showTagRule, setShowTagRule] = useState(false);

// isLeaf 切换时控制显示
<Form.Item name="isLeaf" label="是否末级分类" valuePropName="checked">
    <Switch 
        checkedChildren="是" 
        unCheckedChildren="否"
        onChange={(checked) => setShowTagRule(checked)} 
    />
</Form.Item>

// 条件渲染打标规则
{showTagRule && (
    <Card size="small" title="打标规则配置" style={{ marginTop: 16 }}>
        <Row gutter={16}>
            <Col span={8}>
                <Form.Item name="selectMode" label="选择模式" initialValue="MULTIPLE">
                    <Radio.Group>
                        <Radio value="SINGLE">单选</Radio>
                        <Radio value="MULTIPLE">多选</Radio>
                    </Radio.Group>
                </Form.Item>
            </Col>
            <Col span={8}>
                <Form.Item name="required" label="是否必填" valuePropName="checked" initialValue={false}>
                    <Switch checkedChildren="必填" unCheckedChildren="非必填" />
                </Form.Item>
            </Col>
            <Col span={8}>
                <Form.Item name="threshold" label="匹配度阈值" initialValue={0.7}>
                    <InputNumber min={0} max={1} step={0.01} style={{ width: '100%' }} />
                </Form.Item>
            </Col>
        </Row>
    </Card>
)}
```

### 12. 前端 - API 接口

文件：`odin_node/src/api/tag.js`

```js
// 获取分类的打标规则
export function getCategoryTagRule(id) {
    return request.get(`/tag/category/${id}/tagRule`);
}

// 更新分类的打标规则
export function updateCategoryTagRule(id, data) {
    return request.put(`/tag/category/${id}/tagRule`, data);
}
```

---

## 实现顺序

1. [x] 需求确认
2. [ ] 数据库 SQL 变更（tag_schema.sql）
3. [ ] 新增 AiTagSelectMode 枚举
4. [ ] 新增 TagRule 领域对象
5. [ ] TagCategory Entity 变更
6. [ ] CategoryCreateRequest / CategoryUpdateRequest 变更
7. [ ] TagCategoryMapper.xml 更新 resultMap
8. [ ] TagCategoryService 逻辑修改（组装 extParam + getTagRule）
9. [ ] QConfig 配置
10. [ ] Controller 新增接口
11. [ ] TagRuleValidator 校验类
12. [ ] 前端 category.jsx 修改
13. [ ] 前端 api/tag.js 新增接口

---

## 待确认

- [ ] hotfile 配置文件路径和加载方式
- [ ] TagRuleValidator 在打标流程中的调用位置