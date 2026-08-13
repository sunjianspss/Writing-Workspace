# ADR-0001: Native local-first application spine and authority boundaries

Status: Accepted; recovery controls implemented

Date: 2026-08-12

Decision authority: Product / Architecture Owner
Editorial authority: Repository Maintainer within an authorized change

## Context

Creative Workshop previously had Web, FastAPI, Next.js, and Python runtime paths. The product is now a single-user native macOS writing workbench. Keeping multiple runtime authorities would make behavior, data ownership, recovery, and retirement ambiguous.

This record closes which system owns each load-bearing fact and how projections may participate without becoming parallel authorities.

## Decision

The SwiftUI macOS application is the only product runtime. It uses a local-first spine with the following jurisdictions:

| Fact or surface | Authority / role | Writers and admission | What it does not own |
| --- | --- | --- | --- |
| Articles, topics, materials, styles, prompts, reviews, versions, publishing records | Product SQLite database | `NativeDatabase`; the article/version/pending seam writes through `WritingWorkflow`, while remaining legacy Store writers migrate incrementally | Unsaved edits, credentials, rendering preferences, evaluation evidence |
| Current unsaved writing session | In-memory `WritingSession` | Author edits plus DB-success outcomes from `WritingWorkflow`; `WorkshopStore` only projects it | Committed article history |
| Autosave snapshot | `WritingSession` through `AutosaveController`, as a recovery copy in UserDefaults | Debounced session transitions, without View-level scheduling | Accepted article truth; it may be restored or discarded |
| API credential | macOS Keychain | Settings through `KeychainCredentialStore` | Model configuration or article data |
| AI output | Candidate result with recorded provenance | Declared workflow descriptors through `WorkflowEngine` | Final editorial truth before review/acceptance/save |
| WeChat preview/export | Bundled, non-persistent WebKit rendering projection | Current title, summary, body, and presentation preferences | Article persistence or a second editable draft |
| Formatter theme/CSS preference | UserDefaults presentation preference | Formatter controls | Article content |
| Evaluation result database and reports | Independent evaluation evidence | `CreativeWorkshopEval` | Product facts or automatic release authority outside its declared gate |

`Package.swift` declares shipping targets and dependencies. `ARCHITECTURE.md` describes the current topology. Source, tests, and architecture guards are the behavior evidence when prose drifts.

The retired Web/FastAPI/Next/Python runtime has no compatibility entry point. A local HTTP backend must not be reintroduced without a new architecture decision that names the blocker, migration, recovery, and retirement impact.

## Compatibility surfaces

- Product SQLite schema and stored settings are persisted contracts. Changes require an explicit version transition and tests against an older database shape.
- Workflow descriptors and model configuration are package-internal contracts; callers cross `AIWorkflowExecuting`, not runner or transport internals.
- The WeChat renderer consumes a projection of article fields. Its HTML/JS bridge may change internally while preserving copy/export behavior and non-ownership of article data.
- Generated app metadata is a projection of repository version and build inputs; it is not a second version authority.

## Negative paths and recovery

### Model denial, timeout, decoding failure, or cancellation

- Detection: workflow result and operation state.
- Owner: the initiating native workflow; the author decides whether to retry, accept a clearly marked fallback where supported, or keep existing content.
- Terminal invariant: existing accepted content is not silently cleared or overwritten, and provenance is not represented as remote success.
- Evidence: workflow/store tests, run records, and visible status/pending-review state.

### Unaccepted generated result

- Detection: pending review state.
- Owner: the author.
- Action: confirm, discard, or leave pending; switching context cleans up only the corresponding orphan candidate.
- Terminal invariant: confirmed versions are never deleted by pending-review cleanup.
- Evidence: pending-review state-machine tests and persisted version status.

### Unsaved-session restart

- Detection: autosave snapshot on launch.
- Owner: the author.
- Action: restore or discard.
- Terminal invariant: restore does not claim the snapshot was previously committed; discard leaves saved SQLite content unchanged.

### Renderer failure

- Detection: WebKit bridge/export error.
- Owner: formatter surface.
- Action: preserve the source article, report failure, and allow retry or another export route.
- Terminal invariant: renderer failure cannot mutate or lose the authoritative article.

### Database initialization or migration failure

- Current behavior: an existing database is snapshotted before an upgrade; migrations run in one immediate transaction and advance `user_version` only inside that transaction. A failed transition rolls back and restores the open connection from the verified pre-migration backup before startup reports the error.
- Terminal invariant: the pre-migration database remains recoverable and schema version advances only after the transition completes.
- Evidence: version 10 → 11 backup/restore tests, a deliberately incompatible migration-history table, and the public manual restore entry point. Future schema changes must append an enumerated migration and preserve the same failure test pattern.

## Guards

- `script/architecture_guard.sh` rejects direct model-runner access from Views and enforces workflow descriptor entry paths.
- The same guard rejects direct `saveArticle`, `saveDraftVersion`, `PendingReviewMachine`, or migrated `polishDraft` orchestration from `WorkshopStore*`; those operations belong to `WritingWorkflow`.
- `script/test_architecture_guard.sh` proves the guard passes a clean fixture and rejects an injected Store persistence violation.
- `script/verify.sh` is the supported local and CI gate for architecture guards plus XCTest.
- Package dependency direction is `CreativeWorkshopMac` / `CreativeWorkshopEval` → `CreativeWorkshopCore`; the evaluation executable does not own product runtime state.
- Web runtime directories and package-manager entry points remain retired.

Each new guard must demonstrate that it detects a known or safely planted violation. Exception baselines are shrink-only unless a new architecture decision authorizes growth.

## Consequences

- Native behavior has one executable path and one committed-data authority. `WorkshopStore` remains a transitional hybrid for workflows not yet moved behind `WritingWorkflow`; the new boundary is a shrink-only ratchet, not a claim that every mutation has migrated.
- Renderers, autosave, and evaluation can evolve without becoming peer writers of product truth.
- The author retains editorial decision authority even as workflows become more capable.
- Distribution and product-wide accessibility still require dedicated implementation slices. Migration recovery and the first WritingSession/WritingWorkflow authority cutover are implemented; additional workflow actions may move behind the same command boundary incrementally.
