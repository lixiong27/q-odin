# 项目开发进度

## 项目概述

**项目名称**：ASR和图像理解接入

---

## 开发阶段

### 阶段一：技术方案

| 任务 | 状态 | 说明 |
|------|------|------|
| 技术方案设计 | ✅ 已完成 | Service接口设计、请求/响应模型设计 |
| progress.md更新 | ✅ 已完成 | 调整为纯后端Service封装任务 |

### 阶段二：后端开发

| 任务 | 状态 | 说明 |
|------|------|------|
| QConfig配置类 | ✅ 已完成 | AigcQConfig - aigc.properties |
| 枚举类 | ✅ 已完成 | AsrProvider, ImageType |
| Model类 | ✅ 已完成 | AsrRequest/Response, ImageInput, ImageUnderstandingRequest/Response |
| ASR服务封装 | ✅ 已完成 | AsrService + AsrServiceImpl |
| 图像理解服务封装 | ✅ 已完成 | ImageUnderstandingService + ImageUnderstandingServiceImpl |
| 请求/响应对象 | ✅ 已完成 | domain.request/response.ai |
| DemoController | ✅ 已完成 | AiDemoController - 提供HTTP接口 |

### 阶段三：测试验证

| 任务 | 状态 | 说明 |
|------|------|------|
| 单元测试 | ❌ 待开始 | Service层测试 |
| 接口测试 | ❌ 待开始 | Controller层测试 |

---

## 当前进度

**当前阶段：** 阶段二 - 后端开发（已完成）

**已完成：**
- 技术方案设计
- AigcQConfig配置类
- ASR服务封装（支持火山/阿里云）
- 图像理解服务封装（支持URL/Base64、流式/非流式）
- HTTP接口（AiDemoController）

**待开始：**
- 单元测试
- 接口测试

**下一步：** QConfig平台创建 aigc.properties 配置文件

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
