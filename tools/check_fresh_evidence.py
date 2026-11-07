"""独立验证空包探索的资源、造物身份、已发布规则与未发布草稿。非游戏模拟器。"""
from __future__ import annotations
import copy
import json
from check_snapshot import exact, parse_bounded, require
from check_play_evidence import validate_play_checkpoint
from check_rule_evidence import canonical_pack

def validate_fresh_expedition(text: str, scenario: dict, contract: dict) -> dict:
    data=parse_bounded(text)
    exact(data,{'format','play','editor'},'workspace')
    require(data['format']=='rw.workspace/0.1','未知工作区格式')
    rules=copy.deepcopy(scenario['rules']);rules['modules'].append(copy.deepcopy(contract['pump']))
    play=validate_play_checkpoint(json.dumps(data['play'],ensure_ascii=False),scenario['catalog'],scenario['definition'],rules)
    exp=play['expedition'];sim=exp['simulation'];world=sim['world'];original=scenario['world']
    require(exp['completed']==contract['completed'],'没有完成完整探索目标')
    require(world['entities']['world_id']==original['entities']['world_id'],'更换了世界')
    require(world['actor']['id']==original['actor']['id'] and world['actor']['cell']==contract['actor_cell'],'未返回营地')
    require(sim['clock']=={**scenario['clock'],'paused':True},'收尾应暂停且未修改昼夜')
    require(world['entities']['stacks']=={},'六块石料应全部用于两个载体')
    expected_terrain={tuple(t['cell']):t['material_id'] for t in original['terrain'] if t['cell'] not in contract['harvest_cells']}
    require({tuple(t['cell']):t['material_id'] for t in world['terrain']}==expected_terrain,'采集或地形发生非预期变化')
    entities={e['id']:e for e in world['entities']['instances']}
    require(set(entities)=={'creation:plot',contract['vessel_id'],contract['lamp_id']},'造物身份数量不符')
    vessel=entities[contract['vessel_id']];lamp=entities[contract['lamp_id']];plot=entities['creation:plot']
    require(vessel['material_id']=='user:reservoir' and vessel['location']=={'kind':'inventory','owner':original['actor']['id']},'没有回收同一储水器')
    require(vessel['state']['water_units']>=4500 and vessel['state']['capacity_units']==6000 and vessel['state']['light_on'] is False,'容器状态不符')
    require(vessel['rules']==[{'id':contract['pump']['id'],'version':1}],'绑定规则被替换')
    require(lamp=={'id':contract['lamp_id'],'material_id':'user:crystal','location':{'kind':'world','cell':contract['lamp_cell']},'rules':[{'id':'core:portable_lamp','version':1}],'state':{'capacity_units':1,'water_units':0,'light_on':True}},'制作夜灯的状态或归属不符')
    expected_plot=copy.deepcopy(original['entities']['instances'][0]);expected_plot['state']['water_units']=500
    require(plot==expected_plot,'营地交水不符')
    total=sum(e['state']['water_units'] for e in entities.values())+sum(w['units'] for w in world['water'])
    require(total==contract['initial_water'],'采集/制造/搬运过程水量不守恒')
    editor=data['editor'];exact(editor,{'selected','tool','drafts'},'editor')
    require(editor['selected']==contract['vessel_id'] and editor['tool']=='lamp','编辑选择恢复错误')
    require(type(editor['drafts']) is dict and set(editor['drafts'])=={contract['vessel_id']},'草稿目标集合不符')
    # 比较结构而非节点数组顺序；预期草稿含未连线动作，与已发布图不同。
    draft=editor['drafts'][contract['vessel_id']]
    require(canonical_pack({'format':'rw.rules/0.1','modules':[draft]})==canonical_pack({'format':'rw.rules/0.1','modules':[contract['unfinished']]}),'未发布草稿未完整保留')
    return data
