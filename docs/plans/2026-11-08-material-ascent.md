# Material ascent implementation plan

**Goal:** Finish interrupted v0.17 in the existing game, proving water-backed terrain and two real exploration routes.
**Architecture:** Existing authoritative WorldSession transactions, typed rules and native collision projection; no new interpreter.
**Spec:** docs/specs/2026-11-08-material-ascent.md
**Tech Stack:** pinned Godot4.6.1/GDScript/Python stdlib.

- [ ] Recover and verify baseline; tests RED for formation/rollback and new route.
- [ ] Integrate catalog, transaction, evaluator and existing UI; tests GREEN.
- [ ] Complete fifth goal, old actual workspace compatibility and stone alternative; real keyboard/mouse routes.
- [ ] Add independent accounting/route validators and malformed-data regressions.
- [ ] Full checks, staged startup, screenshots, exact source-tree verification and grouped push.
- [ ] Record actual CI/package status and Notion; do not claim unseen remote results.

Review focus: one-unit water not deleted; no actor entombing; recover capacity failure leaves block; actions see staged terrain; old snapshots do not mint new material; tests must not inject final state for play routes.

Ledger: isolated disposable checkout; extracted source tree exactly matches last committed tree. No independent review agent available; explicit implementer review plus automated tests. Current runtime directory lacks previous uncommitted local sources; reconstruction from preserved change intent is not original file recovery. Uploaded partial tree will only be used as base if byte hashes match our verified files.

完成记录：基线源树一致；新增形成测试先1通过1失败，新目标路线先56通过1失败，独立检查器先失败后通过。当前191 Python/1273原生/15输出全部PASS。软件GL完整路线截图检查、编辑器导入和Linux开发包暂存启动通过。原runtime/presentation与上轮远端未引用树完全一致。
裁决：不复用无法恢复的本地未提交文件；恢复生产改动后重新建立验证。独立检查石块路线时选中物是灯而非容器，明确修正预期并增加拒绝错误选择的测试。旧四目标测试不能自动宣称未来第五目标完成，保留明确前缀。
分支推送前执行干净源码全量复验与根树核对。远程状态、产物哈希由PR/Notion追加，不为写入“成功”再触发一轮相同CI。
