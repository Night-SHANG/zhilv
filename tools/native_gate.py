"""真实 Godot 进程的验证门禁；日志解析测试不是引擎行为测试。"""
from __future__ import annotations
import json
import os
import pathlib
import re
import shutil
import subprocess
from check_snapshot import validate, ValidationError
from check_world import validate_world
from check_rule_evidence import validate_fixture_result
from check_authoring_evidence import validate_authoring_result

ROOT = pathlib.Path(__file__).resolve().parents[1]


def parse_result(exit_code: int, output: str, marker: str) -> dict:
    matches = re.findall(r'^' + re.escape(marker) + r': (\d+) passed; (\d+) failed\s*$', output, re.M)
    good = len(matches) == 1
    passed, failed = map(int, matches[0]) if good else (0, 0)
    errors = any(x in output for x in ('SCRIPT ERROR:', 'Parse Error:', 'ERROR:'))
    ok = good and passed > 0 and failed == 0 and exit_code == 0 and not errors
    return {'status': 'PASS' if ok else 'FAIL', 'passed': passed, 'failed': failed,
            'exit_code': exit_code, 'completion_markers': len(matches),
            'diagnostics': [line for line in output.splitlines() if any(tag in line for tag in ('FAIL:', 'SCRIPT ERROR:', 'Parse Error:', 'ERROR:', ' at:'))][:12]}


def native_check(executable: str | None, reports: pathlib.Path) -> dict:
    path = executable or os.environ.get('GODOT_BIN') or shutil.which('godot') or shutil.which('godot4')
    if not path:
        return {'status': 'BLOCKED', 'reason': 'Godot executable unavailable; no native tests ran'}
    env = os.environ.copy()
    env['GODOT_SILENCE_ROOT_WARNING'] = '1'
    env['RULEWEAVER_FIXTURE_ROOT'] = str(ROOT / 'fixtures')
    evidence = reports.resolve() / 'native_checkpoint.json'
    env['RULEWEAVER_NATIVE_CHECKPOINT'] = str(evidence)
    world_evidence = reports.resolve() / 'native_world.json'
    env['RULEWEAVER_NATIVE_WORLD'] = str(world_evidence)
    rules_evidence = reports.resolve() / 'native_rules.json'
    env['RULEWEAVER_NATIVE_RULES'] = str(rules_evidence)
    authoring_evidence = reports.resolve() / 'native_authoring.json'
    env['RULEWEAVER_NATIVE_AUTHORING'] = str(authoring_evidence)
    expected = json.loads((ROOT / 'toolchain.lock.json').read_text(encoding='utf-8'))['godot_version']
    try:
        version = subprocess.run([path, '--version'], capture_output=True, text=True,
                                 encoding='utf-8', errors='replace', timeout=15)
        text = version.stdout.strip()
        if version.returncode or not text.startswith(expected + '.stable.'):
            return {'status': 'BLOCKED', 'reason': 'Godot version differs from pinned baseline', 'engine': text}
        reports.mkdir(parents=True, exist_ok=True)
        evidence.unlink(missing_ok=True)  # 仅删除本次输出，禁止旧证据蒙混过关。
        world_evidence.unlink(missing_ok=True)
        rules_evidence.unlink(missing_ok=True)
        authoring_evidence.unlink(missing_ok=True)
        suites = []
        for name, marker in (('vendor', 'VENDOR_TEST_RESULT'), ('lifecycle', 'LIFECYCLE_TEST_RESULT'), ('world', 'WORLD_TEST_RESULT'), ('projection', 'PROJECTION_TEST_RESULT'), ('limits', 'LIMITS_TEST_RESULT'), ('rules', 'RULES_TEST_RESULT'), ('rule_edges', 'RULE_EDGES_TEST_RESULT'), ('authoring', 'AUTHORING_TEST_RESULT'), ('draft', 'DRAFT_TEST_RESULT')):
            cmd = [path, '--headless', '--path', str(ROOT / 'godot'),
                   '--script', 'res://tests/test_' + name + '.gd']
            proc = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8',
                                  errors='replace', timeout=90, env=env)
            output = proc.stdout + '\n' + proc.stderr
            (reports / ('godot_' + name + '.log')).write_text(output, encoding='utf-8')
            result = parse_result(proc.returncode, output, marker)
            suites.append({'suite': name, 'command': cmd, **result})
        status = 'PASS' if all(x['status'] == 'PASS' for x in suites) else 'FAIL'
        cross = 'NOT_RUN'
        if status == 'PASS':
            catalog = json.loads((ROOT / 'fixtures/catalog.json').read_text(encoding='utf-8'))
            validate(evidence.read_text(encoding='utf-8'), catalog)
            validate_world(world_evidence.read_text(encoding='utf-8'), catalog)
            rule_catalog = json.loads((ROOT/'fixtures/rules_catalog.json').read_text(encoding='utf-8'))
            rule_world = json.loads((ROOT/'fixtures/rules_world.json').read_text(encoding='utf-8'))
            rule_pack = json.loads((ROOT/'fixtures/rules_pack.json').read_text(encoding='utf-8'))
            validate_fixture_result(rules_evidence.read_text(encoding='utf-8'), rule_catalog, rule_world, rule_pack)
            authoring_expected = json.loads((ROOT/'fixtures/authoring_expected.json').read_text(encoding='utf-8'))
            validate_authoring_result(authoring_evidence.read_text(encoding='utf-8'), rule_catalog, authoring_expected)
            cross = 'PASS'
        return {'status': status, 'engine': text, 'suites': suites, 'native_snapshot_python_validation': cross, 'native_world_python_validation': cross, 'native_rule_fixture_python_validation': cross, 'native_authoring_python_validation': cross,
                'scope': 'headless world, typed rule graphs, replay and TileMapLayer projection; no playable game or performance acceptance'}
    except FileNotFoundError as exc:
        # 启动前缺引擎，不是原生断言通过；启动后缺输出则判失败。
        return {'status': 'FAIL' if 'suites' in locals() else 'BLOCKED', 'reason': str(exc)}
    except (OSError, subprocess.TimeoutExpired, ValueError) as exc:
        return {'status': 'FAIL', 'reason': str(exc)}
