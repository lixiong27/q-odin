# 素材落库策略架构改造方案

## 背景

当前 `MaterialProcessTask.doProcess()` 对所有的 `MaterialCrawlResult` 一视同仁，不区分 `source` 和 `crawlType` 就走同样的落库逻辑。

需要：
1. 按照 `source` + `crawlType` 做策略分发
2. **小红书 bigSearch** 跳过不落库
3. 当前逻辑作为 **default** 策略
4. 通过策略接口抽象

## 方案

### 接口设计

```java
public interface MaterialProcessStrategy {

    /**
     * 该策略是否支持处理指定的 source + crawlType。
     */
    boolean supports(String source, String crawlType);

    /**
     * 处理素材落库，返回失败节点列表。
     */
    List<Map<String, String>> process(MaterialCrawlResult result);
}
```

### 两个实现

| 策略 | `supports` 条件 | `process` 行为 |
|---|---|---|
| `DefaultMaterialProcessStrategy` | `!(redbook && bigSearch)` | 当前 `MaterialProcessService.process()` 逻辑 |
| `RedbookBigSearchSkipStrategy` | `redbook && bigSearch` | 直接返回空（跳过），日志记录 |

### 流程图

```
MaterialProcessTask.doProcess()
  │  subTaskService.getSuccessTasks("materialCrawl", ...)
  ▼
parseResult(subTask.getResult()) → MaterialCrawlResult
  │  result.source, result.crawlType
  ▼
findStrategy(source, crawlType)
  │
  ├── redbook + bigSearch → RedbookBigSearchSkipStrategy
  │     └── log.info("skip redbook bigSearch, keyword={}")
  │
  └── 其他 → DefaultMaterialProcessStrategy
        └── materialProcessService.process(result) → 当前逻辑
```

### 涉及文件

| 文件 | 改动类型 | 内容 |
|---|---|---|
| `MaterialProcessStrategy.java` | **新建** | 策略接口 |
| `DefaultMaterialProcessStrategy.java` | **新建** | 默认策略，委托 `MaterialProcessService` |
| `RedbookBigSearchSkipStrategy.java` | **新建** | 小红书 bigSearch 跳过策略 |
| `MaterialProcessTask.java` | 修改 | 注入策略列表，`doProcess()` 按 `source`+`crawlType` 分发 |
| `MaterialProcessService.java` | 不改 | 已有逻辑不变，作为 default 策略的底层委托 |

### JSON 分析（确认当前处理逻辑正确）

从提供的抖音 bigSearch 子任务 JSON 看，当前提取逻辑已覆盖：

| JSON 字段 | 目标字段 | 状态 |
|---|---|---|
| `sourceId` | material_base.sourceId | ✅ |
| `title` | material_base.title | ✅ |
| `authorId / authorName` | MaterialCrawlItem（传递用） | ✅ |
| `videoUrl` | → OSS 转存 → material_base.videoUrl | ✅ |
| `coverUrl` | material_video.coverUrl | ✅ |
| `duration / width / height` | material_video | ✅ |
| `videoFormat` | material_video.videoFormat | ✅ |
| `publishTime (yyyy-MM-dd HH:mm:ss)` | material_base.publishTime | ✅（修复后） |
| `publishUrl` | material_base.publishUrl | ✅ |
| `totalLikes / totalCollect` | material_metrics | ✅ |
| `label.commonTag / poi / city` | material_base.material_label | ✅ |

JSON 中的 `{}` 空对象，会在 `validate()` 阶段因 `materialId` 为空而自动过滤。

**结论：无需再调整数据提取逻辑**，重点是策略分发改造。

## 执行顺序

1. 新建 `MaterialProcessStrategy` 接口
2. 新建 `DefaultMaterialProcessStrategy`（委托 `MaterialProcessService`）
3. 新建 `RedbookBigSearchSkipStrategy`
4. 修改 `MaterialProcessTask.doProcess()` — 策略分发