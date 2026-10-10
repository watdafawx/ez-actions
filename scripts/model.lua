-- The menu tree, per player: storage.players[i].menu is a list of items. An item is an action
-- {id, title, note, icon, locked, action = {type = "KEY"|"COMMAND"|"EQUIP", ...}} or a bundle
-- {id, title, note, icon, locked, hide, keybind (1..10 or nil), children = {...}}.
-- A path names a page: a list of bundle ids or titles, {} is the root.
local M = {}

M.changed_event = script.generate_event_name()
M.imported_event = script.generate_event_name()

function M.data(pi)
  storage.players = storage.players or {}
  local d = storage.players[pi]
  if not d then
    d = {menu = {}, ids = 0, toggles = {}}
    storage.players[pi] = d
  end
  return d
end

function M.new_id(pi, prefix)
  local d = M.data(pi)
  d.ids = d.ids + 1
  return (prefix or "act") .. "_" .. game.tick .. "_" .. d.ids
end

function M.is_bundle(item)
  return item.children ~= nil
end

local function match(item, key)
  return M.is_bundle(item) and (item.id == key or item.title == key)
end

--- the list a path names, or nil
function M.resolve(pi, path)
  local list = M.data(pi).menu
  for _, key in ipairs(path or {}) do
    local found
    for _, item in ipairs(list) do
      if match(item, key) then found = item break end
    end
    if not found then return nil end
    list = found.children
  end
  return list
end

--- item, its list, its index, the path (bundle ids) of that list
function M.find(pi, id, list, path)
  list, path = list or M.data(pi).menu, path or {}
  for i, item in ipairs(list) do
    if item.id == id then return item, list, i, path end
    if item.children then
      local sub = {table.unpack(path)}
      sub[#sub + 1] = item.id
      local a, b, c, d = M.find(pi, id, item.children, sub)
      if a then return a, b, c, d end
    end
  end
end

function M.walk(list, fn, depth)
  for _, item in ipairs(list) do
    fn(item, depth or 0)
    if item.children then M.walk(item.children, fn, (depth or 0) + 1) end
  end
end

function M.changed(pi, path, reason)
  script.raise_event(M.changed_event, {player_index = pi, path = path or {}, reason = reason or "changed"})
end

-- ---- checking items that come from JSON, the API or the editor ------------------------------------------------

local function str(v)
  if v == nil then return "" end
  return type(v) == "string" and v or (type(v) == "table" and helpers.table_to_json(v) or tostring(v))
end

local function clean_action(a)
  if type(a) ~= "table" then return nil, "action is not an object" end
  local t = a.type
  if t == "KEY" then
    local src = a.source or "control"
    if src ~= "control" and src ~= "shortcut" and src ~= "hotkey" then return nil, "KEY source must be control, shortcut or hotkey" end
    if src ~= "hotkey" and (type(a.name) ~= "string" or a.name == "") then return nil, "KEY needs a name" end
    if src == "hotkey" and type(a.key) ~= "table" then return nil, "a hotkey KEY needs key = {vk, mods, name}" end
    return {type = t, source = src, name = a.name, toggle = a.toggle == true,
            key = src == "hotkey" and {vk = tonumber(a.key.vk), scancode = a.key.scancode, mouse = a.key.mouse,
                                       mods = a.key.mods or {}, name = str(a.key.name)} or nil}
  elseif t == "COMMAND" then
    if type(a.command) ~= "string" then return nil, "COMMAND needs command (text)" end
    return {type = t, command = a.command, delay = math.max(0, math.floor(tonumber(a.delay or a.delayTicks) or 0)),
            cycle = (a.cycle or a.cycleCommands) == true, cursor = 0}
  elseif t == "EQUIP" then
    local slots = {}
    for k, v in pairs(type(a.slots) == "table" and a.slots or {}) do
      if type(v) == "table" and type(v.name) == "string" then slots[k] = {name = v.name, quality = v.quality or "normal"} end
    end
    return {type = t, slots = slots}
  end
  return nil, "unknown action type " .. tostring(t)
end

--- a checked copy of an item from outside (new ids where missing), or nil, error
function M.clean(pi, item, depth)
  if type(item) ~= "table" then return nil, "entry is not an object" end
  if (depth or 0) > 16 then return nil, "bundles nested too deep" end
  local out = {id = type(item.id) == "string" and item.id or nil, title = str(item.title), note = str(item.note),
               icon = type(item.icon) == "string" and item.icon or nil, locked = item.locked == true}
  if item.children then
    if type(item.children) ~= "table" then return nil, "children is not an array" end
    out.id = out.id or M.new_id(pi, "bundle")
    out.hide = (item.hide or item.hideFromMainRadial) == true
    out.keybind = tonumber(item.keybind) or ((item.bundleKeybindEnabled == true) and 1 or nil)
    out.children = {}
    for _, c in ipairs(item.children) do
      local cc, err = M.clean(pi, c, (depth or 0) + 1)
      if not cc then return nil, err end
      out.children[#out.children + 1] = cc
    end
  elseif item.action then
    local a, err = clean_action(item.action)
    if not a then return nil, err end
    out.id = out.id or M.new_id(pi, "act")
    out.action = a
  else
    return nil, "entry has neither action nor children"
  end
  if out.title == "" then out.title = out.id end
  return out
end

--- JSON text or a table: a list of checked items, or nil, error
function M.parse(pi, json)
  local t = json
  if type(json) == "string" then
    if json:match("^%s*$") then return nil, "empty" end
    t = helpers.json_to_table(json)
    if t == nil then return nil, "not JSON" end
  end
  if type(t) ~= "table" then return nil, "not an array" end
  if t.action or t.children then t = {t} end
  if #t == 0 and next(t) ~= nil then return nil, "root JSON is not an array" end
  local out = {}
  for i, item in ipairs(t) do
    local c, err = M.clean(pi, item)
    if not c then return nil, "entry " .. i .. ": " .. err end
    out[#out + 1] = c
  end
  return out
end

--- adds or replaces (same id) items in a list; returns how many
function M.upsert(pi, list, items)
  local n = 0
  for _, item in ipairs(items) do
    local old, olist, oi = M.find(pi, item.id)
    if old then
      olist[oi] = item
    else
      list[#list + 1] = item
    end
    n = n + 1
  end
  return n
end

function M.export(list)
  return helpers.table_to_json(list)
end

--- a bundle title used by another bundle (titles name bundles in paths)
function M.title_taken(pi, title, except_id)
  local taken = false
  M.walk(M.data(pi).menu, function(item)
    if item.children and item.title == title and item.id ~= except_id then taken = true end
  end)
  return taken
end

function M.remove(pi, id, force)
  local item, list, i, path = M.find(pi, id)
  if not item then return false, "no such entry" end
  if item.locked and not force then return false, "locked" end
  local blocked
  if not force then M.walk(item.children or {}, function(c) if c.locked then blocked = true end end) end
  if blocked then return false, "contains a locked entry" end
  table.remove(list, i)
  M.changed(pi, path, "removed")
  return true
end

--- moves an item into a bundle (target id) or a path's list
function M.move_to(pi, id, target_list, target_path)
  local item, list, i = M.find(pi, id)
  if not item or not target_list or list == target_list then return false end
  -- (not into itself)
  local inside = false
  if item.children then M.walk({item}, function(c) if c.children == target_list then inside = true end end) end
  if inside then return false end
  table.remove(list, i)
  target_list[#target_list + 1] = item
  M.changed(pi, target_path, "moved")
  return true
end

--- puts an item where another one is in the same list (dragging a row onto a row): after it when moving down,
--- before it when moving up, so the dragged row takes the target's place
function M.move_before(pi, id, target_id)
  local item, list, i, path = M.find(pi, id)
  local target, tlist = M.find(pi, target_id)
  if not item or not target or list ~= tlist or id == target_id then return false end
  table.remove(list, i)
  local j
  for k, x in ipairs(list) do if x.id == target_id then j = k end end
  table.insert(list, i <= j and j + 1 or j, item)
  M.changed(pi, path, "moved")
  return true
end

function M.sprite(icon)
  if icon and helpers.is_valid_sprite_path(icon) then return icon end
end

return M
