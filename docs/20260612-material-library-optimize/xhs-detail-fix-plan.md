## 小红书 detail 代码需修复点

### 🔴 Bug 1: publishTime 时间戳（同抖音 BUG）
- JSON: `"time": 1770727481000`（毫秒级时间戳）
- 代码: `String.valueOf(noteCard.getTime())` → `"1770727481000"`
- `parseDateTime` 用 `SimpleDateFormat("yyyy-MM-dd HH:mm:ss")` 无法解析 → **返回 1970-01-01**

### 🔴 Bug 2: videoFormat 未提取
- JSON: stream.h264[0] 中有 `"format": "mp4"`
- 代码: 未调用 `item.setVideoFormat()`

### 🟡 缺失: tagList 未提取到 commonTag
- JSON: `"tag_list": [{"name": "三亚旅行", "id":"...", "type":"topic"}, ...]`
- 代码: `NoteCard` DTO 已有 `tagList` 字段，handler 未提取
- 此外 desc 中的 `#三亚旅行` 也可解析

### 🟡 缺失: duration 单位问题
- JSON: stream.h264[0].duration=70204（毫秒），capa.duration=70（秒）
- 代码: 用 `stream.getDuration()`（ms），DB 列注释为 `视频时长(秒)`
- 建议改用 `capa.getDuration()`（秒）