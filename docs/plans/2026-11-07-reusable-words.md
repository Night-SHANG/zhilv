# Reusable player words implementation plan

> For agentic workers: use superpowers:executing-plans; user authorized autonomous grouped execution.

**Goal:** Turn authored programs into typed reusable words through the existing UI and runtime.
**Architecture:** Thin LoomDocument composition operations over RuleDraft/RuleRuntime; unchanged compiler, world, persistence and permissions. Existing GraphEdit handles typed connections.
**Tech Stack:** Godot 4.6.1, GDScript, Python stdlib; no new dependencies.
**Spec:** docs/specs/2026-11-07-reusable-words.md

## Constraints
Keep live and draft state separate. Version pins and limits unchanged. Do not touch vendor or main. Exact source baseline 368a91a / tree39966105bba1cd7f420042589f5715e453f307c4. Native tests and actual package required for corresponding claims.

## Review focus
Same-name parameters cannot silently merge different constants. Bad publication cannot alter world/graph/history. Appended calls cannot break existing graph or overrun limits. UI refresh cannot crash on a former constant now parameter. Changing call target must not retain incompatible ports; old saves and pinned callers must remain executable.

## Tasks
- [x] T1 RED/GREEN typed expose/default/restore/publish/append APIs and boundary tests in test_word_composition.gd; update loom_document.gd only.
- [x] T2 RED/GREEN actual UI publication, selection and invocation, config edits in loom_panel.gd; typed param support and runtime restore.
- [x] T3 end-to-end two-carrier composition, nested export/import, workspace disk restore; independent output checker and adversarial tests.
- [ ] T4 complete regression, software-GL UI capture, clean staging/package, review diff, one grouped push and record exact outcome in Notion.

## Ledger
- Source extracted from mounted v0.15 evidence package, git write-tree exactly equals remote PR tree. Isolated disposable checkout, no main changes.
- Baseline initial outer timeout: first24 suites passed; direct diagnostics43 passed; full bounded rerun in progress. No uncompleted run counted as PASS.
- User delegates routine decisions; retain existing visual layout rather than start new artwork approval cycle. No independent reviewer/subagent tool available; final review is implementer self-review plus tests.

- Baseline complete bounded run confirmed PASS: 163 Python, 908 native and all eleven original outputs. Initial outer timeout was not counted as success.
- T1 RED missing expose API, then native composition tests through types, immutable versions, two carriers, nested export/import and restore. MAX_QUANTITY test corrected to existing 1,000,000,000 limit; no runtime limit weakened.
- T2 real mouse buttons in embedded GraphEdit window verified. Mouse event test routing corrected to root Viewport plus embedded-window position; this was a test-harness issue, not a product defect.
- T3 independent expected module fixture authored separately, 12 adversarial validator tests observed RED then GREEN; actual native output also validated.
- Product regressions reproduced: parameter node overlapping its neighbour, wide integer values silently clamped by UI. Native arrange_nodes on structural changes and exact compiler bounds fixed them; 5 layout assertions pass. Pure scalar changes preserve manual layout.
- Actual software-GL captures regenerated from fresh empty-inventory scene after normal gathering and crafting, at 1440x900 and 1152x720. No concept images, no final-art acceptance.
- Whole-branch review uses implementer self-review plus regression checks; no independent agent available.

- Final complete local verification PASS (175 Python /1012 native /12 independent outputs /vendor hashes), exit0. Linux package staged import, real main startup and archive verification PASS. Remote proof remains pending until grouped commit CI.
