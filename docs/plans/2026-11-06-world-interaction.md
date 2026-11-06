# 统一世界交互与原生投影 Implementation Plan

> 执行方式：executing-plans；按用户授权直接执行，不逐项等待确认。

**Goal:** 在已有实例账本之上完成地形/角色占位、受限挖掘放置、造物搬运和同一检查点恢复，并接入真正 TileMapLayer 投影。
**Architecture:** WorldSession 组合现有 InstanceStore，普通库存仍委托上游 InventoryData。WorldCodec 包装原实例协议，不暗改旧格式；所有命令先完整验证后提交，返回变更坐标供投影同步。
**Tech Stack:** Godot 4.6.1 GDScript；Python 3.11 独立协议检查；沿用已固定的跨平台 CI。
**Spec:** Notion 04 产品基线、05 v0.7 接入原则；README 和本文的明确范围。

## Global Constraints
- 原开发分支上继续；不合并 main、不发布游戏、不带入保留版权素材。
- 本轮是原生世界技术切片，不是角色控制器、图形游戏、规则编辑器或完整生态。
- 地形用稀疏格坐标；最多 16384 个静态实心格，全部范围 ±1000000；未实现流式大世界。
- 单机一个角色：foot 与 foot+(0,-1) 两格占位；交互距离平方<=16；线段遮挡使用保守超覆盖，不能穿过拐角墙。
- 快照 rw.world/0.1 包含原 rw.instances/0.1 快照、terrain、actor；原协议不自动迁移。
- 未加载、无权、超距、遮挡、占位、非法输入都拒绝且不改变旧状态；失败无 committed 信号。
- 存档继续复用 CheckpointFiles；地形、角色、普通材料和有状态造物一起保存。
- 项目原生验证以真实 Godot 为准；本地 DNS 受限，Python 检查不能冒充原生测试。

## Review Focus
- 载入重叠/畸形坐标时是否保留整个旧状态。
- 不同归属、背包操作与世界物体能否被远距离或隔墙访问。
- 地形和库存交易是否重复扣费、重复获得或部分成功。
- 世界恢复后显示层是否仍引用旧世界；不将 TileMapLayer 当存档权威。
- 测试漏跑、缺少新输出或旧报告是否会导致 CI 假绿。

## Task 1: 世界数据契约（独立校验）
Files: fixtures/world_checkpoint.json, tools/check_world.py, tests/test_world_contract.py, godot/runtime/world_codec.gd.
Interface: validate_world(text: str, catalog: dict)->dict；WorldCodec.decode(text:String,catalog:Dictionary)->Dictionary。
- [x] 先写非法版本/重复地形/角色穿墙/实例穿墙/未知材料/未知归属/负坐标等测试，观察本地失败。
- [x] 实现严格外层协议，复用已有实例校验；运行完整 Python 套件。

## Task 2: 原生交互事务
Files: godot/runtime/world_session.gd, godot/tests/test_world.gd.
Interface: load_checkpoint, validate_checkpoint, checkpoint_json, material_at, get_instance, stack_count, actor_cell;
mine(cell), build(material_id,cell), pickup(id), place(id,cell), step_actor(delta), pour_water(source,target,amount)。所有结果含 ok/error；成功 emitted committed(cells:Array)。
- [x] 测试先入库；stub 拒绝 load，原生 CI 应有明确失败断言，而非漏跑。
- [x] 实现通用命令、距离/占位/遮挡，复用 InstanceStore 和 CheckpointFiles。
- [x] 保留状态和规则版本的拾取→磁盘保存→重载→放置闭环；事务失败前后快照完全相同。

## Task 3: TileMapLayer 接入与证据
Files: godot/runtime/terrain_projection.gd, godot/tests/test_projection.gd, tools/native_gate.py.
Interface: projection.bind_world(world,layer,sources,window:Rect2i)->Dictionary；projection.rebuild()->Dictionary；dispose()。
- [x] 用中性程序图块在 headless 环境构建原生 TileSet，不制作正式美术/UI。
- [x] 验证成功修改投影、失败不改、重载同步、缺失映射拒绝、远坐标不被静默环绕。
- [x] 新原生输出通过独立 Python world 协议回读；任何原生失败阻断 PASS。

## Task 4: 审查与提交
- [x] 离线67项、上游哈希、diff与静态审查；4adff9d原生110项通过。满库存回归修复的最终CI另行核验。
- [x] 更新 README/STATUS/Notion，清楚区分已通过的旧提交和待确认的新提交。
- [x] 原分支提交、更新草稿PR、触发跨平台CI；不重复无意义轮询、不声称游戏完成。

## 执行记录
- 基线：远端6d15b0a的Windows/Linux原生任务已成功；Linux日志含8个上游断言、38个生命周期断言。
- 本地从已交付ZIP恢复，git根树与远端3e3a4b24d4c83cc939f4fcbe766799b12a78a0ff一致；49项Python基线通过。
- 本地网络DNS仍不可用，原生新代码运行需要GitHub CI，不把静态审查写成执行结果。

- 世界与投影通过后的复查增加满库存种类回归，CI已复现失败；最小修复是验证成功后才访问snapshot。原生最终状态必须与最后提交绑定。
- 计划中主要实现已完成；没有把规则执行、角色平台物理、无限地图或美术验收标记为完成。
