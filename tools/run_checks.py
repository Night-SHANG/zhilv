"""可复现检查入口。退出0=全部通过；1=失败；2=原生引擎验证受阻。"""
from __future__ import annotations
import argparse
import datetime
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


from native_gate import native_check

def vendor_check() -> dict:
    manifest = json.loads((ROOT/'vendor_manifest.json').read_text(encoding='utf-8'))
    items = []
    for info in manifest['files']:
        raw = (ROOT/info['path']).read_bytes()
        sha = hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()
        items.append({'path':info['path'], 'expected':info['git_blob_sha1'], 'actual':sha,
                      'match':sha==info['git_blob_sha1']})
    return {'status':'PASS' if all(i['match'] for i in items) else 'FAIL','files':items,
            'commit':manifest['commit']}


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--godot', help='Godot executable path; or set GODOT_BIN')
    mode = p.add_mutually_exclusive_group()
    mode.add_argument('--native-only', action='store_true')
    mode.add_argument('--offline-only', action='store_true')
    p.add_argument('--reports',type=pathlib.Path,default=ROOT/'reports')
    args = p.parse_args()
    args.reports.mkdir(parents=True,exist_ok=True)
    report: dict = {'timestamp_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    'scope':'reuse verification pack, not game release','overall':'BLOCKED'}
    failure = False
    if not args.native_only:
        try:
            report['vendor'] = vendor_check()
            failure = report['vendor']['status'] != 'PASS'
            proc = subprocess.run([sys.executable,'-m','unittest','discover','-s','tests','-v'],
                cwd=ROOT,capture_output=True,text=True,timeout=60)
            output = proc.stdout+'\n'+proc.stderr
            (args.reports/'offline_tests.log').write_text(output,encoding='utf-8')
            match = re.search(r'Ran (\d+) tests?',output)
            valid_run = proc.returncode == 0 and match is not None and int(match[1]) > 0
            report['offline'] = {'status':'PASS' if valid_run else 'FAIL',
                                 'count':int(match[1]) if match else None,'exit_code':proc.returncode,
                                 'scope':'Python JSON contract and fail-closed launcher tests ONLY'}
            failure = failure or not valid_run
        except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as exc:
            report['offline'] = {'status':'FAIL','reason':str(exc)}
            failure = True
    report['native'] = ({'status': 'NOT_RUN', 'reason': 'offline-only requested'}
                        if args.offline_only else native_check(args.godot,args.reports))
    report['mode'] = 'offline-only' if args.offline_only else 'full'
    if failure or report['native']['status'] == 'FAIL':
        report['overall'], code = 'FAIL', 1
    elif report['native']['status'] == 'BLOCKED':
        report['overall'], code = 'BLOCKED', 2
    else:
        report['overall'], code = 'PASS', 0
    (args.reports/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2))
    return code

if __name__ == '__main__':
    raise SystemExit(main())
