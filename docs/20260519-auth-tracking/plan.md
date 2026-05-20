# 埋点方案（第一期）

> 基于 AOP 切面异步落库，暂不接入 QSSO/UPMS 鉴权

---

## 整体架构

```
                         ┌──────────────────────────────┐
                         │   TrackAspect (@Around)       │
                         │   @TrackApi("content.search") │
                         │   异步落库 track_record 表     │
                         └──────────┬───────────────────┘
                                    │
                         ┌──────────▼───────────────────┐
                         │   Controller (业务逻辑)        │
                         └──────────────────────────────┘
```

---

## 一、新增依赖

```xml
<!-- Spring AOP (Spring Boot auto-configures @EnableAspectJAutoProxy) -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-aop</artifactId>
</dependency>
```

---

## 二、表结构

```sql
DROP TABLE IF EXISTS `track_record`;
CREATE TABLE `track_record` (
    `id`          BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    `user_id`     VARCHAR(64)  NOT NULL DEFAULT ''    COMMENT '用户ID',
    `api_name`    VARCHAR(128) NOT NULL DEFAULT ''    COMMENT '接口标识(如 content.search)',
    `request_uri` VARCHAR(256) NOT NULL DEFAULT ''    COMMENT '请求路径',
    `params`      TEXT                               COMMENT '请求参数JSON(截断5000字符)',
    `success`     TINYINT      NOT NULL DEFAULT 1    COMMENT '是否成功: 0-失败 1-成功',
    `duration_ms` INT          NOT NULL DEFAULT 0    COMMENT '接口耗时(毫秒)',
    `create_time` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间',
    PRIMARY KEY (`id`),
    KEY `idx_user_id` (`user_id`),
    KEY `idx_api_name` (`api_name`),
    KEY `idx_create_time` (`create_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='请求埋点记录表';
```

---

## 三、代码设计

### 3.1 @TrackApi 注解

```java
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface TrackApi {
    /** 接口标识，如 "content.search"、"content.detail" */
    String value();
}
```

### 3.2 UserIdUtil（从 Cookie 提取 userId）

```java
@Slf4j
public class UserIdUtil {

    public static String getUserId(HttpServletRequest request) {
        Cookie[] cookies = request.getCookies();
        if (cookies == null) {
            return null;
        }
        return Arrays.stream(cookies)
                .filter(c -> "upms_login_user".equals(c.getName()))
                .findFirst()
                .map(Cookie::getValue)
                .orElse(null);
    }
}
```

### 3.3 TrackAspect 切面

```java
@Slf4j
@Aspect
@Component
public class TrackAspect {

    @Resource
    private TrackService trackService;

    @Around("@annotation(trackApi)")
    public Object around(ProceedingJoinPoint joinPoint, TrackApi trackApi) throws Throwable {
        long start = System.currentTimeMillis();
        boolean success = true;
        try {
            return joinPoint.proceed();
        } catch (Throwable e) {
            success = false;
            throw e;
        } finally {
            buildAndSave(joinPoint, trackApi, start, success);
        }
    }

    private void buildAndSave(ProceedingJoinPoint pjp, TrackApi trackApi,
                               long start, boolean success) {
        try {
            TrackRecord record = new TrackRecord();
            record.setApiName(trackApi.value());

            // userId & requestUri（从 RequestContextHolder 获取）
            ServletRequestAttributes attrs = (ServletRequestAttributes)
                    RequestContextHolder.getRequestAttributes();
            if (attrs != null) {
                HttpServletRequest request = attrs.getRequest();
                record.setUserId(UserIdUtil.getUserId(request));
                record.setRequestUri(request.getRequestURI());
            }

            // 请求参数（序列化第一个参数）
            Object[] args = pjp.getArgs();
            if (args != null && args.length > 0 && args[0] != null) {
                String paramsJson = JsonUtils.toJson(args[0]);
                record.setParams(paramsJson.length() > 5000
                        ? paramsJson.substring(0, 5000) : paramsJson);
            }

            record.setSuccess(success ? 1 : 0);
            record.setDurationMs((int) (System.currentTimeMillis() - start));

            trackService.asyncSave(record);
        } catch (Exception e) {
            log.warn("Build track record failed", e);
        }
    }
}
```

### 3.4 TrackService（异步落库）

```java
@Slf4j
@Service
public class TrackService {

    private static final ExecutorService TRACK_POOL = new ThreadPoolExecutor(
            2, 4, 60, TimeUnit.SECONDS,
            new LinkedBlockingQueue<>(1000),
            new ThreadPoolExecutor.CallerRunsPolicy()
    );

    @Resource
    private TrackRecordMapper trackRecordMapper;

    public void asyncSave(TrackRecord record) {
        CompletableFuture.runAsync(() -> {
            try {
                trackRecordMapper.insert(record);
            } catch (Exception e) {
                log.warn("Track record save failed: {}", e.getMessage());
            }
        }, TRACK_POOL);
    }
}
```

### 3.5 实体

```java
@Data
public class TrackRecord {
    private Long id;
    private String userId;
    private String apiName;
    private String requestUri;
    private String params;
    private Integer success;
    private Integer durationMs;
    private Date createTime;
}
```

### 3.6 Mapper

```java
@Mapper
public interface TrackRecordMapper {
    int insert(TrackRecord record);
}
```

### 3.7 Mapper XML

```xml
<mapper namespace="com.qunar.ug.flight.contact.odin.server.infra.dao.TrackRecordMapper">
    <resultMap id="BaseResultMap" type="com.qunar.ug.flight.contact.odin.server.domain.entity.track.TrackRecord">
        <id column="id" property="id"/>
        <result column="user_id" property="userId"/>
        <result column="api_name" property="apiName"/>
        <result column="request_uri" property="requestUri"/>
        <result column="params" property="params"/>
        <result column="success" property="success"/>
        <result column="duration_ms" property="durationMs"/>
        <result column="create_time" property="createTime"/>
    </resultMap>

    <sql id="Base_Column_List">
        id, user_id, api_name, request_uri, params, success, duration_ms, create_time
    </sql>

    <insert id="insert" useGeneratedKeys="true" keyProperty="id">
        INSERT INTO track_record (user_id, api_name, request_uri, params, success, duration_ms)
        VALUES (#{userId}, #{apiName}, #{requestUri}, #{params}, #{success}, #{durationMs})
    </insert>
</mapper>
```

---

## 四、新增文件清单

| 类型 | 文件 | 包路径 |
|------|------|--------|
| 注解 | `TrackApi.java` | `service/track/annotation` |
| 切面 | `TrackAspect.java` | `service/track` |
| 服务 | `TrackService.java` | `service/track` |
| 工具 | `UserIdUtil.java` | `infra/utils` |
| 实体 | `TrackRecord.java` | `domain/entity/track` |
| Mapper | `TrackRecordMapper.java` | `infra/dao` |
| XML | `TrackRecordMapper.xml` | `resources/mapper` |

**修改文件：** 无。

---

## 五、埋点覆盖计划

### P0（本期实现）

| 模块 | API 路径 | TrackApi value |
|------|---------|----------------|
| **内容** | `POST /api/content/search` | `content.search` |
| | `GET /api/content/detail` | `content.detail` |
| | `GET /api/content/preview` | `content.preview` |
| | `POST /api/content/tags` | `content.tags.edit` |
| | `GET /api/content/filter` | `content.filter` |
| | `GET /api/content/download` | `content.download` |
| **标签** | `POST /api/tag/category/create` | `tag.category.create` |
| | `POST /api/tag/category/update` | `tag.category.update` |
| | `POST /api/tag/category/delete` | `tag.category.delete` |
| | `POST /api/tag/category/toggle` | `tag.category.toggle` |
| | `POST /api/tag/leaf/create` | `tag.leaf.create` |
| | `POST /api/tag/leaf/update` | `tag.leaf.update` |
| | `POST /api/tag/leaf/delete` | `tag.leaf.delete` |
| | `POST /api/tag/leaf/toggle` | `tag.leaf.toggle` |
| | `GET /api/tag/export` | `tag.export` |
| | `POST /api/tag/import` | `tag.import` |
| **任务** | `POST /api/task/create` | `task.create` |
| | `POST /api/task/cancel/{id}` | `task.cancel` |
| | `POST /api/task/retry/{id}` | `task.retry` |
| | `POST /api/task/subtask/retry/{id}` | `task.subtask.retry` |
| | `POST /api/task/subtask/skip/{id}` | `task.subtask.skip` |
| | `POST /api/task/subtask/delete/{id}` | `task.subtask.delete` |
| **OSS** | `POST /api/oss/transfer` | `oss.transfer` |
| **AI** | `POST /api/ai/asr/transcribe` | `ai.asr.transcribe` |
| | `POST /api/ai/image/understand` | `ai.image.understand` |
| | `POST /api/ai/image/understand/stream` | `ai.image.understand.stream` |
| | `POST /api/ai/video/process/demo` | `ai.video.process` |
| **RawContent** | `POST /api/raw-content/create` | `raw.create` |
| | `POST /api/raw-content/update` | `raw.update` |
| | `POST /api/raw-content/delete` | `raw.delete` |
| **系统** | `/`、`/health` | — 不埋点 — |

**本期共 29 个接口加 `@TrackApi` 注解。**

---

## 六、注意事项

| 事项 | 说明 |
|------|------|
| **userId 获取** | 从 `upms_login_user` cookie 提取，无 cookie 时 userId 为空字符串，不影响埋点执行 |
| **参数序列化** | 序列化第一个参数（`@RequestBody` DTO），超 5000 字符截断 |
| **异步不阻塞** | `CompletableFuture.runAsync` + 独立线程池，埋点慢不拖慢接口 |
| **埋点不影响主流程** | 埋点失败只记 warn 日志，从不抛异常 |

---

## 检查项

- [ ] 引入 spring-boot-starter-aop 依赖
- [ ] 建表 `track_record`
- [ ] `TrackApi` 注解
- [ ] `UserIdUtil` 工具类
- [ ] `TrackAspect` 切面
- [ ] `TrackService`（异步线程池）
- [ ] `TrackRecord` 实体
- [ ] `TrackRecordMapper` + XML
- [ ] 为 29 个 API 接口方法添加 `@TrackApi` 注解
- [ ] 编译 & 验证