# 代码风格规范

## 1. 响应对象模式

**BaseResponse 非泛型**，每个接口使用具体的响应类继承它：

```java
// 基类（非泛型）
@Data
public class BaseResponse {
    private int code;
    private String msg;
}

// 具体响应类
@Data
@EqualsAndHashCode(callSuper = true)
public class TagListResponse extends BaseResponse {
    private List<TagLeaf> data;  // 具体字段
}

// 简单操作直接返回 BaseResponse
public BaseResponse update(@RequestBody UpdateRequest request) {
    BaseResponse response = new BaseResponse();
    response.setCode(0);
    response.setMsg("success");
    return response;
}

// 带数据的操作返回具体响应类
public TagDetailResponse detail(@RequestParam Long id) {
    TagDetailResponse response = new TagDetailResponse();
    response.setData(entity);
    response.setCode(0);
    response.setMsg("success");
    return response;
}
```

**错误返回：**
```java
// 使用静态工厂方法
return BaseResponse.fail(-1, "错误信息");  // 简单返回
return BaseResponse.fail(e.getCode(), e.getMessage(), TagDetailResponse::new);  // 带具体类型
return BaseResponse.fail(ResultEnum.ERROR, TagDetailResponse::new);  // 使用枚举
```

## 2. 请求对象模式

**使用具体请求类**，禁止用 Map：

```java
@Data
public class TagCreateRequest {
    private String name;
    private Long categoryId;
    private Integer status;
}

@Data
public class BatchUpdateStatusRequest {
    private List<Long> ids;
    private Integer syncStatus;
}
```

## 3. Controller 规范

```java
@Slf4j
@RestController
@RequestMapping("/api/module/resource")
public class XxxController {

    @Resource
    private XxxService xxxService;

    @PostMapping("/create")
    public XxxCreateResponse create(@RequestBody XxxCreateRequest request) {
        XxxCreateResponse response = new XxxCreateResponse();
        try {
            Long id = xxxService.create(request);
            response.setData(id);
            response.setCode(0);
            response.setMsg("success");
        } catch (BusinessException e) {
            log.warn("Business error: {}", e.getMessage());
            return BaseResponse.fail(e.getCode(), e.getMessage(), XxxCreateResponse::new);
        } catch (Exception e) {
            log.error("Failed to create", e);
            return BaseResponse.fail(ResultEnum.ERROR, XxxCreateResponse::new);
        }
        return response;
    }
}
```

## 4. 分页查询

**请求对象包含分页参数：**

```java
@Data
public class ListRequest {
    private Integer pageNum = 1;
    private Integer pageSize = 20;
    // 其他查询条件...
}

// 响应包含 list + total
@Data
@EqualsAndHashCode(callSuper = true)
public class ListResponse extends BaseResponse {
    private List<XxxEntity> list;
    private Integer total;
}
```

## 5. 日志规范

```java
@Slf4j  // 使用 Lombok 注解
public class XxxService {
    // 业务异常用 warn
    log.warn("Business error: {}", e.getMessage());

    // 系统异常用 error
    log.error("Failed to process", e);

    // 关键信息用 info
    log.info("Task completed, total={}", count);
}
```

## 6. 异常处理

```java
// 业务异常
throw new BusinessException(code, message);

// 错误枚举
public enum ResultEnum {
    ERROR(-500, "系统错误"),
    NOT_FOUND(-404, "资源不存在");
}
```

## 7. 包结构

```
domain/
├── entity/          # 实体类（数据库映射）
│   ├── common/      # 公共实体
│   └── xxx/         # 业务实体
├── request/         # 请求对象
└── response/        # 响应对象

infra/
├── dao/             # Mapper 接口
├── qconfig/         # QConfig 配置
└── redis/           # Redis 服务

service/
├── XxxService.java      # 服务接口
└── impl/
    └── XxxServiceImpl.java

task/                # 定时任务
web/                 # Controller
```
