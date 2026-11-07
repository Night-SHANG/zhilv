# 原生平台操控 Implementation Plan

> Execution: superpowers:executing-plans，原生执行；用户已授权自主完成整批。

**Goal:** 在现有世界中接通真实物理角色、输入、交互、暂停及完整恢复。
**Architecture:** 引擎求解运动，WorldSession保存唯一身体占位；PlaySession协调既有探索/模拟与原生节点。
**Tech Stack:** 锁定Godot4.6.1、GDScript、Python标准库检查。
**Spec:** docs/specs/2026-11-07-platform-session.md

## Global Constraints
- 不覆盖远端更晚v0.11；第三方4文件哈希不变。
- 不制作正式视觉；不合并main、不发布Release。
- 0.1/0.2旧存档和旧测试保留；新增协议独立验证。
- 每批真实失败→修复→全量回归；不将headless验收当手感验收。

## Review Focus
- 身体横跨两列/负坐标/规则移动时不能漏判。
- 地形变化后真实碰撞与权威占位一致。
- 暂停/失焦/恢复不能卡键或补算时间。
- 物理状态/世界/规则存档必须全量验证后恢复。
- 引擎对象生命周期和重入不能导致半提交或泄漏。

## Tasks
- [x] T1: tests/test_actor_body.gd与tests/test_actor_contract.py先失败；world_codec/world_session增加亚格身体及旧档兼容，独立Python验证通过。
- [x] T2: tests/test_platform.gd先缺失失败；新增platform_motor.gd及play_session.gd，复用原生碰撞层，测试真实物理帧和输入。
- [x] T3: 输入/交互/暂停/磁盘往返/异常回归；原生工件独立回读；接入native_gate并全部重跑。
- [ ] T4: diff复查、固定基线来源、统一推送，保留草稿；核对快速CI及工件，更新Notion与源码证据。

## Execution ledger
- 基线：112 Python、478 Godot断言通过；实际重跑已记录。
- 决策：机械操控不做视觉素材/界面，视觉样板门槛仍保留。

- 原生操控路线发现实时扩散使旧干格变湿，保留占位拒绝并使用水面上方位置，没有修改原语或场景绕过。
- 复查补充：同帧推进、空中恢复旧接地缓存、编辑门控、退出游离驱动器、通知时运动/世界一致性；观察失败后修复。
- 最终本地129 Python/578原生与8类产物回读通过，编辑器导入无脚本错误。T4远程结果见PR/Notion，不为更新绿灯文字再改已验证代码。
