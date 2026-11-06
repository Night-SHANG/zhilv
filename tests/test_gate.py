import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]

class NativeGateTests(unittest.TestCase):
    def gate(self, executable):
        with tempfile.TemporaryDirectory() as t:
            p = subprocess.run([sys.executable, str(ROOT/'tools/run_checks.py'),
                '--native-only','--godot', str(executable),'--reports',t],
                text=True,capture_output=True,timeout=15)
            self.assertEqual(p.returncode, 2, p.stdout+p.stderr)
            report = json.loads((pathlib.Path(t)/'verification.json').read_text())
            self.assertEqual(report['native']['status'], 'BLOCKED')
            self.assertEqual(report['overall'], 'BLOCKED')

    def test_missing_godot_fails_closed(self):
        self.gate(ROOT/'definitely_missing_engine')

    def test_non_godot_executable_not_accepted(self):
        self.gate(sys.executable)
