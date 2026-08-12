---
name: Creative Workshop
description: A calm native editorial workbench for long-form authors.
rounded:
  control: "8px"
  surface: "12px"
spacing:
  field: "6px"
  control: "8px"
  stack: "12px"
  section: "16px"
  page: "20px"
components:
  operation-status:
    rounded: "{rounded.control}"
    height: "30px"
    padding: "6px 12px"
  labeled-editor:
    rounded: "{rounded.control}"
    padding: "8px"
---

# Design System: Creative Workshop

Status: Canonical native experience contract

Owner role: Design Owner
Production token source: `macos/CreativeWorkshopMac/Sources/CreativeWorkshopMac/Design/WorkshopDesignSystem.swift`

## Overview

**Creative North Star: "The Native Editorial Room"**

Creative Workshop should feel like a private editor's room built into macOS: calm enough for sustained reading, dense enough for serious work, and explicit about what the system is doing. The interface recedes behind the article. Personality comes from precise editorial language, disciplined hierarchy, and trustworthy state—not ornamental chrome.

This is an Operate surface. Familiar macOS behavior, scanability, keyboard efficiency, and recovery outrank surprise. The app may feel warm and authored, but it must never make a standard action harder to recognize.

**Key Characteristics:**

- Native, restrained, and editorial.
- One primary action per decision point.
- Progressive disclosure for expert or experimental controls.
- Persistent, textual feedback for save, generation, review, failure, and fallback provenance.
- Long-form content receives the largest, quietest surface.

## Colors

App chrome uses SwiftUI and AppKit semantic colors so contrast and appearance adapt with macOS. Production code owns the resolved values; this document owns their roles.

- **Accent** — primary action, current selection, and active progress only.
- **Primary text** — article content, headings, and decisive labels.
- **Secondary text** — help, metadata, and explanatory copy; never the sole carrier of critical state.
- **Success / warning / destructive** — system semantic colors paired with a symbol and text.
- **Surfaces** — native window, control, and material surfaces. WeChat article themes are content-rendering themes and do not define app chrome.

**The Rare Accent Rule.** Accent color communicates action or state. It is not page decoration.

## Typography

Use the macOS system family through semantic SwiftUI roles. Product UI does not introduce a display font.

- **Title** — `.title2` or `.title3`, semibold/bold, for the current workspace or page.
- **Headline** — `.headline`, for panel and group titles.
- **Body** — `.body` or `.callout`, for article-adjacent content and editable prose.
- **Label** — `.caption` or `.caption2`, for metadata and help.
- **Monospaced** — code, JSON, paths, run identifiers, and measurements only.

Long explanatory prose should remain near a 65–75 character measure. Do not shrink important copy to make an overloaded panel fit.

## Layout

The primary shell remains Sidebar → Composer → optional Inspector. The Composer owns the current task. Sidebar owns navigation and recent records. Inspector owns supporting context, diagnosis, publishing evidence, and library projections; it must not become a second primary workflow.

Spacing follows the production semantic scale: field 6, control 8, stack 12, section 16, page 20 points. Tight spacing expresses one group; larger spacing marks a new decision. Responsive behavior is structural: panels stack or hide at declared width thresholds while the primary action remains reachable.

Settings use four native categories—Model, Style, Prompts, Advanced—with vertical scrolling only. Expert JSON and experimental controls remain progressively disclosed or isolated from everyday configuration.

## Elevation & Depth

The system is flat by default. Hierarchy comes from native surface differences, dividers, spacing, selection, and material used for functional chrome such as the Inspector or status bar. Cards do not combine a strong border and shadow, and cards are never nested merely to create hierarchy.

**The Structural Depth Rule.** A new surface must represent a distinct task, state, or ownership boundary; decoration alone does not earn a container.

## Shapes

Controls use the native form language. Custom editable controls use an 8-point corner radius; larger task surfaces may use 12 points. Capsules are reserved for compact tags and states. SF Symbols provide the icon vocabulary.

## Components

### Operation Status Bar

A shared bottom status surface is visible in every workspace and in Settings. It shows current textual status, a native progress indicator while work is active, and Cancel only when cancellation is actually supported. It does not infer success or failure from prose and never relies on color alone.

### Labeled Editor

A reusable labeled `TextEditor` supplies title, optional help, prose/code typography, native focus behavior, a semantic border, and VoiceOver label/hint. It is used for multiline settings where the same intent recurs.

### Buttons

- One `.borderedProminent` action per decision group.
- Secondary actions remain native bordered or plain controls.
- Destructive actions use a destructive role and require confirmation when data or credentials cannot be restored from the current screen.
- Loading and disabled behavior must be visible and correctly announced.

### Settings Navigation

Settings use native tabs with labels and SF Symbols. Each tab has one page heading, a short purpose statement, grouped form sections, and one persistent status surface. Advanced model routing is closed by default.

### Empty and Failure States

An empty state explains what is absent and provides the next valid action. An error names the problem and recovery. Demo/fallback output names its provenance and remains reviewable. Existing user content stays visible through failures.

## Do's and Don'ts

### Do:

- **Do** let article content own the largest and quietest region.
- **Do** pair every asynchronous action with running, cancellation, completion, failure, and recovery behavior as applicable.
- **Do** use system colors, fonts, focus rings, menus, dialogs, and keyboard conventions.
- **Do** keep source provenance visible for generated or fallback content.
- **Do** verify wide and narrow windows, light and dark appearances, keyboard order, VoiceOver labels, real Chinese copy, and long content.

### Don't:

- **Don't** create a card for every group or nest cards to manufacture hierarchy.
- **Don't** expose JSON, raw model output, or experimental controls as the default path.
- **Don't** present a local fallback as a successful remote model result.
- **Don't** use decorative gradients, glass, motion, or colored icon tiles as substitutes for information hierarchy.
- **Don't** invent mobile touch patterns or custom controls when a standard macOS affordance exists.
