# ODIN 项目开发进度

## 项目概述

基于脚手架扩展实现 ODIN 运营平台。

**后端工程**：`odin_server/`
**前端工程**：`odin_node/`

---

## 目录结构

```
q-odin/
├── odin_server/                          # 后端项目 (去哪儿内部框架)
│   ├── pom.xml                           # 父 POM
│   └── mkt_odin_server_web/              # Web 模块
│       ├── pom.xml
│       └── src/main/
│           ├── java/com/qunar/ug/flight/contact/odin/server/
│           │   ├── Application.java              # 启动类
│           │   ├── web/                          # 控制层
│           │   ├── service/                      # 服务层
│           │   ├── domain/                       # 领域层
│           │   │   └── entity/                   # 实体类
│           │   ├── infra/                        # 基础设施层
│           │   │   ├── dao/                      # Mapper 接口
│           │   │   ├── config/                   # 配置类
│           │   │   ├── configuration/            # 组件配置
│           │   │   ├── qconfig/                  # QConfig 配置服务
│           │   │   ├── client/                   # 外部服务客户端
│           │   │   └── util/                     # 工具类
│           │   ├── invoker/                      # HTTP 调用器
│           │   └── task/                         # 定时任务
│           └── resources/
│               ├── mapper/                       # Mapper XML
│               └── profiles/                     # 多环境配置
│
├── odin_node/                            # 前端项目
│   ├── config/
│   │   └── config.js                     # UmiJS 配置
│   └── src/
│       ├── api/                          # API 服务
│       ├── components/                   # 组件
│       ├── layouts/                      # 布局
│       └── pages/                        # 页面
│
└── docs/
    └── 20260423-odin-init/               # 本次迭代文档
        ├── tech-spec/                    # 技术方案
        │   └── plan.md
        └── progress.md
```

---

## 开发阶段

### 阶段一：项目初始化

| 任务 | 状态 | 说明 |
|------|------|------|
| CLAUDE.md 初始化 | ✅ 完成 | AI 开发工作流引导 |
| infra.md 初始化 | ✅ 完成 | 项目导航文档 |
| docs 目录结构初始化 | ✅ 完成 | progress-template.md + 需求目录 |
| 后端包结构初始化 | ✅ 完成 | 对齐 q-geo 分层架构 |
| 后端 MyBatis 集成 | ✅ 完成 | mybatis-config.xml + mapper/ 目录 |
| 后端 Redis 集成 | ✅ 完成 | RedisUtil + RedisDistributedLock + RedisBeanFactory |
| 后端 QConfig 集成 | ✅ 完成 | OdinQConfig + HotFileQConfig |
| 后端 QSchedule 集成 | ✅ 完成 | spring-qschedule.xml + QScheduleTaskDemoTask |
| 后端 Profiles 初始化 | ✅ 完成 | 4 个环境（local/betanoah/prod/simulation）x 6 配置文件 |
| 前端项目初始化 | ✅ 完成 | UmiJS 3 + React 16 + Ant Design 4 + package.json + config.js |

### 阶段二：工具类开发

| 任务 | 状态 | 说明 |
|------|------|------|
| 视频下载（HttpUtils.downloadVideo） | ✅ 完成 | 流式下载，支持大文件 |
| 视频抽帧（VideoUtil.extractFrames） | ✅ 完成 | FFmpeg 抽帧，可调间隔和最大帧数 |
| 音频提取（VideoUtil.extractAudio） | ✅ 完成 | 提取视频音频为 MP3 |
| 视频信息获取（VideoUtil.getVideoInfo） | ✅ 完成 | 通过 FFprobe 获取视频元信息 |
| 临时目录清理（VideoUtil.cleanupTempDir） | ✅ 完成 | 使用 commons-io 清理 |

---

## 当前进度

**当前阶段：** 阶段一 - 项目初始化

**已完成：**
- CLAUDE.md + infra.md 文档初始化
- docs 目录结构 + progress-template.md
- 后端包结构重建（移除旧模块，对齐 q-geo 分层）
- MyBatis 集成（mybatis-config.xml + mapper/ 目录 + Jsr310Config）
- Redis 工具类（RedisUtil + RedisDistributedLock + RedisBeanFactory）
- QConfig 业务配置类（OdinQConfig）
- QSchedule 定时任务（spring-qschedule.xml + QScheduleTaskDemoTask）
- 4 个环境 profiles 初始化（local/betanoah/prod/simulation，各 6 个配置文件）
- 前端项目骨架（package.json + config.js + 布局 + health 页面）
- 移除 mkt_odin_server_web-api 模块

**待开始：**

**下一步：**
1. 后端 mvn compile 验证编译通过
2. 根据具体业务需求开始开发

---

## 技术栈

### 后端
- Java 8
- Spring Boot 2.6.6
- MyBatis 3.x
- QConfig（配置中心）
- QSchedule（定时任务）
- qclient-redis

### 前端
- Node.js 12.16.1
- React 16.14.0
- Ant Design 4.x
- UmiJS 3.x
- Axios

---

## 关键约定

### 接口规范
- 统一前缀：`/api`
- 统一响应格式：`{ code: 0, message: "success", data: {} }`

### 本地开发
- 后端：IDEA Tomcat 部署，端口 8080
- 前端：npm start，端口 3000，代理到后端 8080
