"""开发运行包只携带必要工程、官方引擎及许可，不携带测试、缓存或字体。"""
import importlib.util
import pathlib
import tempfile
import unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class DesktopPackTests(unittest.TestCase):
 def api(self):
  path=ROOT/'tools/package_desktop.py'
  self.assertTrue(path.exists(),'desktop staging not implemented')
  spec=importlib.util.spec_from_file_location('desktop_pack',path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
 def test_stages_only_production_game(self):
  with tempfile.TemporaryDirectory() as d:
   stage=pathlib.Path(d)/'bundle';self.api().stage_project(ROOT,stage)
   self.assertTrue((stage/'game/presentation/main.tscn').is_file())
   self.assertFalse((stage/'game/tests').exists());self.assertFalse((stage/'game/scenarios').exists());self.assertFalse((stage/'game/.godot').exists())
   self.assertTrue((stage/'game/vendor/coheronia/LICENSE').is_file())
 def test_refuses_existing_output_directory(self):
  with tempfile.TemporaryDirectory() as d:
   with self.assertRaises(ValueError):self.api().stage_project(ROOT,pathlib.Path(d))
 def test_no_font_files_or_test_references(self):
  with tempfile.TemporaryDirectory() as d:
   stage=pathlib.Path(d)/'bundle';self.api().stage_project(ROOT,stage)
   for p in stage.rglob('*'):
    if p.is_file():
     self.assertNotIn(p.suffix.lower(),['.ttf','.otf','.ttc','.woff','.woff2'])
     if p.suffix in ['.gd','.tscn']:self.assertNotIn('res://tests/',p.read_text(encoding='utf-8'))
 def test_manifest_detects_modified_bytes(self):
  with tempfile.TemporaryDirectory() as d:
   stage=pathlib.Path(d)/'bundle';m=self.api();m.stage_project(ROOT,stage);manifest=m.file_manifest(stage)
   self.assertTrue(m.verify_manifest(stage,manifest))
   (stage/'game/project.godot').write_text('broken')
   self.assertFalse(m.verify_manifest(stage,manifest))
 def test_manifest_rejects_missing_file(self):
  with tempfile.TemporaryDirectory() as d:
   stage=pathlib.Path(d)/'bundle';m=self.api();m.stage_project(ROOT,stage);manifest=m.file_manifest(stage)
   (stage/'game/project.godot').unlink();self.assertFalse(m.verify_manifest(stage,manifest))
if __name__=='__main__':unittest.main()
