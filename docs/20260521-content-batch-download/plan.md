# 内容批量下载方案

## Context

当前单条下载：`GET /api/content/download?contentId=xxx` → ZIP（images/ videos/ text/）

要求：
1. **统一接口**：POST，只传 `contentIds`（单条也传列表）
2. **ZIP 内按 contentId 分文件夹**：每个 content 一个子目录
3. **每个 content 目录下有一个 metric/ 文件夹**：包含该内容的一行指标 Excel
4. **下载数量上限**：hotfile 可配置，默认 10 条
5. **前端列表页多选批量下载**

## ZIP 结构

```
素材下载_20260521.zip
├── content_xxx001/
│   ├── images/1.jpg
│   ├── videos/1.mp4
│   ├── text/正文.txt
│   └── metric/
│       └── 指标数据.xlsx
├── content_xxx002/
│   ├── images/1.jpg
│   └── metric/
│       └── 指标数据.xlsx
└── content_xxx003/
    └── metric/
        └── 指标数据.xlsx
```

每个 content 的 metric 文件独立，仅包含该内容的一行数据。

## 后端改动

### 1. pom.xml 新增 EasyExcel 依赖

```xml
<dependency>
    <groupId>com.alibaba</groupId>
    <artifactId>easyexcel</artifactId>
    <version>3.2.1</version>
</dependency>
```

### 2. RawContentQConfig 新增配置项

```java
// hotfile.properties: content.download.batch.maxSize=10
public int getDownloadBatchMaxSize() {
    return hotFileQConfig.getInt("content.download.batch.maxSize", 10);
}
```

### 3. DownloadController 重构为 POST

```java
@Data
public static class BatchDownloadRequest {
    private List<String> contentIds;
}

@PostMapping("/download")
public ResponseEntity<byte[]> download(@RequestBody BatchDownloadRequest request) {
    List<String> ids = request.getContentIds();
    if (CollectionUtils.isEmpty(ids)) {
        return ResponseEntity.badRequest().build();
    }
    if (ids.size() > rawContentQConfig.getDownloadBatchMaxSize()) {
        throw new IllegalArgumentException("批量下载最多 " + maxSize + " 条");
    }
    DownloadResult result = contentDownloadService.batchDownload(ids);
    return ResponseEntity.ok()
            .header(HttpHeaders.CONTENT_DISPOSITION,
                    "attachment; filename=\"" + result.getFileName() + "\"")
            .contentType(MediaType.APPLICATION_OCTET_STREAM)
            .body(result.getData());
}
```

### 4. ContentDownloadService

**核心重构：提取 `downloadSingleContent(Path contentDir, String contentId)`**

将现有 `download()` 中构建 images/videos/text/metric 的逻辑抽离，写入 `contentDir/contentId/` 子目录。

```java
// 原有 single download 重构
public DownloadResult download(String contentId) throws IOException {
    return batchDownload(Collections.singletonList(contentId));
}

// 新增批量下载（也是统一入口）
public DownloadResult batchDownload(List<String> contentIds) throws IOException {
    if (contentIds.size() > rawContentQConfig.getDownloadBatchMaxSize()) {
        throw new IllegalArgumentException("批量下载最多 " + maxSize + " 条");
    }
    
    Path tempDir = Files.createTempDirectory("batch-dl-");
    try {
        List<ContentBase> bases = queryBases(contentIds);
        
        // 每个 content 并行下载到各自子目录
        List<CompletableFuture<Void>> futures = bases.stream()
            .map(base -> CompletableFuture.runAsync(
                () -> downloadSingleContent(tempDir, base), DOWNLOAD_POOL))
            .collect(Collectors.toList());
        CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();

        // 打包 ZIP
        Path zipPath = tempDir.resolve("素材下载_" + LocalDate.now() + ".zip");
        try (ZipOutputStream zos = new ZipOutputStream(Files.newOutputStream(zipPath))) {
            Files.walk(tempDir)
                .filter(p -> !p.equals(zipPath) && !Files.isDirectory(p))
                .forEach(p -> addToZip(zos, tempDir.relativize(p), p));
        }

        // 更新下载次数
        bases.forEach(base -> incrementDownloadCount(base.getId()));

        return new DownloadResult(Files.readAllBytes(zipPath), zipPath.getFileName().toString());
    } finally {
        FileUtils.deleteDirectory(tempDir.toFile());
    }
}

// 下载单个 content 到 contentId 子目录
private void downloadSingleContent(Path tempDir, ContentBase base) {
    String contentId = base.getContentId();
    Path contentDir = tempDir.resolve("content_" + contentId);
    try {
        ContentRelations relations = GSON.fromJson(base.getContentRelations(), ContentRelations.class);
        
        // 并行查子表
        List<ContentImage> images = ...;
        List<ContentVideo> videos = ...;
        List<ContentText> texts = ...;
        List<ContentMetrics> metrics = ...;

        // 构建文件结构（写入 contentDir 下）
        buildImageFiles(contentDir, images);
        buildVideoFiles(contentDir, videos);
        buildTextFile(contentDir, texts, base.getContentTitle());
        buildMetricsFile(contentDir, base, metrics); // 每个 content 自己的 metric
    } catch (Exception e) {
        log.warn("Failed to download single content: {}", contentId, e);
    }
}
```

### 5. 指标文件生成（每个 content 一个）

```java
private void buildMetricsFile(Path contentDir, ContentBase base, ContentMetrics metrics) throws IOException {
    Path metricDir = contentDir.resolve("metric");
    Files.createDirectories(metricDir);
    Path excelFile = metricDir.resolve("指标数据.xlsx");
    
    // 构建单行 VO
    ContentMetricsVO vo = new ContentMetricsVO();
    vo.setContentId(base.getContentId());
    vo.setContentTitle(base.getContentTitle());
    vo.setContentType(base.getContentType());
    vo.setBusinessLine(base.getBusinessLine());
    vo.setTotalDownloads(metrics != null ? metrics.getTotalDownloads() : 0);
    // ... 其他指标字段
    
    // EasyExcel 写入（单行）
    EasyExcel.write(excelFile.toFile(), ContentMetricsVO.class)
        .sheet("指标数据")
        .doWrite(Collections.singletonList(vo));
}
```

### 6. ContentMetricsVO（EasyExcel VO）

```java
package com.qunar.ug.flight.contact.odin.server.domain.dto.download;

import com.alibaba.excel.annotation.ExcelProperty;
import lombok.Data;

@Data
public class ContentMetricsVO {
    @ExcelProperty("内容ID")
    private String contentId;
    @ExcelProperty("标题")
    private String contentTitle;
    @ExcelProperty("内容形式")
    private String contentType;
    @ExcelProperty("业务线")
    private String businessLine;
    @ExcelProperty("曝光量")
    private Integer totalImpressions;
    @ExcelProperty("点击量")
    private Integer totalClicks;
    @ExcelProperty("阅读量")
    private Integer totalReads;
    @ExcelProperty("互动量")
    private Integer totalInteractions;
    @ExcelProperty("下载次数")
    private Integer totalDownloads;
    @ExcelProperty("CPM")
    private Float cpm;
    @ExcelProperty("CTR")
    private Float ctr;
    @ExcelProperty("CVR")
    private Float cvr;
    // ... 其他指标
}
```

### 7. ContentMetricsMapper 新增批量查询

```sql
<select id="selectByBaseIds" resultMap="BaseResultMap">
    SELECT <include refid="Base_Column_List"/>
    FROM content_metrics
    WHERE base_id IN
    <foreach collection="baseIds" item="id" open="(" separator="," close=")">#{id}</foreach>
</select>
```

### 8. ContentBaseMapper 新增批量按 contentId 查询

```java
List<ContentBase> selectByContentIds(@Param("contentIds") List<String> contentIds);
```

```sql
<select id="selectByContentIds" resultMap="BaseResultMap">
    SELECT <include refid="Base_Column_List"/>
    FROM content_base
    WHERE content_id IN
    <foreach collection="contentIds" item="id" open="(" separator="," close=")">#{id}</foreach>
</select>
```

## 前端改动

### 1. list.jsx — 多选 + 批量下载按钮

```jsx
// 新增 state
const [selectedRowKeys, setSelectedRowKeys] = useState([]);
const [batchDownloading, setBatchDownloading] = useState(false);

// Table 添加 rowSelection
<Table
    rowSelection={{
        selectedRowKeys,
        onChange: setSelectedRowKeys,
    }}
/>

// 批量下载按钮
<Button 
    disabled={selectedRowKeys.length === 0}
    loading={batchDownloading}
    onClick={handleBatchDownload}
>批量下载</Button>

// 批量下载逻辑
const handleBatchDownload = async () => {
    if (selectedRowKeys.length === 0) return;
    setBatchDownloading(true);
    try {
        // 取出选中行的 contentId
        const ids = selectedRowKeys.map(key => {
            const hit = state.hits.find(h => h.baseId === key);
            return hit?.contentId;
        }).filter(Boolean);
        
        const res = await downloadContentBatch(ids);
        const blob = new Blob([res], { type: 'application/zip' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `素材下载_${moment().format('YYYYMMDD')}.zip`;
        a.click();
        URL.revokeObjectURL(url);
        setSelectedRowKeys([]);
    } catch (e) {
        message.error('下载失败: ' + e.message);
    }
    setBatchDownloading(false);
};
```

### 2. api/content.js

```jsx
// 批量/单条下载（POST，返回二进制）
export function downloadContentBatch(contentIds) {
    return request.post('/content/download', { contentIds }, { responseType: 'blob' });
}

// 详情页单条下载改为 POST
export function downloadContentUrl(contentIds) {
    return request.post('/content/download', { contentIds: [contentId] }, { responseType: 'blob' });
}
```

### 3. detail.jsx — 单条下载适配

详情页下载按钮改为调用 `downloadContentBatch([detail.contentId])`。

## 影响范围

| 层 | 文件 | 改动 |
|----|------|------|
| 后端 | pom.xml | 新增 EasyExcel 3.2.1 依赖 |
| 后端 | RawContentQConfig.java | 新增 `getDownloadBatchMaxSize()` |
| 后端 | DownloadController.java | 改为 POST + 统一 contentIds 参数 |
| 后端 | ContentDownloadService.java | 重构为 batchDownload + downloadSingleContent + buildMetricsFile |
| 后端 | ContentMetricsVO.java | **新建** EasyExcel VO |
| 后端 | ContentBaseMapper.java | 新增 `selectByContentIds` |
| 后端 | ContentBaseMapper.xml | 新增 selectByContentIds SQL |
| 后端 | ContentMetricsMapper.java | 新增 `selectByBaseIds` |
| 后端 | ContentMetricsMapper.xml | 新增 selectByBaseIds SQL |
| 前端 | api/content.js | downloadContentBatch + downloadContentUrl 改为 POST |
| 前端 | list.jsx | rowSelection + 批量下载按钮 |
| 前端 | detail.jsx | 下载按钮调 POST 接口 |