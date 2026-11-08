"""独立检查参数词条的确定验收输出，不实现另一个规则执行器。"""
from __future__ import annotations
import json
from check_snapshot import exact, integer, parse_bounded, require
from check_world import validate_world
from check_rule_evidence import canonical_pack


def validate_composition_evidence(text: str, contract: dict) -> dict:
    data = parse_bounded(text)
    exact(data, {'format', 'simulation', 'scroll', 'imported'}, 'composition')
    require(data['format'] == 'rw.composition_evidence/0.1', '未知组合产物格式')
    expected_keys = {tuple(k) for k in contract['export_keys']}
    subset = {'format': 'rw.rules/0.1', 'modules': [
        m for m in contract['rules']['modules'] if (m['id'], m['version']) in expected_keys
    ]}
    scroll = data['scroll']
    exact(scroll, {'format', 'entry', 'rules'}, 'scroll')
    require(scroll['format'] == 'rw.scroll/0.1', '律卷格式错误')
    exact(scroll['entry'], {'id', 'version'}, 'entry')
    integer(scroll['entry']['version'], 1, 1, 'entry version')
    require(scroll['entry']['id'] == 'user:actor_a', '导出入口不同')
    require(canonical_pack(scroll['rules']) == canonical_pack(subset), '依赖闭包缺失或混入未引用模块')
    for key, tick, a, b, bound_b, expected_rules in [
        ('simulation', 2, 200, 400, True, contract['rules']),
        ('imported', 1, 100, 0, False, subset),
    ]:
        sim = data[key]
        exact(sim, {'format', 'tick', 'world', 'rules'}, key)
        require(sim['format'] == 'rw.simulation/0.1', '模拟格式错误')
        integer(sim['tick'], tick, tick, key + '.tick')
        require(canonical_pack(sim['rules']) == canonical_pack(expected_rules), '规则、参数、版本或动作顺序改变')
        world = validate_world(json.dumps(sim['world']), contract['catalog'])
        require(world['actor'] == {'id': 'player:local', 'cell': [1, -2]}, '角色被修改')
        require(world['terrain'] == [{'cell': [1, 1], 'material_id': 'core:stone'}], '地形被修改')
        require(world['water'] == [{'cell': [1, 0], 'units': 1000-a-b}], '水源变化不符')
        require(world['entities']['world_id'] == 'world:words' and world['entities']['stacks'] == {}, '世界身份或材料改变')
        entities = {e['id']: e for e in world['entities']['instances']}
        require(set(entities) == {'creation:a', 'creation:b'}, '实例集合改变')
        for name, x, units, bound in [('a', 0, a, True), ('b', 2, b, bound_b)]:
            require(entities['creation:' + name] == {
                'id': 'creation:' + name, 'material_id': 'user:reservoir',
                'location': {'kind': 'world', 'cell': [x, 0]},
                'state': {'water_units': units, 'capacity_units': 1000, 'light_on': bound},
                'rules': [{'id': 'user:actor_' + name, 'version': 1}] if bound else [],
            }, '造物身份、参数结果或绑定不符')
    return data
