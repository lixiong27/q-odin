# 内容检索模块前端 — 文档计划 & 后端差距分析

## 一、前端原型总览

原型包含 4 个页面：

| 页面 | 文件 | 核心功能 |
|------|------|---------|
| 内容库列表页 | `内容库-列表页.html` | 筛选 + 排序 + 表格 + 自定义列 + 标签编辑 + 批量下载 |
| 内容详情页 | `内容库-详情页.html` | 完整内容信息 + 数据指标 + 标签 |
| 视频预览页 | `视频内容预览.html` | 视频播放 + 互动数据 + 下载 |
| 图文预览页 | `图文内容预览.html` | 图片轮播 + 互动数据 + 下载 |

---

## 二、后端差距分析

### 2.1 检索接口 — 请求字段对照

| 前端筛选条件       | 后端 ContentSearchRequest   | 状态       |
| ------------ | ------------------------- | -------- |
| 内容来源         | `contentSource`           | ✅ 已有     |
| 发布平台         | `platforms`               | ✅ 已有     |
| 内容形式(视频/图文)  | `contentTypes`            | ✅ 已有     |
| 业务线          | `businessLine`            | ✅ 已有     |
| 发布时间范围       | `publishTimeStart/End`    | ✅ 已有     |
| 地理信息(城市/POI) | `cities` / `poi`          | ✅ 已有     |
| 标签(树选)       | `aiTags`                  | ✅ 已有     |
| 排序字段/方向      | `sortField` / `sortOrder` | ✅ 已有     |
| 分页           | `from` / `size`           | ✅ 已有     |
| 曝光量范围        | —                         | ❌ **缺失** |
| CTR 范围       | —                         | ❌ **缺失** |
| CVR 范围       | —                         | ❌ **缺失** |
| 订单量范围        | —                         | ❌ **缺失** |
| 归一新客量范围      | —                         | ❌ **缺失** |
| 新客CAC范围      | —                         | ❌ **缺失** |

> **影响：** 前端"数据指标"区域的 6 个范围筛选字段后端均不支持。需要扩展到 SearchRequest 并可路由到 ES。（详见设计文档 14.1 — P0 已确认）

### 2.2 响应字段对照（列表页表格）

| 表格列            | 后端 ContentSearchHit           | 状态       |
| -------------- | ----------------------------- | -------- |
| 内容ID           | `contentId`                   | ✅ 已有     |
| 内容(缩略图+标题+副标题) | `publishUrl` + `contentTitle` | ✅ 已有     |
| 内容来源           | `contentSource`               | ✅ 已有     |
| 内容形式           | `contentType`                 | ✅ 已有     |
| 发布平台           | `publishPlatform`             | ✅ 已有     |
| 发布时间           | `publishTime`                 | ✅ 已有     |
| 下载次数           | —                             | ❌ **缺失** |
| 操作: 查看详情       | `baseId` 传给前端路由               | ✅ 已有     |
| 操作: 编辑标签       | 需要标签编辑 API                    | ❌ **缺失** |
| 操作: 下载         | `contentId` 传下载接口             | ✅ 已有     |

> **下载次数**缺失已在设计文档 14.6 TODO 中标记为 P0。需要在 `content_metrics` 表加 `total_downloads` 列，ES mapping 加字段，DTO 加字段。

### 2.3 自定义列 — 可选字段对照

| 自定义列选项 | 后端对应字段 | 状态 |
|-------------|-------------|------|
| 生产方式 | `productionTeam` | ✅ 已有 |
| 运营项目 | `operationProject` | ✅ 已有 |
| 投放团队/代理名称 | — | ⚠️ 需确认字段名 |
| 投放位置 | `placementPosition` | ✅ 已有 |
| 城市POI | `city` / `poi` | ✅ 已有 |
| 业务线 | `businessLine` | ✅ 已有 |
| 业务内容ID | `contentId` | ✅ 已有 |
| 是否有版权 | — | ❌ **缺失**（字段不在 ES 索引中） |
| 内容标签 | `aiTag` | ✅ 已有 |
| 运营标签 | — | ⚠️ 待确认字段 |
| 全部 17 个数据指标字段 | 17 个 metrics 字段 | ✅ 已有 |

### 2.4 缺失接口清单

| 接口 | 用途 | 对应前端页面 | 优先级 |
|------|------|-------------|--------|
| `GET /api/content/detail?baseId=xxx` | 单条内容详情（含 labels + metrics） | 详情页、预览页 | **P1** |
| `PUT /api/content/tags` | 编辑内容标签 | 列表页-编辑标签弹窗 | **P1** |
| `POST /api/content/batch-download` | 批量下载选中内容 | 列表页-批量下载 | **P2** |

> **已有接口：**
> - `POST /api/content/retrieve` — 内容检索 ✅
> - `POST /api/content/track-columns` — 自定义列埋点 ✅
> - `GET /api/content/download?contentId=xxx` — 单条内容下载 ✅

### 2.5 不足 4 种内容类型的展示区分

现有 `ContentSearchHit.contentType` 只有字符串（`VIDEO` / `IMAGE` / `TEXT` 等），但前端需要区分：

| 前端页面 | 触发方式 |
|---------|---------|
| 视频预览页 | `contentType == 'VIDEO'` → 打开视频预览页 |
| 图文预览页 | `contentType == 'IMAGE'` → 打开图文预览页 |
| 详情页 | `contentType == any` → 打开通用详情页 |

**现状：** `contentType` 字段已存在，后端按现有值返回即可。前端路由层根据 `contentType` 决定跳转。**后端无需额外改动。**

---

## 三、前端开发计划

### 3.1 页面路由设计 (UmiJS)

```
/content/list          → 内容库列表页
/content/detail/:id    → 内容详情页
/content/preview/video/:id  → 视频预览页
/content/preview/image/:id  → 图文预览页
```

### 3.2 技术要点

| 功能 | 技术方案 |
|------|---------|
| 标签树选择器 | Ant Design Tree + Checkable |
| 自定义列 | Ant Design Table columns 动态配置 + localStorage 持久化 |
| 排序组件 | 下拉选择指标 + 排序方向 |
| 预设保存 | localStorage 存储筛选条件快照 |
| 时间范围 | Ant Design DatePicker.RangePicker |
| 指标范围筛选 | InputNumber 范围组件 |
| 图片轮播 | Ant Design Carousel |
| 查看链接弹窗 | Ant Design Modal + Input(readonly) |
| 批量操作 | Table rowSelection + Checkbox |
| 预览跳转 | 根据 contentType 动态路由 |

### 3.3 组件结构

```
pages/content/
├── list/index.tsx          # 内容库列表页（主页面）
│   ├── components/
│   │   ├── SearchForm.tsx       # 筛选表单
│   │   ├── MetricFilter.tsx     # 数据指标范围筛选
│   │   ├── SortBar.tsx          # 自定义排序栏
│   │   ├── TableView.tsx        # 内容表格
│   │   ├── CustomColumnModal.tsx # 自定义列弹窗
│   │   ├── TagEditModal.tsx     # 编辑标签弹窗
│   │   └── LinkModal.tsx        # 查看链接弹窗
│   └── index.less
├── detail/index.tsx        # 内容详情页
│   ├── components/
│   │   ├── BasicInfo.tsx        # 基础信息面板
│   │   ├── MetricPanel.tsx      # 数据指标面板
│   │   └── TagPanel.tsx         # 标签信息面板
│   └── index.less
└── preview/
    ├── video/index.tsx      # 视频预览页
    │   └── index.less
    └── image/index.tsx      # 图文预览页
        └── index.less
```

### 3.4 API 层

```typescript
// api/content.ts

// 检索内容
POST /api/content/retrieve
Req: ContentSearchRequest
Res: BaseResponse<{ hits: ContentSearchHit[], total: number, took: number, fieldMeta: Record<string, FieldMeta> }>

// 自定义列埋点
POST /api/content/track-columns
Req: string[]  // 选中的字段列表

// 单条内容下载
GET /api/content/download?contentId=xxx
Res: application/zip (二进制流)
```

### 3.5 开发阶段

| 阶段 | 内容 | 估算 |
|------|------|------|
| Phase 1 | 列表页：SearchForm + 表格 + 分页 | 2d |
| Phase 2 | 列表页：排序 + 自定义列 + 预设 | 1d |
| Phase 3 | 弹窗：标签编辑 + 查看链接 | 1d |
| Phase 4 | 详情页：基础信息 + 数据指标 + 标签 | 1d |
| Phase 5 | 预览页：视频 + 图文 | 1d |
| Phase 6 | 下载对接 + 联调 | 1d |
| **合计** | | **7d** |

---

## 四、后端需要补充的改动

### 4.1 P0 — 必须在联调前完成

| 改动 | 说明 | 工作量 |
|------|------|--------|
| `ContentSearchRequest` 扩充指标范围筛选字段 | 曝光量/CTR/CVR/订单量/新客量/CAC 的 min/max | 小 |
| ES 路由支持指标范围查询 | ESSearchServiceImpl 将指标范围转为 ES range query | 中 |
| `totalDownloads` 字段补齐 | content_metrics 表 + ES mapping + DTO | 小 |

### 4.2 P1 — 前端联调前完成

| 改动 | 说明 | 工作量 |
|------|------|--------|
| 内容详情接口 `GET /api/content/detail?baseId=xxx` | 复用 DataAggregator 单条查询 + ResponseAssembler | 小 |
| 标签编辑接口 | 更新 content_label 表 | 中 |

### 4.3 P2 — 后续迭代

| 改动 | 说明 | 工作量 |
|------|------|--------|
| 批量下载接口 | 循环调用单条下载后合并 ZIP | 中 |
| "是否有版权"字段补齐 | content_base.has_copyright | 小 |

---

## 五、总结

**前端需要实现的页面：** 4 个（列表、详情、视频预览、图文预览）

**后端已有但需要补齐的：**
1. 检索请求缺少指标范围筛选（6 个指标的 min/max）
2. 响应缺少 `totalDownloads`（下载次数）
3. 缺少单条内容详情接口（详情页/预览页依赖）
4. 缺少标签编辑接口（列表页编辑标签弹窗依赖）

**后端已有的能力（不需要改动）：**
- 检索路由 + 聚合 + 安全过滤 + 响应组装（`retrieve` 包完整）
- 单条内容下载（`download` 包完整）
- 自定义列埋点（`track-columns` 接口完整）
- 全部基础字段 + 标签字段 + 指标字段的 ES 索引和 MySQL 查询