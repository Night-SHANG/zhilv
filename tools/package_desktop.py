"""打包自包含开发运行包；使用锁定官方引擎运行源码，不冒称优化后的发行导出。"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import pathlib
import platform
import shutil
import subprocess
import tempfile
import zipfile

ROOT=pathlib.Path(__file__).resolve().parents[1]
ALLOWED={'.gd','.uid','.tscn','.json','.godot','.md'}
FONT_EXT={'.ttf','.otf','.ttc','.woff','.woff2'}

def stage_project(root: pathlib.Path, destination: pathlib.Path) -> None:
    if destination.exists():
        raise ValueError('Refusing to overwrite an existing staging directory')
    (destination/'game').mkdir(parents=True)
    shutil.copy2(root/'godot/project.godot',destination/'game/project.godot')
    for folder in ('content','presentation','runtime','vendor'):
        for p in (root/'godot'/folder).rglob('*'):
            if not p.is_file():
                continue
            if p.is_symlink() or p.suffix.lower() in FONT_EXT:
                raise ValueError('Unexpected symlink or font file in source')
            if p.suffix not in ALLOWED and p.name!='LICENSE':
                raise ValueError('Unreviewed production resource: '+str(p))
            target=destination/'game'/p.relative_to(root/'godot')
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(p,target)

def file_manifest(root: pathlib.Path) -> dict:
    return {str(p.relative_to(root)).replace('\\','/'):
            hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob('*')) if p.is_file() and '.godot' not in p.parts}

def verify_manifest(root: pathlib.Path, expected: dict) -> bool:
    return all((root/name).is_file() and hashlib.sha256((root/name).read_bytes()).hexdigest()==digest
               for name,digest in expected.items())

def checked(cmd: list[str], log: pathlib.Path, env: dict) -> str:
    p=subprocess.run(cmd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120,env=env)
    text=p.stdout+'\n'+p.stderr
    log.write_text(text,encoding='utf-8')
    if p.returncode or any(s in text for s in ('SCRIPT ERROR:','Parse Error:','ERROR:')):
        raise ValueError('Staged runtime check failed: '+str(log))
    return text

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',default=os.environ.get('GODOT_BIN'))
    parser.add_argument('--output',type=pathlib.Path,required=True)
    parser.add_argument('--commit',default=os.environ.get('GITHUB_SHA','local-uncommitted'))
    args=parser.parse_args()
    if not args.godot:raise ValueError('A checksum-pinned installed engine is required')
    binary=pathlib.Path(args.godot).resolve()
    system=platform.system().lower()
    if system not in ('windows','linux'):raise ValueError('Only tested desktop targets supported')
    lock=json.loads((ROOT/'toolchain.lock.json').read_text(encoding='utf-8'))
    args.output.mkdir(parents=True,exist_ok=True)
    env=dict(os.environ,GODOT_SILENCE_ROOT_WARNING='1')
    with tempfile.TemporaryDirectory(prefix='ruleweaver-desktop-') as temporary:
        stage=pathlib.Path(temporary)/'Ruleweaver'
        stage_project(ROOT,stage)
        engine=stage/'engine';engine.mkdir()
        shipped=[]
        for name in {lock['platforms'][system]['executable'],lock['platforms'][system]['executable'].replace('_console','')}:
            p=binary.parent/name
            if not p.is_file():raise ValueError('Missing official executable: '+name)
            shutil.copy2(p,engine/name);shipped.append(name)
        runner=engine/binary.name
        text=checked([str(runner),'--version'],args.output/'engine_version.log',env)
        if not text.startswith(lock['godot_version']+'.stable.'):raise ValueError('Engine version mismatch')
        env['RULEWEAVER_LICENSE_OUT']=str(stage)
        checked([str(runner),'--headless','--path',str(ROOT/'godot'),'--script','res://tests/engine_notices.gd'],args.output/'licenses.log',env)
        if not (stage/'GODOT_LICENSE.txt').is_file() or not (stage/'GODOT_THIRD_PARTY.json').is_file():
            raise ValueError('Missing engine copyright notices')
        checked([str(runner),'--headless','--editor','--path',str(stage/'game'),'--import','--quit'],args.output/'package_import.log',env)
        text=checked([str(runner),'--headless','--path',str(stage/'game'),'--quit-after','12'],args.output/'package_launch.log',env)
        if 'RULEWEAVER_APP_READY' not in text:raise ValueError('Main scene did not become ready')
        shutil.rmtree(stage/'game/.godot',ignore_errors=True)
        if system=='windows':
            gui=lock['platforms'][system]['executable'].replace('_console','')
            (stage/'Start_Ruleweaver.bat').write_bytes(('@echo off\r\ncd /d "%~dp0"\r\nstart "" "engine\\'+gui+'" --path "%~dp0game"\r\n').encode('ascii'))
        else:
            script=stage/'Start_Ruleweaver.sh'
            script.write_text('#!/bin/sh\nHERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"\nexec "$HERE/engine/'+binary.name+'" --path "$HERE/game"\n')
            script.chmod(0o755)
        (stage/'README.txt').write_text('织律 v0.17 开发运行包\n\n完整解压后运行 Start_Ruleweaver。无需另装 Godot；内附官方4.6.1引擎。\n新增凝结地块与回收地块水：凝水晶每块封存500水，可形成实际碰撞台阶；挖碎释放水，不重复掉落。前四目标后可搭路到高处(0,-3)，普通石块也可用。\n织律台可公开常量参数、存为自创词条、追加调用、编辑副本和导出所选模块；存为词条不会应用到造物，组合后仍需点击应用。\n这是可操作的开发构建，不是正式发行或优化导出。首次打开世界暂停，点击“继续探索”。\nA/D移动，空格跳跃，1～7选择工具，左键使用，右键收回造物，B背包制作，Tab/E织律台，F5存档，F9读档。\n织律台中草稿不会自动生效；“应用到造物”发布新版本。F5 会将未应用草稿与世界一起保存；恢复草稿不会自动发布。\n新探索不赠送工具。先用挖掘工具采集头顶六块石料，按B制作储水容器（4石料）和夜灯（2石料）。选择容器放在水面上方，再应用限量吸水，回收后带灯进入遗迹，回营地交水。也可挖开地板排水。首次交水后可探索下层回廊，并复用容器建立储水点。\n织律台“预演一拍”只运行隔离副本，不改变真实世界；“应用”才改变造物。\n保存位于系统用户数据目录 RuleweaverDevelopment，不会覆盖其他项目。\n画面为简化程序化资源；没有声音、游泳、无限地图或最终手感验收。\n字体使用操作系统已有字体，不分发字体文件。\n\n本程序使用 Godot Engine，许可与第三方版权见 GODOT_LICENSE.txt、GODOT_THIRD_PARTY.json，亦见 https://godotengine.org/license/ 。\nCoheronia工程代码许可见 game/vendor/coheronia/LICENSE；没有使用其保留版权的美术、音乐或叙事素材。\n\nSource commit: '+args.commit+'\n',encoding='utf-8')
        manifest=file_manifest(stage)
        if not verify_manifest(stage,manifest):raise ValueError('Pre-package hash verification failed')
        (stage/'MANIFEST.json').write_text(json.dumps({'commit':args.commit,'kind':'source-runtime-development','engine':lock['godot_version'],'files':manifest},ensure_ascii=False,indent=2),encoding='utf-8')
        target=args.output/f'Ruleweaver-v0.17-{system}-x86_64-development.zip'
        with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
            for p in sorted(stage.rglob('*')):
                if p.is_file():z.write(p,pathlib.Path('Ruleweaver')/p.relative_to(stage))
        with zipfile.ZipFile(target) as z:
            if z.testzip() is not None:raise ValueError('Archive CRC check failed')
            for name,digest in manifest.items():
                if hashlib.sha256(z.read('Ruleweaver/'+name)).hexdigest()!=digest:raise ValueError('Archive byte mismatch: '+name)
        result={'commit':args.commit,'zip':target.name,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'size':target.stat().st_size,'files':len(manifest),'kind':'development launcher with official engine, not export template build','import_and_main_smoke':'PASS'}
        (args.output/'package.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps(result,ensure_ascii=False))
    return 0
if __name__=='__main__':raise SystemExit(main())
