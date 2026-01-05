# Finder Extension Implementation Phases

This breaks the Finder extension plan into discrete phases, each sized for a single implementation session.

## Phase Documents

| Phase | Document | Description |
|-------|----------|-------------|
| 1 | [phase-1-xcode-setup.md](phases/phase-1-xcode-setup.md) | Xcode project with three targets |
| 2 | [phase-2-catboard-core.md](phases/phase-2-catboard-core.md) | CatboardCore framework (6 files, ~575 lines) |
| 3 | [phase-3-finder-extension.md](phases/phase-3-finder-extension.md) | Finder Sync extension (~200 lines) |
| 4 | [phase-4-container-app.md](phases/phase-4-container-app.md) | Container app (~55 lines) |
| 5 | [phase-5-distribution.md](phases/phase-5-distribution.md) | Signing, notarization, pkg integration |

## Phase Overview

| Phase | Dependencies | Scope |
|-------|--------------|-------|
| 1 | None | Create Xcode project structure |
| 2 | Phase 1 | 6 Swift files (~575 lines) |
| 3 | Phases 1, 2 | 1 Swift file (~200 lines) |
| 4 | Phases 1, 2 | 1 Swift file (~55 lines) |
| 5 | Phases 1-4 | Scripts and configuration |

## Implementation Order

```
Phase 1 ──┬── Phase 2 ──┬── Phase 3 ──┐
          │             │             ├── Phase 5
          │             └── Phase 4 ──┘
          │
          └── (Can start signing setup in parallel)
```

**Critical path:** 1 → 2 → 3 → 5

Phase 4 can be done in parallel with Phase 3 since they're independent once Phase 2 is complete.

## Reference

- [finder-extension-plan.md](finder-extension-plan.md) - Full implementation plan with all code and design decisions
