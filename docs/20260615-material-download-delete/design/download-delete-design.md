# 素材下载 & 删除设计方案

> 日期：2026-06-15
> 状态：待确认

---

## 1. 接口设计

### 1.1 批量下载

| 项目 | 说明 |
|------|------|
| **URL** | `POST /api/material/download` |
| **请求体** | `{ ids: [1, 2, 3] }` — 支持单条和批量 |
| **响应** | ZIP 字节流（`application/octet-stream`） |
| **ZIP 结构** | 详见下方 |

**ZIP 包目录结构：**

```
素材下载_{timestamp}.zip
├── {keyword}_{materialId}/
│   ├── video/
│   │   └── 1.mp4              ← material_base.video_url (OSS 内部)
│   ├── cover/
│   │   └── 1.jpg              ← material_video.internal_cover_url
│   └── metric/
│       └── 指标数据.xlsx       ← material_metrics 字段
├── {materialId}/               ← keyword 为空时
│   ├── video/
│   ├── cover/
│   └── metric/
└── ...
```

> **keyword 来源**：从 `material_base.ext_param` JSON 中提取 `keyword` 字段。  
> **目录命名规则**：`keyword` 不为空 → `{keyword}_{materialId}`，否则 → `{materialId}`。

### 1.2 批量删除

| 项目 | 说明 |
|------|------|
| **URL** | `POST /api/material/delete` |
| **请求体** | `{ ids: [1, 2, 3] }` |
| **响应** | `{ code: 0, msg: "success", data: { successCount: 3, failCount: 0 } }` |
| **逻辑** | 删除三张表记录 + ES 索引文档 |

删除范围：

| 表/索引 | 条件 | 说明 |
|---------|------|------|
| `material_metrics` | `material_id` | 先删指标 |
| `material_video` | `material_id` | 再删视频 |
| `material_base` | `id` | 最后删主表 |
| ES `material_search` | `id` | 删除对应文档 |

> 一个 `material_id` 可能对应多条 metrics/video 记录，按 `material_id` 删除。  
> 事务内执行，任一失败整体回滚。

---

## 2. 后端实现

### 2.1 ElasticsearchDataSource 新增 delete 方法

```java
/**
 * 根据文档 ID 删除
 */
public boolean delete(String index, String id) {
    if (StringUtils.isBlank(index) || StringUtils.isBlank(id)) {
        return false;
    }
    try {
        DeleteRequest request = new DeleteRequest(index, id);
        restHighLevelClient.delete(request, RequestOptions.DEFAULT);
        QMonitor.recordOne("es_delete");
        return true;
    } catch (Exception e) {
        log.error("ES delete error, index: {}, id: {}", index, id, e);
        QMonitor.recordOne("es_delete_error");
        return false;
    }
}
```

### 2.2 MaterialDownloadService

参考 `ContentDownloadService` 的模式，简化实现：

```java
@Component
public class MaterialDownloadService {
    
    public DownloadResult batchDownload(List<Long> ids) {
        // 1. 查询 material_base (含 ext_param 提取 keyword)
        // 2. 查询 material_video / material_metrics
        // 3. 在 temp 目录构建: {keyword}_{materialId}/video/ + cover/ + metric/
        // 4. 打包 ZIP
        // 5. 返回字节流
    }
}
```

### 2.3 MaterialDeleteService

```java
@Service
public class MaterialDeleteService {
    
    @Transactional(rollbackFor = Exception.class)
    public MaterialDeleteResult batchDelete(List<Long> ids) {
        int success = 0, fail = 0;
        for (Long id : ids) {
            try {
                MaterialBase base = materialBaseMapper.selectById(id);
                if (base == null) { fail++; continue; }
                
                // 1. 删 metrics
                materialMetricsMapper.deleteByMaterialId(base.getMaterialId());
                // 2. 删 video
                materialVideoMapper.deleteByMaterialId(base.getMaterialId());
                // 3. 删 base
                materialBaseMapper.deleteById(id);
                // 4. 删 ES
                elasticsearchDataSource.delete(materialSearchIndex, String.valueOf(id));
                
                success++;
            } catch (Exception e) {
                log.error("删除素材失败: id={}", id, e);
                fail++;
            }
        }
        return new MaterialDeleteResult(success, fail);
    }
}
```

### 2.4 Controller 新增接口

```java
@RestController
@RequestMapping("/api/material")
public class MaterialSearchController {

    @PostMapping("/download")
    public ResponseEntity<byte[]> download(@RequestBody MaterialBatchRequest request) { ... }

    @PostMapping("/delete")
    public BaseResponse<MaterialDeleteResult> delete(@RequestBody MaterialBatchRequest request) { ... }
}
```

请求 DTO：

```java
@Data
public class MaterialBatchRequest {
    private List<Long> ids;
}
```

---

## 3. 涉及新增/修改的文件

### 新增文件

| 文件 | 说明 |
|------|------|
| `service/material/MaterialDownloadService.java` | 下载打包服务 |
| `service/material/MaterialDeleteService.java` | 批量删除服务 |
| `domain/dto/material/MaterialBatchRequest.java` | 批量操作请求 DTO |
| `service/download/DownloadResult.java` | 复用现有（如已存在） |

### 修改文件

| 文件 | 改动 |
|------|------|
| `infra/elasticsearch/ElasticsearchDataSource.java` | 新增 `delete(index, id)` 方法 |
| `web/MaterialSearchController.java` | 新增 `/download` 和 `/delete` 端点 |
| `infra/dao/MaterialBaseMapper.java` | 新增 `deleteById(id)` |
| `infra/dao/MaterialVideoMapper.java` | 新增 `deleteByMaterialId(materialId)` |
| `infra/dao/MaterialMetricsMapper.java` | 新增 `deleteByMaterialId(materialId)` |
| `resources/mapper/MaterialBaseMapper.xml` | 新增 delete SQL |
| `resources/mapper/MaterialVideoMapper.xml` | 新增 delete SQL |
| `resources/mapper/MaterialMetricsMapper.xml` | 新增 delete SQL |
| `src/api/material.js` | 新增 `downloadMaterial` / `deleteMaterial` |
| `src/pages/material/list.jsx` | 新增下载/删除按钮 |

---

## 4. 前端改动

### API 封装

```javascript
export function downloadMaterial(ids) {
    return request.post('/material/download', { ids }, { responseType: 'blob', timeout: 120000 });
}

export function deleteMaterial(ids) {
    return request.post('/material/delete', { ids });
}
```

### 列表页改动

- **批量操作栏**：选中行后出现「批量下载」「批量删除」按钮
- **单条操作**：操作列追加「下载」「删除」按钮
- **删除确认**：`Popconfirm` 二次确认
- **下载处理**：接收 blob 后创建 `<a>` 标签下载

---

## 5. 待确认事项

- [ ] 下载 ZIP 的 size 限制？参考 content 模块 500MB？
> 可以
- [ ] 下载是否要异步更新下载次数？(material_metrics 目前无 totalDownloads 字段)
> 暂时不需要
- [ ] 删除成功/失败的响应格式是否满足需求？
> 可以