# Product

<!-- impeccable:product-schema 1 -->

Status: Canonical product intent

Owner role: Product Owner
Validated: 2026-08-12 against the current working tree and `创作工坊-PRD.md`

This record owns durable product intent. `创作工坊-PRD.md` remains the product evolution and implementation history; it is not a competing source for current product truth.

## Platform

macos

`macos` is intentionally recorded even though the current Impeccable product-schema enum does not yet list macOS. Treat this as a native desktop product, never as a web surface.

## Users

The primary user is currently the product developer: a technically capable WeChat Official Account long-form author who writes frequently, collects fragmented ideas, and wants AI assistance without surrendering editorial judgment.

The product may later serve other independent long-form creators, but multi-user product decisions must not distort the current single-author workflow.

## Product Purpose

Creative Workshop is a local AI writing workbench that turns an idea or source fragment into a structured, editable article and helps the author diagnose, revise, prepare, publish, and review the work.

Success means the author starts more easily, reaches a publishable draft with less avoidable editing, preserves a recognizable personal voice, and retains final authority over every material change.

## Positioning

Creative Workshop is a private editorial room, not an AI ghostwriter. Its differentiating mechanism is a reviewable writing loop: local context and style evidence feed bounded AI workflows; material outputs become candidates; diagnostics, provenance, versions, and pending review make the author's decision cheaper without replacing it.

## Operating Context

The core journey is:

```text
idea or material
  -> topic / outline / draft
  -> diagnosis and revision
  -> human review
  -> article editing
  -> community assets and WeChat formatting
  -> publish / archive / retrospective
```

The app is used as a native macOS desktop tool. Article data remains local. Model calls go directly to an OpenAI-compatible endpoint configured by the author. The API key is stored in macOS Keychain.

## Capabilities and Constraints

### Supported

- Native macOS workspace with article, topic, material, style, prompt, diagnosis, version, and publishing workflows.
- Local SQLite persistence for committed product facts.
- Keychain storage for the model credential.
- Bounded AI workflows with local fallbacks, run traces, quality checks, and pending review.
- Markdown/article export, community publishing assets, and offline WeChat formatting/export.
- Independent writing-quality evaluation pipelines: `direct`, `agent`, `deep`, and `agentic`.

### Experimental

- Bounded agent sessions. They remain off by default until evaluation evidence supports wider use.
- Workflow-specific model routing exposed as an advanced setting.

### Planned

- Product-grade application icon, signed and notarized distribution, update strategy, and user-facing data backup/recovery.
- A transactional, recoverable database migration path.
- Product-wide accessibility and visual regression evidence.

### Retired or explicitly out of scope

- The former Web, FastAPI, Next.js, and Python runtime paths are retired.
- Cloud-authoritative data, multi-user collaboration, automatic publishing, and unbounded autonomous agents are not current product goals.

## Brand Commitments

- Product name: **创作工坊 / Creative Workshop**.
- Product metaphor: a calm, capable private editorial room.
- Voice: direct, reassuring, specific, and editorial rather than promotional or technical for its own sake.
- Familiar native macOS behavior outranks decorative novelty.

## Evidence on Hand

- Current product evolution and acceptance history: `创作工坊-PRD.md`.
- Current runtime topology and boundaries: `ARCHITECTURE.md`, verified against source and `Package.swift` when they differ.
- Automated behavior evidence: XCTest suites under `macos/CreativeWorkshopMac/Tests`.
- Writing-quality evidence: cases and reports under `evals/`.
- Existing publishing-workspace visual evidence: `macos/CreativeWorkshopMac/design-qa.md`.

No public customer claims, testimonials, commercial benchmarks, or multi-user evidence are available; future surfaces must not invent them.

## Product Principles

1. **The author decides.** Material AI changes remain candidates until the author reviews and accepts them.
2. **Local facts stay local.** Article data is local by default and secrets live in Keychain.
3. **Degradation stays honest.** Demonstration or fallback output must be visibly distinguishable from a successful model result.
4. **Progress stays recoverable.** Existing content must survive failure, cancellation, restart, and rejected generation.
5. **The shortest governed path wins.** The everyday writing path should be faster than bypassing review, provenance, or save safeguards.

## Accessibility & Inclusion

The supported desktop experience must remain keyboard-operable, preserve native focus behavior, expose meaningful VoiceOver labels and hints, avoid color-only state communication, and remain legible in light and dark appearances. No additional product-specific accommodation has yet been established.
