-- Running an action for a player. GUI events run on every multiplayer peer, so game changes (equip, cursor, toggles)
-- happen here on all of them; what only this computer can do (press a key, send a console line) goes through FSE and
-- only on the peer whose player it is.
local model = require("scripts.model")
local A = {}

local function say(player, text)
  player.create_local_flying_text({text = text, create_at_cursor = true})
end

--- this computer's own player (always true in single player with FSE)
function A.local_peer(player)
  return native ~= nil and native.local_player ~= nil and native.local_player() == player.index
end

function A.has(plugin, fn)
  if not native then return false end
  local fns = native.plugins()[plugin]
  if not fns then return false end
  for _, f in pairs(fns) do if f == fn then return true end end
  return false
end

function A.call(plugin, fn, input)
  if not native then return nil, "no FSE" end
  return native.call(plugin, fn, type(input) == "table" and helpers.table_to_json(input) or (input or ""))
end

-- ---- keys -----------------------------------------------------------------------------------------------------

local function phase(player, item)
  if not item.action.toggle then return "tap" end
  local t = model.data(player.index).toggles
  t[item.id] = not t[item.id]
  return t[item.id] and "down" or "up"
end

local function press_control(player, name, ph)
  if not A.local_peer(player) then return true end
  if not A.has("input", "trigger") then return false, {"ezactions.needs-fse"} end
  local _, err = A.call("input", "trigger", {control = name, phase = ph})
  if err then return false, err end
  return true
end

local shortcut_actions = {
  ["spawn-item"] = function(player, proto)
    local item = proto.item_to_spawn
    if not item then return false end
    player.clear_cursor()
    if not player.cursor_stack or not player.cursor_stack.can_set_stack({name = item.name}) then return false end
    player.cursor_stack.set_stack({name = item.name})
    player.cursor_stack_temporary = true
    return true
  end,
  ["toggle-alt-mode"] = function(player)
    player.game_view_settings.show_entity_info = not player.game_view_settings.show_entity_info
    return true
  end,
  ["toggle-personal-roboport"] = function(player)
    local c = player.character
    if not c then return false end
    c.allow_dispatching_robots = not c.allow_dispatching_robots
    return true
  end,
  ["toggle-equipment-movement-bonus"] = function(player)
    local grid = player.character and player.character.grid
    if not grid then return false end
    grid.inhibit_movement_bonus = not grid.inhibit_movement_bonus
    return true
  end,
}

local function run_shortcut(player, name)
  local proto = prototypes.shortcut[name]
  if not proto then return false, {"ezactions.no-shortcut", name} end
  if name == "ezactions-editor" then
    remote.call("ezactions", "open_editor", player.index)
    return true
  end
  local own = shortcut_actions[proto.action]
  if own then return own(player, proto) end
  if proto.action == "lua" then
    if not player.is_shortcut_available(name) then return false, {"ezactions.unavailable"} end
    if not A.local_peer(player) then return true end
    if not native then return false, {"ezactions.needs-fse"} end
    local ok, err = native.send_action("LuaShortcut", name)
    return ok ~= nil, err
  end
  if proto.associated_control_input then
    return press_control(player, proto.associated_control_input, "tap")
  end
  return false, {"ezactions.no-way", name}
end

local function run_key(player, item)
  local a = item.action
  if a.source == "shortcut" then return run_shortcut(player, a.name) end
  local ph = phase(player, item)
  if a.source == "control" then return press_control(player, a.name, ph) end
  -- hotkey
  if not A.local_peer(player) then return true end
  if not A.has("std", "press") then return false, {"ezactions.needs-fse"} end
  local k = a.key
  local _, err = A.call("std", "press", {vk = k.vk, scancode = k.scancode, mouse = k.mouse, mods = k.mods, phase = ph})
  if err then return false, err end
  return true
end

-- ---- commands -------------------------------------------------------------------------------------------------

local function lines(text)
  local out = {}
  for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" then out[#out + 1] = line:sub(1, 1) == "/" and line or ("/" .. line) end
  end
  return out
end
A.lines = lines

local function send_line(player, line)
  if not A.local_peer(player) then return end
  native.send_action("WriteToConsole", line)
end

--- queue lines, one every `delay` ticks (0: all now); a new queue replaces the one in flight
function A.enqueue(player, list, delay)
  local d = model.data(player.index)
  d.queue = nil
  if not native then return false, {"ezactions.needs-fse"} end
  if delay <= 0 then
    for _, l in ipairs(list) do send_line(player, l) end
    return true
  end
  d.queue = {lines = list, i = 1, delay = delay, next = game.tick}
  storage.queued = storage.queued or {}
  storage.queued[player.index] = true
  return true
end

function A.tick(tick)
  if not storage.queued then return end
  for pi in pairs(storage.queued) do
    local d, player = model.data(pi), game.get_player(pi)
    local q = d.queue
    if not q or not player then
      storage.queued[pi] = nil
    elseif tick >= q.next then
      send_line(player, q.lines[q.i])
      q.i, q.next = q.i + 1, tick + q.delay
      if q.i > #q.lines then
        d.queue, storage.queued[pi] = nil, nil
      end
    end
  end
end

local function run_command(player, item)
  local a = item.action
  local list = lines(a.command)
  if #list == 0 then return false end
  if a.cycle then
    a.cursor = (a.cursor or 0) % #list + 1
    return A.enqueue(player, {list[a.cursor]}, 0)
  end
  return A.enqueue(player, list, a.delay or 0)
end

-- ---- loadouts -------------------------------------------------------------------------------------------------

A.equip_slots = {"armor", "gun1", "gun2", "gun3", "ammo1", "ammo2", "ammo3", "hand"}

local function target(player, slot)
  local kind, n = slot:match("^(%a+)(%d?)$")
  local inv = ({armor = defines.inventory.character_armor, gun = defines.inventory.character_guns,
                ammo = defines.inventory.character_ammo})[kind]
  if not inv then return nil end
  local i = player.get_inventory(inv)
  return i and i[tonumber(n) or 1]
end

local function same(stack, want)
  return stack and stack.valid_for_read and stack.name == want.name and stack.quality.name == (want.quality or "normal")
end

--- the fullest stack of that item in the main inventory, and its slot
local function source(player, want)
  local main = player.get_main_inventory()
  if not main then return nil end
  local best, at
  for i = 1, #main do
    local s = main[i]
    if same(s, want) and (not best or s.count > best.count) then best, at = s, i end
  end
  return best, at
end

--- records what the player wears and holds now, as loadout slots
function A.record(player)
  local slots = {}
  for _, slot in ipairs(A.equip_slots) do
    local s = slot == "hand" and player.cursor_stack or target(player, slot)
    if s and s.valid_for_read then slots[slot] = {name = s.name, quality = s.quality.name} end
  end
  return slots
end

local function run_equip(player, item)
  if not player.character then return false, {"ezactions.no-character"} end
  local done = 0
  for _, slot in ipairs(A.equip_slots) do
    local want = item.action.slots[slot]
    if want then
      if slot == "hand" then
        if same(player.cursor_stack, want) then
          done = done + 1
        else
          local src, at = source(player, want)
          if src and player.clear_cursor() and player.cursor_stack.swap_stack(src) then
            player.hand_location = {inventory = defines.inventory.character_main, slot = at}
            done = done + 1
          end
        end
      else
        local t = target(player, slot)
        if t and same(t, want) then
          done = done + 1
        elseif t then
          local src = source(player, want)
          if src and t.swap_stack(src) then done = done + 1 end
        end
      end
    end
  end
  return done > 0
end

-- ---- running --------------------------------------------------------------------------------------------------

local run = {KEY = run_key, COMMAND = run_command, EQUIP = run_equip}

function A.run(player, item)
  local f = item.action and run[item.action.type]
  if not f then return false end
  local ok, err = f(player, item)
  if not ok and err then say(player, err) end
  return ok
end

return A
