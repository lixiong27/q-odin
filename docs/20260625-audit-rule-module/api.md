# 审核规则模块 API 文档

## 基础信息

- **Base URL**: `/api`
- **统一响应格式**: `{ "code": 0, "msg": "success", "data": {} }`

---

## 1. 查询启用规则列表

对外暴露的查询接口，返回当前所有启用（`status=1`）且未删除的审核规则。

```
GET /api/audit/rule/queryEnabled
```

### 请求参数

无（及物动词 query）

### 响应示例

```json
{
  "code": 0,
  "msg": "success",
  "data": [
    {
      "id": 1,
      "firstCategory": "political_compliance",
      "firstCategoryName": "政治合规",
      "secondCategory": "political_red_line",
      "secondCategoryName": "政法红线",
      "ruleName": "政法红线违规检测",
      "riskLevel": "S",
      "riskLevelName": "S - 高风险",
      "businessLines": "[\"all\"]",
      "businessLineList": ["all"],
      "businessLineNameList": ["全部业务线"],
      "accountScope": "[\"all\"]",
      "accountScopeList": ["all"],
      "accountScopeNameList": ["全部账号"],
      "description": "检测涉及政法红线的违规内容",
      "createdBy": "zhangsan",
      "updatedBy": "zhangsan",
      "status": 1,
      "createTime": "2026-06-25 10:00:00",
      "updateTime": "2026-06-25 10:00:00"
    }
  ]
}
```

---

## 2. 获取审核字典

```
GET /api/audit/dict
```

### 响应示例

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "firstCategories": [
      {
        "code": "political_compliance",
        "name": "政治合规",
        "children": [
          { "code": "political_red_line", "name": "政法红线" },
          { "code": "territorial_integrity", "name": "领土完整" },
          { "code": "leader_image", "name": "领导人形象" }
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
      { "code": "hotel", "name": "酒店" }
    ],
    "accountScopes": [
      { "code": "all", "name": "全部账号" },
      { "code": "normal", "name": "素人号" },
      { "code": "kos", "name": "KOS账号" },
      { "code": "blue_v", "name": "蓝V账号" }
    ]
  }
}
```

---

## 3. 审核规则分页列表

```
GET /api/audit/rule/list
```

### 请求参数

| 参数名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| pageNum | int | 否 | 页码，默认 1 |
| pageSize | int | 否 | 每页条数，默认 20 |
| firstCategory | string | 否 | 一级分类编码（筛选） |
| riskLevel | string | 否 | 风险等级（筛选） |
| status | int | 否 | 状态 0/1（筛选） |

---

## 4. 审核规则详情

```
GET /api/audit/rule/detail?id=1
```

---

## 5. 规则名称查重

```
GET /api/audit/rule/checkName?ruleName=xxx&excludeId=1
```

---

## 6. 创建审核规则

```
POST /api/audit/rule/create
```

### 请求体

```json
{
  "firstCategory": "political_compliance",
  "secondCategory": "political_red_line",
  "ruleName": "政法红线违规检测",
  "riskLevel": "S",
  "businessLines": ["flight", "hotel"],
  "accountScope": ["kos", "blue_v"],
  "description": "规则描述"
}
```

---

## 7. 更新审核规则

```
POST /api/audit/rule/update
```

---

## 8. 删除审核规则

```
POST /api/audit/rule/delete
```

---

## 9. 启用/停用审核规则

```
POST /api/audit/rule/toggle
```

---

## 数据模型

### AuditRule

| 字段 | 类型 | 说明 |
|------|------|------|
| id | Long | 主键ID |
| firstCategory | String | 一级分类编码 |
| firstCategoryName | String | 一级分类名称（查询时回填） |
| secondCategory | String | 二级分类编码 |
| secondCategoryName | String | 二级分类名称（查询时回填） |
| ruleName | String | 规则名称，全局唯一 |
| riskLevel | String | 风险等级：S-高风险，A-中风险 |
| riskLevelName | String | 风险等级名称（查询时回填） |
| businessLines | String | 适用业务线 JSON 字符串 |
| businessLineList | List\<String\> | 适用业务线编码列表（查询时回填） |
| businessLineNameList | List\<String\> | 适用业务线名称列表（查询时回填） |
| accountScope | String | 管控账号范围 JSON 字符串 |
| accountScopeList | List\<String\> | 管控账号范围编码列表（查询时回填） |
| accountScopeNameList | List\<String\> | 管控账号范围名称列表（查询时回填） |
| description | String | 规则描述 |
| createdBy | String | 创建人 |
| updatedBy | String | 修改人 |
| status | Integer | 状态：0-停用，1-启用 |
| createTime | Date | 创建时间 |
| updateTime | Date | 更新时间 |
