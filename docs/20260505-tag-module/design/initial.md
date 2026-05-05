- 知识图谱标签体系（多级树形结构）
    
- 前端树形标签选择器（支持多级展开、跨级勾选、搜索定位）
    
- 后端标签树 CRUD + 素材打标
## 标签模块

### 一、建表SQL

#### 1. 标签分类表 (tag_category)

```SQL
CREATE TABLE `tag_category` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '分类ID',
    `parent_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '父分类ID，0表示根节点',
    `code` VARCHAR(64) NOT NULL DEFAULT '' COMMENT '分类编码，业务唯一标识',
    `name` VARCHAR(100) NOT NULL DEFAULT '' COMMENT '分类名称',
    `level` INT NOT NULL DEFAULT 1 COMMENT '层级深度，从1开始',
    `is_leaf` TINYINT NOT NULL DEFAULT 0 COMMENT '是否末级分类 0-否(仅用于层级管理) 1-是(可直接关联叶子标签)',
    `path` VARCHAR(500) NOT NULL DEFAULT '' COMMENT '路径，格式：/父ID/子ID/，用于快速查询子树',
    `sort_order` INT NOT NULL DEFAULT 0 COMMENT '排序序号',
    `status` TINYINT NOT NULL DEFAULT 1 COMMENT '状态 0-停用 1-启用',
    `description` VARCHAR(500) NOT NULL DEFAULT '' COMMENT '分类描述',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `create_by` VARCHAR(64) NOT NULL DEFAULT '' COMMENT '创建人',
    `update_by` VARCHAR(64) NOT NULL DEFAULT '' COMMENT '更新人',
    `valid` TINYINT NOT NULL DEFAULT 1 COMMENT '是否生效 1-生效 0-失效(软删)',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_code` (`code`),
    KEY `idx_parent_id` (`parent_id`),
    KEY `idx_path` (`path`),
    KEY `idx_level` (`level`),
    KEY `idx_is_leaf` (`is_leaf`),
    KEY `idx_status` (`status`),
    KEY `idx_update_time` (`update_time`),
    KEY `idx_valid` (`valid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='标签分类表';
```

  

### 2. 叶子标签表 (tag_leaf)

  

```SQL
CREATE TABLE `tag_leaf` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '标签ID',
    `category_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '所属末级分类ID，必须关联到is_leaf=1的分类',
    `code` VARCHAR(64) NOT NULL DEFAULT '' COMMENT '标签编码，业务唯一标识',
    `name` VARCHAR(100) NOT NULL DEFAULT '' COMMENT '标签名称',
    `ai_need_flag` TINYINT NOT NULL DEFAULT 0 COMMENT '是否需要AI打标 0-否 1-是',
    `ai_description` TEXT COMMENT 'AI打标描述，用于指导AI识别',
    `tag_description` TEXT COMMENT '标签描述',
    `sort_order` INT NOT NULL DEFAULT 0 COMMENT '排序序号',
    `status` TINYINT NOT NULL DEFAULT 1 COMMENT '状态 0-停用 1-启用',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `create_by` VARCHAR(64) NOT NULL DEFAULT '' COMMENT '创建人',
    `update_by` VARCHAR(64) NOT NULL DEFAULT '' COMMENT '更新人',
    `valid` TINYINT NOT NULL DEFAULT 1 COMMENT '是否生效 1-生效 0-失效(软删)',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_code` (`code`),
    KEY `idx_category_id` (`category_id`),
    KEY `idx_status` (`status`),
    KEY `idx_ai_need_flag` (`ai_need_flag`),
    KEY `idx_update_time` (`update_time`),
    KEY `idx_valid` (`valid`),
    KEY `idx_category_status` (`category_id`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='叶子标签表';
```

  

  

### 二、API核心主流程

  

#### 1. 创建标签分类流程

  

```Plain
POST /api/tag/category/create
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 1. 参数校验                                                  │
│    - 分类名称非空、长度限制                                    │
│    - code唯一性校验                                          │
│    - parent_id有效性校验（如果传了）                           │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. 计算层级属性                                              │
│    if parent_id == null:                                    │
│        level = 1                                            │
│        path = CONCAT('/', id, '/')  // 保存后更新             │
│    else:                                                    │
│        查询父分类                                            │
│        level = parent.level + 1                             │
│        path = CONCAT(parent.path, id, '/')                  │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. 业务规则校验                                              │
│    - 如果 is_leaf = 1（末级分类）：                          │
│        检查是否已存在叶子标签归属（创建时无需检查）              │
│    - 如果 is_leaf = 0（非末级分类）：                        │
│        不能直接关联叶子标签                                   │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. 保存数据                                                  │
│    - 先插入获取自增id                                         │
│    - 更新path字段                                            │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. 记录操作日志                                              │
│    INSERT INTO tag_operation_log                            │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
   返回结果
```

  

### 2. 创建叶子标签流程

  

```Plain
POST /api/tag/leaf/create
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 1. 参数校验                                                  │
│    - 标签名称非空、长度限制                                    │
│    - code唯一性校验                                          │
│    - category_id必填                                         │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. 验证关联分类                                              │
│    SELECT * FROM tag_category WHERE id = category_id        │
│                                                             │
│    校验点：                                                  │
│    - 分类必须存在且未删除                                     │
│    - 分类的is_leaf必须 = 1（末级分类）                        │
│    - 分类的status必须 = 1（启用状态）                         │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. AI打标相关处理                                            │
│    if ai_need_flag == 1:                                    │
│        - ai_description不能为空                              │
│        - 可选：预生成embedding向量（后期检索用）               │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. 保存数据                                                  │
│    INSERT INTO tag_leaf                                     │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
   返回结果
```

  

  

  

```Plain
POST /api/content/tag/save
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 1. 参数校验                                                  │
│    - content_id非空                                          │
│    - tag_ids列表（可空，空表示清除所有标签）                   │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. 批量查询并校验标签                                        │
│    SELECT * FROM tag_leaf                                   │
│    WHERE id IN (tag_ids) AND deleted = 0                    │
│                                                             │
│    校验点：                                                  │
│    - 所有tag_id都必须存在                                     │
│    - 所有标签status必须 = 1（启用状态）                       │
│      如果有停用标签 → 抛出异常："标签[xxx]已停用，无法打标"     │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. 按末级分类聚合标签，校验打标规则                            │
│                                                             │
│    Map<categoryId, List<tagId>>                            │
│                                                             │
│    for each category:                                       │
│        查询该分类的打标规则（单选/多选/必填）                  │
│        - 单选必填：个数必须=1                                 │
│        - 多选可选：个数>=0即可                                │
│        - 单选可选：个数<=1                                    │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. 开启事务                                                  │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. 删除旧关联                                                │
│    UPDATE content_tag_rel                                   │
│    SET deleted = 1                                          │
│    WHERE content_id = #{contentId}                          │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. 批量插入新关联                                            │
│    INSERT INTO content_tag_rel (content_id, tag_id, ...)    │
│    VALUES (...), (...), ...                                 │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 7. 记录打标历史                                              │
│    INSERT INTO content_tag_history                          │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 8. 提交事务                                                  │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
   返回结果
```

  

  

### 三、极端场景Case

#### Case 1：删除非末级分类时，其下存在多层子分类

```Plain
场景描述：
分类树结构：
技术(100, is_leaf=0)
├── 前端(200, is_leaf=0)
│   ├── React(300, is_leaf=1) ← 末级分类，已关联叶子标签
│   └── Vue(301, is_leaf=1)
└── 后端(201, is_leaf=0)
    └── Java(302, is_leaf=1)

操作：尝试删除分类"前端(200)"

处理流程：
┌─────────────────────────────────────────────────────────────┐
│ 1. 查询该分类下的所有子分类                                    │
│    SELECT * FROM tag_category                               │
│    WHERE path LIKE '/200/%' AND deleted = 0                 │
│                                                             │
│    结果：React(300)、Vue(301)                                │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. 检查子分类中是否有末级分类已经关联叶子标签                   │
│    SELECT c.id FROM tag_category c                         │
│    INNER JOIN tag_leaf l ON l.category_id = c.id           │
│    WHERE c.id IN (300, 301) AND l.deleted = 0              │
│                                                             │
│    结果：React下有关联标签 → 不允许直接删除                    │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. 返回错误提示                                              │
│    {                                                        │
│      "code": 400,                                           │
│      "message": "无法删除分类[前端]，其子分类[React]下存在    │
│                  叶子标签，请先处理子分类下的标签"             │
│    }                                                        │
└─────────────────────────────────────────────────────────────┘
```

  

**解决方案**：

```SQL
-- 方案1：先删除或迁移子分类下的所有叶子标签
UPDATE tag_leaf SET category_id = 新分类ID WHERE category_id IN (300, 301);

-- 方案2：软删除所有子分类（需要级联处理）
-- 方案3：递归删除（强制删除，不建议生产使用）
```

  

---

  

#### Case 2：停用叶子标签时，已有大量内容关联

  

```Plain
场景描述：
标签"Java"(id=1001, status=1)已打标到5000篇内容上
操作：停用该标签（status改为0）

业务要求：
- 已打标内容保持不变（仍可查询到"Java"标签）
- 新增内容不能再使用"Java"打标
```

  

**处理流程**：

  

```Java
// 停用标签接口实现
@Transactional
public void disableTag(Long tagId) {
    // 1. 检查标签是否存在
    TagLeaf tag = tagLeafMapper.selectById(tagId);
    if (tag == null || tag.getDeleted() == 1) {
        throw new BusinessException("标签不存在");
    }
    
    if (tag.getStatus() == 0) {
        return; // 已经是停用状态
    }
    
    // 2. 记录关联内容数量（用于审计日志）
    int relatedCount = contentTagRelMapper.countByTagId(tagId);
    
    // 3. 执行停用（只改标签状态，不动已有关联）
    tagLeafMapper.updateStatus(tagId, 0);
    
    // 4. 记录操作日志
    operationLogMapper.insert(OperationLog.builder()
        .operationType("TAG_DISABLE")
        .targetId(tagId)
        .remark(String.format("停用标签[%s]，影响已关联内容%d篇", tag.getName(), relatedCount))
        .build());
    
    // 5. 可选：发送消息通知相关业务方
    eventPublisher.publish(new TagDisabledEvent(tagId, relatedCount));
}
```

  

**打标时的校验**：

```Java
public void validateTagsForTagging(List<Long> tagIds) {
    List<TagLeaf> tags = tagLeafMapper.selectByIds(tagIds);
    
    List<String> disabledTags = tags.stream()
        .filter(t -> t.getStatus() == 0)
        .map(TagLeaf::getName)
        .collect(Collectors.toList());
    
    if (!disabledTags.isEmpty()) {
        throw new BusinessException(
            String.format("以下标签已停用，无法用于新增打标：%s", 
                String.join("、", disabledTags))
        );
    }
}
```

  

**查询已打标内容时的表现**：

```SQL
-- 查询内容时，仍然能查到已停用标签（但前端可以特殊标记显示）
SELECT l.id, l.name, l.status 
FROM content_tag_rel r
INNER JOIN tag_leaf l ON l.id = r.tag_id
WHERE r.content_id = #{contentId} AND r.deleted = 0;
-- 返回结果中 l.status = 0 表示标签已停用
```

  

---

  

#### Case 3：末级分类转非末级分类（或反过来）

  

```Plain
场景描述：
已有末级分类"编程语言"(id=200, is_leaf=1)，下面有关联叶子标签：
- Java(1)
- Python(2)
- Go(3)

操作：将该分类改为非末级分类（is_leaf=1 → is_leaf=0）

冲突：非末级分类不能直接关联叶子标签
```

  

**处理流程**：

  

```Java
@Transactional
public void updateCategoryLeafStatus(Long categoryId, Boolean newIsLeaf) {
    // 1. 查询分类信息
    TagCategory category = categoryMapper.selectById(categoryId);
    
    // 2. 如果要改为非末级分类
    if (category.getIsLeaf() == 1 && newIsLeaf == false) {
        // 检查下是否有关联的叶子标签
        int tagCount = tagLeafMapper.countByCategoryId(categoryId);
        if (tagCount > 0) {
            throw new BusinessException(
                String.format("分类[%s]下关联了%d个叶子标签，无法转换为非末级分类。" +
                    "请先将标签迁移到其他末级分类下", 
                    category.getName(), tagCount)
            );
        }
    }
    
    // 3. 如果要改为末级分类
    if (category.getIsLeaf() == 0 && newIsLeaf == true) {
        // 检查下是否有子分类（末级分类不能有子分类）
        int childCount = categoryMapper.countByParentId(categoryId);
        if (childCount > 0) {
            throw new BusinessException(
                String.format("分类[%s]下存在%d个子分类，无法转换为末级分类。" +
                    "请先删除或迁移子分类", 
                    category.getName(), childCount)
            );
        }
    }
    
    // 4. 执行更新
    categoryMapper.updateIsLeaf(categoryId, newIsLeaf);
}
```

  

---

  

#### Case 4：叶子标签名称变为分类名（业务语义转换）

  

```Plain
场景描述：
有一个叶子标签"数据库"(id=300, category_id=200)
现在需要扩展为分类结构：
数据库(分类)

核心原则
不支持实体上的直接转换，采用以下标准流程：
停用原叶子标签（保留历史关联数据）
创建一个同名的新标签分类
在新分类下创建所需的叶子标签
原叶子标签的已打标内容保持不变
```

  

**标准处理流程（不支持直接转换）**：

  

```Java
原状态：
叶子标签“数据库”(id=300, status=1, category_id=200)
已打标到 1000 篇内容上

                    ↓

Step 1: 停用原叶子标签
┌─────────────────────────────────────────────────────────────┐
│ UPDATE tag_leaf                                             │
│ SET status = 0, update_time = NOW()                         │
│ WHERE id = 300;                                             │
│                                                             │
│ 说明：                                                       │
│ - 原标签不再用于新增内容打标                                   │
│ - 已有关联内容不受影响，仍可查询到该标签                        │
└─────────────────────────────────────────────────────────────┘
                    ↓
Step 2: 创建同名标签分类
┌─────────────────────────────────────────────────────────────┐
│ INSERT INTO tag_category (                                  │
│     parent_id,    -- 根据业务需要指定父分类                   │
│     code,         -- 新生成的唯一编码                        │
│     name,         -- '数据库'（与原标签同名）                 │
│     level,        -- 根据父分类计算                          │
│     is_leaf,      -- 0（非末级，作为容器分类）                │
│     path,         -- 根据父分类计算                          │
│     sort_order,   -- 根据业务需要                            │
│     status,       -- 1（启用）                               │
│     create_by     -- 操作人                                  │
│ ) VALUES ( ... );                                           │
│                                                             │
│ 假设新分类ID = 500                                           │
└─────────────────────────────────────────────────────────────┘
                    ↓
Step 3: 在新分类下创建叶子标签
┌─────────────────────────────────────────────────────────────┐
│ INSERT INTO tag_leaf (                                      │
│     category_id,   -- 500（新创建的父分类）                   │
│     code,          -- 新生成的唯一编码                        │
│     name,          -- 'MySQL'、'PostgreSQL'、'Oracle'等      │
│     ai_need_flag,  -- 根据业务需要                           │
│     sort_order,    -- 根据业务需要                           │
│     status,        -- 1（启用）                              │
│     create_by      -- 操作人                                 │
│ ) VALUES ( ... ), ( ... ), ( ... );                         │
└─────────────────────────────────────────────────────────────┘
                    ↓
Step 4: 记录变更日志（可选）
┌─────────────────────────────────────────────────────────────┐
│ INSERT INTO tag_convert_log (                              │
│     original_tag_id,    -- 300                              │
│     original_tag_name,  -- '数据库'                         │
│     new_category_id,    -- 500                              │
│     new_tag_ids,        -- [601,602,603]                    │
│     convert_type,       -- 'TAG_TO_CATEGORY'                │
│     operator,           -- 操作人                            │
│     create_time         -- NOW()                            │
│ ) VALUES ( ... );                                           │
└─────────────────────────────────────────────────────────────┘
                    ↓
Step 5: 处理已打标内容（后续可选）
┌─────────────────────────────────────────────────────────────┐
│ 方案A：前期 - 单独提刷数需求                                  │
│ 方案B：后期 - 提供迁移能力，按需执行                           │
│                                                             │
│ 例如：将原300标签替换为新分类下的某个叶子标签                    │
│ UPDATE content_tag_rel                                      │
│ SET tag_id = 601  -- 新标签ID                               │
│ WHERE tag_id = 300 AND content_id IN (指定内容范围);         │
└─────────────────────────────────────────────────────────────┘
```

  

**已打标内容处理**：

```SQL
-- 前期：单独提刷数需求
-- 执行刷数SQL（将旧标签替换为新标签树下的某个叶子标签）
UPDATE content_tag_rel r
SET r.tag_id = #{newTagId}
WHERE r.tag_id = #{originalTagId} AND r.content_id IN (#{特定内容范围});
```

  

---

  

#### Case 5：递归停用 - 父分类停用时自动停用所有子标签

  

```Plain
场景描述：
分类结构：
技术(100, status=1)
├── 编程语言(200, status=1)
│   └── Java(1001, status=1) ← 叶子标签

操作：停用分类"编程语言"(200)

业务逻辑：停用父分类时，应该递归停用所有子分类和子标签
```

  

**递归停用实现**：

  

```SQL
-- 存储过程实现递归停用
DELIMITER $$
CREATE PROCEDURE disable_category_recursive(IN category_id BIGINT)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE child_id BIGINT;
    DECLARE cur CURSOR FOR SELECT id FROM tag_category WHERE parent_id = category_id AND deleted = 0;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    -- 1. 停用当前分类下的所有叶子标签
    UPDATE tag_leaf SET status = 0 
    WHERE category_id = category_id AND deleted = 0;
    
    -- 2. 递归处理子分类
    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO child_id;
        IF done THEN
            LEAVE read_loop;
        END IF;
        CALL disable_category_recursive(child_id);
    END LOOP;
    CLOSE cur;
    
    -- 3. 停用当前分类
    UPDATE tag_category SET status = 0 WHERE id = category_id;
END$$
DELIMITER ;
```

  

**Java实现**：

  

```Java
@Transactional
public void disableCategoryRecursive(Long categoryId) {
    // 使用队列实现BFS遍历
    Queue<Long> queue = new LinkedList<>();
    queue.offer(categoryId);
    List<Long> allCategoryIds = new ArrayList<>();
    List<Long> allTagIds = new ArrayList<>();
    
    while (!queue.isEmpty()) {
        Long currentId = queue.poll();
        allCategoryIds.add(currentId);
        
        // 收集当前分类下的所有叶子标签
        List<Long> tagIds = tagLeafMapper.selectIdsByCategoryId(currentId);
        allTagIds.addAll(tagIds);
        
        // 获取所有子分类
        List<TagCategory> children = categoryMapper.selectByParentId(currentId);
        for (TagCategory child : children) {
            queue.offer(child.getId());
        }
    }
    
    // 批量停用标签
    if (!allTagIds.isEmpty()) {
        tagLeafMapper.batchUpdateStatus(allTagIds, 0);
    }
    
    // 批量停用分类
    if (!allCategoryIds.isEmpty()) {
        categoryMapper.batchUpdateStatus(allCategoryIds, 0);
    }
    
    // 记录操作日志
    log.info("递归停用分类{}，影响{}个分类，{}个标签", 
        categoryId, allCategoryIds.size(), allTagIds.size());
}
```

  

---

  

### 快速参考表

  

|            |                  |            |        |
| ---------- | ---------------- | ---------- | ------ |
| 场景         | 处理策略             | 对已有内容影响    | 对新内容影响 |
| 叶子标签停用     | status改为0        | 保留，仍可查询    | 禁止使用   |
| 叶子标签删除     | deleted改为1       | 保留历史关联     | 禁止使用   |
| 非末级分类删除    | 前置检查有子节点则禁止      | -          | -      |
| 末级分类删除     | 前置检查有标签则禁止       | -          | -      |
| 末级分类↔非末级互转 | 检查关联数据，有则禁止      | -          | -      |
| 标签转分类      | 停用原标签+新建分类+新建子标签 | 不变，可单独触发迁移 | 使用新结构  |