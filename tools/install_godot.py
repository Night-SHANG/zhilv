"""从官方固定发行版安装测试引擎；先核对已锁定的 SHA256，再解包。"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import pathlib
import platform
import stat
import tempfile
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MAX_ARCHIVE = 128 * 1024 * 1024


def verify_and_extract(archive: pathlib.Path, destination: pathlib.Path, metadata: dict) -> pathlib.Path:
    if archive.stat().st_size > MAX_ARCHIVE:
        raise ValueError('Archive too large')
    if hashlib.sha256(archive.read_bytes()).hexdigest() != metadata['sha256']:
        raise ValueError('Godot archive SHA256 mismatch')
    destination = destination.resolve()
    with zipfile.ZipFile(archive) as z:
        entries = z.infolist()
        if len(entries) > 16 or sum(i.file_size for i in entries) > 512 * 1024 * 1024:
            raise ValueError('Unexpected archive size')
        if metadata['executable'] not in z.namelist():
            raise ValueError('Pinned executable missing')
        for i in entries:
            # 同时拒绝 Windows/Unix 分隔符的路径穿越和符号链接。
            name = i.filename.replace('\\', '/')
            if name.startswith('/') or ':' in name or '..' in pathlib.PurePosixPath(name).parts:
                raise ValueError('Unsafe archive path')
            if stat.S_ISLNK(i.external_attr >> 16):
                raise ValueError('Symlink in archive')
            if not (destination / name).resolve().is_relative_to(destination):
                raise ValueError('Archive path escapes destination')
        destination.mkdir(parents=True, exist_ok=True)
        z.extractall(destination)
    executable = destination / metadata['executable']
    if not executable.is_file():
        raise ValueError('Executable is not a file')
    executable.chmod(executable.stat().st_mode | stat.S_IXUSR)
    return executable


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=pathlib.Path, required=True)
    args = parser.parse_args()
    lock = json.loads((ROOT / 'toolchain.lock.json').read_text(encoding='utf-8'))
    key = platform.system().lower()
    if key not in lock['platforms']:
        raise ValueError('Only Linux/Windows x86_64 CI is configured')
    metadata = lock['platforms'][key]
    url = 'https://github.com/godotengine/godot-builds/releases/download/' + lock['release_tag'] + '/' + metadata['archive']
    with tempfile.TemporaryDirectory(prefix='ruleweaver-godot-') as folder:
        archive = pathlib.Path(folder) / 'engine.zip'
        request = urllib.request.Request(url, headers={'User-Agent': 'Ruleweaver-CI'})
        with urllib.request.urlopen(request, timeout=60) as response, archive.open('wb') as out:
            count = 0
            while chunk := response.read(1024 * 1024):
                count += len(chunk)
                if count > MAX_ARCHIVE:
                    raise ValueError('Download exceeds budget')
                out.write(chunk)
        executable = verify_and_extract(archive, args.destination, metadata)
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as env_file:
            env_file.write('GODOT_BIN=' + str(executable) + '\n')
    print(json.dumps({'executable': str(executable), 'version': lock['godot_version'],
                      'archive_sha256': metadata['sha256']}))
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
