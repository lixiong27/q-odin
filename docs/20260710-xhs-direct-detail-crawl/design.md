# 小红书图文帖直接抓取 + Excel 导出

## 一、DirectCrawl — 小红书图文帖直接抓取

### 1.1 需求概述

现有抓取链路：
- **PreCrawl：** bigSearch → 作者过滤 → detail + userInfo → 入库
- **PostCrawl：** noteId → 查 DB 校验 → detail → 更新 metrics

新增 **DirectCrawl：**
- 外部传入 noteId 列表
- **不校验 DB**，允许传入未落库的 noteId
- 直接下发 detail 爬取 → 回调落库
- 不走 bigSearch / userInfo 链路

### 1.2 任务创建方式

**不走 `/api/assignTask`，通过现有的可视化 `/api/task/create` 创建。**

前端任务创建页面（`/task/create`）的 4 步向导：
1. **选择类型** — 选择 `materialCrawl`（素材抓取）
2. **选择执行器** — 选择 `hotpredict-redbook-direct-crawl`
3. **数据源** — 选择 `noteIds` 类型，粘贴 JSON 示例 `{"noteIdList": ["noteId1", "noteId2"]}`
4. **确认提交** — 调用 `POST /api/task/create` 创建 Task

`TaskService.createTask()` 接收 `TaskCreateRequest`：
```json
{
  "taskName": "小红书笔记直接抓取",
  "configKey": "hotpredict-redbook-direct-crawl",
  "dataSourceType": "noteIds",
  "data": {
    "noteIdList": ["662df...000", "66312...001"]
  }
}
```

TaskScheduler 自动调度 → `DirectCrawlExecutor.execute()`。

### 1.3 全流程架构

```
Client (前端可视化页面 /task/create)
  │ POST /api/task/create { configKey, dataSourceType:"noteIds", data:{noteIdList} }
  ▼
TaskService.createTask()
  │ → 从 QConfig 加载 ExecutorConfig
  │ → 构建 taskParams = { configKey, dataSourceType, data, executorSnapshot }
  │ → executor = "directCrawl", taskType = "materialCrawl"
  ▼
(QSchedule: mkt_odin_task_schedule)
TaskScheduler → DirectCrawlExecutor.execute()
  │ → 读取 data.noteIdList
  │ → 遍历每个 noteId（不校验 DB，全部创建 SubTask）
  │ → 可选查 DB 获取 xsecToken（有则带，无则 param 中不传）
  ▼
(QSchedule: mkt_odin_subtask_schedule)
DirectCrawlExecutor.subExecute()
  │ → CrawlTaskClient.createTask() 下发 detail 爬取
  ▼
Crawl Service → MQ 回调 → CrawlTaskResultProcessor
  ▼
XhsCrawlTaskResultHandler → DirectCrawlHandler.handleRedbookDetail()
  │ → 解析 NoteCard → 构造 NotePostData → NotePostCrawlResult
  │ → 存入 SubTask.result
  ▼
(QSchedule: mkt_odin_crawtask_material_process)
MaterialProcessTask → HotPredictProcessStrategy.process()
  │ → supports("directCrawl") → true
  │ → 上传图片到 OSS → 入库 redbook_note_post
  ▼
SubTask → ANALYSIS_SUCCESS
```

### 1.4 新增 & 修改组件

| 文件 | 动作 | 说明 |
|------|------|------|
| `DirectCrawlExecutor.java` | 新增 | TaskExecutor, name=`directCrawl`, extends MaterialCrawlExecutor |
| `DirectCrawlHandler.java` | 新增 | ExecutorHandler, executor=`directCrawl`, extends RedbookExecutorHandler |
| `HotPredictProcessStrategy.java` | 修改 | `supports()` 新增 `"directCrawl"` |
| `task_executor_config.json` (QConfig) | 修改 | 新增 `hotpredict-redbook-direct-crawl` 配置项 |

**不需要 `DirectCrawlTaskStrategy`** — 任务创建复用已有的 `/api/task/create` + `TaskService.createTask()`。

### 1.5 DirectCrawlExecutor

**execute() 流程：**
```
1. 从 taskParams.data.noteIdList 读取 noteId 列表
2. 遍历 noteIds（全部创建，无跳过）:
   a. 可选查 DB 获取 xsecToken（有则带上，无则 param 中不传此字段）
   b. 构建 MaterialCrawlSubTaskParams
   c. executor = "directCrawl"
3. 分批创建 SubTask（每批 100 条）
4. 更新父任务统计
```

**subExecute() 流程：**
```
1. 解析 subTaskParams → MaterialCrawlSubTaskParams
2. 提取 noteId / xsecToken（如为空则不传 xsecToken）
3. 构建 CrawlTaskRequest → CrawlTaskClient.createTask()
4. 即使下发失败也不影响 SubTask 状态（等待回调或重试）
```

### 1.6 DirectCrawlHandler

```java
@Component
public class DirectCrawlHandler extends RedbookExecutorHandler {
    @Override
    protected String getExecutorName() { return "directCrawl"; }

    @Override
    public void handleRedbookDetail(CrawlTaskResultContext context, Object parsedData) {
        // 解析 XhsCrawlDetailTaskResultData
        // 提取 NoteCard → 构造 NotePostData（同 PostCrawlHandler 逻辑）
        // 封装 NotePostCrawlResult → subTaskService.completeSubTask()
    }
}
```

### 1.7 QConfig 配置

`task_executor_config.json` 新增：
```json
"hotpredict-redbook-direct-crawl": {
  "type": "materialCrawl",
  "executorName": "directCrawl",
  "desc": "小红书笔记直接抓取",
  "hasSubExecutor": true,
  "dataSource": [{
    "type": "noteIds",
    "desc": "小红书笔记 ID 列表",
    "dataSourceExample": "{\"noteIdList\": [\"note1\", \"note2\"]}"
  }]
}
```

`material.process.source` 增加 `directCrawl`：
```
material.process.source = MaterialCrawlExecutor,hotPredictRedbookPreCrawl,hotPredictRedbookPostCrawl,directCrawl
```

---

## 二、Excel 导出接口

### 2.1 需求

接收 noteIdList，从 `redbook_note_post` 表查询完整数据，返回 `.xlsx` 文件。

- **数据范围**：仅 `redbook_note_post` 表，不关联 `redbook_author_info`
- **排除字段**：`id`、`create_time`、`update_time`
- **触发方式**：独立 HTTP 接口，直接返回文件流

### 2.2 接口定义

```
POST /api/redbook/note/export
请求体: {"noteIdList": ["id1", "id2", "id3"]}
响应: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet 文件流
```

### 2.3 实现

**新增文件：**

| 文件 | 包 | 说明 |
|------|---|------|
| `RedbookNoteExportVO.java` | `domain.dto.redbook` | Excel 导出 VO，`@ExcelProperty` 注解 |
| `RedbookNoteExportService.java` | `service.redbook` | 查询 + EasyExcel 写入 |
| `RedbookNoteExportController.java` | `web` | HTTP 端点 |

**RedbookNoteExportVO 字段（不包括 id/create_time/update_time）：**

| 列名 | 实体字段 | 说明 |
|------|---------|------|
| 笔记ID | noteId | String |
| 标题 | title | String |
| 笔记正文 | noteDesc | String |
| 笔记类型 | noteType | normal/video |
| 封面URL | coverUrl | String |
| 图片列表 | imageList | JSON String |
| 标签列表 | tagList | JSON String |
| IP属地 | ipLocation | String |
| 作者ID | authorId | String |
| 作者名称 | authorName | String |
| 作者头像 | authorAvatar | String |
| 点赞数 | totalLikes | Integer |
| 收藏数 | totalCollect | Integer |
| 评论数 | totalComments | Integer |
| 分享数 | totalShares | Integer |
| 发布时间 | publishTime | Date |
| 最后更新时间 | lastUpdateTime | Date |
| xsecToken | xsecToken | String |
| @用户列表 | atUserList | JSON String |
| 关键词 | keyword | String |
| 标签JSON | label | JSON String |
| 扩展信息 | extra | JSON String |
| 抓取时间 | crawlTime | Date |

**实现逻辑：**
```java
@Service
public class RedbookNoteExportService {
    
    public void exportToExcel(List<String> noteIds, HttpServletResponse response) {
        // 1. 查 DB
        List<RedbookNotePost> notes = redbookNotePostMapper.selectByNoteIdList(noteIds);
        
        // 2. 转 VO
        List<RedbookNoteExportVO> voList = notes.stream().map(this::convert).collect(...);
        
        // 3. EasyExcel 写回
        response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
        response.setHeader("Content-Disposition", "attachment; filename=redbook_notes.xlsx");
        EasyExcel.write(response.getOutputStream(), RedbookNoteExportVO.class)
                .sheet("小红书笔记")
                .doWrite(voList);
    }
}
```

**Mapper 新增方法：**
```xml
<select id="selectByNoteIdList" resultMap="BaseResultMap">
    SELECT <include refid="Base_Column_List"/>
    FROM redbook_note_post
    WHERE note_id IN
    <foreach collection="noteIds" item="noteId" open="(" separator="," close=")">
        #{noteId}
    </foreach>
</select>
```

### 2.4 涉及改造的文件

| 文件 | 动作 | 说明 |
|------|------|------|
| `RedbookNoteExportVO.java` | 新增 | Excel 导出 VO（23 字段） |
| `RedbookNoteExportService.java` | 新增 | 查询 + EasyExcel 导出 |
| `RedbookNoteExportController.java` | 新增 | `GET /api/redbook/note/export` |
| `RedbookNotePostMapper.java` | 修改 | 新增 `selectByNoteIdList` |
| `RedbookNotePostMapper.xml` | 修改 | 新增对应 SQL |

---

## 三、命名规范

### DirectCrawl

| 概念 | 命名 |
|------|------|
| executor 名称 / Bean name | `directCrawl` |
| Executor 类 | `DirectCrawlExecutor` |
| Handler 类 | `DirectCrawlHandler` |
| QConfig key | `hotpredict-redbook-direct-crawl` |
| task 编码前缀 | `DIRECTCRAWL_` |

### Excel Export

| 概念 | 命名 |
|------|------|
| VO 类 | `RedbookNoteExportVO` |
| Service 类 | `RedbookNoteExportService` |
| Controller 类 | `RedbookNoteExportController` |
| API 路径 | `GET /api/redbook/note/export` |

---

## 四、涉及改造的文件汇总

| # | 文件 | 动作 | 所属模块 |
|---|------|------|---------|
| 1 | `service/task/executor/material/DirectCrawlExecutor.java` | 新增 | DirectCrawl |
| 2 | `service/crawl/result/handler/DirectCrawlHandler.java` | 新增 | DirectCrawl |
| 3 | `service/material/HotPredictProcessStrategy.java` | 修改 1 行 | DirectCrawl |
| 4 | `domain/dto/redbook/RedbookNoteExportVO.java` | 新增 | Excel 导出 |
| 5 | `service/redbook/RedbookNoteExportService.java` | 新增 | Excel 导出 |
| 6 | `web/RedbookNoteExportController.java` | 新增 | Excel 导出 |
| 7 | `infra/dao/RedbookNotePostMapper.java` | 新增方法 | Excel 导出 |
| 8 | `resources/mapper/RedbookNotePostMapper.xml` | 新增 SQL | Excel 导出 |