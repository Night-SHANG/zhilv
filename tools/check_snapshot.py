"""离线实例存档质量门。只验证JSON契约，不执行词条、不证明Godot运行。"""
from __future__ import annotations
import argparse
import json
import pathlib
import re
import sys
from typing import Any

MAX_BYTES = 1024 * 1024
MAX_DEPTH = 16
MAX_INSTANCES = 4096
MAX_QUANTITY = 1_000_000_000
ID = re.compile(r"[a-z][a-z0-9_.-]*:[A-Za-z0-9_.-]{1,64}\Z")

class ValidationError(ValueError):
    """输入必须被拒绝，不能静默回退成一个新世界。"""


def require(ok: bool, message: str) -> None:
    if not ok:
        raise ValidationError(message)


def exact(obj: Any, fields: set[str], where: str) -> None:
    require(type(obj) is dict, f'{where}: 必须是对象')
    require(set(obj) == fields, f'{where}: 字段缺失或含未知字段')


def ident(value: Any, where: str) -> None:
    require(type(value) is str and ID.fullmatch(value) is not None, f'{where}: 非法ID')


def integer(value: Any, lo: int, hi: int, where: str) -> None:
    require(type(value) is int and lo <= value <= hi, f'{where}: 要求范围[{lo},{hi}]内的整数')


def _pairs(pairs: list[tuple[str, Any]]) -> dict:
    out: dict = {}
    for k, v in pairs:
        require(k not in out, f'JSON包含重复键: {k}')
        out[k] = v
    return out


def _constant(name: str) -> None:
    raise ValidationError(f'非有限数值: {name}')


def parse_bounded(text: str) -> Any:
    require(type(text) is str, '输入必须为文本')
    require(len(text.encode('utf-8')) <= MAX_BYTES, '输入超过1MiB验证预算')
    depth, in_string, escaped = 0, False, False
    for char in text:
        if in_string:
            if escaped:
                escaped = False
            elif char == '\\':
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
        elif char in '[{':
            depth += 1
            require(depth <= MAX_DEPTH, 'JSON嵌套深度超限')
        elif char in ']}':
            depth -= 1
    try:
        return json.loads(text, object_pairs_hook=_pairs, parse_constant=_constant)
    except (json.JSONDecodeError, RecursionError, OverflowError, ValueError) as exc:
        raise ValidationError(str(exc)) from exc


def validate(text: str, catalog: dict) -> dict:
    """按受信的目录快照验证状态。目录不是可执行模块包；本工具也不是安全沙箱。"""
    require(type(catalog) is dict and catalog.get('format') == 'rw.catalog/0.1', '目录版本不支持')
    materials, rules = catalog.get('materials'), catalog.get('rules')
    require(type(materials) is dict and type(rules) is dict, '目录结构错误')
    for material in materials.values():
        require(type(material) is dict, '材料定义须为对象')
        if 'bound_water_units' in material:
            require(material.get('stackable') is True, '只有地形材料可以封水')
            integer(material['bound_water_units'], 1, 1000, 'bound_water_units')
    d = parse_bounded(text)
    exact(d, {'format', 'world_id', 'stacks', 'instances'}, 'checkpoint')
    require(d['format'] == 'rw.instances/0.1', '存档版本不支持')
    ident(d['world_id'], 'world_id')
    stacks, instances = d['stacks'], d['instances']
    require(type(stacks) is dict and len(stacks) <= 1024, '普通材料表类型错误或超限')
    require(type(instances) is list and len(instances) <= MAX_INSTANCES, '实例数超限或类型错误')
    for material_id, amount in stacks.items():
        ident(material_id, 'stack.material_id')
        material = materials.get(material_id)
        require(type(material) is dict and material.get('stackable') is True, '未知材料或有状态物品不能只存数量')
        integer(amount, 1, MAX_QUANTITY, 'stack.amount')
    seen_ids, seen_cells = set(), set()
    for n, entity in enumerate(instances):
        p = f'instances[{n}]'
        exact(entity, {'id', 'material_id', 'rules', 'state', 'location'}, p)
        ident(entity['id'], p+'.id')
        require(entity['id'] not in seen_ids, '实例ID重复')
        seen_ids.add(entity['id'])
        ident(entity['material_id'], p+'.material_id')
        material = materials.get(entity['material_id'])
        require(type(material) is dict and material.get('stackable') is False, '实例材料不存在或分类错误')
        require(material.get('state') == 'reservoir/0.1', '本验证切片不支持该状态模式')
        refs = entity['rules']
        require(type(refs) is list and len(refs) <= 16, '规则引用类型错误或过多')
        used_rules = set()
        for ref in refs:
            exact(ref, {'id', 'version'}, p+'.rules')
            ident(ref['id'], p+'.rule.id')
            integer(ref['version'], 1, 2**31-1, 'rule.version')
            versions = rules.get(ref['id'])
            require(type(versions) is list and ref['version'] in versions, '规则或版本缺失')
            require(ref['id'] not in used_rules, '重复规则引用')
            used_rules.add(ref['id'])
        state = entity['state']
        exact(state, {'water_units', 'capacity_units', 'light_on'}, p+'.state')
        integer(state['capacity_units'], 1, MAX_QUANTITY, 'capacity_units')
        integer(state['water_units'], 0, state['capacity_units'], 'water_units')
        require(type(state['light_on']) is bool, 'light_on必须为布尔值')
        location = entity['location']
        require(type(location) is dict, 'location必须为对象')
        if location.get('kind') == 'world':
            exact(location, {'kind', 'cell'}, p+'.location')
            cell = location['cell']
            require(type(cell) is list and len(cell) == 2, '格坐标须为二维数组')
            for c in cell:
                integer(c, -1_000_000, 1_000_000, 'cell.coordinate')
            pos = tuple(cell)
            require(pos not in seen_cells, '多个造物占有同一格')
            seen_cells.add(pos)
        elif location.get('kind') == 'inventory':
            exact(location, {'kind', 'owner'}, p+'.location')
            ident(location['owner'], 'inventory.owner')
        else:
            raise ValidationError('不支持的位置类型')
    return d


def read_limited(path: pathlib.Path) -> str:
    with path.open('rb') as f:
        raw = f.read(MAX_BYTES + 1)
    require(len(raw) <= MAX_BYTES, f'{path}: 文件超限')
    return raw.decode('utf-8')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', type=pathlib.Path, required=True)
    parser.add_argument('--snapshot', type=pathlib.Path, required=True)
    args = parser.parse_args()
    try:
        catalog = parse_bounded(read_limited(args.catalog))
        d = validate(read_limited(args.snapshot), catalog)
    except (OSError, UnicodeError, ValidationError) as exc:
        print(f'CONTRACT_FAIL: {exc}', file=sys.stderr)
        return 1
    print(f'CONTRACT_PASS: {len(d["instances"])} instances; Godot runtime not tested')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
