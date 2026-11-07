"""独立核对三条遗迹流程的原生输出；不是第二套模拟器或可玩性验收。"""
from __future__ import annotations
import copy
import json
from check_snapshot import exact, integer, parse_bounded, require
from check_world import validate_world
from check_rule_evidence import canonical_pack


def validate_expedition_result(text: str, scenario: dict, contract: dict) -> dict:
    data = parse_bounded(text)
    exact(data, {'format', 'routes'}, 'evidence')
    require(data['format'] == 'rw.expedition_evidence/0.1', '未知流程证据版本')
    exact(data['routes'], set(contract['routes']), 'routes')
    for route, expected in contract['routes'].items():
        result = data['routes'][route]
        exact(result, {'checkpoint', 'total_water', 'plot_water', 'mined', 'authored_rule'}, route)
        integer(result['total_water'], contract['initial_water'], contract['initial_water'], '总水量声明')
        integer(result['plot_water'], 500, 500, '灌溉量声明')
        integer(result['mined'], expected['mined'], expected['mined'], '采掘声明')
        require(type(result['authored_rule']) is bool and result['authored_rule'] == expected['authored_rule'], '创作声明不符')
        save = parse_bounded(result['checkpoint'])
        exact(save, {'format', 'scenario_id', 'scenario_version', 'completed', 'simulation'}, 'expedition')
        require(save['format'] == 'rw.expedition/0.1', '未知探险存档版本')
        require(save['scenario_id'] == scenario['definition']['id'], '场景ID不符')
        integer(save['scenario_version'], scenario['definition']['version'], scenario['definition']['version'], '场景版本')
        require(save['completed'] == contract['completed'], '目标状态不符')
        sim = save['simulation']
        exact(sim, {'format', 'tick', 'clock', 'world', 'rules'}, 'simulation')
        require(sim['format'] == 'rw.simulation/0.2', '计时存档格式不符')
        integer(sim['tick'], expected['tick'], expected['tick'], '终点模拟步')
        exact(sim['clock'], {'cycle_ticks', 'daylight_ticks', 'paused'}, 'clock')
        for key in ('cycle_ticks', 'daylight_ticks'):
            integer(sim['clock'][key], scenario['clock'][key], scenario['clock'][key], key)
        require(sim['clock']['paused'] is False, '流程结束时不应处于暂停状态')
        rules = copy.deepcopy(scenario['rules'])
        catalog = copy.deepcopy(scenario['catalog'])
        if expected['authored_rule']:
            rules['modules'].append(copy.deepcopy(contract['pump']))
            catalog['rules'][contract['pump']['id']] = [contract['pump']['version']]
        require(canonical_pack(sim['rules']) == canonical_pack(rules), '规则图或依赖被改变')
        world = validate_world(json.dumps(sim['world'], ensure_ascii=False), catalog)
        require(world['format'] == 'rw.world/0.2', '环境水层不能在回读时丢弃')
        original = scenario['world']
        require(world['entities']['world_id'] == original['entities']['world_id'], '世界ID不符')
        require(world['actor'] == {'id': original['actor']['id'], 'cell': contract['actor_cell']}, '角色没有返回营地')
        tiles = {tuple(t['cell']): t['material_id'] for t in world['terrain']}
        expected_tiles = {tuple(t['cell']): t['material_id'] for t in original['terrain']}
        if expected['mined']:
            expected_tiles.pop((1, 1))
        require(tiles == expected_tiles, '地形变化与选定路线不符')
        stacks = copy.deepcopy(original['entities']['stacks'])
        stacks['core:stone'] += expected['mined']
        require(world['entities']['stacks'] == stacks, '挖掘后的普通材料账本不符')
        entities = {e['id']: e for e in world['entities']['instances']}
        expected_entities = {e['id']: copy.deepcopy(e) for e in original['entities']['instances']}
        vessel = expected_entities['creation:vessel']
        vessel['state']['water_units'] = expected['vessel_water']
        if expected['authored_rule']:
            vessel['rules'] = [{'id': contract['pump']['id'], 'version': contract['pump']['version']}]
        expected_entities['creation:plot']['state']['water_units'] = 500
        lamp = expected_entities['creation:lamp']
        lamp['state']['light_on'] = True
        lamp['location'] = {'kind': 'world', 'cell': contract['lamp_cell']}
        require(entities == expected_entities, '造物身份、绑定、容量、状态或位置不符')
        actual_water = sum(e['state']['water_units'] for e in entities.values()) + sum(w['units'] for w in world['water'])
        require(actual_water == contract['initial_water'], '环境水与容器总账不守恒')
    return data
