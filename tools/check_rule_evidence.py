"""独立验证test_rules.gd的确定输出；不是通用规则编译器或执行器。"""
from __future__ import annotations
import copy
import json
from check_snapshot import parse_bounded, exact, integer, require
from check_world import validate_world


def canonical_pack(pack: dict) -> str:
    # 只消除无语义的模块/节点排列差异；保留动作顺序、参数和所有原语内容。
    value = copy.deepcopy(pack)
    require(type(value) is dict and type(value.get('modules')) is list, '规则包结构错误')
    for module in value['modules']:
        require(type(module) is dict and type(module.get('nodes')) is list, '模块结构错误')
        require(all(type(n) is dict and type(n.get('id')) is str for n in module['nodes']), '节点结构错误')
        module['nodes'].sort(key=lambda n: n['id'])
        require(type(module.get('id')) is str and type(module.get('version')) is int, '模块ID/版本错误')
    value['modules'].sort(key=lambda m: (m['id'],m['version']))
    return json.dumps(value,sort_keys=True,separators=(',',':'))


def validate_fixture_result(text: str, catalog: dict, world_fixture: dict, rule_fixture: dict) -> dict:
    d = parse_bounded(text)
    exact(d, {'format','tick','world','rules'}, 'simulation')
    require(d['format'] == 'rw.simulation/0.1', '未知模拟信封')
    integer(d['tick'],5,5,'验收步数')
    world = validate_world(json.dumps(d['world']),catalog)
    expected = copy.deepcopy(world_fixture)
    by_id = {e['id']: e for e in expected['entities']['instances']}
    by_id['creation:001']['state']['water_units'] = 300
    by_id['creation:002']['state']['water_units'] = 200
    require(world == expected, '原生世界输出与规定的搬运/恢复/运行结果不一致')
    require(canonical_pack(d['rules']) == canonical_pack(rule_fixture), '规则包在保存恢复时被改变')
    return d
