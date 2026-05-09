# ASR和图像理解服务技术方案

## 一、方案概述

封装两个底层Service能力：
- **AsrService**：语音转文本服务，支持火山/阿里云两种服务商
- **ImageUnderstandingService**：图像理解服务，支持图片URL/Base64输入

**特点**：实时调用，不持久化

---

## 二、ASR服务设计

### 2.1 接口定义

```java
package com.qunar.ug.flight.contact.odin.server.service.ai;

/**
 * ASR语音转文本服务
 */
public interface AsrService {

    /**
     * 语音转文本
     *
     * @param request ASR请求
     * @return ASR响应
     */
    AsrResponse transcribe(AsrRequest request);
}
```

### 2.2 请求模型

```java
/**
 * ASR请求
 */
@Data
public class AsrRequest {
    /** 服务商: BYTEDANCE / ALIYUN */
    private AsrProvider provider;

    /** 音频文件URL */
    private String audioUrl;

    /** 音频格式: mp3/wav/mp4/ogg/aac/opus/raw */
    private String format;

    /** 采样率: 8000/16000，默认16000 */
    private Integer sampleRate;

    /** 是否开启文本规范化(数字转换) */
    private Boolean enableItn;

    /** 声道处理: true-单声道, false-双声道 */
    private Boolean enableChannelSplit;

    /** 用户标识 */
    private String userIdentityInfo;
}
```

### 2.3 响应模型

```java
/**
 * ASR响应
 */
@Data
public class AsrResponse {
    /** 状态: SUCCESS/FAIL */
    private String status;

    /** 识别文本 */
    private String text;

    /** 音频时长(毫秒) */
    private Long duration;

    /** 消费金额 */
    private Double consume;

    /** 失败码 */
    private String failCode;

    /** 失败原因 */
    private String failMessage;
}
```

### 2.4 服务商枚举

```java
public enum AsrProvider {
    BYTEDANCE,  // 火山 - 4.3元/小时
    ALIYUN      // 阿里云 - 2.5元/小时
}
```

### 2.5 配置项

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| asr.api.url | ASR接口地址 | http://llm.video.api.corp.qunar.com/Audio/asr/textgenerate |
| asr.api.key | AIGC平台账号 | - |
| asr.api.password | AIGC平台密码 | - |
| asr.api.appCode | 调用方appCode | pf_odin_server |
| asr.api.project | 项目场景 | odin_asr |
| asr.api.timeout | 超时时间(毫秒) | 30000 |

---

## 三、图像理解服务设计

### 3.1 接口定义

```java
package com.qunar.ug.flight.contact.odin.server.service.ai;

/**
 * 图像理解服务
 */
public interface ImageUnderstandingService {

    /**
     * 图像理解(非流式)
     *
     * @param request 图像理解请求
     * @return 图像理解响应
     */
    ImageUnderstandingResponse understand(ImageUnderstandingRequest request);

    /**
     * 图像理解(流式)
     *
     * @param request 图像理解请求
     * @return 流式响应内容
     */
    String understandStream(ImageUnderstandingRequest request);
}
```

### 3.2 请求模型

```java
/**
 * 图像理解请求
 */
@Data
public class ImageUnderstandingRequest {
    /** 模型名称 */
    private String model;

    /** 图片输入 */
    private ImageInput image;

    /** 提示词 */
    private String prompt;

    /** 用户标识 */
    private String userIdentityInfo;

    /** 是否流式返回 */
    private Boolean stream;

    /** 温度参数 0-2 */
    private Double temperature;

    /** 最大token数 */
    private Integer maxTokens;
}

/**
 * 图片输入
 */
@Data
public class ImageInput {
    /** 图片类型: URL / BASE64 */
    private ImageType type;

    /** 图片URL或Base64编码 */
    private String data;

    /** 图片细节级别: high/low/auto */
    private String detail;
}

public enum ImageType {
    URL,    // 图片URL
    BASE64  // Base64编码
}
```

### 3.3 响应模型

```java
/**
 * 图像理解响应
 */
@Data
public class ImageUnderstandingResponse {
    /** 响应ID */
    private String id;

    /** 模型名称 */
    private String model;

    /** 生成内容 */
    private String content;

    /** Token使用量 */
    private TokenUsage usage;

    /** 完成原因: stop/length */
    private String finishReason;
}

@Data
public class TokenUsage {
    private Integer promptTokens;
    private Integer completionTokens;
    private Integer totalTokens;
}
```

### 3.4 配置项

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| image.api.url | 图像理解接口地址 | http://llm.api.corp.qunar.com/v1/chat/completions |
| image.api.key | API Key | - |
| image.api.appCode | 调用方appCode | pf_odin_server |
| image.api.project | 项目场景 | odin_image |
| image.api.defaultModel | 默认模型 | gpt-4o |
| image.api.timeout | 超时时间(毫秒) | 60000 |

---

## 四、实现要点

### 4.1 鉴权方式

**ASR服务**：请求头中传递账号密码
```json
{
  "Header": {
    "key": "xxx",
    "password": "xxx",
    "appCode": "pf_odin_server",
    "project": "odin_asr",
    "apiType": "ALIYUN",
    "userIdentityInfo": "user_id",
    "traceID": "uuid"
  }
}
```

**图像理解服务**：Bearer Token鉴权
```
Authorization: Bearer {api_key}:{appCode}:{project}:{userIdentityInfo}::{traceId}
```

### 4.2 HTTP调用

复用现有 `HttpUtils` 工具类，使用 `QunarAsyncClient`

**ASR调用示例**：
```java
Map<String, Object> headers = new HashMap<>();
headers.put("Content-Type", "application/json");

String requestBody = JacksonSupport.toJson(asrApiRequest);
String response = HttpUtils.postHttp(asrApiUrl, requestBody, headers, 30, TimeUnit.SECONDS);
```

### 4.3 异常处理

- 网络超时：记录日志，返回失败状态
- 鉴权失败：明确返回错误信息
- 参数校验：前置校验必填参数

### 4.4 监控埋点

- 请求耗时监控
- 成功/失败计数
- 按服务商分类统计

---

## 五、目录结构

```
odin_server/mkt_odin_server_web/src/main/java/com/qunar/ug/flight/contact/odin/server/
├── service/
│   └── ai/
│       ├── AsrService.java              # ASR服务接口
│       ├── impl/
│       │   └── AsrServiceImpl.java      # ASR服务实现
│       ├── ImageUnderstandingService.java  # 图像理解服务接口
│       │   └── ImageUnderstandingServiceImpl.java
│       ├── model/
│       │   ├── AsrRequest.java
│       │   ├── AsrResponse.java
│       │   ├── ImageUnderstandingRequest.java
│       │   ├── ImageUnderstandingResponse.java
│       │   └── ImageInput.java
│       └── enums/
│           ├── AsrProvider.java
│           └── ImageType.java
└── infra/
    └── qconfig/
        └── AiApiConfig.java             # AI API配置类
```

---

## 六、依赖

无需新增Maven依赖，使用项目现有依赖：
- `qunar.hc.QunarAsyncClient` - HTTP客户端
- `qunar.api.pojo.node.JacksonSupport` - JSON序列化
- `lombok` - 简化代码

---

## 七、后续扩展

1. **重试机制**：网络异常时自动重试
2. **熔断降级**：服务商不可用时切换
3. **缓存**：相同音频/图片识别结果缓存
4. **异步调用**：支持异步处理大批量任务
