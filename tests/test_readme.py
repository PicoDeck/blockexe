"""The README's Build section names every file and folder the app ships. Run from the repo root:
python3 -m unittest discover -s tests -p 'test_*.py'"""
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class ReadmeTest(unittest.TestCase):
    def test_build_section_names_every_shipped_file(self):
        readme = (ROOT / "README.md").read_text()
        build = readme[readme.index("## Build"):readme.index("## Release")]
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(["sh", str(ROOT / "tools/stage.sh"), tmp], check=True, capture_output=True)
            shipped = sorted(p.name + ("/" if p.is_dir() else "") for p in Path(tmp).iterdir())
        missing = [name for name in shipped if f"`{name}`" not in build]
        self.assertEqual(missing, [], "README Build section should name these shipped files")


if __name__ == "__main__":
    unittest.main()
