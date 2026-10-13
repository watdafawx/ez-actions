-- real client through the fse launcher: the radial opened by its key (input.trigger), the mouse and the held key faked
-- with std.mock, each kind of slice run by letting go; the editor at fse-std's window scale 150 %; screenshots to
-- script-output/ez-gui-*.png
local out, seen = {}, {}
local function check(name, ok, detail)
  out[#out + 1] = (ok and "PASS " or "FAIL ") .. name .. (detail ~= nil and (" :: " .. tostring(detail)) or "")
end
local function R(fn, ...) return remote.call("ezactions", fn, ...) end
local function J(t) return helpers.table_to_json(t) end
local function mock(t) native.call("std", "mock", t and J(t) or "") end
local function shot(p, file)
  game.take_screenshot({player = p, show_gui = true, path = file, resolution = {p.display_resolution.width, p.display_resolution.height}, zoom = p.zoom})
end

script.on_init(function()
  if remote.interfaces.freeplay then
    remote.call("freeplay", "set_skip_intro", true)
    remote.call("freeplay", "set_disable_crashsite", true)
  end
end)
script.on_event("ez-guitest-probe", function(e) seen[#seen + 1] = "probe@" .. e.tick end)
script.on_event(defines.events.on_lua_shortcut, function(e)
  if e.prototype_name == "ez-guitest-sc" then seen[#seen + 1] = "sc@" .. e.tick end
end)
commands.add_command("eztest", "", function(c) seen[#seen + 1] = "cmd:" .. (c.parameter or "") end)

local function has(prefix)
  for _, s in ipairs(seen) do if s:sub(1, #prefix) == prefix then return true end end
  return false
end

-- the slices on the root page, in order
local ROOT = {"blueprint", "loadout", "control", "hotkey", "command", "lua", "bundle"}
local steps = {}
local function slice(name) for i, n in ipairs(ROOT) do if n == name then return i end end end

-- one pick: hold U (faked), press it, point at slice i of n, let go
local function pick(t0, i, check_fn, label)
  steps[t0] = function(p)
    -- (whatever the radial is bound to: the player's own controls reach test games through Steam)
    mock({keys = {85}})
    local ok, err = native.call("input", "trigger", J({control = "ezactions-radial", hold_ms = 30}))
    if not ok then check(label .. ": trigger", false, err) end
  end
  steps[t0 + 10] = function(p)
    local s = R("radial_state", 1)
    check(label .. ": radial opened, holding", s and s.holding, s and J(s))
    if not s then return end
    local a = (i - 1) / s.count * 2 * math.pi
    mock({keys = {85}, x = math.floor(s.x + math.sin(a) * 90), y = math.floor(s.y - math.cos(a) * 90)})
  end
  steps[t0 + 14] = function(p)
    local s = R("radial_state", 1)
    check(label .. ": slice " .. i .. " pointed", s and s.selected == i, s and s.selected)
    if label == "blueprint" then shot(p, "ez-gui-1-radial.png") end
    mock({keys = {}})
  end
  steps[t0 + 30] = function(p)
    check(label .. ": radial closed", R("radial_state", 1) == nil or label == "bundle")
    check(label .. ": ran", check_fn(p))
  end
end

local function setup(p)
  local main = p.get_main_inventory()
  main.insert({name = "modular-armor"})
  main.insert({name = "submachine-gun"})
  main.insert({name = "firearm-magazine", count = 50})
  R("replace_all", 1, "[]")
  local function add(title, action, icon) return R("add_action", 1, {}, title, "", icon, action, false) end
  add("Blueprint", {type = "KEY", source = "shortcut", name = "give-blueprint"}, "item/blueprint")
  add("Loadout", {type = "EQUIP", slots = {armor = {name = "modular-armor"}, gun1 = {name = "submachine-gun"}}}, "item/modular-armor")
  add("Probe (control)", {type = "KEY", source = "control", name = "ez-guitest-probe"}, "item/radar")
  add("Probe (hotkey)", {type = "KEY", source = "hotkey", key = {vk = 75, mods = {"shift", "alt"}, name = "K"}}, "item/lamp")
  add("Command", {type = "COMMAND", command = "eztest one\n/eztest two", delay = 3}, "virtual-signal/signal-C")
  add("Lua shortcut", {type = "KEY", source = "shortcut", name = "ez-guitest-sc"}, "item/iron-chest")
  R("add_bundle", 1, {}, "Sub", "a bundle", "item/steel-chest", false, 2, false)
  R("add_action", 1, {"Sub"}, "Sub command", "", nil, {type = "COMMAND", command = "eztest sub"}, false)
  R("add_action", 1, {"Sub"}, "Cycle", "", nil, {type = "COMMAND", command = "eztest c1\neztest c2", cycle = true}, false)
end

steps[30] = setup
pick(60, slice("blueprint"), function(p) return p.cursor_stack.valid_for_read and p.cursor_stack.name == "blueprint" end, "blueprint")
steps[95] = function(p) p.clear_cursor() end
pick(100, slice("loadout"), function(p)
  local ai, gi = p.get_inventory(defines.inventory.character_armor), p.get_inventory(defines.inventory.character_guns)
  if not (ai and gi) then return false end  -- (no character's inventories: a FAIL, not a crash)
  local armor, gun = ai[1], gi[1]
  return armor.valid_for_read and armor.name == "modular-armor" and gun.valid_for_read and gun.name == "submachine-gun"
end, "loadout")
pick(140, slice("control"), function() return has("probe@") end, "control")
steps[175] = function() seen = {} end
pick(180, slice("hotkey"), function() return has("probe@") end, "hotkey")
pick(220, slice("command"), function() return has("cmd:one") and has("cmd:two") end, "command")
pick(260, slice("lua"), function() return has("sc@") end, "lua shortcut")
pick(300, slice("bundle"), function()
  local s = R("radial_state", 1)
  return s and s.depth == 2 and s.count == 2 and not s.holding
end, "bundle")
steps[335] = function(p) shot(p, "ez-gui-2-bundle.png") end
steps[337] = function(p) R("close_radial", 1) end
steps[340] = function(p)
  R("open_editor", 1)
end
-- the editor: fse-std's layout (Add on a rail, the tools on a dock, the gear's settings), or the game's styles without it
local D = 100  -- (the steps after the editor's)
local fstd = script.active_mods["fse-std"] ~= nil
local function E(what, arg) return R("_editor", 1, what, arg) end
local function frames(s)
  local t = {}
  for _, n in ipairs(s.frames or {}) do t[n] = true end
  return t
end
steps[345] = function(p)
  check("editor open", p.gui.screen.ezactions_editor ~= nil)
  local drag = 0
  local function walk(el)
    if el.tags.fstd_drag then drag = drag + 1 end
    for _, c in pairs(el.children) do walk(c) end
  end
  walk(p.gui.screen.ezactions_editor)
  if fstd then check("editor rows draggable (fse-std)", drag == 7, drag) end
  local s = E("state")
  check("layout: fse-std's when it's there", s.layouts == fstd and s.docked == fstd, serpent.line(s))
  local f = frames(s)
  if fstd then
    check("Add on a tools rail (right), tools on a dock", f.ezactions_editor__right and f.ezactions_editor__bottom
          and not f.ezactions_editor__left, serpent.line(s.frames))
  end
  check("nothing selected: Edit, Remove, Up, Down off",
        s.tools.edit == false and s.tools.remove == false and s.tools.up == false and s.tools.down == false
        and s.tools.import == true and s.tools.preview == true, serpent.line(s.tools))
  check("breadcrumb: All actions", type(s.crumb) == "table" and s.crumb[1] == "ezactions.all-actions", serpent.line(s.crumb))
  shot(p, "ez-gui-3-editor.png")
end
steps[370] = function(p)
  local s = E("select", "Command")
  check("selected: Edit, Remove, Up, Down on", s.sel == "Command" and s.tools.edit and s.tools.remove and s.tools.up
        and s.tools.down, serpent.line(s))
  s = E("select", "Blueprint")
  check("first entry: Up off", s.tools.up == false and s.tools.down == true, serpent.line(s.tools))
  s = E("select", "Sub")
  check("last entry: Down off", s.tools.down == false and s.tools.up == true, serpent.line(s.tools))
  check("type badge only where the title doesn't say it", s.badges.Loadout == false and s.badges.Command == false
        and s.badges["Probe (control)"] == true and s.badges.Sub == true, serpent.line(s.badges))
  s = E("remove")
  check("Remove asks first (nothing gone yet)", #R("list", 1, {}) == 7, #R("list", 1, {}))
  if fstd then check("fse-std's question", s.asking, serpent.line(s)) end
end
steps[372] = function(p) if fstd then shot(p, "ez-gui-3a-remove.png") end end
steps[395] = function(p)
  if fstd then
    p.opened = nil  -- (Esc: the question closes, as a no)
    check("Esc = no: still there", #R("list", 1, {}) == 7 and not E("state").asking)
    E("remove")
    check("asked again", p.gui.screen.fstd_confirm_ezactions_remove ~= nil)
    E("answer_yes")  -- (its Remove button, as fse-std answers it)
  else
    E("remove")  -- (the second click removes)
  end
  check("bundle removed with its entries", #R("list", 1, {}) == 6 and not R("exists_path", 1, {"Sub"}),
        serpent.line(R("list", 1, {})))
  check("removed: tools off again", E("state").tools.edit == false)
end
steps[397] = function(p)
  if not fstd then return end
  local s = E("settings")
  check("gear: settings panel", s.open and frames(s).ezactions_editor__menu, serpent.line(s))
end
steps[399] = function(p) if fstd then shot(p, "ez-gui-3b-settings.png") end end
steps[420] = function(p)
  if not fstd then return end
  local s = E("docked", false)  -- (from the gear's panel, still open)
  local f = frames(s)
  check("Docked off: all inside", s.open and not s.docked and not f.ezactions_editor__right
        and not f.ezactions_editor__bottom, serpent.line(s))
end
steps[424] = function(p)
  if not fstd then return end
  p.opened = nil  -- (Esc: the panel closes, and gives Esc to the window made again, not the old one)
end
steps[426] = function(p)
  if not fstd then return end
  check("after Docked: the new window has Esc", p.opened and p.opened.name == "ezactions_editor",
        p.opened and p.opened.name)
  shot(p, "ez-gui-3c-inside.png")
end
steps[445] = function(p)
  if fstd then E("docked", true) end
  R("replace_all", 1, "[]")
  setup(p)
end
steps[350 + D] = function(p)
  R("open_editor", 1) -- (toggles closed? open_editor only opens)
  check("open_editor keeps it open", p.gui.screen.ezactions_editor ~= nil)
  local ok = R("open_temporary_radial", 1, J({{title = "Temp", action = {type = "COMMAND", command = "eztest temp"}}}),
               {openStyle = "GROW", ringColor = -1})
  check("temporary radial", ok and R("radial_state", 1).count == 1)
end
-- the key action picker: icons, and @mod filters
local function listbox(el)
  if el.type == "list-box" then return el end
  for _, c in pairs(el.children) do
    local f = listbox(c)
    if f then return f end
  end
end
local function picker(p, source, filter)
  R("open_editor", 1, {add = "KEY", source = source, filter = filter})
  local box = listbox(p.gui.screen.ezactions_editor)
  return box and box.items or {}
end
local function all_mod(items, mod)
  for _, it in ipairs(items) do if it[7] ~= mod then return false end end
  return #items > 0
end
local function names(items)
  local t = {}
  for _, it in ipairs(items) do t[#t + 1] = (it[2] or "") .. tostring(it[5]) end
  return table.concat(t, ",")
end
steps[352 + D] = function(p)  -- (the editor's Preview: the radial over it)
  R("close_radial", 1)
  R("open_editor", 1)
  R("preview", 1)
end
steps[355 + D] = function(p)
  check("Preview over the editor keeps it open", p.gui.screen.ezactions_editor ~= nil and R("radial_state", 1) ~= nil)
  if fstd then check("... and has Esc", p.opened and p.opened.name == "ezactions_radial_1", p.opened and p.opened.name) end
end
steps[360 + D] = function(p)
  R("close_radial", 1)
  if fstd then
    check("radial closed: the editor has Esc back", p.opened and p.opened.name == "ezactions_editor",
          p.opened and p.opened.name)
  end
  local items = picker(p, "shortcut", "@base")
  check("shortcuts @base: all from base", all_mod(items, "base"), #items)
  check("shortcuts show their icon", names(items):find("[img=shortcut/give-blueprint]", 1, true) ~= nil)
  check("black shortcut icons made white on a dark window", names(items):find("[img=ezactions-scb-undo]", 1, true) ~= nil)
  local t = E("state").tools
  check("form open: Import, Export, Preview off too", t.import == false and t.export == false and t.preview == false
        and t.edit == false, serpent.line(t))
end
steps[362 + D] = function(p) shot(p, "ez-gui-4-picker.png") end
steps[364 + D] = function(p)
  local items = picker(p, "shortcut", "@guitest")
  check("shortcuts @guitest: just the test's", #items == 1 and items[1][5] == "ez-guitest-sc", names(items))
  items = picker(p, "control", "@core undo")
  check("controls @core undo", #items >= 1 and all_mod(items, "core") and names(items):find("ezactions-scb-undo", 1, true) ~= nil,
        names(items))
  items = picker(p, "control", "@ez-actions bundle")
  check("controls @ez-actions bundle: the ten bundle keys", #items == 10 and all_mod(items, "ez-actions"), #items)
  items = picker(p, "control", "@nomodlikethis")
  check("unknown mod: nothing", #items == 0)
end
-- every new-entry form opens (a new bundle's checkbox once had no state)
local untitled
steps[365 + D] = function(p)
  untitled = R("add_action", 1, {}, "", "", nil, {type = "KEY", source = "shortcut", name = "undo"}, false)
end
steps[368 + D] = function(p)
  local it = R("find_by_id", 1, untitled)
  check("no title: the game's name for it, not its internal one", it and it.title == "Undo", it and it.title)
  R("remove_by_id", 1, untitled)
end
steps[366 + D] = function(p)
  for _, kind in ipairs({"KEY", "COMMAND", "EQUIP", "bundle"}) do
    local ok, err = pcall(R, "open_editor", 1, {add = kind})
    check("new " .. kind .. " form opens", ok, err)
  end
end
-- the drawn ring's styles and animations, screenshots ez-gui-5-<style>.png
local STYLES = {{"solid", "WIPE"}, {"segmented", "GROW"}, {"outline", "NONE"}, {"glass", "FADE"}}
for k, v in ipairs(STYLES) do
  local t = 370 + D + k * 20
  steps[t] = function(p)
    local items = {}
    for i = 1, 8 do
      items[i] = {title = i == 3 and "Merge the chests into one wide chest" or ("Slice " .. i), icon = i % 2 == 0 and "item/coal" or "item/iron-chest",
                  action = {type = "COMMAND", command = "eztest " .. i}}
    end
    p.zoom = k == 4 and 2 or 1 -- (zoomed in: ring, lit slice and icons must still line up)
    R("open_temporary_radial", 1, J(items), {designStyle = v[1], openStyle = v[2], sliceGapDeg = 3,
                                            iconOutline = ({solid = "glow", segmented = "stroke", outline = "both"})[v[1]] or "off",
                                            hoverColor = v[1] == "glass" and -16733441 or nil})
    local s = R("radial_state", 1)
    check(v[1] .. ": drawn ring", s and s.drawn and s.ring, s and J(s))
    mock({x = math.floor(s.x + 100), y = math.floor(s.y + 20)})
  end
  steps[t + 12] = function(p) shot(p, "ez-gui-5-" .. v[1] .. ".png") end
  steps[t + 14] = function(p)
    check(v[1] .. ": slice under the mouse", R("radial_state", 1).selected == 3, R("radial_state", 1).selected)
    R("close_radial", 1)
    p.zoom = 1
  end
end
-- (what the 0.2.1 migration does: a player's ring style written at run time)
steps[460 + D] = function(p)
  local D, RA, B = "ezactions-design", "ezactions-radius", "ezactions-button-size"
  local m = R("_migrate_settings", 1, "0.2.0", {[D] = "slot", [RA] = 100, [B] = 40})
  check("migration from 0.2.0: old defaults become new", m[D] == "solid" and m[RA] == 170 and m[B] == 40, serpent.line(m))
  m = R("_migrate_settings", 1, "0.2.0", {[D] = "glass", [RA] = 120, [B] = 32})
  check("migration: own choices stay", m[D] == "glass" and m[RA] == 120 and m[B] == 32, serpent.line(m))
  m = R("_migrate_settings", 1, "0.2.2", {[D] = "slot", [RA] = 100, [B] = 40})
  check("migration from 0.2.2: only the sizes", m[D] == "slot" and m[RA] == 170 and m[B] == 40, serpent.line(m))
  m = R("_migrate_settings", 1, "0.2.3", {[D] = "slot", [RA] = 100, [B] = 40})
  check("migration from 0.2.3: nothing", m[D] == "slot" and m[RA] == 100 and m[B] == 40, serpent.line(m))
  m = R("_migrate_settings", 1, "0.2.3", {[B] = 28})
  check("migration from 0.2.3: icons 28 -> 40", m[B] == 40, serpent.line(m))
  R("_migrate_settings", 1, "9.9.9", {[D] = "solid", [RA] = 170, [B] = 40})
end
-- fse-std's window scale (0.8): the editor at 150 %, put back on the screen with its rail and dock from the right
-- edge, Size in the gear's panel after Docked
local function on_screen(p)
  local res, out = p.display_resolution, {}
  local w0 = p.gui.screen.ezactions_editor
  for _, n in ipairs({"ezactions_editor", "ezactions_editor__right", "ezactions_editor__bottom"}) do
    local el = p.gui.screen[n]
    if el and el.location then
      local t = el.tags
      local w, h
      if t.fstd_attach then w, h = t.fstd_attach.w, t.fstd_attach.h
      elseif type(t.fstd_tweak) == "table" and t.fstd_tweak.width then w, h = t.fstd_tweak.width, t.fstd_tweak.height
      else w, h = 600, 620 end
      local sc = p.display_scale * (t.fstd_scale or (w0 and w0.tags.fstd_scale) or 1)
      local x, y = el.location.x, el.location.y
      if x < 0 or y < 0 or x + w * sc > res.width + 1 or y + h * sc > res.height + 1 then
        out[#out + 1] = string.format("%s %d,%d %dx%d", n, x, y, w * sc, h * sc)
      end
    end
  end
  return #out == 0, string.format("%dx%d at ui %s: %s", res.width, res.height, p.display_scale,
                                  #out == 0 and "on screen" or table.concat(out, "; "))
end
steps[480 + D] = function(p)
  if not fstd then return end
  R("open_editor", 1)
  local f = p.gui.screen.ezactions_editor
  if f then f.location = {9999, 60} end  -- (off the right edge, as a drag can put it)
  check("fse-std has set_window_scale", remote.interfaces["fse-std"].set_window_scale ~= nil)
  remote.call("fse-std", "set_window_scale", 1, 150)
end
steps[482 + D] = function(p)
  if not fstd then return end
  local f = p.gui.screen.ezactions_editor
  local ok, detail = on_screen(p)
  -- (at 150 %, or less where the screen is too small for it: at the game's GUI scale 200 % on 2560x1440, 100 %)
  local sc = f and f.tags.fstd_scale
  check("window scale 150 %: drawn at it (or capped)", sc and (sc == 1.5 or (sc < 1.5 and p.display_scale > 1.25)), sc)
  check("window scale 150 %: editor, rail and dock on the screen", ok, detail)
  E("settings")
  local m = p.gui.screen.ezactions_editor__menu
  local function find(el) if el.type == "drop-down" and el.tags.fstd_scale_pick then return el end
    for _, c in pairs(el.children) do local r = find(c) if r then return r end end end
  check("gear: Size", m and find(m) ~= nil)
end
steps[484 + D] = function(p) if fstd then shot(p, "ez-gui-6-scale150.png") end end
steps[505 + D] = function(p)
  if not fstd then return end
  local m = p.gui.screen.ezactions_editor__menu
  if m then m.destroy() end
  E("docked", false)  -- (all inside at 150 %)
end
steps[507 + D] = function(p)
  if not fstd then return end
  local ok, detail = on_screen(p)
  check("window scale 150 %, all inside: on the screen", ok, detail)
  shot(p, "ez-gui-6b-scale150-inside.png")
end
steps[530 + D] = function(p)
  if not fstd then return end
  E("docked", true)
  remote.call("fse-std", "set_window_scale", 1, 100)
end
steps[535 + D] = function(p)
  mock()
  check("seen", true, table.concat(seen, ","))
  helpers.write_file("ez-gui.txt", table.concat(out, "\n"))
  helpers.write_file("ez-gui-done.txt", "done")
end

script.on_event(defines.events.on_tick, function(e)
  local p = game.get_player(1)
  if not (p and p.character) then return end
  -- (in game: the runner focuses the window for 1.5 s more, then never again; the steps start after that)
  if e.tick == 1 then helpers.write_file("ez-gui-ready.txt", "ready") end
  local f = e.tick > 150 and steps[e.tick - 150]
  if f then f(p) end
end)
