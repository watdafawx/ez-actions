# EZ Actions

A Factorio 2.0 port of the Minecraft mod [EZ Actions](https://github.com/z2six/EZActions) by z2six: a radial menu
for anything you do often. Hold **U**, point the mouse at a slice, let go.

## What a slice can do

- **Key action**: fires one of
  - a **game control or mod keybind**: any entry of Settings → Controls (the game's own and every mod's custom
    inputs), picked from the list, pressed with whatever key the player bound to it;
  - a **shortcut** from the shortcut bar: spawn items (blueprint, planners, remotes), alt mode, personal roboport,
    movement bonus, undo/redo/copy/paste, and other mods' Lua shortcuts;
  - a **direct hotkey**: a key (with Ctrl/Shift/Alt) recorded in the editor.

  The control and shortcut lists show each entry's icon (a control gets the icon of the shortcut that fires it), its
  key and its mod. Type to filter by internal name; `@word` filters by mod (`@core` for the game's own controls), e.g.
  `@space toggle`. A new slice takes the picked entry's icon unless you choose one.

  **Toggle** holds the key down on one use and lets go on the next.
- **Command**: one or more console lines (a leading `/` is optional). With a delay (ticks) they go out one after
  another; **cycle** sends one line per use, in turn. A new run replaces lines still waiting.
- **Loadout** (EZ Actions' Item Equip): armor, three guns, three ammo slots and the item in your hand. **Record what
  I wear now** fills it in; running it swaps each item in from your inventory (same item and quality, the fullest
  stack), skips slots already right or left empty, and does what it can.
- **Bundle**: a page of more slices. Bundles nest, can be **hidden from the main radial**, and can get **their own
  key** (ten slots, *EZ Actions: bundle key N* under Settings → Controls).

## Using it

- **U** opens the radial at the mouse (kept on screen near edges). With FSE in single player the mouse direction
  picks the slice and letting go of U runs it, so you never need to touch a button; with the
  *Let go of the key to choose* setting off, without FSE, or in multiplayer, hover a slice and click it or press U
  again. A bundle opens in place and then waits for a click. Right-click, Escape or the arrow in the middle goes back
  out; at the top they close.
- You keep walking while it is open.
- **Shift+U** or the shortcut-bar button opens the **editor**: add, edit, remove, reorder (▲▼), filter (Ctrl+F),
  Delete removes the selected entry. Click selects, click again edits, right-click opens a bundle. With an entry
  selected, the arrow beside a bundle (or a *Back to…* row) moves it there. Locked entries (set through JSON or the
  API) can't be removed in game.
- **Export** puts the whole menu as JSON on the clipboard (with FSE) and in a box; **Import** reads the clipboard (or
  a pasted box) and adds to the current page, replacing entries with the same id; **Replace all** swaps the menu.
  EZ Actions' own field names (`hideFromMainRadial`, `delayTicks`, `cycleCommands`, ...) are read too.
- **Preview** opens the radial looping its open animation, to tune the look.
- Look and feel are per-player mod settings: open animation (wipe / grow, direction, duration), hover style
  (light, grow, both), hover label, deadzone, radius, slice size, growing the ring past N slices, slice style, label
  colour.

Each player has their own menu (it lives in the save).

## What needs FSE

Factorio's Lua can't press keys, run console commands or click another mod's shortcut. With the
[FSE](https://github.com/watdafawx/fse) loader (0.14.0+) all of that works; without it you still get the radial,
the editor, loadouts and the shortcuts the mod can do itself (spawned items, alt mode, roboport, movement bonus).

New FSE pieces this mod added: `std.press` / `std.key_info` / held keys in `std.input`, `input.controls` /
`input.trigger`, and `native.send_action("LuaShortcut", name)`.

## Differences from the Minecraft mod

- The ring is made of Factorio slot buttons, not a drawn ring, so ring/hover/border colours and the
  segmented/outline/glass designs became a choice of button style; *fade* opening became *grow*.
- Icons come from the game's signal picker (items, fluids, virtual signals, entities, recipes, ...); there is no
  custom icon folder (Factorio loads images only at startup).
- Bundle keys are ten fixed key slots (Factorio can't add keybinds at run time); EZ Actions needed a restart instead.
- Config lives in Mod settings rather than its own screen.

## API

`remote.call("ezactions", fn, player_index, ...)`. Paths are lists of bundle titles (or ids), `{}` is the root.

| | |
|---|---|
| read | `list(pi, path)`, `find_by_id(pi, id)`, `exists_path(pi, path)` |
| write | `add_action(pi, path, title, note, icon, action, locked)`, `add_bundle(pi, path, title, note, icon, hide, keybind, locked)`, `ensure_bundles(pi, path)`, `move_within(pi, path, from, to)`, `move_to(pi, id, path)`, `remove_by_id(pi, id, ignore_lock)`, `update_meta(pi, id, title, note, icon)`, `replace_action(pi, id, action)`, `set_bundle_flags(pi, id, hide, keybind)`, `set_locked(pi, id, locked)`, `upsert_json(pi, path, json)` |
| JSON | `export_all_json(pi)`, `export_bundle_json(pi, path)`, `import_into(pi, path, json)`, `replace_all(pi, json)`, `validate(pi, json)` |
| input | `deliver(pi, action)`, `enqueue_commands(pi, lines, delay)` |
| screens | `open_editor(pi, opts?)` (`{add = "KEY", source, filter}` opens a new key action filtered), `open_radial(pi)`, `open_radial_at_bundle(pi, title_or_id)`, `open_temporary_radial(pi, json, style)`, `preview(pi)`, `close_radial(pi)`, `radial_state(pi)` |
| events | `events()` → `{menu_changed, imported}` ids for `script.on_event` |

Actions: `{type = "KEY", source = "control"|"shortcut"|"hotkey", name = "toggle-map", key = {vk, mods, name}, toggle}`,
`{type = "COMMAND", command = "line\nline", delay, cycle}`, `{type = "EQUIP", slots = {armor = {name, quality}, gun1, ..., hand}}`.
A temporary radial's `style` takes this mod's setting names or EZ Actions' (`openStyle`, `hoverStyle`, `deadzone`,
`baseOuterRadius`, `textColor` as ARGB, ...).

## Tests

`test\run.py`: the menu model and API, headless. `test\run_gui.py`: a real game window through the FSE launcher
(`fse\dist`, or `FSE_DIR`): U posted to the game, the mouse and held key faked with `std.mock`, every kind of slice
run; screenshots in `test\run\script-output`. Close your own game first.
