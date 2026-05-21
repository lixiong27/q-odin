# 前端埋点增强方案

## Context

前端已通过 `POST /api/track/event` 上报埋点，但 params 过于简单。需补充 page_type、prev_sort/current_sort、user_defined_column 字段。

**已具备的基础设施（后端无需改动）：**

| 能力 | 当前 | 说明 |
|------|------|------|
| `POST /api/track/event` | `{event, params}` | 接收前端上报，异步入库 |
| userId 提取 | 从 cookie 自动提取 | TrackController + UserIdConfig 已实现 |
| createTime | `DB CURRENT_TIMESTAMP` | 自动填充 |
| params | TEXT 字段 | 任意 JSON 字符串，已支持 |
| TrackEventType | 5 种事件已定义 | 含 CONTENT_PAGE_VIEW / SORT / COLUMN |

**user_name = user_id**，后端已自动提取，前端无需关心。

### 前端已有调用汇总

| 文件 | 行 | 事件 | 当前 params | 改为 |
|------|-----|------|------------|------|
| list.jsx | 189 | `content_page_view` | 无 | `{page_type:"内容列表页"}` |
| list.jsx | 262 | `content_sort_change` | `{field, order}` | `{prev_sort, current_sort}` |
| list.jsx | 267 | `content_sort_change` | `{field, order}` | `{prev_sort, current_sort}` |
| list.jsx | 552 | `user_defined_column` | `{reset:true}` | `{user_defined_column:[], reset:true}` |
| list.jsx | 702 | `user_defined_column` | `{fields}` | `{user_defined_column}` |
| detail.jsx | 新增 | `content_page_view` | 无 | `{page_type:"内容详情页"}` |

## 改动方案

### 仅前端改动（后端不变）

**1. `list.jsx` — page load（第 189 行）**

```jsx
// 旧
trackEvent('content_page_view');

// 新
trackEvent('content_page_view', JSON.stringify({ page_type: '内容列表页' }));
```

**2. `list.jsx` — sort change（第 260-268 行）**

```jsx
// 旧
const handleSortChange = (value) => {
    dispatch({ type: 'SET_SORT', field: value, order: state.sortOrder });
    trackEvent('content_sort_change', JSON.stringify({ field: value, order: state.sortOrder }));
};

const toggleSortOrder = () => {
    dispatch({ type: 'SET_SORT', field: state.sortField, order: state.sortOrder === 'desc' ? 'asc' : 'desc' });
    trackEvent('content_sort_change', JSON.stringify({ field: state.sortField, order: state.sortOrder === 'desc' ? 'asc' : 'desc' }));
};

// 新
const handleSortChange = (value) => {
    const prev = prevSortStr(state.sortField, state.sortOrder);
    const curr = currSortStr(value, state.sortOrder);
    dispatch({ type: 'SET_SORT', field: value, order: state.sortOrder });
    trackEvent('content_sort_change', JSON.stringify({ prev_sort: prev, current_sort: curr }));
};

const toggleSortOrder = () => {
    const newOrder = state.sortOrder === 'desc' ? 'asc' : 'desc';
    const prev = prevSortStr(state.sortField, state.sortOrder);
    const curr = currSortStr(state.sortField, newOrder);
    dispatch({ type: 'SET_SORT', field: state.sortField, order: newOrder });
    trackEvent('content_sort_change', JSON.stringify({ prev_sort: prev, current_sort: curr }));
};

// 辅助函数
function sortFieldToLabel(field) {
    return FIELD_LABELS[field] || field;
}
function prevSortStr(field, order) {
    return field ? `${sortFieldToLabel(field)}${order === 'desc' ? '降序' : '升序'}` : '';
}
function currSortStr(field, order) {
    return field ? `${sortFieldToLabel(field)}${order === 'desc' ? '降序' : '升序'}` : '';
}
```

**3. `list.jsx` — user_defined_column 确认（第 702 行）**

```jsx
// 旧
trackEvent('user_defined_column', JSON.stringify({ fields: tempColumnFields }));

// 新
trackEvent('user_defined_column', JSON.stringify({ user_defined_column: tempColumnFields }));
```

**4. `list.jsx` — user_defined_column 恢复默认（第 552 行）**

```jsx
// 旧
trackEvent('user_defined_column', JSON.stringify({ reset: true }));

// 新
trackEvent('user_defined_column', JSON.stringify({ user_defined_column: [], reset: true }));
```

**5. `list.jsx` — content_page_view 自定义列弹窗**

```jsx
// 在 setColumnModalVisible(true) 处
const handleColumnModalOpen = () => {
    setTempColumnFields(visibleFields || DEFAULT_FIELDS);
    setColumnModalVisible(true);
    trackEvent('content_page_view', JSON.stringify({ page_type: '自定义列弹窗页' }));
};
```

**6. `list.jsx` — content_page_view 预览弹窗（第 303-316 行）**

```jsx
const handlePreview = async (baseId) => {
    setPreviewVisible(true);
    setPreviewLoading(true);
    setPreviewIndex(0);
    trackEvent('content_page_view', JSON.stringify({ page_type: '内容预览页' }));
    // ... rest unchanged
};
```

**7. `detail.jsx` — page load**

```jsx
useEffect(() => {
    if (!baseId) {
        message.error('缺少 baseId 参数');
        setLoading(false);
        return;
    }
    loadDetail();
    getContentDict().then(res => setDict(res.data)).catch(() => {});
    trackEvent('content_page_view', JSON.stringify({ page_type: '内容详情页' }));
}, [baseId]);
```

## 影响范围

| 文件 | 改动 |
|------|------|
| `odin_node/src/pages/content/list.jsx` | 7 处 trackEvent 调用增强 |
| `odin_node/src/pages/content/detail.jsx` | 新增 1 处 trackEvent |
| 后端所有文件 | 无改动 |