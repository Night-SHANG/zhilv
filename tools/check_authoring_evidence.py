"""独立验证test_draft.gd的确定输出；不解释执行规则，也不信任产物自带权限。"""
from __future__ import annotations
import copy
import json
from check_snapshot import parse_bounded, exact, integer, require
from check_world import validate_world
from check_rule_evidence import canonical_pack


def validate_authoring_result(text: str, catalog: dict, expected: dict) -> dict:
    data = parse_bounded(text)
    exact(data, {'format', 'tick', 'world', 'rules'}, 'authored simulation')
    require(data['format'] == 'rw.simulation/0.1', '未知创作存档格式')
    integer(data['tick'], 6, 6, '创作验收步数')
    # 用测试合同中的固定期望建立规则目录，不从待检查产物中授予新权限。
    approved = copy.deepcopy(catalog)
    for module in expected['rules']['modules']:
        versions = approved['rules'].setdefault(module['id'], [])
        if module['version'] not in versions:
            versions.append(module['version'])
    world = validate_world(json.dumps(data['world']), approved)
    require(world == expected['world'], '创作/绑定/保存/恢复后的世界状态不符')
    require(canonical_pack(data['rules']) == canonical_pack(expected['rules']),
            '新规则、旧版本或参数化依赖未完整保留')
    return data
