"""tools/stage.sh ships exactly the app's files. Run from the repo root:
python3 -m unittest discover -s tests -p 'test_*.py'"""
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULES = ["main.lua", "theme.lua", "highscores.lua", "sfx.lua", "title.lua", "name_entry.lua", "pad.lua"]


class StageTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name) / "repo"
        (self.repo / "tools").mkdir(parents=True)
        (self.repo / "assets").mkdir()
        shutil.copy(ROOT / "tools/stage.sh", self.repo / "tools/stage.sh")
        for name in ["app.json", "icon.png"] + MODULES:
            shutil.copy(ROOT / name, self.repo / name)
        (self.repo / "assets/placeholder.txt").write_text("x")

    def tearDown(self):
        self.tmp.cleanup()

    def stage(self):
        out = Path(self.tmp.name) / "out"
        result = subprocess.run(["sh", str(self.repo / "tools/stage.sh"), str(out)],
                                capture_output=True, text=True)
        return result, out

    def test_a_stray_lua_file_is_not_shipped(self):
        (self.repo / "scratch.lua").write_text("-- scratch")
        result, out = self.stage()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((out / "scratch.lua").exists())
        for name in MODULES:
            self.assertTrue((out / name).exists(), name)

    def test_a_missing_module_fails_loudly(self):
        (self.repo / "sfx.lua").unlink()
        result, _ = self.stage()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sfx.lua", result.stderr)


if __name__ == "__main__":
    unittest.main()
