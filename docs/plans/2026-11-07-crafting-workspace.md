# Crafting and workspace implementation plan

> For agentic workers: use superpowers:executing-plans. User authorized grouped autonomous execution; do not pause between tasks.

**Goal:** Complete the playable gathering → crafting → rule editing → exploration → persistent draft loop.
**Architecture:** Existing authoritative world and inventory, trusted data recipe catalog, right-side inventory adapter, atomic outer workspace checkpoint.
**Tech Stack:** pinned Godot 4.6.1, GDScript, Python 3.11 stdlib, existing native test runner.
**Spec:** docs/specs/2026-11-07-crafting-workspace.md

## Constraints / review focus
- Do not change third-party files or masks; do not give scripts/new primitive permissions to recipes or drafts.
- Same-material objects must retain independent identity, water, rule versions through selection/transport/save.
- Failures never consume materials, publish rules, replace valid world or partially restore draft data.
- New paused inventory must block keyboard/mouse world actions without changing previous pause state.
- Input sizes and draft totals bounded; empty/legacy checkpoints and selected non-existent IDs handled explicitly.

## Tasks
- [x] T1 test_crafting.gd RED; CreationRecipes + WorldSession.craft + InstanceStore insertion; tests GREEN.
- [x] T2 test_workspace.gd RED; workspace envelope with old play compatibility, incomplete draft validation and atomic load; tests GREEN.
- [x] T3 test_crafting_ui.gd RED; fresh scenario, instance-aware selectors, inventory/crafting UI, workspace save entry; tests GREEN.
- [x] T4 full real-input fresh expedition regression + screenshots at 1152x720; old tests remain tested via original fixture.
- [ ] T5 full Preflight, source/tree verification, one grouped repository push, CI/package evidence and Notion update.

## Ledger
- Source recovery: current remote PR remains ef01392. Extracted provided v0.13 backup has exact same git tree; v0.14 screenshot is not source recovery.
- Baseline: individual original UI input suite passed 23/23; complete runner exceeded outer command timeout without returning report. Existing per-suite logs show no failures; full aggregate will be rerun with sufficient bounded runner time before delivery.
- No independent agent reviewer available; use explicit branch review and regressions, not claim independent audit.

- T1 actual RED: 1 passed/1 failed missing craft; GREEN30. Test floor mining order corrected for existing occlusion; production reach not weakened.
- T2 actual RED missing workspace; GREEN28. Invalid draft and failed world restore preserve both states.
- T3 actual RED no inventory interface; GREEN38 including full real-input fresh expedition. Tests call existing LoomDocument.add (not an invented add_node interface).
- T4 actual small/large GL captures inspected, original three UI tests pinned to legacy scene; new route runs default fresh scene. Inventory/multiple draft edges22; legacy-slot method observed RED then GREEN.
- Independent artifact validator13 Python tests RED→GREEN; actual output cross-checked, not just synthetic fixture.
- Final local full check151 Python /763 native /10 independent outputs PASS, vendor unchanged; editor import passed.
- Ruling: use new outer workspace envelope rather than widening physics/play schema; separate v0.14 slot and explicit legacy fallback avoid overwriting prior user saves.
- Ruling: use existing procedural presentation and surviving inventory screenshot as layout reference, not as proof of recovered implementation or final aesthetic approval.
