# Guided expedition implementation plan
> Execute inline using the established test-first process. User delegated grouped execution; no per-task approval loops.

Goal: Make existing rule creativity understandable and reusable in an extended exploration route.
Architecture: Reuse runtime/evaluator snapshots, append-only data goal versions, existing HUD and loom. See docs/specs/2026-11-07-guided-expedition.md.
Stack: Godot4.6.1 GDScript; Python3.11+ stdlib.

- [x] Baseline: verify zip source root equals 04d7a46e; run all existing gates. Current disposable branch dev/local-v015, main untouched.
- [x] T1 test_diagnostics.gd: RED missing APIs, then bounded evaluation outcomes, actual commit results, preview on isolated copy; guard stale cache and reentry. runtime rule_evaluator.gd / rule_runtime.gd.
- [x] T2 test_progression.gd: RED supply/compat unsupported, then strict goal schema and old-version prefix validation; add two goals to fresh data only. Independent Python validators updated without weakening existing fixtures.
- [x] T3 test_guidance_ui.gd: contextual hints + selected-object outcome + dry run on existing loom; pause/input still safe; no redesign. Add lower-region world marker through existing drawing.
- [x] T4 test_extended_route.gd: actual mouse/keyboard first loop and lower extension, mid-route disk restore, independent resource/identity/target readback. Fresh route test retains first-two completion, new test completes all four.
- [ ] Final: complete native/Python gates, actual software-GL captures, production staging and startup, review, source tree match, push once then no lengthy CI polling; Notion record evidence and actual limits.

Ledger:
- Source zip SHA256 matches previous evidence, reconstructed git tree matches upstream exactly.
- Baseline outer invocation was terminated at120s; no aggregate success claimed. Restarted with bounded independent verification process while reading/planning; will collect before code gates.
- Ruling: append same-map objectives rather than add separate scene/campaign runtime. Retains creations, water, rules, and saves and avoids resource-spawning transition.
- Ruling: diagnostics are ephemeral last-step evidence, not persistent gameplay state; dry run uses existing whole tick candidate execution.
- Baseline full result151/763 PASS collected before implementation.
- T1 RED missing APIs→34 PASS; T2 RED unsupported extended definition→24 PASS; T3 RED missing controls→19 PASS. Existing parsed-JSON fixture normalized back to integers before malformed-variant checks; no weakened world validator.
- Ruling: lower supply target moved to dry headroom (8,1), not floor (8,2). Tiny conserved water on the floor must not create a frustrating one-unit placement race; player excavates headroom and reuses same container without removing water by tolerance.

- T4 full native input route initially hit conserved shallow water during placement, not a missing rule feature. Reused the same lamp at (7,0); allowed gravity several ticks before placing reservoir at (8,1). Real route then passed57 (58 with first-output emission), total6000; no world validator weakened.
- Screenshot review found preview text clipped by the scroll area. New geometry assertion observed RED then GREEN; result now occupies existing validation area above buttons, not a new visual redesign.
- Added conflict and budget preview checks: diagnostic suite43. Current full check163 Python /908 native /11 outputs PASS. Clean-copy and package verification remains final gate.
- Review: no external subagent available; implementation review plus focused regressions, not an independent security or gameplay audit.
