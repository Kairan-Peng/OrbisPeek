import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("validate_installed", ROOT / "scripts/validate-installed.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RegistrationParsingTests(unittest.TestCase):
    def test_preserves_election_states_multiple_copies_and_spaces_in_paths(self):
        identifier = MODULE.DEFAULT_EXTENSION_ID
        sample = "\n".join([
            f"+    {identifier}(0.1.1)\tABC-123\t2026-11-10 14:47:57 +0000\t/Applications/Quicklook.app/Contents/PlugIns/QuicklookPreview.appex",
            f"-    {identifier}(0.1.0)\tDEF-456\t2026-11-09 14:47:57 +0000\t/Users/test/Local Builds/Quicklook.app/Contents/PlugIns/QuicklookPreview.appex",
            f"     {identifier}(0.1.1)\tGHI-789\t2026-11-10 14:47:57 +0000\t/Volumes/Quicklook/Quicklook.app/Contents/PlugIns/QuicklookPreview.appex",
            " (3 plug-ins)",
        ])
        records = MODULE.parse_registrations(sample, identifier)
        self.assertEqual([r["election"] for r in records], ["use", "ignore", "default"])
        self.assertEqual(records[1]["path"], "/Users/test/Local Builds/Quicklook.app/Contents/PlugIns/QuicklookPreview.appex")
        self.assertEqual(records[0]["version"], "0.1.1")

    def test_unknown_markers_and_missing_path_remain_unknown_evidence(self):
        identifier = MODULE.DEFAULT_EXTENSION_ID
        records = MODULE.parse_registrations(f"!    {identifier}(0.1.0)\n (1 plug-in)", identifier)
        self.assertEqual(records[0]["election"], "unknown")
        self.assertIsNone(records[0]["path"])
        self.assertEqual(MODULE.parse_registrations("No matching plug-ins\n", identifier), [])

    def test_path_prefix_does_not_treat_backup_as_installed_app(self):
        app = Path("/Applications/Quicklook.app")
        self.assertTrue(MODULE.inside(app / "Contents/PlugIns/QuicklookPreview.appex", app))
        self.assertFalse(MODULE.inside(Path("/Applications/Quicklook.app-backup/Contents/PlugIns/QuicklookPreview.appex"), app))


if __name__ == "__main__":
    unittest.main()
