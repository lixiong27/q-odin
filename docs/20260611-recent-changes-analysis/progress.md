# 素材库 - 项目开发进度

## 项目概述

**项目名称**：素材库模块

通过抓取调度系统从抖音、小红书抓取视频素材，经 QMQ 回调后落地到素材库表，支持前端 ES 检索。

---

## 开发阶段

### 阶段一：设计文档

| 任务 | 状态 | 说明 |
|------|------|------|
| 需求文档 | ✅ 已完成 | requirements.md — 表设计、整体流程、处理策略 |
| 前端原型 | ✅ 已完成 | 列表页 + 详情页 HTML 原型 |
| 字典配置 | ✅ 已完成 | material_dict.example.json — QConfig 配置示例 |

### 阶段二：技术方案

| 任务 | 状态 | 说明 |
|------|------|------|
| 后端技术方案 | ✅ 已完成 | tec-spec/backend-tech-spec.md |
| 数据库建表脚本 | ❌ 待开始 | 基于 requirements.md 表结构生成 DDL |
| QConfig 动态字典 | ❌ 待开始 | MaterialDictConfig + MaterialDictService |

### 阶段三：后端开发

| 任务 | 状态 | 说明 |
|------|------|------|
| Entity + Mapper（三张表） | ❌ 待开始 | MaterialBase / MaterialVideo / MaterialMetrics |
| 回调 Handler 增强 | ❌ 待开始 | DouyinHandler + XhsHandler 写 result + SUCCESS |
| MaterialCrawlResult DTO | ❌ 待开始 | 中间传输结构 |
| MaterialProcessTask | ❌ 待开始 | @QSchedule 定时任务主类 |
| MaterialProcessService | ❌ 待开始 | 核心处理（校验→查重→验证→OSS→入库→ES） |
| MaterialOssService | ❌ 待开始 | OSS 转存服务 |
| MaterialSearchDocument | ❌ 待开始 | ES Document POJO |
| MaterialSearchSyncService | ❌ 待开始 | ES 索引同步 |
| MaterialSearchDocAssembler | ❌ 待开始 | ES Document 组装（material_label 展开） |
| MaterialSearchService | ❌ 待开始 | ES 检索 Service（筛选参数→DSL） |
| MaterialSearchController | ❌ 待开始 | /api/material/search + /api/material/detail |
| SubTaskStatus 新增枚举 | ❌ 待开始 | ANALYSIS_SUCCESS / ANALYSIS_FAIL |

### 阶段四：前端开发

| 任务 | 状态 | 说明 |
|------|------|------|
| 素材列表页 | ❌ 待开始 | /material 路由 + 筛选 + 表格 |
| 素材详情页 | ❌ 待开始 | /material/detail 路由 |
| API 封装 | ❌ 待开始 | src/api/material.js |
| 路由配置 | ❌ 待开始 | config/config.js 新增路由 |

### 阶段五：联调测试

| 任务 | 状态 | 说明 |
|------|------|------|
| 抓取→回调→入库全链路 | ❌ 待开始 | QMQ 回调 → MaterialProcessTask → DB |
| ES 检索功能 | ❌ 待开始 | 各筛选条件验证 |
| 前端集成 | ❌ 待开始 | 列表/详情页交互验证 |

---

## 当前进度

**当前阶段：** 阶段一 - 设计文档（已完成）

**已完成：**
- 需求文档（requirements.md v0.5）：表结构、全流程、小红书两段式处理策略
- 前端原型：素材库列表页、详情页 HTML 原型
- 字典配置示例 material_dict.example.json：sources / aspectRatios / resolutions / frameRates / metricFilters / columns
- 后端技术方案（tec-spec/backend-tech-spec.md）

**待开始：**
- 数据库建表脚本
- QConfig 动态字典 MaterialDictService
- 三阶段后端开发（回调增强 → 定时任务 → ES 同步）
- 前端开发（列表 + 详情）
- 全链路联调测试

**下一步：** 阶段三 - 后端开发

---

## 技术栈

### 后端
- Java 17
- Spring Boot 2.6.6
- MyBatis 3.x
- QConfig（配置中心 + hotfile 热加载）
- QSchedule（定时任务）
- QMQ（消息消费）
- Elasticsearch（检索）

### 前端
- Node.js 12.16.1
- React 16.14.0
- Ant Design 4.x
- UmiJS 3.x

---

## 关键约定

### 接口规范
- 统一前缀：`/api`
- 素材模块前缀：`/api/material`
- 统一响应格式：`{ code: 0, message: "success", data: {} }`

### dict 配置
- 文件名：`material_dict.json`
- 托管方式：QConfig（@QConfig 热加载）
- 默认值：`{}`（配置未加载时前端回退硬编码默认值）