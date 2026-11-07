# 规则创作、显式绑定与律卷交换 Implementation Plan

> For agentic workers: use superpowers:executing-plans. 用户已授权继续当前路线，不重复要求技术选择。

**Goal:** 在已有原生世界上完成新建规则→校验→发布不可变版本→绑定→执行→导出依赖闭包→另一世界导入→保存重载。
**Architecture:** 一个纯数据RuleLibrary薄层复用现有RuleCompiler；RuleRuntime协调规则目录和WorldSession原子更换；RuleDraft只保存未发布草稿，不直接改活动世界。
**Tech Stack:** 固定Godot4.6.1/GDScript、现有Python验证器，第三方源码不改。
**Spec:** docs/RULES.md、Notion04/05现有产品方向；本文件补充下列明确合同。

## 设计合同与边界

- 新规则只开放user:命名空间；已有受信目录中的其他ID可以按既有授权校验。材料、状态容量、原语能力不由导入包授予。
- 同ID+版本不能换内容；新版本并存，只有明确选中的造物更改绑定。解绑不重置水量/灯光等现存状态。
- publish_pack(text, bindings={})将包与最多64个造物的完整新绑定一起校验；任何失败不修改规则库、世界、步数，不发成功事件。
- 绑定必须通过既有距离、遮挡、归属规则。导入本身不绑定、不执行。运行回调内禁止重入发布/绑定/恢复。
- 发布与恢复先准备全部状态，再一起采用，最后通知订阅者；订阅者看到的是同一份新世界和规则库。
- 律卷rw.scroll/0.1只有format、entry(id/version)、rules；包含入口所需的准确传递依赖，禁止额外无关模块，不携带世界、库存、材料权限或脚本。
- 导入仍走原始JSON词法检查和原有编译器；256KiB/64模块等预算继续有效。完整存档沿用rw.simulation/0.1，加载时从已验证user规则恢复版本目录。
- 草稿允许临时不完整连线；发布前必须完整编译。节点编辑、连接/断开、参数和动作列表都不触碰运行中的版本。
- 不实现正式UI/美术、不扩展物理/流体，不合并main、不发布Release。

## Review Focus

版本冲突与依赖缺失；一次批量绑定中后项非法；返回数据引用污染；重入时半更新；新版本在全新运行时保存恢复。各项纳入原生断言。

## 任务

### 1. 版本库、原子发布/绑定、律卷
- [x] 先写godot/tests/test_authoring.gd，在缺失publish_pack时实际失败，旧套件保持通过。
- [x] 新建runtime/rule_library.gd；修改rule_runtime.gd、world_session.gd，复用编译器及存档校验，不复制运行器。
- [x] 验证新模块动态注册、明确绑定、旧版本不变、正确依赖导出导入、敌意JSON、访问拒绝和回调一致性。

### 2. 编辑草稿
- [x] 先写test_draft.gd，缺失RuleDraft时实际失败。
- [x] 新建rule_draft.gd：start/restore/upsert_node/connect_input/disconnect_input/remove_node/set_parameter/set_effects/pack_json。
- [x] 用这些操作从零建立夜间发光规则，发布绑定执行；修改新版本验证旧对象不被改动。

### 3. 一次完整使用流程和质量门
- [x] 测试从零创作、复用模块、交换、磁盘重载后继续；产出原生证据。
- [x] 运行完整Python和原生套件，复查diff和许可哈希；更新README/RULES/STATUS。
- [ ] 同一开发分支提交，更新PR与Notion；触发CI后及时汇报，不持续轮询大型构建。

## 执行记录

基线：附件source根树4edf13648ee1f0adf63c0de9c819498acfe92ab7与远端da6bd0b完全相同；独立临时目录、非main分支。官方引擎归档SHA256核对通过。重新运行80项Python及223项原生断言全通过。

本地完成：91项Python、358项原生断言（新增authoring71、draft64）全部通过；实例/世界/旧规则/新创作四份原生存档独立回读通过。新增规则入口与草稿先观察功能缺失失败；11项Python证据测试先观察9项断言失败再通过。

审查修复并保留RED日志：草稿总值遍历预算1024；恢复草稿前检查ID类型；完整读档仅以初始受信目录重建动态版本，防止旧会话记录泄漏；旧install_pack也禁止先删除已发布版本再换内容。每项修复后完整套件重新通过。

本环境无独立审查代理；本轮为实现者复查与自动测试，非独立安全审计。未实现UI，未改变视觉方案或合并main。远程结果以提交对应CI为准。
