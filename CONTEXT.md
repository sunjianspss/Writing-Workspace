# Creative Workshop Context

Status: Canonical repository navigation and domain language

Owner role: Repository Maintainer
Validated: 2026-08-12 against commit `7453181` and the current working tree

This file tells maintainers and agents where accepted facts live and which words the project uses. It is an index, not a second product or architecture specification.

## Authority by concern

There is no single document that overrides every other concern.

| Question | Authority | Notes |
| --- | --- | --- |
| What product are we building and for whom? | `PRODUCT.md` | Current product intent and non-negotiable product principles. |
| How should the native interface behave and feel? | `DESIGN.md` | Experience, state, layout, accessibility, and design-system contract. |
| Why is the system native and local-first? | `docs/adr/0001-native-local-first-spine.md` | Accepted load-bearing decision and authority boundaries. |
| What is the current runtime topology? | `ARCHITECTURE.md` plus source evidence | `Package.swift`, source, tests, and guards win when prose has drifted. |
| Which targets and dependencies ship? | `macos/CreativeWorkshopMac/Package.swift` | SwiftPM manifest is the executable package contract. |
| What does the system actually do now? | Source, tests, runtime output, and `script/architecture_guard.sh` | Do not infer behavior from old implementation notes. |
| How do I build, verify, evaluate, or package? | `README.md` and `script/` | A documented command is supported only when its script exists and passes. |
| How did the product evolve? | `创作工坊-PRD.md` and older PRDs | Historical evidence; not current fact authority. |

If sources in the same jurisdiction conflict, stop and surface the conflict. Do not silently combine stale and current behavior.

## Repository shape

```text
macos/CreativeWorkshopMac/
  Sources/CreativeWorkshopCore/   domain models, persistence, AI workflows
  Sources/CreativeWorkshopMac/    SwiftUI app, views, and store projections
  Sources/CreativeWorkshopEval/   independent evaluation executable
  Tests/                           XCTest behavior evidence
evals/                             cases, style samples, reports, local result store
script/                            supported verification, development, and packaging paths
docs/adr/                          accepted load-bearing decisions
```

The macOS app is the only product runtime. Do not add a local HTTP backend or revive the retired Web/Python path as a fallback.

## Domain language

- **当前稿件 (working draft)** — the editable in-memory writing session currently projected into the UI. It may contain unsaved changes.
- **已保存文章 (saved article)** — the committed article record in the product SQLite database.
- **待复核版本 (pending review)** — a material generated candidate shown for comparison. It is not an accepted article revision until the author confirms it.
- **改稿版本 (draft version)** — persisted before/after evidence used for review and recovery. Its review status determines whether it is pending or confirmed.
- **智能下一步 (writing advisor)** — a bounded observation and plan, not unrestricted agent authority.
- **代理会话 (agent session)** — an experimental, budgeted decision loop over an allowed action set. It cannot publish or bypass pending review.
- **演示 fallback (demo fallback)** — clearly labelled local illustrative output used when an established workflow permits demonstration without a configured key.
- **调用失败 (model failure)** — transport, HTTP, timeout, cancellation, or decoding failure. It must remain observable and must not be represented as a successful model result.
- **发布物料 (publishing assets)** — derivative copy such as summary, cover text, Moments copy, tags, and Xiaohongshu text.
- **公众号排版 (WeChat formatting)** — a non-authoritative rendering/export projection of the current article in a bundled WebKit surface.
- **文档导出 (document export)** — producing Markdown, HTML, image, or PDF artifacts. It is distinct from **数据可移植性**, which means backup/import of authoritative product records.
- **主 SQLite (product SQLite)** — authority for committed product facts.
- **自动保存快照 (autosave snapshot)** — a disposable recovery copy of unsaved work; it is not a committed article.
- **评测证据库 (evaluation store)** — independent quality evidence. It never becomes product data.

## Evaluation pipeline names

- `direct` — direct draft path.
- `agent` — structured agent-draft pipeline.
- `deep` — iterative diagnosis/revision pipeline.
- `agentic` — bounded decision-loop pipeline.

Use these names exactly in code, reports, and documentation.

## Historical records

- `创作工坊-PRD.md` is the detailed product evolution and implementation log.
- `《创作工坊》产品需求文档 PRD-第一版.md`, `创作工坊_PRD-第二版.md`, and `创作工坊_PRD_修订版.md` are historical proposals.
- `PRD_完成度审计.md` is a point-in-time audit.

Historical records may explain why a decision exists. They do not reopen a retired runtime or override current product, design, package, or behavior contracts.
