# 数仓宽表 ES 加速查询方案 - 开发进度

## 项目概述

**项目名称**：ES 内容搜索加速（Content Search ES）

---

## 开发阶段

### 阶段一：设计文档

| 任务 | 状态 | 说明 |
|------|------|------|
| 设计文档 | ✅ 完成 | docs/20260513-es-content-search/design/design.md |

### 阶段二：后端开发

| 任务 | 状态 | 说明 |
|------|------|------|
| Step 1: ElasticsearchDataSource 增强 | ✅ 完成 | 已具备 create/existIndex/batchInsert/update/bulkUpdate/search |
| Step 2: Entity/DTO 类 | ✅ 完成 | ContentSearchDocument/Request/Response/Hit |
| Step 3: DocAssembler + MyBatis Mapper | ✅ 完成 | 6 表 JOIN 查询 + Map→Document 转换 |
| Step 4: ContentSearchIndexService | ✅ 完成 | ensureIndexExists/indexDocument/updateDocument/bulkUpdateDocuments |
| Step 5: ContentSearchService 搜索服务 | ✅ 完成 | 多维过滤 + 排序 + 分页 |
| Step 6: IndexQConfig 动态配置 | ✅ 完成 | es-index.properties: shards/replicas/batch/sync_enabled/repair_enabled |
| Step 7: RawContentServiceImpl 集成 | ✅ 完成 | triggerSync() 中新增 esPostSync() 调用 |
| Step 8: 搜索 API Controller | ✅ 完成 | POST /api/content/search + GET /api/content/filter |
| Step 9: 定时任务 | ✅ 完成 | ContentRepairTask / ContentReconcileTask / ContentFullRebuildTask |

---

## 文件变更清单

### 新增文件

| 文件 | 说明 |
|------|------|
| `domain/entity/es/ContentSearchDocument.java` | ES 文档 POJO（camelCase → snake_case 转换） |
| `domain/request/es/ContentSearchRequest.java` | 搜索请求 DTO |
| `domain/response/es/ContentSearchResponse.java` | 搜索响应 DTO |
| `domain/response/es/ContentSearchHit.java` | 搜索命中文档 DTO |
| `infra/qconfig/IndexQConfig.java` | ES 索引配置（QConfig） |
| `service/es/ContentSearchDocAssembler.java` | 文档组装接口 |
| `service/es/impl/ContentSearchDocAssemblerImpl.java` | 文档组装实现 |
| `service/es/ContentSearchService.java` | 搜索服务接口 |
| `service/es/impl/ContentSearchServiceImpl.java` | 搜索服务实现 |
| `service/es/ContentSearchIndexService.java` | 索引服务接口 |
| `service/es/impl/ContentSearchIndexServiceImpl.java` | 索引服务实现 |
| `service/es/ContentSearchSyncService.java` | 同步服务接口 |
| `service/es/impl/ContentSearchSyncServiceImpl.java` | 同步服务实现 |
| `web/ContentSearchController.java` | 搜索 API 控制器 |
| `task/es/ContentRepairTask.java` | ES 不完整文档修复定时任务 |
| `task/es/ContentReconcileTask.java` | ES/MySQL 对账定时任务 |
| `task/es/ContentFullRebuildTask.java` | ES 全量重建定时任务 |

### 修改文件

| 文件 | 变更 |
|------|------|
| `ElasticsearchDataSource.java` | 暴露 getRestHighLevelClient() + 新增 bulkUpdate/update/search 方法 |
| `ContentBaseMapper.java` | 新增 7 个 ES 辅助查询方法 |
| `ContentBaseMapper.xml` | 新增 EsDoc_Column_List + EsDocResultMap + 5 个 SELECT 查询 |
| `RawContentService.java` | 接口新增 esPostSync() 方法 |
| `RawContentServiceImpl.java` | triggerSync() + processItem() 中调用 esPostSync() ES 索引同步 |
| `RawContentSyncTask.java` | processItem() 中新增 esPostSync() 调用 |

---

## 当前进度

**当前阶段：** 阶段二 - 后端开发（全部完成）

**已完成：**
- Step 1-9 全部后端开发完成
- 编译验证通过（mvn compile）

**待开始：**
- 前端搜索页面开发（如需要）
- 联调测试

---

## QSchedule 任务配置

| QSchedule Key | 任务 | 频率建议 |
|---------------|------|----------|
| `mkt_odin_es_repair` | ContentRepairTask | 每 30 分钟 |
| `mkt_odin_es_reconcile` | ContentReconcileTask | 每小时 |
| `mkt_odin_es_full_rebuild` | ContentFullRebuildTask | 按需手动触发 |

## 监控指标

| 指标名 | 说明 |
|--------|------|
| es_content_index | 新内容索引成功次数 |
| es_content_index_error | 新内容索引失败次数 |
| es_content_index_created | ES 索引创建成功次数 |
| es_content_sync_new | 新内容同步成功 |
| es_content_sync_new_error | 新内容同步失败 |
| es_content_metrics_update | 指标批量更新成功（带数量） |
| es_content_metrics_update_error | 指标批量更新失败 |
| es_content_ai_tag_update | AI 标签更新成功 |
| es_content_ai_tag_update_error | AI 标签更新失败 |
| es_repair_incomplete | 对账任务发现不完整文档数 |
| es_repair_fixed | 对账任务修复数 |
| es_reconcile_mismatch | ES/MySQL 数量不匹配告警 |
| es_full_rebuild_total | 全量重建索引总数 |
| es_full_rebuild_fail | 全量重建失败数 |