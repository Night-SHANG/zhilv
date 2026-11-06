# 第一版受限规则图协议

这是一组可以从JSON组合的游戏能力，不是任意GDScript、Lua或在线AI代码。
可运行样例在fixtures/rules_pack.json；材质/可用规则版本目录在rules_catalog.json；世界状态在rules_world.json。

## 图与行为模块

包格式为rw.rules/0.1，包含modules数组。每个模块有id、version、parameters、nodes、effects。
每个节点有局部id、op、inputs（端口到源节点ID）、config。输入引用构成有向无环图，动作执行顺序由effects数组决定；保存时节点顺序不决定语义。
参数仅支持int/bool和默认值；call可以覆盖参数，遗漏时使用默认值。行为模块没有返回值，不允许递归。

| 原语 | 输入 | 结果/配置 |
|---|---|---|
| bool / int | 无 | config.value，布尔或有限范围整数 |
| param | 无 | config.name指向模块参数 |
| is_night | 无 | 宿主本步传入的布尔昼夜状态 |
| read_state | 无 | config.field为water_units/capacity_units/light_on |
| neighbor | 无 | config.material为空或已注册物质；返回相邻世界实例ID，未找到为空引用 |
| exists | value:ref | 是否有目标 |
| not / and | 布尔 | 布尔结果 |
| lt / add | a:int,b:int | 比较/有界加法 |
| set_light | when:bool,value:bool | 改变自身灯光开关状态 |
| move | when:bool | config.dx/dy必须正交一步 |
| take_water | when:bool,source:ref,amount:int | 从邻接容器精确转入自身；检查双方水量/容量 |
| call | when:bool及被调用模块参数 | config.id/version，调用行为子模块 |

所有节点都必须通过端口/类型/字段检查。执行器先判断动作when；false时不求值该动作的其他输入。
纯数据节点同一调用内只求值一次；不同模块调用可有不同参数和缓存。邻接查询固定按上、右、下、左排列。

## 例子及非配方边界

night_light由is_night、bool、set_light三个节点构成；absorb通过call调用带amount参数的transfer；drift由bool和move构成。
规则执行器不识别“夜光石”“吸水石”等造物名称。更换物质或规则数据不需要新增专用行为脚本。
但没有支持的原语不会被JSON自动创造出来。第一批实例共用reservoir状态契约，尚非所有物质/生命系统。

## 调度和原子性

宿主调用advance(night, per_instance_budget=512, total_budget=32768)。每个调用对应一个模拟步，不是墙上时钟。
首先用稳定世界快照生成全部计划，再按实例ID排序提交；同一实例规则按ID排序。同一实例整组动作全成功或全失败。
因此缺水可能同时阻止该实例其他动作；玩法层要设计条件或以后明确分组事务，不能靠隐式部分成功掩盖。
不同实例争抢资源会按稳定顺序仲裁；不会读取同一步其他实例刚提交的结果来重新决策。
背包实例不运行。动作不能操作文件/网络、删除任意对象、修改身份/容量或远程偷水；所有副作用走WorldSession。

## 限制与恢复

规则包最多256KiB、64模块；每模块64节点、8参数、16动作；调用深度8。每实例最多64条命令。
每实例指令预算1..4096，每步总预算1..65536；世界中带规则的活动实例最多256。预算是保护阈值，不是性能结论。
相同id+version的定义不能在运行时被静默替换；改动须使用新版本并显式绑定；v0.10允许经编译校验的user:规则自动加入动态版本目录。
完整存档rw.simulation/0.1包含tick、world、rules。沿用CheckpointFiles的原子替换和显式备份恢复。
保存后没有后台执行；宿主加载后继续推进。完整昼夜时间、信号/邻格事件队列、跨格式迁移、图形编辑器仍未实现；v0.10已实现非视觉草稿与发布服务。

## 验证与复用来源

使用Godot JSON读取数据，并沿用项目已有严格词法/类型闸门；Godot自身的JSON解析并不等于完整的输入安全校验。
文档参考：https://docs.godotengine.org/en/stable/classes/class_json.html
继续复用原有Coheronia库存、格坐标模块与本项目WorldSession/CheckpointFiles；没有另建物理引擎、库存或图形框架。

## v0.10 创作、版本与律卷

RuleDraft是非视觉编辑模型：start建立草稿；upsert_node增改节点；connect_input/disconnect_input调整连线；set_parameter、set_effects设置参数和动作顺序。remove_node拒绝删除仍被引用的源节点，删除动作同时移除其执行入口。草稿支持临时缺线，预览/发布才执行完整编译；失败不触碰活动世界。snapshot返回副本，restore用于已有规范化模块副本，不将任意对象视为JSON。

RuleRuntime.preview_pack(text, bindings)只返回校验摘要。publish_pack(text, bindings)合并新版本并可一次替换指定造物的全部绑定；最多64个绑定对象，任一访问/类型/依赖失败都不提交。bind_rules(id, refs)单独替换一个对象的绑定，空列表解绑，不清空状态。世界中的绑定仍受4格距离、遮挡限制；背包仅限当前角色所有。

rule_definition返回已发布图的副本；next_rule_version返回可用后继版本。只有user:可以动态增加ID/版本；原语、材料目录、状态能力不由用户包定义。已发布同ID+版本内容不可改，旧install_pack也不能先忘记未绑定旧版本再替换。完整load_checkpoint是显式世界恢复，可恢复旧时间点；它仅由初始受信目录加存档中验证通过的图重建版本目录，不保留被恢复掉的临时版本。

export_rule(id,version)返回纯JSON律卷rw.scroll/0.1：format、entry(id/version)、rules。只包含入口及其递归依赖，保持各版本准确固定。import_scroll要求自包含且不存在无关模块；先完整编译再合并，不改变任何造物绑定，也不执行动作。律卷不包含库存、地形、材料注册、文件路径或宿主脚本。依赖/同版本冲突应提示用户创建新版本/新ID，不自动改名或静默覆盖。

发布、绑定及读档先准备所有状态，规则库、目录、世界采用完成后才发reloaded；通知期间禁止运行时重入。仍是单机同步调用，无多线程/多人写入协议。

新版本仍用rw.simulation/0.1共同保存程序和世界；现有存档可继续读取。每库64个版本化模块的上限仍存在，未实现安全旧版本回收。RuleDraft另限制1024个数据值访问和10层嵌套；这不是最终内容数量承诺。

原生可复现流程：test_draft.gd从空图经编辑操作创建夜灯、复制日灯新版本，再构造可参数化子模块及调用者；导出闭包、磁盘恢复后继续运行。test_authoring.gd另验证另一世界导入、显式绑定、拒绝非法包与访问、失败原子性。Python只核对固定预期工件，不复制第二套规则运行器。

## v0.11 环境原语与计时补充

环境水不是造物实例，使用独立类型`cell_ref`：`neighbor_water`→`water_exists`/`water_units`→`take_environment_water`；`release_environment_water`按固定相邻方向排水。`sub/min`用于通用容量限量；`is_ambient_dark`判断天光/顶上遮挡。它们复用原图编译、预算、版本不可变及律卷机制，不是新的配方运行时。

设置时钟后用`advance_tick`，不再用外部布尔`advance`绕过昼夜；simulation0.2保存clock，0.1仍兼容无时钟历史档。每tick规则先读取同一快照、按稳定ID提交到暂存世界，再流动水；全局失败不推进tick。`clock_state.night`对应最后完成的步，而不是下一步相位。完整契约与非目标见`ENVIRONMENT.md`。
