"""Headless check of EZ Actions' menu model and remote API."""
import json, shutil, subprocess, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from factorio_paths import PATHS, run_dir  # noqa: E402
RUN = run_dir(HERE / "run")
MODS = RUN / "ez-mods"
shutil.rmtree(MODS, ignore_errors=True)
MODS.mkdir(parents=True)
shutil.copytree(HERE.parent, MODS / "ez-actions", ignore=shutil.ignore_patterns("test"))
shutil.copytree(HERE / "ez-test", MODS / "ez-test")
names = ["base", "ez-actions", "ez-test"]
(MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in names]}))
out = RUN / "script-output" / "ez-test.txt"
out.unlink(missing_ok=True)
save = RUN / "ez-test.zip"
save.unlink(missing_ok=True)
common = [str(PATHS["factorio_exe"]), "--config", str(RUN / "config.ini"), "--mod-directory", str(MODS)]
for args in (["--create", str(save)], ["--benchmark", str(save), "--benchmark-ticks", "5", "--disable-audio"]):
    p = subprocess.run(common + args, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode or "non-recoverable" in p.stdout or "Error" in p.stdout:
        print(p.stdout[-2500:]); sys.exit(1)
text = out.read_text() if out.exists() else "no result"
print(text)
sys.exit(0 if "FAIL" not in text and "PASS" in text else 1)
