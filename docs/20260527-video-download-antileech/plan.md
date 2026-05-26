# 视频下载防盗链修复

## 问题

`ContentVideoPreprocessor.downloadVideo()` 使用裸 `HttpURLConnection` 下载外网视频 URL，无任何请求头（Referer/User-Agent），遇到 oceanengine 等 CDN 防盗链时返回 HTTP 403，导致预处理（抽帧/ASR）全部跳过。

## 方案

`downloadVideo()` 中判断无内网 URL 时，改走 `OssTransferService.downloadFile()`（已内置自适应防盗链重试），下载成功后自动转存 OSS 并回填 `internalVideoUrl`。

### 顺序

```
1. internalVideoUrl 存在?
   → 内网直接 downloadFromUrl，返回 path

2. videoUrl 存在（外网 URL）?
   a. ossTransferService.downloadFile(videoUrl) → tempFile
   b. 复制 tempFile → tempDir/video.mp4
   c. ossTransferService.transferFromFile(tempFile, videoUrl) → OSS 转存
   d. 回填 internalVideoUrl 到 DB
   e. ossTransferService.cleanupFile(tempFile)
   f. 返回 tempDir/video.mp4
```

## 改动文件

### ContentVideoPreprocessor.java

`downloadVideo()` 方法重构，新增 `OssTransferService` 注入（已有）。

### RawContentServiceImpl.transferVideos()

无需改动。