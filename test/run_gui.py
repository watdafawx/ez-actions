"""EZ Actions in a real game client through the fse launcher (fse/dist): the radial opened by its key (input.trigger), the mouse
and the held key faked (std.mock), every kind of slice run. Screenshots: test/run/script-output/ez-gui-*.png.
The editor: fse-std's layout (rail, dock, gear, questions), or with --plain the game's styles without fse-std.
Then the editor at fse-std's window scale 150 % (on the screen?); --scale 2: the game's GUI at 200 %.
The window closes itself when done. Close your own game first."""
import ctypes, json, os, shutil, subprocess, sys, time
from ctypes import wintypes
from pathlib import Path

HERE = Path(__file__).resolve().parent
MOD = HERE.parent
sys.path.insert(0, str(HERE))
from factorio_paths import run_dir, watch_game  # noqa: E402
RUN = run_dir(HERE / "run")
MODS = RUN / "ez-mods-gui"
OUT = RUN / "script-output"


def game_gui_scale(config, scale):
    """--scale N: the game's GUI scale in the run's config.ini (manual, N = 2 for 200 %); without it, automatic again
    (the config is kept between runs)"""
    lines = config.read_text(encoding="utf-8").splitlines() if config.exists() else []
    lines = [l for l in lines if not l.startswith(("ui-scale-mode=", "custom-ui-scale="))]
    if scale:
        add = ["ui-scale-mode=manual-pixels", f"custom-ui-scale={scale}"]
        if "[interface]" in lines:
            i = lines.index("[interface]") + 1
            lines[i:i] = add
        else:
            lines += ["[interface]"] + add
    config.write_text("\n".join(lines) + "\n", encoding="utf-8")


SCALE = sys.argv[sys.argv.index("--scale") + 1] if "--scale" in sys.argv else None
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
            r = wintypes.RECT()
            u32.GetClientRect(h, ctypes.byref(r))
            found.append((r.right * r.bottom, h))
        return True
    u32.EnumWindows(each, 0)
    # (the biggest: fse's own windows, an overlay or the hub panel, belong to the process too)
    return max(found)[1] if found else None


# (a second game can't start while the player's own runs: its --create fails and the player gets an error window.
# Only a game with a window counts: other tests run headless games all the time)
if game_window():
    sys.exit("Factorio is running: close it first")
shutil.rmtree(MODS, ignore_errors=True)
MODS.mkdir(parents=True)
shutil.copytree(MOD, MODS / "ez-actions", ignore=shutil.ignore_patterns("test", ".git"))
shutil.copytree(HERE / "ez-guitest", MODS / "ez-guitest")
# (fse-std: drag & drop and the window layout in the editor; --plain: without it, the editor in the game's styles)
PLAIN = "--plain" in sys.argv
if not PLAIN:
    shutil.copytree(MOD.parents[1] / "fse" / "mods" / "fse-std", MODS / "fse-std")
names = ["base", "elevated-rails", "quality", "space-age"] + ([] if PLAIN else ["fse-std"]) + ["ez-actions", "ez-guitest"]
(MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in names]}))
for f in OUT.glob("ez-gui*"):  # (ready, done, results, screenshots)
    f.unlink()
save = RUN / "ez-gui.zip"
save.unlink(missing_ok=True)
# (the scale in a config of its own; the shared config.ini never keeps one, an older run's removed)
game_gui_scale(RUN / "config.ini", None)
CONFIG = RUN / "config-gui.ini"
shutil.copyfile(RUN / "config.ini", CONFIG)
game_gui_scale(CONFIG, SCALE)
launcher = Path(os.environ.get("FSE_DIR", MOD.parents[1] / "fse" / "dist")) / "fse-launcher.exe"
common = [str(launcher), "--config", str(CONFIG), "--mod-directory", str(MODS)]
subprocess.run(common + ["--create", str(save)], capture_output=True)


game = watch_game(common + ["--load-game", str(save.resolve())])
start = time.time()
while time.time() - start < 150 and not (OUT / "ez-gui-done.txt").exists() and game.poll() is None:
    # (until the test mod is in game, then never again: focusing mid-press would reset the held modifiers)
    ready = OUT / "ez-gui-ready.txt"
    h = game_window() if not ready.exists() or time.time() - ready.stat().st_mtime < 1.5 else None
    if h:  # (posted keys count only while the game thinks it has the focus)
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
