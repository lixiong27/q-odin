# 标签模块设计文档

## 一、模块概述

### 1.1 功能定位

标签模块是内容中台（ODIN）的核心基础模块，为内容打标、分类检索、智能推荐提供标签体系支撑。

### 1.2 核心能力

| 能力 | 说明 |
|------|------|
| 标签分类管理 | 多级树形分类结构，支持层级扩展 |
| 叶子标签管理 | 标签实体管理，支持 AI 打标配置 |
| 标签树可视化 | 思维导图式展示，拖拽编辑 |
| 打标规则控制 | 单选/多选、必填/可选配置 |

### 1.3 业务流程

```
创建标签分类 → 配置末级分类 → 创建叶子标签 → 内容打标 → 标签检索
```

---

## 二、数据模型

### 2.1 表结构设计

#### 标签分类表 (tag_category)

| 字段 | 类型 | 说明 |
|------|------|------|
| id | BIGINT | 主键，自增 |
| parent_id | BIGINT | 父分类ID，0表示根节点 |
| code | VARCHAR(64) | 分类编码，业务唯一标识 |
| name | VARCHAR(100) | 分类名称 |
| level | INT | 层级深度，从1开始 |
| is_leaf | TINYINT | 是否末级分类 0-否 1-是 |
| path | VARCHAR(500) | 路径，格式：/父ID/子ID/ |
| sort_order | INT | 排序序号 |
| status | TINYINT | 状态 0-停用 1-启用 |
| valid | TINYINT | 软删标记 0-失效 1-生效 |

**核心约束：**
- `code` 业务唯一
- `is_leaf=1` 的分类才能关联叶子标签
- `path` 字段支持快速子树查询

#### 叶子标签表 (tag_leaf)

| 字段 | 类型 | 说明 |
|------|------|------|
| id | BIGINT | 主键，自增 |
| category_id | BIGINT | 所属末级分类ID |
| code | VARCHAR(64) | 标签编码，业务唯一标识 |
| name | VARCHAR(100) | 标签名称 |
| ai_need_flag | TINYINT | 是否需要AI打标 0-否 1-是 |
| ai_description | TEXT | AI打标描述 |
| tag_description | TEXT | 标签描述 |
| sort_order | INT | 排序序号 |
| status | TINYINT | 状态 0-停用 1-启用 |
| valid | TINYINT | 软删标记 |

**核心约束：**
- `category_id` 必须关联 `is_leaf=1` 的分类
- 停用标签禁止用于新内容打标，已打标内容保留

### 2.2 ER 关系

```
tag_category (1) ←→ (N) tag_category  -- 自关联父子关系
tag_category (1) ←→ (N) tag_leaf       -- 末级分类关联叶子标签
tag_leaf (N) ←→ (N) content            -- 通过 content_tag_rel 关联
```

---

## 三、API 接口设计

### 3.1 标签分类接口

| 接口 | 方法 | 说明 |
|------|------|------|
| /api/tag/category/create | POST | 创建分类 |
| /api/tag/category/update | POST | 更新分类 |
| /api/tag/category/delete | POST | 删除分类（软删） |
| /api/tag/category/list | GET | 分类列表（支持树形） |
| /api/tag/category/tree | GET | 分类树结构 |
| /api/tag/category/toggle | POST | 启用/停用分类 |

### 3.2 叶子标签接口

| 接口 | 方法 | 说明 |
|------|------|------|
| /api/tag/leaf/create | POST | 创建标签 |
| /api/tag/leaf/update | POST | 更新标签 |
| /api/tag/leaf/delete | POST | 删除标签（软删） |
| /api/tag/leaf/list | GET | 标签列表 |
| /api/tag/leaf/toggle | POST | 启用/停用标签 |

### 3.3 内容打标接口

| 接口 | 方法 | 说明 |
|------|------|------|
| /api/content/tag/save | POST | 内容打标（批量） |
| /api/content/tag/list | GET | 获取内容标签 |
| /api/content/tag/search | GET | 按标签检索内容 |

---

## 四、核心业务规则

### 4.1 分类创建规则

```
1. code 唯一性校验
2. 计算 level 和 path
3. 如果 is_leaf=1：
   - 可直接关联叶子标签
   - 不能有子分类
4. 如果 is_leaf=0：
   - 可有子分类
   - 不能直接关联叶子标签
```

### 4.2 删除保护规则

| 场景 | 处理策略 |
|------|---------|
| 删除非末级分类 | 检查子分类，有则禁止删除 |
| 删除末级分类 | 检查叶子标签，有则禁止删除 |
| 删除叶子标签 | 检查已打标内容，有则提示确认 |

### 4.3 停用联动规则

```
停用分类 → 递归停用所有子分类 + 子标签
停用标签 → 仅停用当前标签，已打标内容保留
```

### 4.4 打标规则校验

| 规则类型 | 校验逻辑 |
|---------|---------|
| 单选必填 | 必须选择1个标签 |
| 多选可选 | 可选择0~N个标签 |
| 单选可选 | 可选择0或1个标签 |

---

## 五、极端场景处理

### 5.1 末级分类转非末级分类

**场景：** 末级分类下已有叶子标签，需要转为非末级分类

**处理：**
1. 前置检查：存在叶子标签 → 禁止转换
2. 用户需先迁移标签到其他末级分类

### 5.2 标签转分类

**场景：** 叶子标签需要扩展为分类结构

**标准流程：**
1. 停用原叶子标签（保留历史关联）
2. 创建同名新分类
3. 在新分类下创建叶子标签
4. 可选：刷数迁移已打标内容

### 5.3 大批量打标

**优化策略：**
- 批量插入 content_tag_rel
- 异步记录打标历史
- 事务控制保障一致性

---

## 六、技术实现要点

### 6.1 树形结构查询优化

```sql
-- 使用 path 字段快速查询子树
SELECT * FROM tag_category 
WHERE path LIKE '/100/%' AND valid = 1;

-- 使用递归CTE查询（MySQL 8.0+）
WITH RECURSIVE category_tree AS (
    SELECT * FROM tag_category WHERE id = #{rootId}
    UNION ALL
    SELECT c.* FROM tag_category c
    INNER JOIN category_tree ct ON c.parent_id = ct.id
)
SELECT * FROM category_tree;
```

### 6.2 并发控制

- 分类/标签编辑：乐观锁（update_time）
- 批量打标：分布式锁（content_id）

### 6.3 缓存策略

| 数据 | 缓存策略 |
|------|---------|
| 标签分类树 | Redis 缓存，变更时失效 |
| 叶子标签信息 | 本地缓存 + Redis 双层缓存 |
| 打标规则 | Redis 缓存 |

---

## 七、前端交互设计

### 7.1 标签树可视化

- 思维导图式展示（参考原型）
- 拖拽创建节点
- 双击连线建立父子关系
- 右键取消连线
- 缩放/平移/全屏支持

### 7.2 表单联动

- 末级分类 ↔ 打标规则显示/隐藏
- 父节点关闭 → 子节点联动关闭
- 标签选择器支持多级展开、搜索

---

## 八、参考文档

- 建表SQL：`docs/20260505-tag-module/design/initial.md`
- 原型文件：`docs/20260505-tag-module/design/标签管理-思维导图版.html`
