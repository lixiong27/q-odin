# 素材库设计

> 基于内容中台（ODIN）现有内容库构建的独立素材管理系统

## 背景

内容中台已有完整的内容管理体系（content_base/text/image/video/metrics/label），视频/图片素材中包含大量"带 UI 元素"的画面（字幕、贴纸、水印、特效文字等）。需要从中抽取出"干净"的素材帧/片段，复用到其他内容生成中。

## 目标

构建与内容库平行的**独立素材模块**，素材作为"一等公民"管理。

## 素材范围

| 维度 | 说明 |
|------|------|
| **素材类型** | 图片帧（IMAGE）、视频片段（VIDEO）、音频片段（AUDIO） |
| **来源** | 内容库提取（EXTRACT）、外部上传（UPLOAD）、AI 生成（AI_GENERATED） |
| **使用场景** | 内容再创作（下载复用）、AI 内容生成的输入素材 |
| **与内容关系** | 独立管理，保留来源追溯（contentId + 时间戳 + 提取方式） |
| **加工方式** | 按需触发素材提取任务（利用现有任务模块） |

## 数据模型

### material_asset — 素材主表

素材的核心实体，独立于内容库管理。

| 字段 | 类型 | 说明 |
|------|------|------|
| id | Long | 自增主键 |
| material_id | String | 业务ID（UUID） |
| material_type | String | IMAGE / VIDEO / AUDIO |
| material_name | String | 素材名称 |
| material_description | String | 素材描述 |
| internal_url | String | OSS 内部 URL（素材文件本体） |
| cover_url | String | 封面图 URL |
| file_size | Long | 文件大小（字节） |
| file_format | String | 文件格式（jpg / mp4 / wav） |
| width | Integer | 图片/视频宽度（px） |
| height | Integer | 图片/视频高度（px） |
| aspect_ratio | Decimal | 宽高比 |
| duration | Integer | 视频/音频时长（秒） |
| cleanliness_score | Integer | AI 干净度评分（0-100，提取素材时评估） |
| status | String | DRAFT / REVIEW / PUBLISHED / ARCHIVED |
| download_count | Integer | 下载次数 |
| ext_param | Text | 扩展参数 JSON |
| create_time | Date | 创建时间 |
| update_time | Date | 更新时间 |

### material_source_ref — 来源追溯表

| 字段 | 类型 | 说明 |
|------|------|------|
| id | Long | 自增主键 |
| material_id | String | 关联 material_asset |
| source_type | String | EXTRACT / UPLOAD / AI_GENERATED |
| source_content_id | String | 来源内容 content_id（从内容库提取时） |
| source_material_type | String | VIDEO / IMAGE（来源内容的媒体类型） |
| extract_params | JSON | 提取参数 {timestamp, region, frame_index} |
| upload_file_name | String | 上传原始文件名 |
| ai_task_id | String | AI 生成任务 ID |
| ai_prompt | String | AI 生成提示词 |

## 架构方案

采用**方案 B：独立素材模块**。

图片帧、视频片段、音频作为独立资产，有自己的一套实体/服务/API/前端页面，与内容库平行。

### 核心模块划分

```
material/
├── entity/
│   ├── MaterialAsset.java        — 素材主表实体
│   └── MaterialSourceRef.java    — 来源追溯表实体
├── service/
│   ├── MaterialService.java      — 素材 CRUD + 搜索
│   ├── MaterialExtractService.java   — 从内容库提取素材
│   ├── MaterialUploadService.java    — 外部上传素材
│   └── MaterialAiService.java        — AI 生成素材
├── executor/
│   └── MaterialExtractionExecutor.java — 提取任务执行器（任务模块）
├── web/
│   ├── MaterialController.java   — 素材 REST API
│   └── MaterialSourceController.java — 来源追溯 API
└── dao/
    ├── MaterialAssetMapper.java
    └── MaterialSourceRefMapper.java
```

### 三种来源的接入方式

1. **内容库提取（EXTRACT）**：
   - 用户选择一批内容 → 创建"素材提取任务" → `MaterialExtractionExecutor` 处理
   - 对视频：抽帧 → AI 评估画面干净度 → 筛选干净帧 → 写入 material_asset
   - 对视频：截取干净片段 → 写入 material_asset（VIDEO类型）
   - 对视频：提取音频 → 写入 material_asset（AUDIO类型）

2. **外部上传（UPLOAD）**：
   - 前端上传页面 → `MaterialUploadService` → OSS 转存 → 写入 material_asset

3. **AI 生成（AI_GENERATED）**：
   - 利用现有 AI 能力层 → `MaterialAiService` → 生成结果写入 material_asset

### 标签与管理

- 素材自身的标签体系独立于内容库的 tag_category/tag_leaf
- 可考虑复用标签模块（新增素材分类目录），或素材自带的 AI 标签

## 设计待细化

- [ ] 素材标签体系具体设计（复用现有标签模块还是独立标签）
- [ ] 前端素材库页面设计（列表/详情/预览/上传）
- [ ] 素材搜索方案（ES 独立索引 vs 已有索引扩展）
- [ ] 素材下载/打包复用现有的 ContentDownloadService
- [ ] AI 画面干净度评估的具体实现方案