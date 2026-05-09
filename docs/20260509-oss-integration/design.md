# 后端 OSS 能力接入设计

## 一、需求概述

**目标**：实现图片/视频 URL 转存到内部 OSS，并返回内部 OSS 公网 URL。

**输入**：公网可访问的图片/视频 URL
**输出**：内部 OSS 公网 URL

---

## 二、技术方案

### 2.1 核心依赖

```xml
<!-- qunar-oss-sdk -->
<dependency>
    <groupId>qunar.tc.oss</groupId>
    <artifactId>qunar-oss-sdk</artifactId>
    <version>1.0.2</version>
    <exclusions>
        <exclusion>
            <artifactId>httpclient</artifactId>
            <groupId>org.apache.httpcomponents</groupId>
        </exclusion>
        <exclusion>
            <artifactId>httpcore</artifactId>
            <groupId>org.apache.httpcomponents</groupId>
        </exclusion>
    </exclusions>
</dependency>
```

### 2.2 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                         Controller                          │
│  POST /api/oss/transfer                                    │
│  请求: { "url": "https://example.com/image.jpg" }          │
│  响应: { "ossUrl": "https://xxx.qunarzz.com/bucket/file" } │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                         Service                             │
│  OssTransferService                                         │
│  1. 下载文件到临时目录                                       │
│  2. 上传到 OSS                                              │
│  3. 构建公网 URL                                            │
│  4. 清理临时文件                                            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Infrastructure                         │
│  OSSClient (qunar-oss-sdk)                                 │
│  HotFileQConfig (配置项)                                    │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 核心流程

```
URL 输入
    │
    ▼
┌──────────────────┐
│ 1. URL 合法性校验 │
│    - 非空校验     │
│    - 协议校验     │
│    - 黑名单校验   │
└──────────────────┘
    │
    ▼
┌──────────────────┐
│ 2. 下载文件       │
│    - HTTP 连接    │
│    - 超时控制     │
│    - 重定向处理   │
│    - 写入临时文件 │
└──────────────────┘
    │
    ▼
┌──────────────────┐
│ 3. 文件校验       │
│    - 大小限制     │
│    - 类型校验     │
└──────────────────┘
    │
    ▼
┌──────────────────┐
│ 4. 上传到 OSS     │
│    - 生成文件名   │
│    - 调用 SDK     │
│    - 获取内网 URL │
└──────────────────┘
    │
    ▼
┌──────────────────┐
│ 5. 构建公网 URL   │
│    - 拼接域名前缀 │
└──────────────────┘
    │
    ▼
┌──────────────────┐
│ 6. 清理临时文件   │
└──────────────────┘
    │
    ▼
返回 OSS URL
```

---

## 三、实现细节

### 3.1 文件结构

```
odin_server/mkt_odin_server_web/src/main/java/com/qunar/ug/flight/contact/odin/server/
├── service/
│   └── oss/
│       └── OssTransferService.java      # 核心服务
├── domain/
│   ├── request/oss/
│   │   └── OssTransferRequest.java      # 请求对象
│   └── response/oss/
│       └── OssTransferResponse.java     # 响应对象
├── web/
│   └── OssController.java               # 控制器
└── infra/
    └── config/
        └── OssConfig.java               # OSS 配置（可选）
```

### 3.2 配置项 (hotfile.properties)

```properties
# OSS 公网访问域名前缀
oss.extranet.url.prefix=https://f-odin.qunarzz.com/

# HTTP 连接超时（毫秒）
oss.http.connect.timeout=10000

# HTTP 读取超时（毫秒）
oss.http.read.timeout=30000

# 最大文件大小（字节），默认 50MB
oss.max.file.size=52428800

# 允许的文件类型（逗号分隔）
oss.allowed.types=jpg,jpeg,png,gif,webp,mp4,webm,mov

# URL 黑名单（防止 SSRF）
oss.url.blacklist=127.0.0.1,localhost,10.,192.168.,172.16.,172.17.,172.18.,172.19.,172.20.,172.21.,172.22.,172.23.,172.24.,172.25.,172.26.,172.27.,172.28.,172.29.,172.30.,172.31.
```

### 3.3 核心代码

#### 3.3.1 OssTransferService.java

```java
package com.qunar.ug.flight.contact.odin.server.service.oss;

import com.qunar.flight.qmonitor.QMonitor;
import com.qunar.ug.flight.contact.odin.server.infra.qconfig.HotFileQConfig;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import qunar.tc.oss.OSSClient;

import javax.annotation.Resource;
import java.io.*;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

@Slf4j
@Service
public class OssTransferService {

    @Resource
    private OSSClient ossClient;

    @Resource
    private HotFileQConfig hotFileQConfig;

    private static final String TEMP_FILE_PREFIX = "oss-transfer-";

    /**
     * 从公网 URL 下载文件并转存到 OSS
     *
     * @param publicUrl 公网可访问的 URL
     * @return OSS 公网 URL
     */
    public String transferFromUrl(String publicUrl) {
        // 1. 校验 URL
        validateUrl(publicUrl);

        // 2. 下载文件
        File tempFile = downloadToTempFile(publicUrl);

        try {
            // 3. 校验文件
            validateFile(tempFile);

            // 4. 上传到 OSS
            return uploadToOss(tempFile);
        } finally {
            // 5. 清理临时文件
            cleanupTempFile(tempFile);
        }
    }

    /**
     * URL 校验
     */
    private void validateUrl(String url) {
        if (url == null || url.isEmpty()) {
            throw new IllegalArgumentException("URL 不能为空");
        }

        try {
            URL parsedUrl = new URL(url);
            String protocol = parsedUrl.getProtocol().toLowerCase();
            if (!"http".equals(protocol) && !"https".equals(protocol)) {
                throw new IllegalArgumentException("仅支持 HTTP/HTTPS 协议");
            }

            // SSRF 防护：检查黑名单
            String host = parsedUrl.getHost().toLowerCase();
            String blacklist = hotFileQConfig.getString("oss.url.blacklist", "");
            Set<String> blockedPrefixes = new HashSet<>(Arrays.asList(blacklist.split(",")));

            for (String blocked : blockedPrefixes) {
                if (host.equals(blocked.trim()) || host.startsWith(blocked.trim())) {
                    throw new IllegalArgumentException("URL 不在允许访问的范围内");
                }
            }
        } catch (Exception e) {
            QMonitor.recordOne("oss_transfer_url_invalid");
            throw new IllegalArgumentException("URL 格式无效: " + e.getMessage());
        }
    }

    /**
     * 下载文件到临时目录
     */
    private File downloadToTempFile(String publicUrl) {
        int connectTimeout = hotFileQConfig.getInt("oss.http.connect.timeout", 10000);
        int readTimeout = hotFileQConfig.getInt("oss.http.read.timeout", 30000);

        HttpURLConnection conn = null;
        try {
            URL url = new URL(publicUrl);
            conn = (HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(connectTimeout);
            conn.setReadTimeout(readTimeout);
            conn.setInstanceFollowRedirects(true);

            // 处理重定向
            int status = conn.getResponseCode();
            if (status >= 300 && status < 400) {
                String location = conn.getHeaderField("Location");
                if (location != null && !location.isEmpty()) {
                    conn.disconnect();
                    url = new URL(location);
                    conn = (HttpURLConnection) url.openConnection();
                    conn.setConnectTimeout(connectTimeout);
                    conn.setReadTimeout(readTimeout);
                }
            }

            int responseCode = conn.getResponseCode();
            if (responseCode != HttpURLConnection.HTTP_OK) {
                conn.disconnect();
                QMonitor.recordOne("oss_transfer_download_failed");
                throw new RuntimeException("下载失败，HTTP code=" + responseCode);
            }

            // 提取文件名
            String fileName = extractFileName(conn, url);
            String fileExt = extractFileExtension(fileName);

            // 创建临时文件
            File tempFile = File.createTempFile(TEMP_FILE_PREFIX, fileExt);
            log.info("下载文件到临时路径: {}", tempFile.getAbsolutePath());

            // 写入文件
            try (InputStream in = conn.getInputStream();
                 FileOutputStream out = new FileOutputStream(tempFile)) {
                byte[] buffer = new byte[8192];
                int len;
                while ((len = in.read(buffer)) != -1) {
                    out.write(buffer, 0, len);
                }
            }

            // 校验文件是否有效
            if (!tempFile.exists() || tempFile.length() == 0) {
                cleanupTempFile(tempFile);
                QMonitor.recordOne("oss_transfer_empty_file");
                throw new RuntimeException("下载的文件为空");
            }

            return tempFile;

        } catch (IOException e) {
            QMonitor.recordOne("oss_transfer_download_error");
            throw new RuntimeException("下载文件失败: " + e.getMessage(), e);
        } finally {
            if (conn != null) {
                conn.disconnect();
            }
        }
    }

    /**
     * 提取文件名
     */
    private String extractFileName(HttpURLConnection conn, URL url) {
        String disposition = conn.getHeaderField("Content-Disposition");
        String fileName = null;

        if (disposition != null && disposition.contains("filename=")) {
            int idx = disposition.indexOf("filename=");
            fileName = disposition.substring(idx + 9).replaceAll("\"", "").trim();
        }

        if (fileName == null || fileName.isEmpty()) {
            String path = url.getPath();
            if (path != null) {
                fileName = Paths.get(path).getFileName().toString();
            }
        }

        if (fileName == null || fileName.isEmpty()) {
            fileName = "downloaded_file";
        }

        // 清理文件名
        return sanitizeFileName(fileName);
    }

    /**
     * 清理文件名
     */
    private String sanitizeFileName(String fileName) {
        String name = Paths.get(fileName).getFileName().toString();
        name = name.replaceAll("[^a-zA-Z0-9._-]", "_");
        if (name.isEmpty()) {
            name = "unnamed_file";
        }
        if (name.startsWith(".")) {
            name = "file" + name;
        }
        return name;
    }

    /**
     * 提取文件扩展名
     */
    private String extractFileExtension(String fileName) {
        int dot = fileName.lastIndexOf('.');
        if (dot >= 0) {
            return fileName.substring(dot);
        }

        // 尝试从 Content-Type 推断
        return ".dat";
    }

    /**
     * 文件校验
     */
    private void validateFile(File file) {
        // 大小校验
        long maxSize = hotFileQConfig.getLong("oss.max.file.size", 52428800L);
        if (file.length() > maxSize) {
            throw new IllegalArgumentException("文件大小超过限制: " + file.length() + " bytes");
        }

        // 类型校验（可选）
        String allowedTypes = hotFileQConfig.getString("oss.allowed.types", "");
        if (!allowedTypes.isEmpty()) {
            String name = file.getName().toLowerCase();
            boolean valid = Arrays.stream(allowedTypes.split(","))
                    .anyMatch(type -> name.endsWith("." + type.trim()));
            if (!valid) {
                throw new IllegalArgumentException("文件类型不支持");
            }
        }
    }

    /**
     * 上传到 OSS
     */
    private String uploadToOss(File tempFile) {
        try {
            // 生成唯一文件名
            String originalName = tempFile.getName();
            String extension = originalName.contains(".")
                    ? originalName.substring(originalName.lastIndexOf("."))
                    : ".dat";
            String newFileName = UUID.randomUUID() + extension;

            // 上传
            long startTime = System.currentTimeMillis();
            String intranetUrl = ossClient.putObject(newFileName, tempFile).getUrl();
            long duration = System.currentTimeMillis() - startTime;

            QMonitor.recordQuantile("oss_transfer_upload_duration", duration);
            log.info("上传到 OSS 完成, 文件名: {}, 耗时: {}ms", newFileName, duration);

            // 构建公网 URL
            String urlPrefix = hotFileQConfig.getString("oss.extranet.url.prefix", "");
            String extranetUrl = urlPrefix + ossClient.getCurrentBucketName() + "/" + newFileName;

            log.info("OSS 内网URL: {}, 公网URL: {}", intranetUrl, extranetUrl);
            return extranetUrl;

        } catch (Exception e) {
            QMonitor.recordOne("oss_transfer_upload_error");
            throw new RuntimeException("上传到 OSS 失败: " + e.getMessage(), e);
        }
    }

    /**
     * 清理临时文件
     */
    private void cleanupTempFile(File tempFile) {
        if (tempFile != null && tempFile.exists()) {
            if (!tempFile.delete()) {
                QMonitor.recordOne("oss_transfer_temp_delete_error");
                log.warn("临时文件删除失败: {}", tempFile.getAbsolutePath());
            }
        }
    }
}
```

#### 3.3.2 OssController.java

```java
package com.qunar.ug.flight.contact.odin.server.web;

import com.qunar.ug.flight.contact.odin.server.domain.entity.common.BaseResponse;
import com.qunar.ug.flight.contact.odin.server.domain.request.oss.OssTransferRequest;
import com.qunar.ug.flight.contact.odin.server.domain.response.oss.OssTransferResponse;
import com.qunar.ug.flight.contact.odin.server.service.oss.OssTransferService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.*;

import javax.annotation.Resource;

@Slf4j
@RestController
@RequestMapping("/api/oss")
public class OssController {

    @Resource
    private OssTransferService ossTransferService;

    /**
     * URL 转存到 OSS
     */
    @PostMapping("/transfer")
    public BaseResponse<OssTransferResponse> transfer(@RequestBody OssTransferRequest request) {
        try {
            String ossUrl = ossTransferService.transferFromUrl(request.getUrl());

            OssTransferResponse response = new OssTransferResponse();
            response.setOssUrl(ossUrl);

            return BaseResponse.success(response);
        } catch (IllegalArgumentException e) {
            log.warn("参数错误: {}", e.getMessage());
            return BaseResponse.fail(e.getMessage());
        } catch (Exception e) {
            log.error("转存失败", e);
            return BaseResponse.fail("转存失败: " + e.getMessage());
        }
    }
}
```

#### 3.3.3 Request/Response

```java
// OssTransferRequest.java
package com.qunar.ug.flight.contact.odin.server.domain.request.oss;

import lombok.Data;

@Data
public class OssTransferRequest {
    /**
     * 公网可访问的图片/视频 URL
     */
    private String url;
}

// OssTransferResponse.java
package com.qunar.ug.flight.contact.odin.server.domain.response.oss;

import lombok.Data;

@Data
public class OssTransferResponse {
    /**
     * OSS 公网访问 URL
     */
    private String ossUrl;
}
```

---

## 四、安全考量

### 4.1 SSRF 防护

- URL 黑名单：禁止访问内网地址（127.0.0.1, 10.x, 192.168.x, 172.16-31.x）
- 协议限制：仅允许 HTTP/HTTPS
- 可选：白名单模式，仅允许特定域名

### 4.2 文件安全

- 大小限制：防止大文件耗尽资源
- 类型限制：仅允许图片/视频类型
- 文件名清理：防止路径遍历攻击

### 4.3 资源管理

- 临时文件清理：finally 块保证清理
- 超时控制：防止长时间阻塞
- 监控告警：QMonitor 记录关键指标

---

## 五、监控指标

| 指标名 | 说明 |
|--------|------|
| oss_transfer_url_invalid | URL 校验失败次数 |
| oss_transfer_download_failed | 下载失败次数 |
| oss_transfer_download_error | 下载异常次数 |
| oss_transfer_empty_file | 空文件次数 |
| oss_transfer_upload_error | 上传失败次数 |
| oss_transfer_upload_duration | 上传耗时分布 |
| oss_transfer_temp_delete_error | 临时文件删除失败次数 |

---

## 六、后续扩展

1. **批量转存**：支持一次请求转存多个 URL
2. **进度查询**：大文件转存时支持进度查询
3. **异步处理**：大文件使用异步队列处理
4. **缓存去重**：相同 URL 缓存结果，避免重复下载
5. **CDN 加速**：返回 CDN URL 而非 OSS 直连 URL

---

## 七、待确认

1. **OSS Bucket 配置**：需要确认 ODIN 项目的 bucket 名称和权限
2. **公网域名前缀**：需要确认 ODIN 的公网访问域名
3. **文件大小限制**：根据实际业务需求调整
4. **是否需要支持 Base64 转存**：参考 Poseidon 的 `base64ToImageUrl` 方法
