# 视频工具类设计文档

## 1. 需求

实现 3 个视频处理功能：
1. 根据视频链接下载视频到本地（临时目录）
2. 根据本地视频文件抽帧（固定间隔 n 秒，最多提取 10 张）
3. 提取视频文件的音频，输出为 MP3

## 2. 技术方案

### 2.1 依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| `net.bramp.ffmpeg:ffmpeg` | 0.8.0 | FFmpeg Java 包装器，提供 FFmpeg/FFprobe 对象 |
| `commons-io:commons-io` | 2.11.0 | 临时目录清理（FileUtils.deleteDirectory） |

FFmpeg 作为系统命令运行，需确保服务器已安装 ffmpeg/ffprobe。

### 2.2 参考方案

参考 `ares_live` 项目的直播流监控方案（`live_stream_monitor_solution.md`），采用相同的技术栈：
- `net.bramp.ffmpeg.FFprobe` 用于探测文件信息
- `net.bramp.ffmpeg.FFmpeg` 获取 ffmpeg 可执行文件路径
- `ProcessBuilder` 执行实际的 FFmpeg 命令

### 2.3 存储策略

使用 `java.nio.file.Files.createTempDirectory()` 创建临时目录，业务处理完成后调用 `VideoUtil.cleanupTempDir()` 清理。

## 3. 类设计

### 3.1 HttpUtils（已有类扩展）

**文件**: `infra/util/HttpUtils.java`

新增方法：

```java
public static Path downloadVideo(String url, Path targetPath, long timeout, TimeUnit unit)
```

- 使用 `async-http-client` 的 `AsyncCompletionHandler` 流式下载
- `onBodyPartReceived` 将数据块写入 `FileOutputStream`
- 支持大文件，不加载全部内容到内存
- 下载失败自动清理不完整文件

### 3.2 VideoUtil（新建）

**文件**: `infra/util/VideoUtil.java`

Spring `@Component`，注入 `HotFileQConfig` 获取配置。

**方法列表：**

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getVideoInfo(String)` | 视频路径 | `VideoInfo` | 获取视频信息（时长、分辨率、编码等） |
| `extractFrames(String, int, int, Path)` | 视频路径、间隔秒数、最大帧数、输出目录 | `List<File>` | 抽帧，返回生成的 jpg 文件列表 |
| `extractAudio(String, Path)` | 视频路径、输出 MP3 路径 | `boolean` | 提取音频为 MP3 |
| `cleanupTempDir(Path)` | 临时目录路径 | `void` | 清理临时目录 |

**FFmpeg 命令：**

抽帧：
```bash
ffmpeg -i input.mp4 -vf fps=1/5 -frames:v 10 -q:v 2 -y output/frame_%03d.jpg
```

音频提取：
```bash
ffmpeg -i input.mp4 -vn -acodec libmp3lame -q:a 2 -y output.mp3
```

### 3.3 VideoInfo（内部类）

```java
class VideoInfo {
    double duration;      // 时长（秒）
    long size;            // 文件大小（字节）
    String formatName;    // 格式名称
    String videoCodec;    // 视频编码
    int width;            // 宽度
    int height;           // 高度
    double fps;           // 帧率
    boolean hasAudio;     // 是否有音频
    String audioCodec;    // 音频编码
}
```

## 4. 配置项

需在 `hotfile.properties` 中配置（带默认值）：

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `ffmpeg.path` | ffmpeg | FFmpeg 可执行文件路径 |
| `ffprobe.path` | ffprobe | FFprobe 可执行文件路径 |
| `video.extract.frame.timeout.seconds` | 120 | 抽帧超时时间（秒） |
| `video.extract.audio.timeout.seconds` | 120 | 音频提取超时时间（秒） |

## 5. 使用示例

```java
// 注入
@Resource
private VideoUtil videoUtil;

// 1. 下载视频到临时目录
Path tempDir = Files.createTempDirectory("video");
Path videoFile = tempDir.resolve("video.mp4");
Path downloaded = HttpUtils.downloadVideo(videoUrl, videoFile, 300, TimeUnit.SECONDS);

// 2. 获取视频信息
VideoUtil.VideoInfo info = videoUtil.getVideoInfo(downloaded.toString());

// 3. 抽帧（每5秒一帧，最多10张）
Path frameDir = tempDir.resolve("frames");
List<File> frames = videoUtil.extractFrames(downloaded.toString(), 5, 10, frameDir);

// 4. 提取音频
Path audioFile = tempDir.resolve("audio.mp3");
boolean success = videoUtil.extractAudio(downloaded.toString(), audioFile);

// 5. 清理
videoUtil.cleanupTempDir(tempDir);
```

## 6. 监控指标

| 指标名称 | 说明 |
|----------|------|
| `download_video` | 视频下载耗时 |
| `download_video_error` | 下载失败次数 |
| `video_extract_frame` | 抽帧耗时 |
| `video_extract_frame_error` | 抽帧失败次数 |
| `video_extract_audio` | 音频提取耗时 |
| `video_extract_audio_error` | 音频提取失败次数 |
| `video_get_info_error` | 获取视频信息失败次数 |

## 7. 文件清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `mkt_odin_server_web/pom.xml` | 修改 | 添加 ffmpeg + commons-io 依赖 |
| `infra/util/HttpUtils.java` | 修改 | 新增 `downloadVideo` 方法 |
| `infra/util/VideoUtil.java` | 新增 | 视频处理工具类 |
