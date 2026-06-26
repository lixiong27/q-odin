# 审核规则模块开发进度

## 项目概述

**项目名称**：审核规则模块

**目标**：实现审核规则 CRUD + QConfig 字典驱动配置，前端多页面实现（列表页 + 新建/编辑页）

---

## 开发阶段

### 阶段一：设计文档 ✅

| 任务 | 状态 | 说明 |
|------|------|------|
| 设计文档 | ✅ 已完成 | 表设计、接口设计、QConfig 字典设计、前后端方案 |

### 阶段二：数据库 & QConfig ✅

| 任务 | 状态 | 说明 |
|------|------|------|
| 建表脚本 (audit_rule) | ✅ 已完成 | `odin_server/docs/sql/audit_rule_schema.sql` |
| audit_dict.json QConfig 配置 | ❌ 待开始 | 需在 QConfig 平台手动创建配置项 |

### 阶段三：后端开发 ✅

| 任务 | 状态 | 说明 |
|------|------|------|
| AuditDictQConfig + POJO | ✅ 已完成 | `infra/qconfig/AuditDictQConfig.java` + `domain/dto/audit/` |
| AuditRule 实体 | ✅ 已完成 | `domain/entity/audit/AuditRule.java` |
| AuditRuleMapper + XML | ✅ 已完成 | `infra/dao/AuditRuleMapper.java` + `resources/mapper/AuditRuleMapper.xml` |
| Request/Response 对象 | ✅ 已完成 | `domain/request/audit/` 7 个 + `domain/response/audit/` 6 个 |
| AuditRuleService | ✅ 已完成 | `service/audit/AuditRuleService.java`（含唯一校验、分类联动校验、互斥逻辑、字典名称回填） |
| AuditRuleController | ✅ 已完成 | `web/AuditRuleController.java`（8 个 REST 接口） |

### 阶段四：前端开发 ✅

| 任务 | 状态 | 说明 |
|------|------|------|
| audit.js API 封装 | ✅ 已完成 | `src/api/audit.js`（8 个接口封装） |
| 审核规则列表页 list.jsx | ✅ 已完成 | 筛选栏 + 表格 + 分页 + 启用/停用/删除 |
| 新建/编辑页 create.jsx | ✅ 已完成 | 二级联动 + 互斥选择 + 名称唯一校验（blur 校验） |
| 路由配置 | ✅ 已完成 | `config/config.js` 审核模块 3 条路由 |

### 阶段五：联调测试

| 任务 | 状态 | 说明 |
|------|------|------|
| 功能测试 | ❌ 待开始 | CRUD + 联动 + 互斥逻辑 |
| 边界测试 | ❌ 待开始 | 规则名称超长/重名、空选项等 |

---

## 当前进度

**当前阶段：** 后端 & 前端开发已完成，待联调测试

**已完成：**
- SQL 建表脚本
- 后端完整 CRUD（QConfig + Entity + Mapper + Service + Controller）
- 前端完整页面（列表页 + 创建/编辑页 + 路由配置）
- progress.md 更新

**待开始：**
- QConfig 平台配置 `audit_dict.json`
- DBA 执行建表脚本
- 联调测试

**下一步：**
- 联调测试

---

## 关键约定

### 接口规范
- 统一前缀：`/api`
- 统一响应格式：`{ code: 0, message: "success", data: {} }`

### QConfig 键名
- 字典配置：`audit_dict.json`

### 数据库
- 表名：`audit_rule`
- 业务唯一键：`rule_name`

### 前端路由
- 列表页：`/audit/rule/list`
- 新建页：`/audit/rule/create`
- 编辑页：`/audit/rule/edit/:id`

### 已创建文件清单

**后端（7 个目录 / 14 个文件）：**

| 层级 | 文件 |
|------|------|
| DDL | `odin_server/docs/sql/audit_rule_schema.sql` |
| QConfig POJO | `domain/dto/audit/AuditDict.java`, `CategoryItem.java`, `DictItem.java` |
| QConfig 配置 | `infra/qconfig/AuditDictQConfig.java` |
| Entity | `domain/entity/audit/AuditRule.java` |
| Mapper | `infra/dao/AuditRuleMapper.java`, `resources/mapper/AuditRuleMapper.xml` |
| Request | `domain/request/audit/` (7 files) |
| Response | `domain/response/audit/` (6 files) |
| Service | `service/audit/AuditRuleService.java` |
| Controller | `web/AuditRuleController.java` |

**前端（3 个文件）：**

| 文件 | 说明 |
|------|------|
| `src/api/audit.js` | API 封装 |
| `src/pages/audit/rule/list.jsx` | 列表页 |
| `src/pages/audit/rule/create.jsx` | 新建/编辑页 |
| `config/config.js` | 路由配置（已修改） |
