# AI 能力抽象层 — 实现计划

## 目标

将 ASR、ImageUnderstand 等 AI 能力的 QConfig 配置从单体 `aigc.properties` 中拆离，实现每个能力独立配置，支持多实例（同一能力多账号），热加载生效方式热加载。

## 核心设计

- **配置格式**：单一 JSON 文件 `ai-capabilities.json`，QConfig 托管
- **配置结构**：`Map<实例名, CapabilityEntry>`，每个 entry 带 `type` + 各能力专属 param
- **类型安全**：每个能力对应一个 POJO（AsrParams、ImageParams），JSON 直接反序列化，零运行时转换
- **渐进式迁移**：新旧并存，旧 `AigcQConfig` 不动，仅新增重载方法

## 新增文件

| # | 文件 | 说明 |
|---|------|------|
| 1 | CapabilityType.java | 枚举：ASR, IMAGE_UNDERSTAND |
| 2 | AiCapabilitiesConfig.java | JSON 顶层映射 |
| 3 | CapabilityEntry.java | 单个配置实例，type + 各能力 param |
| 4 | AsrParams.java | ASR 参数 POJO |
| 5 | ImageParams.java | Image 参数 POJO |
| 6 | AiCapabilitiesQConfig.java | QConfig 监听 + 查询入口 |

## 修改文件

| # | 文件 | 改动 |
|---|------|------|
| 1 | AsrService.java | 加 `transcribe(request, configName)` 重载 |
| 2 | AsrServiceImpl.java | 注入 AiCapabilitiesQConfig，实现新重载 |
| 3 | ImageUnderstandingService.java | 加 `understand(request/understandStream(request, configName)` 重载 |
| 4 | ImageUnderstandingServiceImpl.java | 注入 AiCapabilitiesQConfig，实现新重载 |

## 不受影响

AigcQConfig、AiDemoController、ContentVideoPreprocessor、ContentAnalyzer 系列、ContentTagExecutor — 均不动。

## 新重载方法实现要点

新重载逻辑与旧方法 95% 相同，唯一区别：
- `aigcQConfig.getAsrApiUrl()` → `params.getApiUrl()`
- `aigcQConfig.getAsrApiKey()` → `params.getApiKey()` ... 以此类推

## 检查项

- [x] 新增 6 个文件，包路径 `service/ai/capability/`
- [x] 两个接口各加 2 个重载
- [x] 两个 impl 各加 1 个 `@Resource AiCapabilitiesQConfig`
- [x] 旧 AigcQConfig 和其他调用方不受影响
- [x] 验证编译通过