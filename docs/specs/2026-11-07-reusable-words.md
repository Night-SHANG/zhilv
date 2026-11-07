# v0.16 玩家词条封装与参数化复用

## 用户目标与范围
沿用Godot4.6.1、2D和当前界面。不新增引擎/平台，不增加第三方权限。把“玩家创造的行为能成为新词条”从数据接口接到现有织律台，支持公开常量参数、命名发布、追加调用、默认值/覆盖、再封装、导出和恢复。

## 采用方案
复用已有RuleDraft.set_parameter、Compiler.param/call和Runtime.publish_pack/export_rule；Godot GraphEdit/GraphNode负责交互，没有新解释器。官方4.6文档表明GraphEdit只发出连接请求，由现有RuleDraft负责语义。无需接入另一套可视化脚本插件。

1. 常量int/bool可在原节点编辑中公开为命名参数；保留节点ID和所有连线。默认值和类型与现有编译器一致；显式还原时所有同名param回到常量。
2. 整个有效草稿以user:ID发布为新版本。发布到库不应用给造物，不替换草稿，不推进模拟。库就是存档中的已有规则集合，不建立平行数据源。
3. 已发布词条可追加为call与执行条件节点。默认参数自动生成独立常量输入，能在原节点图修改或换成其他计算结果。调用锁定具体版本；发布新版本不自动升级原调用。
4. 整个组合可再次封装为词条；使用现有DAG、深度、节点和指令预算。动作函数仍不返回任意值，不宣称完整编程语言或无限能力。
5. 保存恢复、律卷依赖闭包和不自动绑定仍由原服务执行；未发布参数草稿沿用rw.workspace/0.1，无协议升级。
6. UI只在已有高级编辑栏/右侧滚动区增加功能入口，沿用已有样式，不改整体美术，不称最终视觉验收。

## 接口与失败边界
LoomDocument.expose_constant(node_id,name)、set_parameter_default(name,value)、internalize_parameter(name)、publish_word(runtime,id)、append_word(runtime,id,version)、change_call_target(runtime,node_id,id,version)。全部草稿操作要可一次撤销；参数同名冲突、保留名when、非法值、预算失败不改变图/历史/世界。命名只支持现有ASCII ID，界面明确示例，不增加未维护的中文名数据库。

## 验收
从泵图公开rate，保存为user:water_pump；从发光图保存user:dark_lamp；空白图追加两者，设置不同调用参数，再封装为user:smart_carrier。两个实体复用同一底层词条但使用不同数量；第三层组合可导出到无规则新世界，保存重载后运行不改身份/资源。参数化草稿缺线仍可保存但不能发布。真实按钮、参数编辑、小窗、调用端口和依赖闭包要测试。

## 不在本批
生态系统、新地图、美术重做、任意返回值、模块删除、节点位置持久化与大型性能优化。
