# 分类&标签导出/导入 实现计划

> **For Claude:** 按此 plan 逐步实现

**目标：** 提供后端 API 将全部分类 & 标签导出为 JSON，并支持通过 JSON 导入（编码重复则跳过）

**架构：** 导出复用 `TagCategoryService.getCategoryTree()` 树形数据，转换为纯 code 引用的导出 DTO（无 DB ID）；导入按层级遍历，通过 `parentCode` 映射回 `parentId`，code 重复直接 skip。全部新增文件，零侵入现有代码。

**Tech Stack:** Java 17 + Spring Boot + MyBatis + Jackson (JsonUtils)

---

## 导出 JSON 格式

```json
{
  "categories": [
    {
      "code": "tech",
      "name": "技术",
      "parentCode": null,
      "isLeaf": 0,
      "sortOrder": 1,
      "description": "技术相关分类",
      "status": 1,
      "tagRule": {
        "selectMode": "SINGLE",
        "required": 1,
        "threshold": 0.8
      },
      "children": [...],
      "tags": [
        {
          "code": "react",
          "name": "React",
          "aiNeedFlag": 1,
          "aiDescription": "React框架相关",
          "tagDescription": "React前端框架",
          "sortOrder": 1,
          "status": 1
        }
      ]
    }
  ]
}
```

---

## 新增文件

| # | 文件 | 说明 |
|---|------|------|
| 1 | `TagExportData.java` | 导出/导入顶层 DTO，含 `List<CategoryExportNode> categories` |
| 2 | `CategoryExportNode.java` | 分类导出节点，含 code/name/parentCode/isLeaf/.../tagRule/children/tags |
| 3 | `TagExportLeaf.java` | 叶子标签导出 DTO |
| 4 | `ImportResult.java` | 导入结果，含 imported/skipped/skippedCodes |
| 5 | `TagExportService.java` | 导出/导入业务逻辑 |
| 6 | `TagExportController.java` | `/api/tag/export` + `/api/tag/import` 端点 |

**修改文件：** 无

---

## 详细设计

### Task 1: 导出 DTO 类 (3个)

**`TagExportData.java`** - 包路径：`domain/dto/tag/TagExportData.java`

```java
@Data
public class TagExportData {
    private List<CategoryExportNode> categories;
}
```

**`CategoryExportNode.java`** - 包路径：`domain/dto/tag/CategoryExportNode.java`

```java
@Data
public class CategoryExportNode {
    private String code;
    private String name;
    private String parentCode;
    private Integer isLeaf;
    private Integer sortOrder;
    private String description;
    private Integer status;
    private TagRule tagRule;
    private List<CategoryExportNode> children;
    private List<TagExportLeaf> tags;
}
```

**`TagExportLeaf.java`** - 包路径：`domain/dto/tag/TagExportLeaf.java`

```java
@Data
public class TagExportLeaf {
    private String code;
    private String name;
    private Integer aiNeedFlag;
    private String aiDescription;
    private String tagDescription;
    private Integer sortOrder;
    private Integer status;
}
```

### Task 2: 导入结果 DTO

**`ImportResult.java`** - 包路径：`domain/dto/tag/ImportResult.java`

```java
@Data
public class ImportResult {
    private int imported;
    private int skipped;
    private List<String> skippedCodes;
}
```

### Task 3: TagExportService

**包路径：** `service/tag/TagExportService.java`

**导出逻辑：**

```
1. tagCategoryService.getCategoryTree() 获取完整树
2. 递归转换为 List<CategoryExportNode>：
   - category.id → 忽略
   - category.parentId → 查对应 code 填入 parentCode（0 则 null）
   - category.extParam → 解析 tagRule 填入 tagRule 字段
   - category.children → 递归转换
   - category.tags → 转换为 List<TagExportLeaf>
3. 包装为 TagExportData 返回
```

**导入逻辑：**

```
1. 参数校验：TagExportData 非空，categories 非空
2. 遍历 categories 列表（注意：入参是扁平列表or树均可，先处理树形）
   对于树形结构：
   ① 第一遍：按层级遍历，收集所有节点到扁平列表
   ② 按 sortOrder 排序（同层按 sortOrder，不同层按 level 先后）
   ③ 遍历处理每个 category：
      - selectByCode(code) 查是否已存在
      - 已存在 → skipped++，记录 code
      - 不存在 → insert，记录 code→newId 到 Map
      - 根据 parentCode 从 Map 取 parentId，未关联则为 0
      - 计算 level（parentLevel + 1 或 1）
      - 先 insert 获得 id → 再 update path
   ④ 遍历处理每个 leaf 分类下的 tag：
      - selectByCode(code) 查是否已存在
      - 已存在 → skipped++
      - 不存在 → insert，categoryId 从 code→id Map 取
3. 返回 ImportResult
```

**Transaction**：整个导入使用 `@Transactional(rollbackFor = Exception.class)`，部分失败整体回滚。

### Task 4: TagExportController

**包路径：** `web/TagExportController.java`

| Method | Route | 说明 |
|--------|-------|------|
| GET | `/api/tag/export` | 导出全部分类&标签为 JSON |
| POST | `/api/tag/import` | 导入 JSON 数据 |

```java
@Slf4j
@RestController
@RequestMapping("/api/tag")
public class TagExportController {

    @Resource
    private TagExportService tagExportService;

    @GetMapping("/export")
    public BaseResponse<TagExportData> export() {
        try {
            TagExportData data = tagExportService.exportData();
            return BaseResponse.success(data);
        } catch (Exception e) {
            log.error("Failed to export tags", e);
            return BaseResponse.fail(ResultEnum.ERROR);
        }
    }

    @PostMapping("/import")
    public BaseResponse<ImportResult> import_(@RequestBody TagExportData importData) {
        try {
            ImportResult result = tagExportService.importData(importData);
            return BaseResponse.success("导入完成", result);
        } catch (BusinessException e) {
            log.warn("Business error importing tags: {}", e.getMessage());
            return BaseResponse.fail(e.getCode(), e.getMessage());
        } catch (Exception e) {
            log.error("Failed to import tags", e);
            return BaseResponse.fail(ResultEnum.ERROR);
        }
    }
}
```

### Task 5: 编译验证

```bash
cd odin_server && mvn compile -q
```

预期结果：`BUILD SUCCESS`

---

## 检查项

- [x] 导出 DTO 3 个（TagExportData / CategoryExportNode / TagExportLeaf）
- [x] 导入结果 DTO（ImportResult）
- [x] TagExportService（exportData / importData）
- [x] TagExportController（/api/tag/export + /api/tag/import）
- [x] 编译通过
- [ ] 提交代码