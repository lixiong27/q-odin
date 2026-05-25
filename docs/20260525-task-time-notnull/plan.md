# task/sub_task 表 start_time/end_time 非空约束变更方案

> 代码层确保创建时写入默认值（当前时刻），避免 insert 产生 NULL

---

## 一、变更原因

- 创建 Task/SubTask 时 `start_time`/`end_time` 未设值，写入数据库为 NULL
- 下游查询、报表计算需额外处理 NULL 判断
- 代码层拦截比 DDL 约束更灵活，不依赖 DBA 执行

---

## 二、现状分析

### 2.1 表定义

**`task_schema.sql`** — task 表（第 53-54 行）和 sub_task 表（第 107-108 行）：
```sql
`start_time` DATETIME DEFAULT NULL COMMENT '实际开始时间',
`end_time` DATETIME DEFAULT NULL COMMENT '实际结束时间',
```

### 2.2 服务层创建入口

**task 表**：
- `TaskService.buildTask()` — 创建任务时组装 Task 对象，未设置 startTime/endTime

**sub_task 表**：
- `SubTaskService.createSubTask()` — 单个创建，未设置 startTime/endTime
- `SubTaskService.batchCreateSubTasks()` — 批量创建，未设置 startTime/endTime

### 2.3 MyBatis Mapper

| 文件 | 问题 |
|---|---|
| `SubTaskMapper.xml:48-60` | `batchInsert` **不含** `start_time`/`end_time` 列，代码设了值也写不进去 |
| `SubTaskMapper.xml:40-44` | `insert` 含这两列 |
| `TaskMapper.xml:42-48` | `insert` 含这两列 |

---

## 三、执行步骤

### Step 1: Java 代码修改

**`TaskService.java`** `buildTask()` 方法，在 `task.setErrorMsg("");` 之后追加：

```java
task.setStartTime(new Date());
task.setEndTime(new Date());
```

**`SubTaskService.java`** `createSubTask()` 方法，在 `subTask.setPriority(...)` 之后追加：

```java
subTask.setStartTime(new Date());
subTask.setEndTime(new Date());
```

**`SubTaskService.java`** `batchCreateSubTasks()` 循环内，在 `subTask.setPriority(...)` 之后追加：

```java
subTask.setStartTime(new Date());
subTask.setEndTime(new Date());
```

### Step 2: MyBatis Mapper 补充

**`SubTaskMapper.xml`** `batchInsert` 补充 `start_time`/`end_time` 列：

- INSERT 列列表增加 `start_time, end_time,`
- VALUES 部分增加 `#{item.startTime}, #{item.endTime},`

### Step 3: 回归验证

1. 创建新任务/子任务，观察写入的 `start_time`/`end_time` 为当前时刻而非 NULL
2. 确认已有旧数据的 NULL 行不受影响（如需要可单独清理）

---

## 四、影响范围

| 维度 | 影响 |
|---|---|
| 数据库 | 无 DDL 变更，零影响 |
| 后端 | 仅修改创建入口的方法，不影响已有逻辑 |
| 前端 | 无影响 |

---

## 五、回滚方案

回退 Java 代码和 Mapper XML 的修改即可，数据库无需任何操作。