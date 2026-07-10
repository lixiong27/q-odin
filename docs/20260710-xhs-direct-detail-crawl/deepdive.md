# DirectCrawl + Excel 导出 — Deep Dive 代码对照分析

## 一、DirectCrawl（直接抓取）

### 1.1 任务创建方式变更

**之前（plan）：** 通过 `DirectCrawlTaskStrategy` + `/api/assignTask`

**实际决定：** 通过可视化前端 `/api/task/create` 创建。

影响：
- 不需要新建 `DirectCrawlTaskStrategy`（废弃）
- 前端任务创建页面（`/task/create` 4 步向导）已有完整创建能力：
  1. 选择类型 → `materialCrawl`
  2. 选择执行器 → `hotpredict-redbook-direct-crawl`
  3. 选择数据源 → `noteIds`，粘贴 JSON
  4. 确认提交 → `POST /api/task/create`

### 1.2 TaskService.createTask() 创建链路

`TaskController.create()` → `TaskService.createTask()`:
- 从 QConfig 加载 `ExecutorConfig`（`taskQConfig.getConfig(configKey)`）
- 构建 `TaskParamBO`（含 `configKey`, `dataSourceType`, `data`, `executorSnapshot`）
- `task.executor` = `executorConfig.getExecutorName()` = `"directCrawl"`
- `task.taskType` = `executorConfig.getType()` = `"materialCrawl"`
- 状态 PENDING → 等待 `TaskScheduler` 调度

### 1.3 DirectCrawlExecutor.execute()

参考 `HotPredictRedbookPostCrawl.execute()`（`HotPredictRedbookPostCrawl.java`），关键差异：

| 环节 | PostCrawl | DirectCrawl |
|------|-----------|-------------|
| 数据来源 | `data.noteIds` | `data.noteIdList` |
| DB 校验 | 查 DB，无 xsecToken 则跳过 | 不校验，直接创建 SubTask |
| 全部无效时 | 子任务 FAILED | 不存在"全部无效"场景 |
| xsecToken | 必须从 DB 获取 | 可选，有则带，无则不传 |

execute() 不会 fail — 全部 noteId 都创建 SubTask。

### 1.4 DirectCrawlExecutor.subExecute()

参考 `HotPredictRedbookPostCrawl.subExecute()`，注意 `CrawlTaskRequest.addParam()` 会过滤空白值：
```java
public void addParam(String key, Object value) {
    if (value instanceof String && StringUtils.isBlank((String) value)) {
        return;  // 空白字符串不会写入 param
    }
}
```

所以当 xsecToken 为空时，不应调用 `addParam("xsecToken", "")`，而应直接跳过：
```java
Map<String, Object> param = new HashMap<>();
param.put("noteId", noteId);
param.put("taskType", CrawlTaskTypeEnum.DETAIL.getCode());
if (StringUtils.isNotBlank(xsecToken)) {
    param.put("xsecToken", xsecToken);
}
```

### 1.5 DirectCrawlHandler

逻辑与 `HotPredictRedbookPostCrawlHandler.handleRedbookDetail()` 一致：
- 解析 `XhsCrawlDetailTaskResultData`
- 提取 `NoteCard` → 构造 `NotePostData`
- 封装 `NotePostCrawlResult` → `subTaskService.completeSubTask()`

**区别：** 不提取首日数据 extra（与 PostCrawl 不同，DirectCrawl 没有 bigSearch 阶段）

### 1.6 HotPredictProcessStrategy.supports()

```java
// 新增 directCrawl
"hotPredictRedbookPreCrawl".equals(executorName)
    || "hotPredictRedbookPostCrawl".equals(executorName)
    || "directCrawl".equals(executorName)
```

`HotPredictProcessStrategy.process()` 内部解析 `NotePostCrawlResult` 落库，行为与 preCrawl/postCrawl 完全一致。

### 1.7 MaterialProcessTask 扫描范围

已有 QConfig 配置 `material.process.source` 支持多 executor 逗号分隔：
```java
String executorsConfig = hotFileQConfig.getString("material.process.source", "MaterialCrawlExecutor");
List<String> executors = executorsConfig == null ? List.of("MaterialCrawlExecutor")
        : List.of(executorsConfig.split(","));
```

需在 QConfig 追加 `directCrawl`。

---

## 二、Excel 导出

### 2.1 现有导出模式参考

`MaterialDownloadService` 已有使用 `EasyExcel` 写 `MaterialDownloadVO` 的模式：
```java
EasyExcel.write(excelFile.toFile(), MaterialDownloadVO.class)
        .sheet("指标数据")
        .doWrite(Collections.singletonList(vo));
```

`MaterialDownloadVO` 使用 `@ExcelProperty` 注解定义列名。

DirectCrawl 导出遵循相同模式，但直接写回 `HttpServletResponse` 输出流（不写本地文件）。

### 2.2 字段清单（来自 RedbookNotePost）

排除 id / createTime / updateTime，共 23 字段：

| # | 字段 | 类型 | 说明 |
|---|------|------|------|
| 1 | noteId | String | 笔记ID |
| 2 | title | String | 标题 |
| 3 | noteDesc | String | 笔记正文 |
| 4 | noteType | String | 类型 |
| 5 | coverUrl | String | 封面URL |
| 6 | imageList | String(JSON) | 图片列表 |
| 7 | tagList | String(JSON) | 标签列表 |
| 8 | ipLocation | String | IP属地 |
| 9 | authorId | String | 作者ID |
| 10 | authorName | String | 作者名称 |
| 11 | authorAvatar | String | 作者头像 |
| 12 | totalLikes | Integer | 点赞数 |
| 13 | totalCollect | Integer | 收藏数 |
| 14 | totalComments | Integer | 评论数 |
| 15 | totalShares | Integer | 分享数 |
| 16 | publishTime | Date | 发布时间 |
| 17 | lastUpdateTime | Date | 最近更新 |
| 18 | xsecToken | String | xsecToken |
| 19 | atUserList | String(JSON) | @用户列表 |
| 20 | keyword | String | 关键词 |
| 21 | label | String(JSON) | 标签JSON |
| 22 | extra | String(JSON) | 扩展信息 |
| 23 | crawlTime | Date | 抓取时间 |

### 2.3 Mapper 新增

`RedbookNotePostMapper` 已有 `selectNoteIdsByNoteIdList`（返回 String 列表），需新增返回完整实体的方法：
```java
List<RedbookNotePost> selectByNoteIdList(@Param("noteIds") List<String> noteIds);
```

对应 XML SQL 复用 `Base_Column_List` + `WHERE note_id IN (...)`。

### 2.4 Controller 设计

`GET /api/redbook/note/export` — GET 请求，参数逗号分隔：
- 不写临时文件，直接流式写入 response
- 异常时返回 JSON 错误（检查 response.isCommitted 决定能否切换）

---

## 三、QConfig 配置示例

### 3.1 task_executor_config.json

在 QConfig 平台 `task_executor_config.json` 中新增：
```json
{
  // ... 已有配置 ...

  "hotpredict-redbook-direct-crawl": {
    "type": "materialCrawl",
    "executorName": "directCrawl",
    "desc": "小红书笔记直接抓取",
    "hasSubExecutor": true,
    "dataSource": [
      {
        "type": "noteIds",
        "desc": "小红书笔记 ID 列表",
        "dataSourceExample": "{\"noteIdList\": [\"662df131000000002101aa61\", \"663120b10000000026012ce5\"]}"
      }
    ]
  }

  // ... 已有配置 ...
}
```

### 3.2 hotfile.properties

在 QConfig 平台 `hotfile.properties` 中，追加 `directCrawl` 到 `material.process.source`：
```properties
material.process.source = MaterialCrawlExecutor,hotPredictRedbookPreCrawl,hotPredictRedbookPostCrawl,directCrawl
```

### 3.3 前端执行器类型标签

在 QConfig 平台 `task_common_config.properties` 中，`executor.type.labels` 已有 `materialCrawl` 配置，无需修改。DirectCrawl 复用 `materialCrawl` 类型标签（"素材抓取"）：

```properties
# materialCrawl 类型标签已经存在，无需新增
executor.type.labels = materialCrawl:素材抓取,aiTag:AI打标,mediaInfo:媒体信息,stats:数据统计
```

### 3.4 效果

配置完成后，前端 `/task/create` 页面自动加载：
1. **选择类型** → 下拉出现 "素材抓取"（已有）
2. **选择执行器** → 下拉出现 "小红书笔记直接抓取"
3. **数据源** → 自动填充示例 `{"noteIdList": ["662df...", "66312..."]}`

---

## 四、文件清单确认

### DirectCrawl 模块

| # | 文件 | 动作 | 说明 |
|---|------|------|------|
| 1 | `service/task/executor/material/DirectCrawlExecutor.java` | 新增 | 继承 MaterialCrawlExecutor |
| 2 | `service/crawl/result/handler/DirectCrawlHandler.java` | 新增 | 继承 RedbookExecutorHandler |
| 3 | `service/material/HotPredictProcessStrategy.java` | 修改 1 行 | supports() 加 directCrawl |

### Excel 导出模块

| # | 文件 | 动作 | 说明 |
|---|------|------|------|
| 4 | `domain/dto/redbook/RedbookNoteExportVO.java` | 新增 | 23 字段 @ExcelProperty |
| 5 | `service/redbook/RedbookNoteExportService.java` | 新增 | 查询 + EasyExcel 写入 |
| 6 | `web/RedbookNoteExportController.java` | 新增 | GET /api/redbook/note/export |
| 7 | `infra/dao/RedbookNotePostMapper.java` | 新增方法 | selectByNoteIdList |
| 8 | `resources/mapper/RedbookNotePostMapper.xml` | 新增 SQL | selectByNoteIdList |

### QConfig 配置

| # | Key | 文件 | 说明 |
|---|-----|------|------|
| 9 | `hotpredict-redbook-direct-crawl` | task_executor_config.json | executor 定义 |
| 10 | `directCrawl` | material.process.source | 追加到扫描范围 |
