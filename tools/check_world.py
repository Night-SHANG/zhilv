"""rw.world/0.1 与 0.2 独立协议回读；不模拟 Godot 物理或交互行为。"""
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
    require(type(d) is dict and d.get('format') in ('rw.world/0.1', 'rw.world/0.2', 'rw.world/0.3'), '不支持的世界版本')
    fields = {'format', 'entities', 'terrain', 'actor'}
    if d['format'] in ('rw.world/0.2', 'rw.world/0.3'):
        fields.add('water')
    exact(d, fields, 'world')
    entities = validate(json.dumps(d['entities'], ensure_ascii=False), catalog)
    exact(d['actor'], {'id', 'cell', 'body_foot'} if d['format']=='rw.world/0.3' else {'id', 'cell'}, 'actor')
    ident(d['actor']['id'], 'actor.id')
    foot = cell(d['actor']['cell'], 'actor.cell')
    head = (foot[0], foot[1] - 1)
    require(head[1] >= -COORD_LIMIT, '角色头部越界')
    body_cells={foot,head}
    if d['format']=='rw.world/0.3':
        point=d['actor']['body_foot']
        require(type(point) is list and len(point)==2, '身体脚点必须为二维整数')
        for n in point: integer(n,-COORD_LIMIT*1024,(COORD_LIMIT+1)*1024,'body_foot')
        x,y=point
        require(foot==(x//1024,(y-1)//1024),'身体脚点与交互格不一致')
        body_cells={(cx,cy) for cy in range((y-1792)//1024,(y-1)//1024+1) for cx in range((x-320)//1024,(x+319)//1024+1)}
        require(all(-COORD_LIMIT<=cx<=COORD_LIMIT and -COORD_LIMIT<=cy<=COORD_LIMIT for cx,cy in body_cells),'身体越界')
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
    require(body_cells.isdisjoint(occupied), '角色与实体/地形重叠')
    if d['format'] in ('rw.world/0.2', 'rw.world/0.3'):
        require(type(d['water']) is list and len(d['water']) <= 4096, '水层类型/预算错误')
        seen_water = set()
        for entry in d['water']:
            exact(entry, {'cell', 'units'}, 'water.entry')
            pos = cell(entry['cell'], 'water.cell')
            integer(entry['units'], 1, 1000, 'water.units')
            require(pos not in occupied and pos not in seen_water, '水与实体/地形或其他水格重叠')
            seen_water.add(pos)
        # 允许角色暂时处在洪水中；不能因加载器禁止此状态而丢失可恢复存档。
    return d
