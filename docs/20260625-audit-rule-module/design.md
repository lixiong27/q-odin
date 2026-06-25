# 审核规则模块设计文档

## 一、模块概述

### 1.1 功能定位

审核规则模块负责维护社媒内容审核的规则配置。通过可配置的规则引擎，支持按分类、风险等级、业务线、账号范围等多维度组合，实现对内容的自动化审核管控。

### 1.2 核心能力

| 能力 | 说明 |
|------|------|
| 审核规则 CRUD | 规则的创建、编辑、删除、查询 |
| 二级分类联动 | 一级分类切换后，二级分类清空并刷新可选值 |
| QConfig 字典驱动 | 分类枚举、业务线、账号范围等字典项通过 QConfig 热加载 |
| 规则去重校验 | 规则名称全局唯一 |

### 1.3 业务流程

```
QConfig (audit_dict.json) → 前端加载字典 → 用户配置规则 → 保存到 audit_rule 表
```

---

## 二、数据模型

### 2.1 审核规则表 (audit_rule)

| 字段 | 类型 | 说明 |
|------|------|------|
| id | BIGINT | 主键，自增 |
| first_category | VARCHAR(64) | 一级分类编码（如：political_compliance） |
| second_category | VARCHAR(64) | 二级分类编码（如：political_red_line） |
| rule_name | VARCHAR(30) | 规则名称，全局唯一 |
| risk_level | VARCHAR(4) | 风险等级：S-高风险、A-中风险 |
| business_lines | VARCHAR(500) | 适用业务线，JSON 数组（如：["all","flight","hotel"]） |
| account_scope | VARCHAR(500) | 管控账号范围，JSON 数组（如：["all","kos","blue_v"]） |
| status | TINYINT | 状态 0-停用 1-启用 |
| deleted | TINYINT | 软删标记 0-未删除 1-已删除 |
| create_time | DATETIME | 创建时间 |
| update_time | DATETIME | 更新时间 |

**核心约束：**
- `rule_name` 业务唯一（全局去重）
- `first_category`、`second_category` 非空
- `business_lines`、`account_scope` 存储 JSON 字符串

### 2.2 建表语句

```sql
CREATE TABLE `audit_rule` (
    `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `first_category` VARCHAR(64) NOT NULL COMMENT '一级分类编码',
    `second_category` VARCHAR(64) NOT NULL COMMENT '二级分类编码',
    `rule_name` VARCHAR(30) NOT NULL COMMENT '规则名称',
    `risk_level` VARCHAR(4) NOT NULL DEFAULT 'S' COMMENT '风险等级：S-高风险，A-中风险',
    `business_lines` VARCHAR(500) NOT NULL DEFAULT '' COMMENT '适用业务线，JSON数组',
    `account_scope` VARCHAR(500) NOT NULL DEFAULT '' COMMENT '管控账号范围，JSON数组',
    `status` TINYINT NOT NULL DEFAULT 1 COMMENT '状态：0-停用，1-启用',
    `deleted` TINYINT NOT NULL DEFAULT 0 COMMENT '删除标记：0-未删除，1-已删除',
    `create_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_rule_name` (`rule_name`),
    KEY `idx_first_category` (`first_category`),
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='审核规则表';
```

---

## 三、QConfig 配置设计

### 3.1 audit_dict.json

```json
{
  "firstCategories": [
    {
      "code": "political_compliance",
      "name": "政治合规",
      "children": [
        { "code": "political_red_line", "name": "政法红线" },
        { "code": "territorial_integrity", "name": "领土完整" },
        { "code": "leader_image", "name": "领导人形象" }
      ]
    },
    {
      "code": "content_safety",
      "name": "内容安全",
      "children": [
        { "code": "pornographic", "name": "色情低俗" },
        { "code": "violence", "name": "暴力血腥" },
        { "code": "gambling", "name": "赌博欺诈" }
      ]
    },
    {
      "code": "ad_compliance",
      "name": "广告合规",
      "children": [
        { "code": "false_ad", "name": "虚假宣传" },
        { "code": "competitive_ad", "name": "竞品引流" },
        { "code": "unauthorized_brand", "name": "未经授权品牌使用" }
      ]
    },
    {
      "code": "intellectual_property",
      "name": "知识产权",
      "children": [
        { "code": "copyright_infringement", "name": "版权侵权" },
        { "code": "trademark_infringement", "name": "商标侵权" }
      ]
    }
  ],
  "riskLevels": [
    { "code": "S", "name": "S - 高风险" },
    { "code": "A", "name": "A - 中风险" }
  ],
  "businessLines": [
    { "code": "all", "name": "全部业务线" },
    { "code": "flight", "name": "机票" },
    { "code": "hotel", "name": "酒店" },
    { "code": "train", "name": "火车票" },
    { "code": "vacation", "name": "度假" },
    { "code": "ticket", "name": "门票" },
    { "code": "car", "name": "用车" }
  ],
  "accountScopes": [
    { "code": "all", "name": "全部账号" },
    { "code": "normal", "name": "素人号" },
    { "code": "kos", "name": "KOS账号" },
    { "code": "blue_v", "name": "蓝V账号" }
  ]
}
```

### 3.2 QConfig 配置类

```java
@Slf4j
@Service
public class AuditDictQConfig {

    @Getter
    private volatile AuditDict dict = new AuditDict();

    @QConfig("audit_dict.json")
    private void onChanged(String json) {
        if (StringUtils.isBlank(json)) {
            return;
        }
        try {
            AuditDict newDict = JsonUtils.jsonToObject(json, AuditDict.class);
            if (newDict != null) {
                dict = newDict;
                log.info("Audit dict loaded, firstCategories={}, businessLines={}, accountScopes={}",
                    newDict.getFirstCategories().size(),
                    newDict.getBusinessLines().size(),
                    newDict.getAccountScopes().size());
            }
        } catch (Exception e) {
            log.error("Failed to parse audit_dict.json", e);
        }
    }
}
```

### 3.3 AuditDict POJO 结构

```java
@Data
public class AuditDict {
    private List<CategoryItem> firstCategories;
    private List<DictItem> riskLevels;
    private List<DictItem> businessLines;
    private List<DictItem> accountScopes;
}

@Data
public class CategoryItem {
    private String code;
    private String name;
    private List<DictItem> children;
}

@Data
public class DictItem {
    private String code;
    private String name;
}
```

---

## 四、API 接口设计

### 4.1 接口列表

| 接口 | 方法 | 说明 |
|------|------|------|
| `/api/audit/rule/create` | POST | 创建审核规则 |
| `/api/audit/rule/update` | POST | 更新审核规则 |
| `/api/audit/rule/delete` | POST | 删除审核规则（软删） |
| `/api/audit/rule/toggle` | POST | 启用/停用审核规则 |
| `/api/audit/rule/list` | GET | 审核规则列表（分页） |
| `/api/audit/rule/detail` | GET | 审核规则详情 |
| `/api/audit/rule/checkName` | GET | 校验规则名称是否已存在 |
| `/api/audit/dict` | GET | 获取审核字典（分类、业务线等） |

### 4.2 接口详情

#### 4.2.1 创建审核规则

```
POST /api/audit/rule/create
```

**Request:**
```json
{
  "firstCategory": "political_compliance",
  "secondCategory": "political_red_line",
  "ruleName": "政法红线违规检测",
  "riskLevel": "S",
  "businessLines": ["flight", "hotel"],
  "accountScope": ["kos", "blue_v"]
}
```

**Response:**
```json
{
  "code": 0,
  "msg": "success",
  "data": 1
}
```

#### 4.2.2 更新审核规则

```
POST /api/audit/rule/update
```

**Request:**
```json
{
  "id": 1,
  "firstCategory": "political_compliance",
  "secondCategory": "political_red_line",
  "ruleName": "政法红线违规检测",
  "riskLevel": "A",
  "businessLines": ["all"],
  "accountScope": ["all"]
}
```

#### 4.2.3 删除审核规则

```
POST /api/audit/rule/delete
```

**Request:**
```json
{ "id": 1 }
```

#### 4.2.4 启用/停用

```
POST /api/audit/rule/toggle
```

**Request:**
```json
{ "id": 1, "status": 0 }
```

#### 4.2.5 审核规则列表（分页）

```
GET /api/audit/rule/list?pageNum=1&pageSize=20&firstCategory=political_compliance&riskLevel=S&status=1
```

**Response:**
```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "list": [
      {
        "id": 1,
        "firstCategory": "political_compliance",
        "firstCategoryName": "政治合规",
        "secondCategory": "political_red_line",
        "secondCategoryName": "政法红线",
        "ruleName": "政法红线违规检测",
        "riskLevel": "S",
        "riskLevelName": "S - 高风险",
        "businessLines": ["flight", "hotel"],
        "businessLineNames": ["机票", "酒店"],
        "accountScope": ["kos", "blue_v"],
        "accountScopeNames": ["KOS账号", "蓝V账号"],
        "status": 1,
        "createTime": "2026-06-25 10:00:00",
        "updateTime": "2026-06-25 10:00:00"
      }
    ],
    "total": 1
  }
}
```

#### 4.2.6 规则名称查重

```
GET /api/audit/rule/checkName?ruleName=xxx&excludeId=1
```

**Response:**
```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "exists": false
  }
}
```

`excludeId` 用于编辑时排除自身。

#### 4.2.7 获取审核字典

```
GET /api/audit/dict
```

**Response:**
```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "firstCategories": [...],
    "riskLevels": [...],
    "businessLines": [...],
    "accountScopes": [...]
  }
}
```

---

## 五、实体设计

### 5.1 Entity

```java
@Data
public class AuditRule {
    private Long id;
    private String firstCategory;
    private String secondCategory;
    private String ruleName;
    private String riskLevel;
    private String businessLines;     // JSON 字符串
    private String accountScope;      // JSON 字符串
    private Integer status;
    private Integer deleted;
    private Date createTime;
    private Date updateTime;

    // 非数据库字段，查询时填充
    private String firstCategoryName;
    private String secondCategoryName;
    private String riskLevelName;
    private List<String> businessLineList;
    private List<String> businessLineNameList;
    private List<String> accountScopeList;
    private List<String> accountScopeNameList;
}
```

### 5.2 Request

```java
@Data
public class AuditRuleCreateRequest {
    @NotBlank private String firstCategory;
    @NotBlank private String secondCategory;
    @NotBlank @Size(max = 30) private String ruleName;
    @NotBlank private String riskLevel;
    @NotEmpty private List<String> businessLines;
    @NotEmpty private List<String> accountScope;
}

@Data
public class AuditRuleUpdateRequest {
    @NotNull private Long id;
    @NotBlank private String firstCategory;
    @NotBlank private String secondCategory;
    @NotBlank @Size(max = 30) private String ruleName;
    @NotBlank private String riskLevel;
    @NotEmpty private List<String> businessLines;
    @NotEmpty private List<String> accountScope;
}

@Data
public class AuditRuleDeleteRequest {
    @NotNull private Long id;
}

@Data
public class AuditRuleToggleRequest {
    @NotNull private Long id;
    @NotNull private Integer status;
}

@Data
public class AuditRuleListRequest {
    private Integer pageNum = 1;
    private Integer pageSize = 20;
    private String firstCategory;
    private String riskLevel;
    private Integer status;
}

@Data
public class AuditRuleDetailRequest {
    @NotNull private Long id;
}

@Data
public class AuditRuleCheckNameRequest {
    @NotBlank private String ruleName;
    private Long excludeId;
}
```

### 5.3 Response

```java
@Data @EqualsAndHashCode(callSuper = true)
public class AuditRuleCreateResponse extends BaseResponse {
    private Long data;
}

@Data @EqualsAndHashCode(callSuper = true)
public class AuditRuleListResponse extends BaseResponse {
    private PageResult<AuditRule> data;
}

@Data @EqualsAndHashCode(callSuper = true)
public class AuditRuleDetailResponse extends BaseResponse {
    private AuditRule data;
}

@Data @EqualsAndHashCode(callSuper = true)
public class AuditRuleCheckNameResponse extends BaseResponse {
    private Map<String, Boolean> data;
}

@Data @EqualsAndHashCode(callSuper = true)
public class AuditDictResponse extends BaseResponse {
    private AuditDict data;
}
```

---

## 六、后端代码结构

```
domain/
├── entity/
│   └── audit/
│       └── AuditRule.java
│   └── common/
│       ├── BaseResponse.java
│       ├── BusinessException.java
│       ├── PageResult.java
│       └── ResultEnum.java
├── request/
│   └── audit/
│       ├── AuditRuleCreateRequest.java
│       ├── AuditRuleUpdateRequest.java
│       ├── AuditRuleDeleteRequest.java
│       ├── AuditRuleToggleRequest.java
│       ├── AuditRuleListRequest.java
│       ├── AuditRuleDetailRequest.java
│       └── AuditRuleCheckNameRequest.java
├── response/
│   └── audit/
│       ├── AuditRuleCreateResponse.java
│       ├── AuditRuleListResponse.java
│       ├── AuditRuleDetailResponse.java
│       ├── AuditRuleCheckNameResponse.java
│       └── AuditDictResponse.java
└── dto/
    └── audit/
        ├── AuditDict.java
        ├── CategoryItem.java
        └── DictItem.java

infra/
├── dao/
│   └── AuditRuleMapper.java
└── qconfig/
    └── AuditDictQConfig.java

service/
└── audit/
    ├── AuditRuleService.java
    └── impl/
        └── AuditRuleServiceImpl.java

web/
└── AuditRuleController.java

resources/mapper/
└── AuditRuleMapper.xml
```

---

## 七、核心业务逻辑

### 7.1 创建规则校验

```
1. ruleName 全局唯一性校验
2. firstCategory 有效性校验（从 QConfig 字典中检查）
3. secondCategory 有效性校验（必须属于 firstCategory 的子项）
4. riskLevel 有效性校验
5. businessLines 校验（含"全部业务线"时互斥其他选项）
6. accountScope 校验（含"全部账号"时互斥其他选项）
7. businessLines / accountScope 序列化为 JSON 字符串存库
```

### 7.2 业务线 / 账号范围互斥规则

```
"全部业务线" (all) 与其它业务线互斥：
  - 选择 all → 自动清除其他选项
  - 已选其他 → 点击 all → 清除其他，仅保留 all

"全部账号" (all) 与其它账号范围互斥：
  - 选择 all → 自动清除其他选项
  - 已选其他 → 点击 all → 清除其他，仅保留 all
```

### 7.3 二级分类联动逻辑

```
1. 一级分类变更时：
   - 清空二级分类已选项
   - 从 QConfig 字典中取出 firstCategory 对应的 children 列表
   - 刷新二级分类下拉选项
2. 二级分类无选项时禁用选择
3. 只选择一级分类不选择二级分类视为不完整的规则，不允许提交
```

---

## 八、前端设计

### 8.1 页面路由

| 路由 | 页面 | 说明 |
|------|------|------|
| `/audit/rule/list` | 审核规则列表 | 规则列表页，支持搜索和筛选 |
| `/audit/rule/create` | 新建审核规则 | 表单页，创建新规则 |
| `/audit/rule/edit/:id` | 编辑审核规则 | 表单页，编辑已有规则 |

### 8.2 路由配置

```javascript
// config/config.js 新增路由
{ path: '/audit/rule/list', component: '@/pages/audit/rule/list' },
{ path: '/audit/rule/create', component: '@/pages/audit/rule/create' },
{ path: '/audit/rule/edit/:id', component: '@/pages/audit/rule/create' },
```

### 8.3 前端文件结构

```
src/
├── api/
│   └── audit.js                    — 审核模块 API
└── pages/
    └── audit/
        └── rule/
            ├── list.jsx            — 审核规则列表页
            └── create.jsx          — 新建/编辑规则页
```

### 8.4 API 封装 (src/api/audit.js)

```javascript
import request from './request';

export function getAuditDict() {
    return request.get('/audit/dict');
}

export function getAuditRuleList(params) {
    return request.get('/audit/rule/list', { params });
}

export function getAuditRuleDetail(id) {
    return request.get('/audit/rule/detail', { params: { id } });
}

export function checkRuleName(ruleName, excludeId) {
    return request.get('/audit/rule/checkName', { params: { ruleName, excludeId } });
}

export function createAuditRule(data) {
    return request.post('/audit/rule/create', data);
}

export function updateAuditRule(data) {
    return request.post('/audit/rule/update', data);
}

export function deleteAuditRule(id) {
    return request.post('/audit/rule/delete', { id });
}

export function toggleAuditRule(id, status) {
    return request.post('/audit/rule/toggle', { id, status });
}
```

### 8.5 列表页核心交互

- 头部筛选：一级分类下拉、风险等级下拉、状态切换
- 表格列：ID、一级分类、二级分类、规则名称、风险等级（Tag 色标 S=red/A=orange）、适用业务线（Tags）、管控账号范围（Tags）、状态、操作
- 操作列：编辑、启用/停用、删除（Popconfirm 二次确认）
- 新建按钮 → 跳转 `/audit/rule/create`
- 编辑按钮 → 跳转 `/audit/rule/edit/${id}`

### 8.6 表单页核心交互

- 表单顶部标题：「新建审核规则」/「编辑审核规则」
- 一级分类：Select，选项来自 QConfig，onChange 联动二级分类
- 二级分类：Select，disabled 当一级未选或无子项，options 由一级分类 children 决定
- 规则名称：Input，最大 30 字，失去焦点或 onBlur 校验唯一性（调用 checkName）
- 风险等级：Radio.Group，默认选中 S
- 适用业务线：Select mode="multiple"，含"全部业务线"互斥逻辑
- 管控账号范围：Select mode="multiple"，含"全部账号"互斥逻辑
- 提交：调用 create/update 接口，成功后跳转列表页
- 取消：返回列表页

### 8.7 互斥选择逻辑

```javascript
// 业务线/账号范围互斥处理
const handleMutualExclusive = (selected, key) => {
    const allCode = key === 'businessLines' ? 'all' : 'all';
    if (selected.includes(allCode)) {
        // 选了"全部" → 清除其他选项
        return [allCode];
    }
    return selected;
};
```

---

## 九、字段校验规则汇总

| 字段 | 组件类型 | 校验 / 交互规则 |
|------|---------|----------------|
| 一级分类 | 下拉单选 | 选项：QConfig 配置；必填，无默认值 |
| 二级分类 | 下拉单选 | 联动一级分类（一级切换后清空并刷新）；枚举值 QConfig 配置；必填，无默认值 |
| 规则名称 | 输入框 | 必填，最多 30 字，全局唯一（异步校验） |
| 风险等级 | 单选按钮 | S - 高风险（默认选中）、A - 中风险；必填 |
| 适用业务线 | 下拉多选 | 必填；选项含"全部业务线"互斥；多选时只能选全部或其他 |
| 管控账号范围 | 下拉多选 | 必填；选项含"全部账号"互斥；多选时只能选全部或其他 |

---

## 十、参考文档

- 后端代码风格：`infra/tec-coding-style.md`
- 技术组件使用：`infra/tec-components.md`
- 业务模块文档：`infra/biz-modules.md`
- 进度模板：`docs/progress-template.md`
