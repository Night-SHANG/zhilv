"""测试日志判定，不模拟游戏行为。"""
import importlib.util
import pathlib
import sys
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))

class NativeReportTests(unittest.TestCase):
    def read(self, rc, text, marker='LIFECYCLE_TEST_RESULT'):
        path = ROOT / 'tools/native_gate.py'
        self.assertTrue(path.exists(), 'native_gate.py 尚未实现')
        spec = importlib.util.spec_from_file_location('native_gate', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module.parse_result(rc, text, marker)

    def test_success_requires_positive_complete_count(self):
        self.assertEqual(self.read(0, 'LIFECYCLE_TEST_RESULT: 20 passed; 0 failed')['status'], 'PASS')
    def test_empty_stdout_is_not_success(self):
        self.assertEqual(self.read(0, '')['status'], 'FAIL')
    def test_zero_tests_is_not_success(self):
        self.assertEqual(self.read(0, 'LIFECYCLE_TEST_RESULT: 0 passed; 0 failed')['status'], 'FAIL')
    def test_script_error_overrides_success_marker(self):
        self.assertEqual(self.read(0, 'SCRIPT ERROR: bad\nLIFECYCLE_TEST_RESULT: 20 passed; 0 failed')['status'], 'FAIL')
    def test_failed_count_overrides_process_zero(self):
        self.assertEqual(self.read(0, 'LIFECYCLE_TEST_RESULT: 20 passed; 1 failed')['status'], 'FAIL')
    def test_nonzero_exit_overrides_marker(self):
        self.assertEqual(self.read(1, 'LIFECYCLE_TEST_RESULT: 20 passed; 0 failed')['status'], 'FAIL')
    def test_wrong_suite_marker_is_not_success(self):
        self.assertEqual(self.read(0, 'VENDOR_TEST_RESULT: 8 passed; 0 failed')['status'], 'FAIL')
    def test_multiple_markers_are_rejected(self):
        self.assertEqual(self.read(0, 'LIFECYCLE_TEST_RESULT: 1 passed; 0 failed\nLIFECYCLE_TEST_RESULT: 2 passed; 0 failed')['status'], 'FAIL')
