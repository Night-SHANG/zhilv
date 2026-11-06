# 织律 · Ruleweaver

2D 横向探索建造沙盒：玩家组合规则，创造物质与行为。

**当前是 v0.10 规则创作与律卷交换技术实现，不是可玩游戏。** 已实现空白草稿编辑、校验、不可变版本发布、显式绑定、依赖闭包导出/导入及保存恢复。此前有界世界、库存搬运、规则运行和地图同步继续保留。无正式美术、平台角色与拖拽织律台。

## 本轮范围

RuleDraft负责编辑模型，RuleLibrary负责版本/交换，RuleRuntime负责发布、绑定、执行和存档，WorldSession保持唯一世界状态。没有引入第二套引擎、库存或在线AI依赖。

新规则只通过已有受限指令组合。新版本与旧版本并存，不自动修改其他造物；发布与批量绑定全成功才采用。律卷只含入口及必要依赖，导入不执行、不绑定，也不能注册材料权限或运行宿主脚本。已有Coheronia两份工程源码及许可保持原样。

本地完整检查：91项Python，358项Godot原生断言及四份原生存档独立回读通过。当前提交的跨平台结论以对应Actions为准。见docs/STATUS.md及docs/RULES.md。

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

实例状态目前覆盖容量、水量和灯光开关。**受限规则图已执行**，但只有已列出的原语；子模块封装的是行为序列，不是支持任意返回值的通用函数语言。昼夜由宿主逐步传入，未实现完整时间系统、邻格事件队列或自然流体。正式接入点使用 `WorldSession`，而不是绕过它直接调用底层实例服务。已编写网格占位、四格交互距离和保守遮挡检查；角色步进不是完整的平台跳跃/刚体物理。当前完整快照事务适合有界技术验证，尚未进行大地图增量事务与性能验收。水量转移仍是容器账本，不是流体模拟。文件恢复必须显式启用，损坏主文件不自动覆盖。详见 `docs/STATUS.md`、`docs/RULES.md` 和 `docs/plans/2026-11-07-rule-authoring.md`。

## 来源与许可

第三方工程源码见 `THIRD_PARTY_NOTICES.md`、`vendor_manifest.json` 和 `godot/vendor/coheronia/` 内的许可文件。不包含上游美术、音乐、剧情或其他保留版权内容。仓库新代码的整体发行许可尚未单独确定；第三方各自许可不变。
