"""Release bundle discovery must work across the application rename."""

from pathlib import Path
import runpy
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
PACKAGED_APP = runpy.run_path(str(ROOT / "scripts/verify-release"))["packaged_app"]


class PackagedAppTests(unittest.TestCase):
    def test_accepts_current_and_legacy_bundle_names(self):
        for name in ("OrbisPeek.app", "Quicklook.app"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                app = directory / name
                app.mkdir()
                (directory / "Applications").symlink_to("/Applications")
                self.assertEqual(PACKAGED_APP(directory), app)

    def test_rejects_missing_or_ambiguous_bundles(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with self.assertRaises(RuntimeError):
                PACKAGED_APP(directory)
            (directory / "OrbisPeek.app").mkdir()
            (directory / "Quicklook.app").mkdir()
            with self.assertRaises(RuntimeError):
                PACKAGED_APP(directory)


if __name__ == "__main__":
    unittest.main()
