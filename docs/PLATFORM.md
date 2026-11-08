# 原生操控集成契约 · v0.12

## 唯一世界与角色

`WorldCodec`接受rw.world/0.3：actor增加body_foot整数数组，1024单位/格。actor.cell由脚点向下取整派生；负坐标不可截断向零。宽640、高1792的全身体用于占位，不仅判断脚点或头部两格。旧world0.1/0.2不强制迁移；PlaySession显式启用body后升级。

`PlatformMotor`继承CharacterBody2D，用move_and_slide求解运动，16px/格，碰撞盒10×28px，速度96px/s、重力900px/s²、跳速260px/s、最大落速384px/s。每个物理帧结果经WorldSession.move_actor_body提交；原生与游戏权限冲突时还原位置/速度。最多移动一格/轴，额外64单位有界扫掠，防止只查终点穿墙。大型逻辑坐标映射到装载窗口局部坐标。

`PlaySession.bind_session(expedition, world, window)`必须绑定同一权威世界，在树内调用。自动创建隐藏的TileMapLayer碰撞投影和无精灵原生角色；这不是视觉样板。`start()`开启自动物理与输入，或测试在真实physics_frame里调用step_frame。重复同帧推进被忽略。

## 输入和操作

A/D、左右键移动，Space跳跃，Escape暂停。只处理未被上层UI消费的输入；set_controls_enabled(false)清空按键并阻止世界操作，供未来织律台使用。失焦自动暂停，恢复不沿用按住键，不追赶离线时间。单步只推进暂停中的水/规则，不移动冻结的角色。

`command`只转发mine/build/pickup/place/collect/release/pour到已有ExpeditionSession，仍检查距离/遮挡/资源。禁止move或任意坐标注入绕过原生角色。用户规则不能访问这些宿主对象。

## 检查点

rw.play/0.1 = 完整rw.expedition/0.1 + motion.velocity_x/y（1/64px/s整数）。所有嵌套世界、规则、目标和运动范围先校验，失败不改变正在运行的状态。成功时准备速度、采用世界并同步身体，再通知上层。中间通知的检查点读取不会将新世界和旧速度混存。恢复空中状态后，旧is_on_floor缓存不能授权跳跃，必须重新查询脚下支撑。

输入不保存；小于一个模拟tick的驱动器余量在恢复/暂停时清空，因此不承诺亚帧续演完全一致。保存可在空中完成，保留合法身体位置与速度；固定窗口外存档拒绝加载，不把人传送到已装载场景之外。

`dispose()`断开世界订阅、释放独立驱动器及子节点。正常退出树也会执行清理；已释放后重复dispose安全。调用方可持有WorldSession继续保存或重新绑定新PlaySession。

## 验证入口与限制

```sh
python tools/run_checks.py --godot /path/to/Godot_v4.6.1-stable_linux.x86_64
```

新增原生测试使用真实SceneTree物理帧/CharacterBody2D/TileMapLayer/InputMap；--fixed-fps60只加速无窗口回放，不换成Python物理模拟。tools/check_play_evidence.py只独立验证存档契约和预期结果，不复制引擎或通用规则编译器。

正式画面尚未实现。规则/水固定tick与角色帧的提交分开，成功角色移动不随后续失败的环境tick回滚。当前不会自动游泳或模拟压力流体。固定窗口、全快照写入、活动扫描未做大型负载验收。权威整数脚点便于读档，不保证浮点物理跨平台逐帧等同。

## 参考与复用

Godot官方CharacterBody2D / TileMapLayer原生接口；项目既有TerrainProjection、SimulationDriver、ExpeditionSession与CheckpointFiles。未引入新第三方插件或上游保留版权素材。复用文件许可及哈希保持不变。
