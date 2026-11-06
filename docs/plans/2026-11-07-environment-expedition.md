# 环境资源与湿暗遗迹完整流程 Implementation Plan

> 执行方式：superpowers:executing-plans；用户已明确授权整组自主完成，不逐项请求确认。

**Goal:** 在原有正式工程内，一次接通真实网格水、规则取水/排水、固定昼夜、暂停单步、探索目标、搬运回用和中途存档恢复，并用三种解法验证同一遗迹。
**Architecture:** WorldSession仍是唯一世界权威；新水层是同一世界的整数账本，不伪装成预置容器。规则复用现有编译器与创作后端；有时钟的整步在隔离候选状态计算后一次提交。场景只定义世界与结果目标，不检查特定配方。
**Tech Stack:** 锁定Godot 4.6.1/GDScript；Python独立工件校验；现有Coheronia库存与坐标模块保持未修改。
**Spec:** Notion 04当前2D探索创造方向、05 v0.10交接、docs/RULES.md。

## 决策与非目标
- 自主选择将环境数据升级为rw.world/0.2（water层）；显式兼容0.1，不静默清除新字段。
- 复核固定上游Coheronia fluid_sim.gd：直接修改原世界、浮点微水删除和预设反应不适合统一整数事务。保留其局部元胞/固定步思路，编写小型无副作用整数求解器；不再建一套游戏引擎。
- 官方Godot 4.6固定物理步文档与JSON文档复核；模拟使用整数tick，不依赖系统时钟，暂停/关闭不补算。
- 当前视觉尚未确认，本批不擅自制作正式UI、美术或宣称可玩性已过。提供可执行整段场景验收而非更多孤立接口。
- 不实现流体压力、气体、生态进化、无限地图、网络多人、跳跃角色或插件平台。

## Global Constraints
所有水为整数；格容量1000；活跃水格4096上限；输入水必须在边界内且不与固体重叠；不得删掉1单位余水。新手场景深水阈值200；普通挖掘/手工搬水/规则泵均是有效解法。每个变更失败不得改变旧世界/目录/规则/时钟/进度。既有358项原生和91项Python继续通过。

## Review Focus
1. 规则与流体同一tick争用水时仍守恒，失败与预算耗尽不能部分推进。
2. 建造/移动不得把已有水覆盖掉；世界边界和水格预算不得吞水。
3. 非法0.2存档、旧0.1恢复、暂停恢复、相位边界处理一致。
4. 场景结果不能依赖规则名；不写专用“遗迹泵”脚本冒充组合。
5. 观察者只能看到一致的水/世界/tick；退出无引用循环，读取返回副本。

## Task 1 — 水层与完整守恒路径
Files: water_flow.gd、world_codec.gd、world_session.gd、instance_store.gd、test_water.gd、check_world.py。
Interfaces: step(water,blockers,max_cells,operation_budget)->result；collect_water/release_water/advance_water；water_at/total_water_units。
- [x] 先写缺失接口、水重力/横流、1单位余量、阻挡、边界、预算、错误输入测试并观察RED。
- [x] 实现世界0.2读写、纯整数水求解与手工资源转移；新旧协议并存。
- [x] 运行旧完整套件与新增水测试，保留证据。

## Task 2 — 规则、时钟和实际驱动节点
Files: rule_compiler/evaluator/runtime、simulation_driver.gd、test_environment.gd。
Interfaces: neighbor_water(cell_ref)、water_units、water_exists、take_environment_water、release_environment_water、is_ambient_dark、sub/min；configure_clock/set_paused/advance_tick/single_step；driver.process_delta。
- [x] 新规则接口、暂停/单步/保存、失败整步回滚及隔墙照明测试先RED。
- [x] 实现原语并复用现有草稿/发布/绑定；clock显式保存为simulation0.2。
- [x] 固定步驱动有界追帧；同输入和不同字典顺序结果一致；运行完整套件。

## Task 3 — 同一湿暗遗迹三条完整路径
Files: content/wet_ruins.json、expedition_session.gd、test_expedition.gd、demo_expedition.gd。
Interfaces: load/observe/status/checkpoint；同一world/runtime，不新增物品账本。
- [x] 编写手工搬水、挖排水沟、从空白编辑自动泵的端到端用例；目标只检查位置、照明、交水。
- [x] 加入有限内容地图、可保存里程碑；返回营地交水继续利用资源。
- [x] 证明中途保存恢复与不中断运行一致、依赖律卷跨世界仍可使用，输出真实状态证据。

## Task 4 — 合同、审查和仓库交付
Files: tests/test_environment_evidence.py、tools/check_environment_evidence.py、native_gate.py、README/STATUS/RULES。
- [x] 独立Python读取原生水/时钟/场景输出，畸形协议与质量门本身先RED后GREEN。
- [x] 完整原生、Python、来源哈希、差异与边界复查；没有审查子代理，不冒称独立审计。
- [ ] 同组提交开发分支，触发固定版本跨平台Preflight；长CI不持续轮询；更新既有Notion，保持PR草稿。

## 本地审查结果

旧基线91/358与新增批次完整通过，现112项Python/478项原生。无独立子代理；实现者复查发现并通过原生RED/GREEN修复跨世界误绑定、旧档清除时钟后驱动器抛错和昼夜显示相位提前。32种固定种子×30步的容量/守恒/排序不变性通过。源协议和回放说明见docs/ENVIRONMENT.md。原生长期维护仍有有界扫描、全快照成本和视觉未验收限制。
