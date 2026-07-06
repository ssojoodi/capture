# Capture Project Memory

## Product Direction

Capture is a fast, minimal, native macOS image annotation app inspired by Skitch.

Persistent product constraints:

- User-facing app name: `Capture`.
- Native Swift + AppKit.
- Elegant light-mode UI.
- Fast and minimal over feature-rich.
- Core workflow: open or paste image, annotate quickly, crop if needed, copy flattened image or export JPG.
- No editable project file format unless explicitly planned later.
- No screenshot capture feature unless explicitly planned later.

## Iteration Planning Convention

Each implementation iteration must have a dedicated planning document in `docs/`.

Filename format:

```text
YYYY-MM-DD-HH-MM-2-4-words-describing-iteration.md
```

Example:

```text
2026-06-26-09-52-wysiwyg-undo-redo.md
```

Each planning file should include:

- Summary
- Product behavior target
- Architecture changes
- UX acceptance criteria
- Automated test plan
- Manual verification plan
- Assumptions and non-goals

Older planning files remain as historical records. Do not overwrite prior iteration plans when planning a new iteration.

## Goal Structure for Iterations

When using the Goal feature for an implementation iteration, keep the objective consistent:

```text
Implement docs/<timestamped-plan-file>.md, creating focused tests and minimal meaningful commits for each milestone, then verify with xcrun xcodebuild and a screen capture artifact before marking the goal complete.
```

Expected goal milestones:

- Read the current timestamped plan.
- Implement the smallest coherent product slice from that plan.
- Add or update focused automated tests where behavior can be isolated.
- Run `xcrun xcodebuild -project Capture.xcodeproj -scheme Capture -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test`.
- Launch the built `Capture.app`.
- Capture a verification screenshot under `artifacts/verification/`.
- Commit the plan and implementation with short, meaningful commit messages.
- Confirm the working tree is clean before completing the goal.

## Current Architecture Notes

- Internals may still use `Capture` names for project/module targets.
- Product-facing naming should stay `Capture`.
- The canvas is AppKit/Core Graphics based.
- Annotation coordinates should remain in image space so zoom does not reduce export fidelity.
- Expensive rendering, especially blur, should be cached or applied only when needed.
- Prefer direct, understandable model changes over broad abstraction.

## UX Principles

- Tools should feel immediate.
- Drag previews are transient. After mouse-up, the user should see the actual result, not a lingering construction rectangle.
- Copy/export should not be the first time an edit appears correct.
- Toolbar and keyboard shortcuts should expose common actions without adding inspector complexity.
- If behavior differs from Skitch, document why in the relevant iteration plan.
