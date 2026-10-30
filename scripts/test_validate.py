import importlib.util
import hashlib
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("validate.py")
SPEC = importlib.util.spec_from_file_location("validate", MODULE_PATH)
VALIDATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATE)


class ValidationStatusTests(unittest.TestCase):
    def test_pass_requires_zero_exit_and_final_marker(self):
        self.assertEqual(VALIDATE.case_status(0, False, True), "PASS")
        self.assertEqual(VALIDATE.case_status(1, False, True), "FAIL")
        self.assertEqual(VALIDATE.case_status(0, False, False), "FAIL")

    def test_timeout_has_its_own_status(self):
        self.assertEqual(VALIDATE.case_status(124, True, False), "TIMEOUT")

    def test_snapshot_digest_requires_valid_manifest_content(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.bend"
            source.write_bytes(b"source")
            entry = hashlib.sha256(b"source").hexdigest() + "  source.bend\n"
            (root / "MANIFEST.sha256").write_text(entry)
            self.assertEqual(
                VALIDATE.source_digest(root),
                "manifest-" + hashlib.sha256(entry.encode()).hexdigest(),
            )
            source.write_bytes(b"changed")
            with self.assertRaises(ValueError):
                VALIDATE.source_digest(root)

    def test_snapshot_digest_rejects_parent_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "MANIFEST.sha256").write_text("0" * 64 + "  ../source.bend\n")
            with self.assertRaises(ValueError):
                VALIDATE.source_digest(root)


if __name__ == "__main__":
    unittest.main()
