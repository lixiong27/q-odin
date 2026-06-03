# 内容列表字段优化

## 项目概述

**项目名称**：内容列表字段优化

---

## 需求描述

### 1. 去掉操作列的"查看"按钮

**现状**：内容列表的操作列右侧有一个眼睛图标按钮（`EyeOutlined`），点击在新标签页打开 `publishUrl`。

**改动**：移除该按钮。用户仍可通过发布平台列的"查看"链接访问发布URL，操作列只保留"详情"和"下载"。

**影响文件**：`odin_node/src/pages/content/list.jsx`

### 2. 去掉列表页标题列的超链接

**现状**：内容标题（`contentTitle`）列由 `renderCell` 的 `link` 类型渲染为 `<a>` 超链接，点击跳转到发布URL。

**改动**：当 `field === 'contentTitle'` 时渲染为纯文本，不再做超链接跳转。其余字段的 `link` 类型渲染保持不变。

**影响文件**：`odin_node/src/pages/content/list.jsx`

### 3. 隐藏新客CAC / 潜新CAC / CPM 字段

**现状**：
- 列表页：`cpm`、`newCustomerCac`、`potentialNewCac` 可通过自定义列功能显示
- 详情页：在"数据指标"卡片中直接展示这三项

**改动**：
- 列表页：从可选列集合中移除这三个字段的选项，从高级筛选中移除对应指标范围输入
- 详情页：从"数据指标"卡片中移除对应的 `Descriptions.Item`

**影响文件**：
- `odin_node/src/pages/content/list.jsx`
- `odin_node/src/pages/content/detail.jsx`

---

## 开发阶段

### 阶段一：后端改动

| 任务 | 状态 | 说明 |
|------|------|------|
| 数据模型: ColumnConfig 新增 disabled 字段 | ✅ 已完成 | ContentDictConfig.java +1 字段 |
| 新建 ContentFieldMaskService | ✅ 已完成 | maskHit / maskDetail，根据 disabled 配置设 null |
| 改造 ContentResponseAssembler | ✅ 已完成 | buildFieldMeta 跳过 disabled；convertToHit 末尾 maskHit |
| 改造 ContentSearchController.convertToDetail | ✅ 已完成 | convertToDetail 末尾 maskDetail |
| ESSearchServiceImpl 移除 cpm 排序 | ✅ 已完成 | SORT_WHITELIST 移除 cpm |

### 阶段二：前端改动

| 任务 | 状态 | 说明 |
|------|------|------|
| list.jsx: disabledFields 替换硬编码 | ✅ 已完成 | fieldLabelMap 跳过 disabled；displayFields 用 fieldLabelMap 兜底；metricFilters 用 disabledFields 过滤 |
| detail.jsx: 条件渲染隐藏指标行 | ✅ 已完成 | 从 dict 读取 detailDisabledFields，CAC/CPM 行条件渲染 |

### 阶段二：验证

| 任务 | 状态 | 说明 |
|------|------|------|
| 功能测试 | ❌ 待开始 | - |

---

## 当前进度

**当前阶段：** 阶段一 - 前端改动（✅ 已完成）

**已完成：**
- 操作列查看按钮移除
- 标题列超链接移除
- 敏感指标字段隐藏（list + detail）

**待开始：**
- 功能验证

---

## 关键约定

### 前端改动原则
- 仅做展示层屏蔽，后端数据仍在 API 响应中，不影响其他消费方
- 不改动后端 DTO / API 层，纯前端变更