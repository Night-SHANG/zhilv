"""仅验证下载文件完整性与解包边界；不以假文件证明 Godot 可运行。"""
import hashlib
import importlib.util
import pathlib
import tempfile
import unittest
import zipfile
ROOT = pathlib.Path(__file__).resolve().parents[1]

class ToolchainTests(unittest.TestCase):
    def extract(self, archive, target, metadata):
        script = ROOT/'tools/install_godot.py'
        self.assertTrue(script.exists(), 'installer not implemented')
        spec = importlib.util.spec_from_file_location('installer', script)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module.verify_and_extract(archive, target, metadata)

    def test_expected_entry_is_extracted(self):
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d); archive = root/'test.zip'
            with zipfile.ZipFile(archive, 'w') as z: z.writestr('engine', b'NOT A REAL ENGINE')
            meta = {'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'executable': 'engine'}
            result = self.extract(archive, root/'out', meta)
            self.assertEqual(result.read_bytes(), b'NOT A REAL ENGINE')

    def test_wrong_digest_rejects_before_writing(self):
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d); archive = root/'test.zip'; archive.write_bytes(b'bad')
            with self.assertRaises(ValueError):
                self.extract(archive, root/'out', {'sha256':'0'*64, 'executable':'engine'})
            self.assertFalse((root/'out').exists())

    def test_parent_escape_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d); archive = root/'test.zip'
            with zipfile.ZipFile(archive, 'w') as z:
                z.writestr('../escape', b'x'); z.writestr('engine', b'x')
            meta = {'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'executable': 'engine'}
            with self.assertRaises(ValueError): self.extract(archive, root/'out', meta)
            self.assertFalse((root/'escape').exists())

    def test_missing_executable_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d); archive = root/'test.zip'
            with zipfile.ZipFile(archive, 'w') as z: z.writestr('other', b'x')
            meta = {'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'executable': 'engine'}
            with self.assertRaises(ValueError): self.extract(archive, root/'out', meta)
