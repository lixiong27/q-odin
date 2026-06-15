# 标签可视化 — 未保存分类拖拽拦截 + 视觉强化方案

## 目标

1. 未保存的分类节点有醒目的阴影和高光，区别于已保存节点
2. 拖拽分类/标签到未保存分类上时：有高亮提示可放置，放手后弹异常提示，不执行操作

## 改动

### 1. CSS 视觉强化（`visual.less`）

现状：未保存节点仅有 `border: 2px dashed #f59e0b` + `background: #fffbeb` + `animation: pulse`

增强：
- 增加 `.node-card.unsaved` 的 `box-shadow`（外发光阴影）
- 增加 `.node-card.unsaved::after` 伪元素，在节点外围渲染半透明光晕（高光）
- 增加 `.node-card.unsaved.drop-target` 覆盖样式，确保拖拽高亮时仍然是绿色高亮为主

### 2. 拖拽逻辑（`visual.jsx`）

现状：`canDrop`/`canDropForCreate` 对 `targetNode.isUnsaved` 返回 false → 无高亮

改回：让 `canDrop`/`canDropForCreate` 对未保存节点返回 true（有高亮），在 `handleDrop`/`handleDropForCreate` 中检测 `targetNode.isUnsaved` 后弹 warning 并中断

## 涉及文件

| 文件 | 改动 |
|------|------|
| `src/pages/tag/visual.jsx` | `canDrop` 移除 `isUnsaved` 拦截；`handleDrop` 中 unsaved 检查保持不动 |
| `src/pages/tag/visual.less` | 增强 `.node-card.unsaved` 的阴影和高光 |

## 验证

1. 拖拽工具栏"拖拽创建分类"到未保存分类上 → 未保存节点出现绿色高亮边框
2. 放手后 → 弹出 warning "分类"XXX"未保存，暂不可在其下新增内容"
3. 拖拽"拖拽创建标签"到未保存末级分类上 → 同上
4. 已保存的分类拖拽到未保存分类上 → 同上