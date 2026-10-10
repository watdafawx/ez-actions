-- real client through the fse launcher: the radial opened by its key (input.trigger), the mouse and the held key faked
-- with std.mock, each kind of slice run by letting go; screenshots to script-output/ez-gui-*.png
local out, seen = {}, {}
local function check(name, ok, detail)
  out[#out + 1] = (ok and "PASS " or "FAIL ") .. name .. (detail ~= nil and (" :: " .. tostring(detail)) or "")
end
local function R(fn, ...) return remote.call("ezactions", fn, ...) end
local function J(t) return helpers.table_to_json(t) end
local function mock(t) native.call("std", "mock", t and J(t) or "") end
local function shot(p, file)
  game.take_screenshot({player = p, show_gui = true, path = file, resolution = {p.display_resolution.width, p.display_resolution.height}, zoom = 1})
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
  local armor = p.get_inventory(defines.inventory.character_armor)[1]
  local gun = p.get_inventory(defines.inventory.character_guns)[1]
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
steps[335] = function(p) shot(p, "ez-gui-2-bundle.png") R("close_radial", 1) end
steps[340] = function(p)
  R("open_editor", 1)
end
steps[345] = function(p)
  check("editor open", p.gui.screen.ezactions_editor ~= nil)
  shot(p, "ez-gui-3-editor.png")
end
steps[350] = function(p)
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
steps[360] = function(p)
  R("close_radial", 1)
  local items = picker(p, "shortcut", "@base")
  check("shortcuts @base: all from base", all_mod(items, "base"), #items)
  check("shortcuts show their icon", names(items):find("[img=shortcut/give-blueprint]", 1, true) ~= nil)
end
steps[362] = function(p) shot(p, "ez-gui-4-picker.png") end
steps[364] = function(p)
  local items = picker(p, "shortcut", "@guitest")
  check("shortcuts @guitest: just the test's", #items == 1 and items[1][5] == "ez-guitest-sc", names(items))
  items = picker(p, "control", "@core undo")
  check("controls @core undo", #items >= 1 and all_mod(items, "core") and names(items):find("shortcut/undo", 1, true) ~= nil,
        names(items))
  items = picker(p, "control", "@ez-actions bundle")
  check("controls @ez-actions bundle: the ten bundle keys", #items == 10 and all_mod(items, "ez-actions"), #items)
  items = picker(p, "control", "@nomodlikethis")
  check("unknown mod: nothing", #items == 0)
end
-- every new-entry form opens (a new bundle's checkbox once had no state)
steps[366] = function(p)
  for _, kind in ipairs({"KEY", "COMMAND", "EQUIP", "bundle"}) do
    local ok, err = pcall(R, "open_editor", 1, {add = kind})
    check("new " .. kind .. " form opens", ok, err)
  end
end
steps[370] = function(p)
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
