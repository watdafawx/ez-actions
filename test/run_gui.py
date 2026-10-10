"""EZ Actions in a real game client through the fse launcher (fse/dist): the radial opened with a posted U, the mouse
and the held key faked (std.mock), every kind of slice run. Screenshots: test/run/script-output/ez-gui-*.png.
The window closes itself when done. Close your own game first."""
import ctypes, json, os, shutil, subprocess, sys, time
from ctypes import wintypes
from pathlib import Path

HERE = Path(__file__).resolve().parent
MOD = HERE.parent
sys.path.insert(0, str(HERE))
from factorio_paths import run_dir  # noqa: E402
RUN = run_dir(HERE / "run")
MODS = RUN / "ez-mods-gui"
OUT = RUN / "script-output"
shutil.rmtree(MODS, ignore_errors=True)
MODS.mkdir(parents=True)
shutil.copytree(MOD, MODS / "ez-actions", ignore=shutil.ignore_patterns("test", ".git"))
shutil.copytree(HERE / "ez-guitest", MODS / "ez-guitest")
names = ["base", "elevated-rails", "quality", "space-age", "ez-actions", "ez-guitest"]
(MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in names]}))
for f in OUT.glob("ez-gui*"):
    f.unlink()
save = RUN / "ez-gui.zip"
save.unlink(missing_ok=True)
launcher = Path(os.environ.get("FSE_DIR", MOD.parents[1] / "fse" / "dist")) / "fse-launcher.exe"
common = [str(launcher), "--config", str(RUN / "config.ini"), "--mod-directory", str(MODS)]
subprocess.run(common + ["--create", str(save)], capture_output=True)
u32 = ctypes.windll.user32


def game_window():
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq factorio.exe", "/FO", "CSV", "/NH"], capture_output=True,
                         text=True).stdout
    pids = {int(l.split('","')[1]) for l in out.splitlines() if l.startswith('"factorio')}
    found = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def each(h, _):
        p = wintypes.DWORD()
        u32.GetWindowThreadProcessId(h, ctypes.byref(p))
        if p.value in pids and u32.IsWindowVisible(h) and u32.GetWindowTextLengthW(h) > 0:
            found.append(h)
        return True
    u32.EnumWindows(each, 0)
    return found[0] if found else None


game = subprocess.Popen(common + ["--load-game", str(save.resolve())], stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL)
start = time.time()
focused = 0
while time.time() - start < 150 and not (OUT / "ez-gui-done.txt").exists() and game.poll() is None:
    h = game_window() if focused < 3 else None
    if h:
        focused += 1  # (a few times while it loads; focusing again mid-press would reset the held modifiers)  # (posted keys count only while the game thinks it has the focus)
        u32.PostMessageW(h, 0x0006, 1, 0)  # WM_ACTIVATE
        u32.PostMessageW(h, 0x0007, 0, 0)  # WM_SETFOCUS
    time.sleep(0.5)
time.sleep(2)
subprocess.run(["taskkill", "/F", "/T", "/PID", str(game.pid)], capture_output=True)
log = (RUN / "factorio-current.log").read_text(encoding="utf-8", errors="replace").splitlines()
errors = [l for l in log if "Error" in l or "non-recoverable" in l]
print("screenshots:", sorted(f.name for f in OUT.glob("ez-gui-*.png")))
text = (OUT / "ez-gui.txt").read_text() if (OUT / "ez-gui.txt").exists() else "no result"
print(text)
print("errors:", "\n".join(errors[-10:]) or "none")
sys.exit(0 if "FAIL" not in text and "PASS" in text and not errors else 1)
