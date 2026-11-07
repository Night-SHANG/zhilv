# 织律 · Ruleweaver

2D 横向探索建造沙盒：玩家组合规则，创造物质与行为。

**当前为v0.12原生操控接入：真实CharacterBody2D、按键、跳跃、碰撞、暂停及恢复已经与同一世界连通。尚无经过确认的正式画面/织律台，也不是已导出的可玩成品。**

## 本轮范围

基于仓库已验证的v0.11（bef633d），不是聊天里另一份未提交的实验附件。保留原有环境水、规则和三种网格解法；新增原生身体和非视觉PlaySession，不另建物理/库存真相。

已通过真实Godot输入事件与物理帧走通：积水阻挡 → 放置自创泵 → 自动抽水 → 途中存档并创建新会话恢复 → 携灯进入遗迹 → 返回营地交付500单位水。总水量始终6000。实时水流会改变可放置位置，测试使用水面上方的合法位置，不伪造完成状态。

```sh
/path/to/godot --headless --fixed-fps 60 --path godot --script res://tests/test_live_expedition.gd
```

此命令是自动验收，不是正式游戏启动入口。按键A/D或方向键移动、Space跳跃、Escape暂停，由PlaySession接收；正式交互画面仍须先确认视觉样板。机械契约、集成入口、恢复边界见 `docs/PLATFORM.md`；环境三解见 `docs/ENVIRONMENT.md`。

## 运行检查

Python 3.11+，标准库，无 pip 依赖：

```sh
python tools/run_checks.py --offline-only
```

完整检查（须提供 Godot 4.6.1 的实际路径）：

```sh
python tools/run_checks.py --godot /path/to/godot
```

Windows 示例：

```powershell
python tools/run_checks.py --godot "D:\Godot\Godot_v4.6.1-stable_win64_console.exe"
```

也可运行 `python tools/install_godot.py --destination .tools/godot` 下载固定官方版本；安装器在执行前核对归档 SHA256。

退出码：`0` 当前请求范围通过，`1` 失败，`2` 缺少/不匹配原生引擎。`--offline-only` 的成功不是原生 Godot 成功。CI 报告在 Actions 的 `offline-*`、`native-*` 工件中。

## 工程边界

`godot/runtime/` 是待验证的游戏数据层，不是第二套游戏引擎。`godot/vendor/` 是未修改的上游工程代码。`fixtures/` 保存实例/世界契约与规则验收数据；`tools/` 只承担开发验证和工具链安装，正式游戏不依赖 Python 服务。

实例状态目前覆盖容量、水量和灯光开关。规则系统为有限原语/行为模块，不支持任意宿主代码；材料/形态仍来自受信目录。时间以整数tick推进，暂停/关闭不离线补算。环境水为有界元胞模型，不是真实压力流体。

角色已使用原生平台运动与整数亚格身体占位；light_on和遮挡仍是逻辑条件，不是视觉照明。正式美术/织律台需先样板确认。完整快照事务仍有规模上限，没有无限地形、性能验收、main合并或Release。当前验证数量与限制见 `docs/STATUS.md`。

## 来源与许可

第三方工程源码见 `THIRD_PARTY_NOTICES.md`、`vendor_manifest.json` 和 `godot/vendor/coheronia/` 内的许可文件。不包含上游美术、音乐、剧情或其他保留版权内容。仓库新代码的整体发行许可尚未单独确定；第三方各自许可不变。
