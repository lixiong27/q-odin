# 素材模块前端增强 — Deep Dive

## 问题

1. 素材列表页缺少排序选项下拉
2. 素材详情页回退丢失搜索条件

## 后端现状（已就绪，无需改动）

| 文件 | 已有内容 |
|------|---------|
| `MaterialDictConfig.sortOptions` | `material_dict.json` 中包含 `sortOptions` |
| `MaterialSearchRequest.sortField/sortOrder` | DTO 已包含这两个字段 |
| `GET /api/material/dict` | 已返回 `sortOptions` |
| `POST /api/material/search` | 已接收 `sortField`/`sortOrder` |

## 改动方案

### 1. 排序选项

**参考**: `content/list.jsx` 的 `dict?.sortOptions` + `Select` + 升序降序切换

**具体改动** (`material/list.jsx`):
- `initialState` 新增 `sortField: '', sortOrder: 'desc'`
- `reducer` 新增 `SET_SORT` case（类似 SET_FILTER，重置 from=0）
- `useEffect` 依赖新增 `state.sortField, state.sortOrder` 触发自动重新加载
- `loadData` 中传递 `sortField`/`sortOrder` 到请求体
- 新增排序 UI 组件（Select + 升降序切换按钮）
- `defaultSort` 常量用于空 sortField 时投射为默认值

### 2. 回退保留搜索条件

**参考**: `content/list.jsx` 的 `sessionStorage` + `getInitialState` + `saveListState` 模式

**具体改动**:
- `material/list.jsx`:
  - 新增 `STORAGE_KEY_LIST_STATE`、`saveListState()`、`getInitialState()`
  - `useReducer` 改为惰性初始化：`useReducer(reducer, null, () => getInitialState())`
  - 详情按钮点击时先 `saveListState(state)` 再跳转
  - `reducer` 新增 `SET_SORT`

- `material/detail.jsx`:
  - 返回按钮保持 `history.push('/material')` 不变（和 content/detail.jsx 一样走 `/content/list`）

## 影响范围

| 文件 | 改动类型 |
|------|---------|
| `odin_node/src/pages/material/list.jsx` | ~40 行增改 |
| `odin_node/src/pages/material/detail.jsx` | 无需改动（已有 `history.push('/material')`）|