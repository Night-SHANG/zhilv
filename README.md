# 织律 · Ruleweaver

2D 横向探索建造沙盒：玩家组合规则，创造物质与行为。

**当前是 v0.8 世界交互与 TileMapLayer 接入技术切片，不是可玩游戏。** 原生测试操作真实地图节点，但没有正式美术、可玩角色控制器、织律台或完整规则图。实际通过状态以该提交对应的 CI 原生报告为准。

## 本轮范围

- 复用 Coheronia 的两份 MIT 工程源码，保持上游内容及哈希不变。
- 普通材料使用计数库存；有状态造物拥有唯一实例 ID、程序版本和单一位置。
- 在实例层之上增加统一世界命令：挖掘、建造、拾取、放置、受限网格步进、倒水。
- 静态地形、两格角色占位、距离/遮挡检查，与实例和普通库存共同提交及保存。
- 原生 TileMapLayer 订阅成功变更与世界重载；用窗口内局部坐标显示远处逻辑格。
- 非法输入或冲突不得修改已有状态；返回数据是副本。
- Windows 与 Linux CI 使用官方 Godot 4.6.1 固定校验版本，不代表要求更改玩家本地引擎版本。

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

`godot/runtime/` 是待验证的游戏数据层，不是第二套游戏引擎。`godot/vendor/` 是未修改的上游工程代码。`fixtures/` 保存 v0.6 检查点契约；`tools/` 只承担开发验证和工具链安装，正式游戏不依赖 Python 服务。

实例模块目前只覆盖储水造物状态。规则引用会被保存，但**规则图尚不执行**。正式接入点使用 `WorldSession`，而不是绕过它直接调用底层实例服务。已编写网格占位、四格交互距离和保守遮挡检查；角色步进不是完整的平台跳跃/刚体物理。当前完整快照事务适合有界技术验证，尚未进行大地图增量事务与性能验收。水量转移仍是容器账本，不是流体模拟。文件恢复必须显式启用，损坏主文件不自动覆盖。详见 `docs/STATUS.md` 和 `docs/plans/2026-11-06-world-interaction.md`。

## 来源与许可

第三方工程源码见 `THIRD_PARTY_NOTICES.md`、`vendor_manifest.json` 和 `godot/vendor/coheronia/` 内的许可文件。不包含上游美术、音乐、剧情或其他保留版权内容。仓库新代码的整体发行许可尚未单独确定；第三方各自许可不变。
