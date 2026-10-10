local model = require("scripts.model")
local actions = require("scripts.actions")
local radial = require("scripts.radial")
local editor = require("scripts.editor")

local function player_of(e) return game.get_player(e.player_index) end

local function open_main(player, e, hold)
  return radial.open(player, {pages = {model.data(player.index).menu}, root_filter = true, hold = hold,
                              control = e and e.input_name,
                              x = e and e.cursor_display_location and e.cursor_display_location.x,
                              y = e and e.cursor_display_location and e.cursor_display_location.y})
end

local function find_bundle(pi, key)
  local found
  model.walk(model.data(pi).menu, function(item)
    if not found and item.children and (item.id == key or item.title == key or item.keybind == key) then found = item end
  end)
  return found
end

local function open_bundle(player, bundle, e, hold)
  return radial.open(player, {pages = {bundle.children}, hold = hold, control = e and e.input_name,
                              x = e and e.cursor_display_location and e.cursor_display_location.x,
                              y = e and e.cursor_display_location and e.cursor_display_location.y})
end

script.on_event("ezactions-radial", function(e)
  local player = player_of(e)
  if radial.is_open(player) then return radial.key(player) end
  if editor.is_open(player) then editor.close(player) end
  open_main(player, e, true)
end)

script.on_event("ezactions-editor", function(e)
  local player = player_of(e)
  radial.close(player)
  editor.open(player)
end)

for i = 1, 10 do
  script.on_event("ezactions-bundle-" .. i, function(e)
    local player = player_of(e)
    if radial.is_open(player) then return radial.key(player) end
    local b = find_bundle(player.index, i)
    if b then open_bundle(player, b, e, true) end
  end)
end

script.on_event("ezactions-delete", function(e) editor.delete(player_of(e)) end)
script.on_event("ezactions-focus-search", function(e) editor.focus_search(player_of(e)) end)

script.on_event(defines.events.on_lua_shortcut, function(e)
  if e.prototype_name == "ezactions-editor" then
    local player = player_of(e)
    radial.close(player)
    editor.open(player)
  end
end)

local dnd_click = editor.dnd and editor.dnd.handlers[defines.events.on_gui_click]
local dnd_tick = editor.dnd and editor.dnd.handlers[defines.events.on_tick]

script.on_event(defines.events.on_gui_click, function(e)
  if dnd_click then
    dnd_click(e)
    if editor.dnd.handled(e) then return end
  end
  if not e.element.valid then return end
  local tags = e.element.tags
  if tags.ezactions_slice or tags.ezactions_back then return radial.on_click(e) end
  if editor.owns(e.element) then return editor.on_click(e) end
end)
script.on_event(defines.events.on_gui_hover, function(e) radial.on_hover(e, true) end)
script.on_event(defines.events.on_gui_leave, function(e) radial.on_hover(e, false) end)
script.on_event(defines.events.on_gui_closed, function(e) if e.element then radial.on_closed(e) end end)
script.on_event(defines.events.on_gui_text_changed, function(e) if editor.owns(e.element) then editor.on_text(e) end end)
script.on_event(defines.events.on_gui_selection_state_changed, function(e)
  if editor.owns(e.element) then editor.on_selection(e) end
end)
script.on_event(defines.events.on_gui_checked_state_changed, function(e)
  if editor.owns(e.element) then editor.on_checked(e) end
end)

script.on_event(defines.events.on_tick, function(e)
  if dnd_tick then dnd_tick(e) end
  radial.tick()
  actions.tick(e.tick)
  editor.tick()
end)

script.on_event(model.changed_event, function(e)
  local player = game.get_player(e.player_index)
  if player then editor.refresh(player) end
end)

script.on_event(defines.events.on_player_removed, function(e)
  for _, t in pairs({storage.players, storage.radial, storage.editor, storage.queued, storage.recording}) do
    t[e.player_index] = nil
  end
end)

-- 0.2.0 drew the ring, but players updating kept the old default ring style ("slot", buttons): move them over once
local function migrate_ring_style(player)
  local s = player.mod_settings["ezactions-design"]
  if s and s.value == "slot" then player.mod_settings["ezactions-design"] = {value = "solid"} end
end
script.on_configuration_changed(function(data)
  local c = data.mod_changes["ez-actions"]
  if not (c and c.old_version and helpers.compare_versions(c.old_version, "0.2.1") < 0) then return end
  for _, player in pairs(game.players) do migrate_ring_style(player) end
end)

script.on_init(function()
  storage.players, storage.radial, storage.editor, storage.queued, storage.recording = {}, {}, {}, {}, {}
end)

-- ---- the API: remote.call("ezactions", fn, player_index, ...) ---------------------------------------------------
-- Paths are lists of bundle titles (or ids); {} is the root. Write calls honour `locked` unless told otherwise.

local function P(pi)
  local p = game.get_player(pi)
  if not p then error("ezactions: no player " .. tostring(pi)) end
  return p
end

local function snapshot(item)
  return {id = item.id, title = item.title, note = item.note, icon = item.icon, is_category = item.children ~= nil,
          type_label = item.children and "bundle" or item.action.type, hide = item.hide, keybind = item.keybind,
          locked = item.locked == true, action_type = item.action and item.action.type,
          action_json = item.action and helpers.table_to_json(item.action),
          children = item.children and #item.children or nil}
end

local function list_of(pi, path)
  local l = model.resolve(pi, path)
  if not l then error("ezactions: no such path " .. serpent.line(path)) end
  return l
end

local function add(pi, path, item)
  local clean, err = model.clean(pi, item)
  if not clean then return nil, err end
  if clean.children and model.title_taken(pi, clean.title) then return nil, "bundle title taken" end
  local l = list_of(pi, path)
  l[#l + 1] = clean
  model.changed(pi, path, "added")
  return clean.id
end

local api = {
  -- read
  list = function(pi, path)
    local out = {}
    for _, item in ipairs(list_of(pi, path)) do out[#out + 1] = snapshot(item) end
    return out
  end,
  find_by_id = function(pi, id) local item = model.find(pi, id) return item and snapshot(item) end,
  exists_path = function(pi, path) return model.resolve(pi, path) ~= nil end,
  -- write
  add_action = function(pi, path, title, note, icon, action, locked)
    return add(pi, path, {title = title, note = note, icon = icon, action = action, locked = locked})
  end,
  add_bundle = function(pi, path, title, note, icon, hide, keybind, locked)
    return add(pi, path, {title = title, note = note, icon = icon, hide = hide, keybind = keybind, locked = locked,
                          children = {}})
  end,
  ensure_bundles = function(pi, path)
    local list, walked = model.data(pi).menu, {}
    for _, title in ipairs(path) do
      local found
      for _, item in ipairs(list) do
        if item.children and (item.title == title or item.id == title) then found = item break end
      end
      if not found then
        found = model.clean(pi, {title = title, children = {}})
        list[#list + 1] = found
        model.changed(pi, walked, "added")
      end
      walked[#walked + 1] = found.id
      list = found.children
    end
    return true
  end,
  move_within = function(pi, path, from, to)
    local l = list_of(pi, path)
    if not l[from] or to < 1 or to > #l then return false end
    table.insert(l, to, table.remove(l, from))
    model.changed(pi, path, "moved")
    return true
  end,
  move_before = function(pi, id, target_id) return model.move_before(pi, id, target_id) end,
  move_to = function(pi, id, target_path)
    return model.move_to(pi, id, list_of(pi, target_path), target_path)
  end,
  remove_by_id = function(pi, id, ignore_lock) return model.remove(pi, id, ignore_lock) end,
  update_meta = function(pi, id, title, note, icon)
    local item, _, _, path = model.find(pi, id)
    if not item then return false end
    if title then item.title = title end
    if note then item.note = note end
    if icon then item.icon = icon end
    model.changed(pi, path, "edited")
    return true
  end,
  replace_action = function(pi, id, action)
    local item, _, _, path = model.find(pi, id)
    if not item or not item.action then return false end
    local clean, err = model.clean(pi, {id = id, title = item.title, action = action})
    if not clean then return false, err end
    item.action = clean.action
    model.changed(pi, path, "edited")
    return true
  end,
  set_bundle_flags = function(pi, id, hide, keybind)
    local item, _, _, path = model.find(pi, id)
    if not item or not item.children then return false end
    item.hide, item.keybind = hide == true, tonumber(keybind)
    model.changed(pi, path, "edited")
    return true
  end,
  set_locked = function(pi, id, locked)
    local item = model.find(pi, id)
    if not item then return false end
    item.locked = locked == true
    return true
  end,
  upsert_json = function(pi, path, json)
    local items, err = model.parse(pi, json)
    if not items then return nil, err end
    local n = model.upsert(pi, list_of(pi, path), items)
    model.changed(pi, path, "imported")
    return n
  end,
  -- import / export
  export_all_json = function(pi) return model.export(model.data(pi).menu) end,
  export_bundle_json = function(pi, path) return model.export(list_of(pi, path)) end,
  import_into = function(pi, path, json)
    local items, err = model.parse(pi, json)
    if not items then return nil, err end
    local n = model.upsert(pi, list_of(pi, path), items)
    model.changed(pi, path, "imported")
    script.raise_event(model.imported_event, {player_index = pi, path = path, json = json, count = n})
    return n
  end,
  replace_all = function(pi, json)
    local items, err = model.parse(pi, json)
    if not items then return nil, err end
    model.data(pi).menu = items
    model.changed(pi, {}, "imported")
    script.raise_event(model.imported_event, {player_index = pi, path = {}, json = json, count = #items})
    return #items
  end,
  validate = function(pi, json)
    local items, err = model.parse(pi, json)
    return items ~= nil, err
  end,
  -- input
  deliver = function(pi, action) return actions.run(P(pi), {id = "api", title = "api", action = model.clean(pi, {action = action}).action}) end,
  enqueue_commands = function(pi, commands, delay)
    local list = type(commands) == "table" and commands or actions.lines(commands)
    return actions.enqueue(P(pi), actions.lines(table.concat(list, "\n")), delay or 0)
  end,
  -- screens
  --- opts (optional): {add = "KEY"|"COMMAND"|"EQUIP"|"bundle", source = "control"|"shortcut"|"hotkey",
  --- filter = "@mod words"}: straight to a new entry's form
  open_editor = function(pi, opts)
    radial.close(P(pi))
    if not editor.is_open(P(pi)) then editor.open(P(pi)) end
    if opts and opts.add then editor.add(P(pi), opts.add, opts.source, opts.filter) end
  end,
  open_radial = function(pi) editor.close(P(pi)) return open_main(P(pi), nil, false) end,
  open_radial_at_bundle = function(pi, key)
    local b = find_bundle(pi, key)
    editor.close(P(pi))
    return b ~= nil and open_bundle(P(pi), b, nil, false)
  end,
  open_temporary_radial = function(pi, json, style)
    local items, err = model.parse(pi, json)
    if not items then return nil, err end
    editor.close(P(pi))
    return radial.open(P(pi), {pages = {items}, style = style, temp = true})
  end,
  preview = function(pi)
    return radial.open(P(pi), {pages = {model.data(pi).menu}, root_filter = true, preview = true})
  end,
  close_radial = function(pi) radial.close(P(pi)) end,
  -- (tests: the 0.2.1 settings migration for one player, which only this mod may write)
  _migrate_ring_style = function(pi, from)
    if from then P(pi).mod_settings["ezactions-design"] = {value = from} end
    migrate_ring_style(P(pi))
    return P(pi).mod_settings["ezactions-design"].value
  end,
  --- the open radial: {x, y (pixels), count, selected, holding, depth}, or nil
  radial_state = function(pi)
    local s = storage.radial and storage.radial[pi]
    return s and {x = s.x, y = s.y, count = #s.items, selected = s.sel, holding = s.hold ~= nil, depth = #s.pages,
                  drawn = s.drawn == true, ring = s.ring ~= nil and s.ring.hover ~= nil}
  end,
  -- events: script.on_event(remote.call("ezactions", "events").menu_changed, fn)
  events = function() return {menu_changed = model.changed_event, imported = model.imported_event} end,
}
remote.add_interface("ezactions", api)
