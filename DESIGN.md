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
    height: "32px"
    padding: "6px 12px"
  labeled-editor:
    rounded: "{rounded.control}"
    padding: "8px"
  navigation-column:
    width: "252px"
    row-rounded: "6px"
    row-padding: "6px 8px"
  screen-header:
    padding: "12px 20px"
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

Appearance is the author's choice: Follow System, Light, or Dark, set in Settings → Advanced or from the navigation column footer. The navigation column, screen headers, and status bar take their values from `WorkshopPalette`, whose every token is an AppKit dynamic color resolving per appearance, so all three settings hold. Everything else continues to use SwiftUI and AppKit semantic colors. Semantic colors take darker variants on light grounds so contrast survives both. Production code owns the resolved values; this document owns their roles.

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

The primary shell is two columns: a navigation column and a content column. The navigation column is the single source of navigation and ends in a footer holding Settings, the appearance switch, and the author identity. The content column shows exactly one destination at a time and carries the status bar at its bottom. There is no persistent inspector column.

Every destination is one of two groups. **Current draft** destinations follow the open article—writing process, article body, publishing assets, diagnosis review, and pre-publish audit—and the group stays visible so the open draft, its status, and any pending review are always legible. **Workspace** destinations are cross-article libraries: articles, topics, materials, and the reference library. A collapsed Recents affordance in the navigation column is a shortcut, not the article list; the article list is its own destination.

Because no third column exists, a screen that needs before/after comparison splits inside the content column and must offer an explicit return to the article body. Every content screen opens with a breadcrumb header naming its group and title, so the column always self-identifies.

Spacing follows the production semantic scale: field 6, control 8, stack 12, section 16, page 20 points. Tight spacing expresses one group; larger spacing marks a new decision. Responsive behavior is structural: panels stack or hide at declared width thresholds while the primary action remains reachable.

Settings is a destination in the content column, reached from the navigation column footer or ⌘,. It keeps four categories—Model, Style, Prompts, Advanced—with vertical scrolling only. Expert JSON and experimental controls remain progressively disclosed or isolated from everyday configuration.

## Elevation & Depth

The system is flat by default. Hierarchy comes from native surface differences, dividers, spacing, selection, and the darker ground used for functional chrome such as the navigation column or status bar. Selection is a raised neutral surface, never the accent color. Cards do not combine a strong border and shadow, and cards are never nested merely to create hierarchy.

**The Structural Depth Rule.** A new surface must represent a distinct task, state, or ownership boundary; decoration alone does not earn a container.

## Shapes

Controls use the native form language. Custom editable controls use an 8-point corner radius; larger task surfaces may use 12 points. Capsules are reserved for compact tags and states. SF Symbols provide the icon vocabulary.

## Components

### Operation Status Bar

A single status surface sits at the foot of the content column, below whichever destination is showing. It shows current textual status, a native progress indicator while work is active, and Cancel only when cancellation is actually supported. Its trailing side carries read-only measurements of the open draft—word count and latest diagnosis score—which is where information too small to earn a destination belongs. It does not infer success or failure from prose and never relies on color alone.

### Navigation Row

One row shape serves every navigation destination: optional symbol, title, and a trailing count or attention badge. Counts are tertiary and monospaced. An attention badge is reserved for work awaiting the author's decision and is the only place red appears in navigation. Selection and hover are neutral raised surfaces.

### Author Identity

The navigation column footer names the author: avatar and pen name, with the running model on a second line beneath. The profile is local display only—no account, no server, no registration—and it never reaches prompts, bylines, or generated output. The avatar falls back to initials from the pen name. Making the profile influence writing is a separate decision and would need its own record of intent.

### Screen Header

Each content screen opens with a breadcrumb naming its group and title, followed by that screen's actions. A screen that replaces the article body must offer a return to it.

### Labeled Editor

A reusable labeled `TextEditor` supplies title, optional help, prose/code typography, native focus behavior, a semantic border, and VoiceOver label/hint. It is used for multiline settings where the same intent recurs.

### Buttons

- One `.borderedProminent` action per decision group.
- Secondary actions remain native bordered or plain controls.
- Destructive actions use a destructive role and require confirmation when data or credentials cannot be restored from the current screen.
- Loading and disabled behavior must be visible and correctly announced.

### Settings Navigation

Settings uses a segmented category control in its screen header, with labels and SF Symbols. Each tab has one page heading, a short purpose statement, grouped form sections, and one persistent status surface. Advanced model routing is closed by default.

### Empty and Failure States

An empty state explains what is absent and provides the next valid action. An error names the problem and recovery. Demo/fallback output names its provenance and remains reviewable. Existing user content stays visible through failures.

## Do's and Don'ts

### Do:

- **Do** let article content own the largest and quietest region.
- **Do** pair every asynchronous action with running, cancellation, completion, failure, and recovery behavior as applicable.
- **Do** use system colors, fonts, focus rings, menus, dialogs, and keyboard conventions.
- **Do** keep source provenance visible for generated or fallback content.
- **Do** verify wide and narrow windows, light and dark appearances, keyboard order, VoiceOver labels, real Chinese copy, and long content.
- **Do** take draft status color from `WorkshopPalette.statusColor` rather than re-deciding what "已发布" looks like.

### Don't:

- **Don't** create a card for every group or nest cards to manufacture hierarchy.
- **Don't** expose JSON, raw model output, or experimental controls as the default path.
- **Don't** present a local fallback as a successful remote model result.
- **Don't** use decorative gradients, glass, motion, or colored icon tiles as substitutes for information hierarchy.
- **Don't** invent mobile touch patterns or custom controls when a standard macOS affordance exists.
