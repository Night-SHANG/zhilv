# 织律原生实例生命周期与仓库接入计划

> 执行方式：在独立工作目录与 `dev/native-instance-lifecycle` 分支执行。用户已授权自主推进；不合并主线、不发布。

**Goal:** 将 v0.6 验证包落入仓库，增加 Godot 原生实例拾取、放置、整数水量转移与同一检查点保存/恢复，并用 CI 解除本地引擎缺失阻塞。
**Architecture:** 保留两份上游工程源码原样；原生实例表是唯一位置/状态权威，普通堆叠委托上游 InventoryData。校验、状态提交和文件持久化分离；拒绝输入时不修改已有世界。
**Tech Stack:** Godot 4.6.1 标准版基线，GDScript，Python 3.11 标准库，GitHub Actions Linux/Windows。
**Spec:** 当前 Notion 04 产品方向、05 v0.6 接入契约；`fixtures/checkpoint.json` 和 `tools/check_snapshot.py` 是本轮 wire-schema 基线。

## Global Constraints
- 上游提交固定为 `3f4dbdd7a268f232a49407db5160111a090ea964`，四份 vendor 文件哈希保持不变。
- 不携带第三方素材/剧情，不新增正式 UI，不将本技术切片称为游戏。
- 1MiB 文本、16 层深度、4096 实例、单量上限 1,000,000,000；只接受整数数量。
- 未运行的原生检查标记 BLOCKED；Python 校验不代替 Godot。
- 默认测试只写 Godot 独立 user 目录中的测试槽位，禁止任意路径。
- CI 运行后汇报入口，不持续轮询；不修改仓库权限或删除工件。

## Review Focus
1. 同种材料的两个实例不得堆叠或互相覆盖。
2. 占位、错误所有者、非法数量和缺失规则均保持旧状态。
3. JSON 重复键、布尔冒充整数、坐标越界、未知字段及超限输入拒绝。
4. 保存中断、损坏主文件、有效备份和无文件分别反馈，不静默重置。
5. 原生失败日志、缺少完成标记、错误引擎版本和缺引擎都不能误报通过。

## Task 1: 仓库与验证基线
- [x] 读取空仓库与写权限；main 仅初始化 README，创建独立开发分支。
- [x] 在隔离目录解包 v0.6，运行已有 37 项测试。
- [x] 保留上游原文、许可和来源清单，排除历史生成日志/缓存。

## Task 2: 原生生命周期
Files: `godot/runtime/snapshot_codec.gd`, `instance_store.gd`, `checkpoint_files.gd`, `godot/tests/test_lifecycle.gd`。
Interfaces: `SnapshotCodec.decode(text,catalog)->Dictionary`; `InstanceStore.load_checkpoint(text)`, `checkpoint_json()`, `get_instance(id)`, `pickup(id,owner)`, `place(id,owner,cell)`, `transfer_water(source,target,amount)`, `change_stack(id,delta)`；所有操作返回 `{ok,error}`，读取结果深拷贝。
- [x] 先写原生正反例；本地执行受阻应如实记录，不伪造 RED/GREEN。
- [x] 实现受限 schema、原子内存操作和检查点恢复；不接入规则执行/地形渲染。
- [ ] 确认原生脚本与完整 fixture 一致，将实际执行交给 CI。

## Task 3: 可复现质量门
Files: `tools/native_gate.py`, `tools/install_godot.py`, `toolchain.lock.json`, `.github/workflows/preflight.yml`。
- [x] 先写并运行 Python 门禁负例，再实现结果解析与工具链完整性校验。
- [x] CI 配置先离线检查，后 Linux/Windows Godot 原生测试；官方版本与压缩包 SHA256 固定。
- [ ] 提交、建立草稿 PR、确认触发入口；更新 Notion 已验证/未验证状态。

## Ruling
本地无法解析 GitHub DNS，下载 Godot 失败；不再反复尝试同一路径。原生代码允许提交开发分支进行自动验证，未经原生通过不合并、不发布。此规则不把缺环境改称测试通过。

## 本轮本地复核
2026-11-06 21:44 北京时间（UTC+08:00）：49项Python检查通过、四份vendor哈希一致；原生执行缺环境为BLOCKED，尚待远程CI。没有图形或真实玩法验收。
