# ODIN 项目初始化计划

## 1. CLAUDE.md 初始化

参考 q-geo 的 CLAUDE.md 结构，适配 odin 项目的特点：

- 项目概述：ODIN 运营平台
- 导航指针：指向 infra.md
- 工作流程：确认开发目录 → 读取 progress.md → 确认任务 → 更新进度
- 需求结构：`docs/{yyyyMMdd-需求名}/` 目录结构
- 技术栈：Java 8 + Spring Boot 2.6.6 + MyBatis + QConfig + QSchedule（后端），Node 12.16.1 + React 16 + Ant Design 4.x（前端）
- Git 提交规范

## 2. infra.md 初始化

创建项目导航文档：

- 业务模块表格（预留，待后续补充）
- 共享参考表格
- 技术组件说明
- 代码规范

## 3. docs/ 目录结构

```
docs/
├── 20260423-odin-init/          # 本次初始化文档
│   └── plan.md                  # 本计划文件
└── progress-template.md         # 进度追踪模板
```

## 4. 后端 odin_server 初始化

### 4.1 MyBatis 集成

- 在 pom.xml 中添加 MyBatis 和 MyBatis-Spring 依赖
- 移除 `mkt_odin_server_web-api` 模块（用户已删除）
- 创建 `mybatis-config.xml` 配置文件
- 创建 `resources/mapper/` 目录（Mapper XML）

### 4.2 Redis 集成

- 创建 `infra/util/RedisUtil.java` 工具类
- 创建 `infra/util/RedisDistributedLock.java` 分布式锁

### 4.3 QConfig 集成

- 创建 `infra/qconfig/` 包结构
- 创建基础 QConfig 类

### 4.4 QSchedule 集成

- 创建 `spring-qschedule.xml` 配置文件
- `task/` 包结构已存在，补充标准模式

### 4.5 包结构初始化（完全对齐 q-geo 分层）

**完全按照 q-geo 的包结构重新组织**，移除 odin_server 现有所有目录模块（bean、controller、service/consumer、service/provider、tcdev/factory），重新创建为：

```
com.qunar.ug.flight.contact.odin.server/
├── Application.java             # Spring Boot 入口
├── CybertronConfiguration.java  # 配置聚合类（参考 q-geo）
│
├── web/                         # Controller 层（REST API）
│
├── service/                     # Service 层（业务逻辑）
│
├── domain/                      # 领域模型
│   ├── entity/                  # 实体类
│   │   └── common/              # 公共实体：BaseResponse, PageResult, ResultEnum
│   └── request/response/        # 请求响应对象
│
├── infra/                       # 基础设施层
│   ├── dao/                     # MyBatis Mapper 接口
│   ├── config/                  # Spring 配置类（如 Jsr310Config）
│   ├── configuration/           # Spring configurations
│   ├── qconfig/                 # 业务 QConfig 配置类
│   ├── client/                  # 外部服务客户端（HTTP invoker）
│   └── util/                    # 工具类：RedisUtil, RedisDistributedLock, JsonUtils 等
│
├── invoker/                     # HTTP 调用器
│   └── http/                    # HTTP invokers for downstream services
│
└── task/                        # QSchedule 定时任务
```

### 4.6 Profiles 初始化（4 个环境对齐 q-geo）

参考 q-geo 的 `src/main/profiles/{local,betanoah,prod,simulation}/`，每个环境包含 6 个配置文件：

| 文件 | 说明 |
|------|------|
| `db.properties` | 数据库连接（主从读写分离 via Cybertron） |
| `redis.properties` | Redis 连接（namespace, cipher, pool, zkAddr） |
| `dubbo.properties` | Dubbo 注册中心配置 |
| `http.properties` | HTTP 客户端配置 |
| `mq.properties` | 消息队列配置 |
| `tenant.properties` | 租户配置 |

```
src/main/profiles/
├── local/                   # 本地开发环境
│   ├── db.properties
│   ├── redis.properties
│   ├── dubbo.properties
│   ├── http.properties
│   ├── mq.properties
│   └── tenant.properties
├── betanoah/                # Beta 环境
│   ├── db.properties
│   ├── redis.properties
│   ├── dubbo.properties
│   ├── http.properties
│   ├── mq.properties
│   └── tenant.properties
├── prod/                    # 生产环境
│   ├── db.properties
│   ├── redis.properties
│   ├── dubbo.properties
│   ├── http.properties
│   ├── mq.properties
│   ├── tenant.properties
│   └── myid
└── simulation/              # 预发环境
    ├── db.properties
    ├── redis.properties
    ├── dubbo.properties
    ├── http.properties
    ├── mq.properties
    ├── tenant.properties
    └── myid
```

### 4.7 配置文件初始化

- `mybatis-config.xml` - MyBatis 配置（JSR310 类型处理器、驼峰映射、超时 600s）
- `spring-qschedule.xml` - QSchedule 配置（端口 28888，扫描 task 包）
- `qunar-app.properties` - 已有
- `qunar-env.properties` - 已有
- `logback.xml` - 已有
- `dubbo-consumer.xml` - Dubbo 消费者配置（参考 q-geo）

## 5. 前端 odin_node 初始化

### 5.1 项目结构

```
odin_node/
├── package.json
├── config/
│   └── config.js           # UmiJS 配置
├── public/                 # 静态资源
└── src/
    ├── api/                # API 客户端
    ├── components/         # 组件
    ├── layouts/            # 布局
    └── pages/              # 页面
```

### 5.2 package.json 依赖

参考 q-geo 的 package.json：

- React 16.14.0
- Ant Design 4.18.0
- UmiJS 3.5.41
- Axios 0.21.4
- @ant-design/icons 4.7.0
- Less 相关

### 5.3 config.js 配置

- 环境检测（local/beta/prod）
- 代理配置
- 路由配置
- Umi 插件配置

## 实施顺序

1. 创建 CLAUDE.md 和 infra.md
2. 创建 docs/ 目录结构（progress-template.md）
3. 后端 odin_server 初始化（移除旧目录、重建包结构、MyBatis、Redis、QConfig、QSchedule、Profiles）
4. 前端 odin_node 初始化

## 验证

- 后端 mvn compile 通过
- 前端 npm install 通过
