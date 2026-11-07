"""独立检查原生角色存档与实时探索产物；不模拟物理或重新编译玩家程序。"""
from __future__ import annotations
import copy
import json
from check_snapshot import exact, integer, parse_bounded, require
from check_world import validate_world
from check_rule_evidence import canonical_pack


def validate_play_checkpoint(text: str, catalog: dict, definition: dict, expected_rules: dict) -> dict:
    data = parse_bounded(text)
    exact(data, {'format', 'expedition', 'motion'}, 'play')
    require(data['format'] == 'rw.play/0.1', '未知操作存档版本')
    exact(data['motion'], {'velocity_x', 'velocity_y'}, 'motion')
    integer(data['motion']['velocity_x'], -6144, 6144, '水平速度')
    integer(data['motion']['velocity_y'], -16640, 24576, '垂直速度')
    expedition = data['expedition']
    exact(expedition, {'format', 'scenario_id', 'scenario_version', 'completed', 'simulation'}, 'expedition')
    require(expedition['format'] == 'rw.expedition/0.1' and expedition['scenario_id'] == definition['id'], '场景身份不符')
    integer(expedition['scenario_version'], definition['version'], definition['version'], '场景版本')
    completed = expedition['completed']
    require(type(completed) is list and all(type(x) is str for x in completed), '目标状态类型错误')
    accepted = []
    for goal in definition['objectives']:
        if goal['id'] in completed:
            require(all(x in accepted for x in goal['requires']), '目标依赖缺失')
            accepted.append(goal['id'])
    require(completed == accepted, '目标未知、重复或顺序错误')
    sim = expedition['simulation']
    exact(sim, {'format', 'tick', 'clock', 'world', 'rules'}, 'simulation')
    require(sim['format'] == 'rw.simulation/0.2', '需要带时钟模拟存档')
    integer(sim['tick'], 0, 2147483647, '模拟步')
    exact(sim['clock'], {'cycle_ticks', 'daylight_ticks', 'paused'}, 'clock')
    integer(sim['clock']['cycle_ticks'], 2, 1000000, '周期')
    integer(sim['clock']['daylight_ticks'], 1, sim['clock']['cycle_ticks']-1, '白昼')
    require(type(sim['clock']['paused']) is bool, '暂停必须为布尔')
    require(canonical_pack(sim['rules']) == canonical_pack(expected_rules), '规则图不符合测试预期')
    derived = copy.deepcopy(catalog)
    available = set()
    for module in expected_rules['modules']:
        available.add((module['id'], module['version']))
        versions = derived['rules'].setdefault(module['id'], [])
        if module['version'] not in versions:
            versions.append(module['version'])
    world = validate_world(json.dumps(sim['world'], ensure_ascii=False), derived)
    require(world['format'] == 'rw.world/0.3', '连续身体缺失')
    for entity in world['entities']['instances']:
        for binding in entity['rules']:
            require((binding['id'], binding['version']) in available, '绑定规则不在完整检查点中')
    return data


def validate_native_play(text: str, catalog: dict) -> dict:
    definition = {'id': 'scenario:platform', 'version': 1, 'objectives': [{'id': 'goal:walk', 'requires': []}]}
    rules = {'format': 'rw.rules/0.1', 'modules': [{'id': 'user:idle', 'version': 1, 'parameters': {},
             'nodes': [{'id': 'yes', 'op': 'bool', 'inputs': {}, 'config': {'value': True}}], 'effects': []}]}
    data = validate_play_checkpoint(text, catalog, definition, rules)
    sim = data['expedition']['simulation']
    require(sim['world']['entities']['world_id'] == 'world:platform', '操作测试世界不符')
    require(sim['clock'] == {'cycle_ticks': 120, 'daylight_ticks': 60, 'paused': True}, '测试应暂停收尾')
    total = sum(x['units'] for x in sim['world']['water']) + sum(e['state']['water_units'] for e in sim['world']['entities']['instances'])
    require(total == 150, '操作恢复过程水量改变')
    return data


def validate_live_expedition(text: str, scenario: dict, contract: dict, *, paused: bool = False) -> dict:
    rules = copy.deepcopy(scenario['rules'])
    rules['modules'].append(copy.deepcopy(contract['pump']))
    data = validate_play_checkpoint(text, scenario['catalog'], scenario['definition'], rules)
    expedition, original = data['expedition'], scenario['world']
    sim = expedition['simulation']
    world = sim['world']
    require(expedition['completed'] == contract['completed'], '真实操控未完成完整目标')
    require(world['actor']['id'] == original['actor']['id'] and world['actor']['cell'] == contract['actor_cell'], '角色未返回营地')
    require(world['entities']['world_id'] == original['entities']['world_id'], '世界被更换')
    for key in ('cycle_ticks', 'daylight_ticks'):
        require(sim['clock'][key] == scenario['clock'][key], '昼夜配置被更换')
    require(sim['clock']['paused'] is paused, '真实路线收尾暂停状态不符')
    require({tuple(t['cell']): t['material_id'] for t in world['terrain']} == {tuple(t['cell']): t['material_id'] for t in original['terrain']}, '自动泵路线不应改地形')
    require(world['entities']['stacks'] == original['entities']['stacks'], '普通材料被改变')
    entities = {e['id']: e for e in world['entities']['instances']}
    expected = {e['id']: copy.deepcopy(e) for e in original['entities']['instances']}
    require(set(entities) == set(expected), '造物身份集合被改变')
    vessel = entities['creation:vessel']
    require(vessel['state']['water_units'] >= 4500, '未真实搬走足够入口积水')
    expected['creation:vessel']['state']['water_units'] = vessel['state']['water_units']
    expected['creation:vessel']['rules'] = [{'id': contract['pump']['id'], 'version': contract['pump']['version']}]
    expected['creation:plot']['state']['water_units'] = 500
    expected['creation:lamp']['state']['light_on'] = True
    expected['creation:lamp']['location'] = {'kind': 'world', 'cell': contract['lamp_cell']}
    require(entities == expected, '真实路线造物状态/归属不符')
    total = sum(e['state']['water_units'] for e in entities.values()) + sum(w['units'] for w in world['water'])
    require(total == contract['initial_water'], '真实运动/资源/恢复总水量不守恒')
    return data


def validate_ui_expedition(text: str, scenario: dict, contract: dict) -> dict:
    return validate_live_expedition(text, scenario, contract, paused=True)
