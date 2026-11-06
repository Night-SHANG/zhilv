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
相同id+version的定义不能在运行时被静默替换；改动须使用新版本并更新受信目录及绑定。
完整存档rw.simulation/0.1包含tick、world、rules。沿用CheckpointFiles的原子替换和显式备份恢复。
保存后没有后台执行；宿主加载后继续推进。完整昼夜时间、信号/邻格事件队列、跨版本迁移、动态编辑器仍未实现。

## 验证与复用来源

使用Godot JSON读取数据，并沿用项目已有严格词法/类型闸门；Godot自身的JSON解析并不等于完整的输入安全校验。
文档参考：https://docs.godotengine.org/en/stable/classes/class_json.html
继续复用原有Coheronia库存、格坐标模块与本项目WorldSession/CheckpointFiles；没有另建物理引擎、库存或图形框架。
