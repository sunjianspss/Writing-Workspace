# PRD 完成度审计

更新时间：2026-07-01

## 范围

本审计覆盖当前 `创作工坊-PRD.md` 中第 17 章和第 18 章的已实施优化，以及原生化后仍需保留的验收边界。旧 Web / FastAPI / Next / Python 方案已归档，不再作为当前完成度证据。

## 当前结论

| 范围 | 结论 | 证据 |
| --- | --- | --- |
| 17.1 近期最值得做 | 已完成 | 原生风格库、全文润色、多版本候选、提示词模板、归档筛选、版本差异、复盘详情均已进入 SwiftUI / SQLite 主线 |
| 17.2 技术债清理 | 已完成 | `ContextPackage`、`AIWorkflowRunner`、可编辑 `prompt_templates`、`ai_calls.input_summary/output_summary`、`PRAGMA user_version` 均已落地 |
| 18.3 P1 写作质量改造 | 已完成 | 诊断-改写闭环、诊断记忆、防空转、作者雷区、体裁化风格、生成后自检 |
| 18.4 P2 写作台深化 | 已完成 | 待复核工作流、文学写作能力趋势、读者视角模拟 |
| 18.5 P3 | 部分完成 | 选题去重已完成；分段生成 + 段落级连贯性校验明确暂缓 |
| 旧架构清理 | 已完成当前源码清理 | 工作区源代码只保留 SwiftPM 原生路径；App 不再从仓库 `data/` 自动复制旧库 |

## 验证命令

```bash
env SWIFTPM_CONFIG_PATH="$PWD/.swiftpm-state/config" \
  SWIFTPM_SECURITY_PATH="$PWD/.swiftpm-state/security" \
  SWIFTPM_CACHE_PATH="$PWD/.swiftpm-state/cache" \
  CLANG_MODULE_CACHE_PATH="$PWD/.swiftpm-state/module-cache" \
  swift test --disable-sandbox --package-path macos/CreativeWorkshopMac
```

当前测试覆盖：模型解码、写作诊断结构、文本差异、文章归档、风格库、提示词模板、AI 调用摘要、草稿版本和候选版本确认。

## 后续不在本轮范围

- 导入 / 导出。
- 签名、公证、自动更新。
- 云同步、多用户、移动端、浏览器插件、热点抓取。

模型路由已实现（不再属于本轮范围外事项）：`ModelConfig.workflowOverrides` 支持按工作流覆盖模型/端点，见第 20.6 与第 21 章 R4 实施记录。

流式输出已实现（不再属于本轮范围外事项）：`OpenAICompatibleModelGateway.stream(_:)` + `AIWorkflowRunner` 的 `onPartialOutput` 增量回调，见第 19.3.5 与第 22 章任务 9 实施记录。
