"""rw.world/0.1 独立协议回读；不模拟 Godot 物理或交互行为。"""
from __future__ import annotations
import json
from check_snapshot import exact, ident, integer, parse_bounded, require, validate

MAX_TERRAIN = 16384
COORD_LIMIT = 1_000_000


def cell(value, where: str) -> tuple[int, int]:
    require(type(value) is list and len(value) == 2, where + ': 必须为二维坐标')
    for n in value:
        integer(n, -COORD_LIMIT, COORD_LIMIT, where)
    return tuple(value)


def validate_world(text: str, catalog: dict) -> dict:
    """只在完整验证后返回独立解码结果；未知版本不会静默降级。"""
    d = parse_bounded(text)
    exact(d, {'format', 'entities', 'terrain', 'actor'}, 'world')
    require(d['format'] == 'rw.world/0.1', '不支持的世界版本')
    entities = validate(json.dumps(d['entities'], ensure_ascii=False), catalog)
    exact(d['actor'], {'id', 'cell'}, 'actor')
    ident(d['actor']['id'], 'actor.id')
    foot = cell(d['actor']['cell'], 'actor.cell')
    head = (foot[0], foot[1] - 1)
    require(head[1] >= -COORD_LIMIT, '角色头部越界')
    require(type(d['terrain']) is list and len(d['terrain']) <= MAX_TERRAIN, '地形类型/预算错误')
    occupied = set()
    for tile in d['terrain']:
        exact(tile, {'cell', 'material_id'}, 'terrain.tile')
        pos = cell(tile['cell'], 'terrain.cell')
        ident(tile['material_id'], 'terrain.material_id')
        mat = catalog['materials'].get(tile['material_id'])
        require(type(mat) is dict and mat.get('stackable') is True, '静态地形仅接纳普通材料')
        require(pos not in occupied, '地形重叠')
        occupied.add(pos)
    for entity in entities['instances']:
        loc = entity['location']
        if loc['kind'] == 'world':
            pos = cell(loc['cell'], 'instance.cell')
            require(pos not in occupied, '造物与地形重叠')
            occupied.add(pos)
        else:
            require(loc['owner'] == d['actor']['id'], '单角色世界中存在其他库存归属')
    require(foot not in occupied and head not in occupied, '角色与实体/地形重叠')
    return d
