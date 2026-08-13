# Changelog

This file records user-visible changes. Versions follow Semantic Versioning; public macOS distribution additionally requires the release gates in `docs/RELEASING.md`.

## [Unreleased]

### Added

- The workbench is now a two-column shell: a single navigation column and a content column that shows one destination at a time. Navigation previously lived in three separate controls (sidebar list, composer segments, inspector segments); its ten destinations are now grouped as Current draft and Workspace.
- Articles gained their own destination with status filtering; the navigation column keeps only a collapsed Recents shortcut.
- Appearance is selectable—Follow System, Light, or Dark—from the navigation column footer or Settings → Advanced.
- A local author profile (pen name and avatar) identifies the workbench. It is display only: no account, no server, and it never reaches prompts, bylines, or generated output.
- Settings moved from a separate preferences window into a content-column destination, still reachable with ⌘,.

### Changed

- Current draft, pending review, autosave, and unsaved-change baselines now live in `WritingSession`; article/version persistence crosses a typed `WritingWorkflow` boundary and projects only after database success.
- Full-document polish, self-check, AgentRun evidence, and pending delivery now execute as one `WritingWorkflow` vertical slice, with the database facts committed atomically.
- Product database schema upgrades are versioned, transactional, backed up before migration, and recoverable through a verified restore path.
- Diagnosis, pre-publish audit, and library evidence moved from the persistent inspector column into their own destinations; draft measurements too small to earn a destination moved into the status bar.
- Draft text location and workflow narration moved out of `WorkshopStore` into `DraftTextLocator` and `WorkflowNarration`, so the exact-match and truncation rules are independently testable.

### Fixed

- Failed pending confirm/discard operations no longer clear the review card or resume a paused plan as if they succeeded.
- Late AI results no longer overwrite edits made after generation started; autosave recovery reconciles pending, confirmed, missing, and temporarily unknown database states.
- New/open article actions now require confirmation before discarding unsaved edits; backgrounding or terminating the app synchronously flushes the recovery snapshot.
- Discarding a generated candidate now preserves any manual edits made on its preview as a recoverable confirmed version before restoring the original draft.
- Opening an article or starting a new draft no longer navigates away while the session switch is still awaiting confirmation, which previously showed the target view holding the *previous* draft.

### Verification

- Architecture guard self-test injects forbidden Store persistence and polish-orchestration calls and proves the guard rejects them in local and CI verification.

### Planned

- Developer ID signing, notarization and a production app icon.

## [0.1.0] - 2026-08-12

### Added

- A native, local-first writing workspace with materials, topics, article drafting and review.
- Governed AI workflows with explicit fallback, pending-review and evaluation paths.
- WeChat Official Account formatting and multi-format export.
- Canonical product, design and architecture authority records.
- A shared native settings system and app-wide operation status surface.
- Reproducible ad-hoc release packaging with CI verification.
