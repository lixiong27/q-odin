# 视频工具类开发进度

## 需求概述

实现视频处理工具类，支持：
1. 根据视频链接下载视频到本地
2. 根据本地视频文件进行抽帧（固定间隔，最多 N 张）
3. 提取视频文件的音频保存为 MP3 文件

---

## 开发阶段

### 阶段一：需求分析与设计

| 任务 | 状态 | 说明 |
|------|------|------|
| 技术方案设计 | ✅ 完成 | FFmpeg + async-http-client |
| 依赖选型 | ✅ 完成 | net.bramp.ffmpeg:0.8.0, commons-io:2.11.0 |
| 设计文档 | ✅ 完成 | docs/20260505-video-util/design/design.md |

### 阶段二：功能实现

| 任务 | 状态 | 说明 |
|------|------|------|
| 视频下载（HttpUtils.downloadVideo） | ✅ 完成 | 流式下载，支持大文件，AsyncHandler 实现 |
| 视频抽帧（VideoUtil.extractFrames） | ✅ 完成 | FFmpeg fps 滤镜，可配置间隔和最大帧数 |
| 音频提取（VideoUtil.extractAudio） | ✅ 完成 | libmp3lame 编码，输出 MP3 |
| 视频信息获取（VideoUtil.getVideoInfo） | ✅ 完成 | FFprobe 获取元信息 |
| 临时目录清理（VideoUtil.cleanupTempDir） | ✅ 完成 | commons-io FileUtils |

### 阶段三：功能验证

| 任务 | 状态 | 说明 |
|------|------|------|
| 单元测试编写 | ✅ 完成 | VideoUtilTest.java |
| 本地功能验证 | ✅ 完成 | 测试视频 45.79s, 4.84MB |
| 抽帧验证 | ✅ 完成 | 10 张 JPG 图片（~80KB/张） |
| 音频提取验证 | ✅ 完成 | MP3 文件（0.68MB） |

---

## 当前进度

**当前阶段：** 已完成

**已完成：**
- 技术方案设计
- 视频下载功能（流式，支持大文件）
- 视频抽帧功能（可配置间隔、最大帧数）
- 音频提取功能（MP3 格式）
- 视频信息获取功能
- 临时目录清理功能
- 功能验证通过

**待开始：**
- 业务服务集成（按需）

---

## 关键文件

| 文件 | 说明 |
|------|------|
| `infra/util/HttpUtils.java` | HTTP 工具类，新增 downloadVideo 方法 |
| `infra/util/VideoUtil.java` | 视频处理工具类 |
| `test/.../VideoUtilTest.java` | 功能测试类 |
| `docs/20260505-video-util/design/design.md` | 设计文档 |

---

## 技术要点

### 依赖版本
- `net.bramp.ffmpeg:ffmpeg:0.8.0` - FFmpeg Java 包装器
- `commons-io:commons-io:2.11.0` - 文件清理工具

### FFmpeg 命令
```bash
# 抽帧
ffmpeg -i input.mp4 -vf fps=1/N -frames:v 10 -q:v 2 -y frame_%03d.jpg

# 音频提取
ffmpeg -i input.mp4 -vn -acodec libmp3lame -q:a 2 -y output.mp3
```

### 配置项（QConfig）
- `ffmpeg.path` - FFmpeg 可执行文件路径
- `ffprobe.path` - FFprobe 可执行文件路径
- `video.extract.frame.timeout.seconds` - 抽帧超时时间（默认 120s）
- `video.extract.audio.timeout.seconds` - 音频提取超时时间（默认 120s）
