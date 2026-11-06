# 织律 · Ruleweaver

2D 横向探索建造沙盒：玩家组合规则，创造物质与行为。

**当前为v0.11环境资源与遗迹多解流程的原生技术实现，尚不是带角色和界面的可玩版本。** 已在同一张湿暗遗迹地图上验证手工搬水、挖沟排水、自创规则泵三种解法；随后携灯进入遗迹，把收集的水带回营地。整个流程使用已有创作、绑定、搬运和存档接口。

## 本轮范围

真实网格水（整数守恒、重力和水平流动）＋规则取水/排水＋可保存昼夜时钟＋暂停/单步＋场景目标和恢复，成组接入唯一WorldSession。所有水在环境与容器间转移，不靠假容器冒充河流，也不为每个解法写专用成品行为。

原生三路线回放：

```sh
/path/to/godot --headless --path godot --script res://scenarios/demo_expedition.gd
```

这是无窗口自动验收，不是游戏启动入口。三条路线都完成遗迹到访与回营地交付500单位水，并保持初始6000单位总水量。旧规则创作、律卷交换、地图节点同步继续保留。细节见 `docs/ENVIRONMENT.md`。

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

角色仍是网格占位，不是平台跳跃/刚体物理；light_on和遮挡是逻辑条件，不是视觉照明。正式美术/织律台需先样板确认。完整快照事务仍有规模上限，没有无限地形、性能验收、main合并或Release。当前验证数量与限制见 `docs/STATUS.md`。

## 来源与许可

第三方工程源码见 `THIRD_PARTY_NOTICES.md`、`vendor_manifest.json` 和 `godot/vendor/coheronia/` 内的许可文件。不包含上游美术、音乐、剧情或其他保留版权内容。仓库新代码的整体发行许可尚未单独确定；第三方各自许可不变。
