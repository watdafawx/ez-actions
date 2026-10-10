-- The menu editor: the current page's entries on the right (root or a bundle), buttons on the left. Click selects,
-- clicking the selected row again edits it, right-click opens a bundle. With an entry selected, the arrow beside a
-- bundle or a "back" row moves it there. Delete removes the selected entry, Ctrl+F jumps to the filter.
local model = require("scripts.model")
local actions = require("scripts.actions")
local E = {}

local SOURCES = {"control", "shortcut", "hotkey"}
local SLOT_NAMES = {armor = {"ezactions.slot-armor"}, gun1 = {"ezactions.slot-gun", 1}, gun2 = {"ezactions.slot-gun", 2},
                    gun3 = {"ezactions.slot-gun", 3}, ammo1 = {"ezactions.slot-ammo", 1}, ammo2 = {"ezactions.slot-ammo", 2},
                    ammo3 = {"ezactions.slot-ammo", 3}, hand = {"ezactions.slot-hand"}}

local function st(pi)
  storage.editor = storage.editor or {}
  return storage.editor[pi]
end

local function say(player, text)
  player.create_local_flying_text({text = text, create_at_cursor = true})
end

local function type_label(item)
  if item.children then return {"ezactions.type-bundle"} end
  local a = item.action
  if a.type == "KEY" then return {"ezactions.type-key-" .. a.source} end
  return {"ezactions.type-" .. a.type:lower()}
end

local function rich_icon(item)
  local s = model.sprite(item.icon)
  return s and ("[img=" .. s .. "] ") or ""
end

local function page(pi, s)
  local list = model.resolve(pi, s.path)
  if not list then s.path = {} list = model.data(pi).menu end
  return list
end

local function titles(pi, path)
  local out, list = {}, model.data(pi).menu
  for _, id in ipairs(path) do
    for _, item in ipairs(list) do
      if item.id == id then out[#out + 1] = item.title list = item.children break end
    end
  end
  return out
end

-- ---- the list -------------------------------------------------------------------------------------------------

local function matches(item, filter, pi)
  if filter == "" then return true end
  filter = filter:lower()
  local hay = (item.title .. " " .. (item.note or "") .. " " .. (item.children and "bundle" or item.action.type)):lower()
  return hay:find(filter, 1, true) ~= nil
end

local function row(parent, caption, tags, selected, move_tags, tooltip)
  local flow = parent.add({type = "flow", direction = "horizontal"})
  flow.style.vertical_align = "center"
  local b = flow.add({type = "button", caption = caption, style = "list_box_item", tags = tags, tooltip = tooltip,
                      mouse_button_filter = {"left", "right"}})
  b.style.horizontally_stretchable = true
  b.style.maximal_width = 1000
  b.toggled = selected
  if move_tags then
    flow.add({type = "sprite-button", style = "mini_button", sprite = "utility/enter", tags = move_tags,
              tooltip = {"ezactions.move-here"}})
  end
end

local function fill_list(player, s)
  local pi = player.index
  local pane = s.list
  if not (pane and pane.valid) then return end
  pane.clear()
  local list = page(pi, s)
  local names = titles(pi, s.path)
  s.crumb.caption = "root" .. (#names > 0 and (" / " .. table.concat(names, " / ")) or "")
  local sel_here = s.sel and model.find(pi, s.sel)
  if #s.path > 0 then
    row(pane, {"ezactions.back-root"}, {ezactions_nav = 0}, false, sel_here and {ezactions_move_nav = 0} or nil)
    if #s.path > 1 then
      row(pane, {"ezactions.back-to", names[#names - 1]}, {ezactions_nav = #s.path - 1}, false,
          sel_here and {ezactions_move_nav = #s.path - 1} or nil)
    end
  end
  for i, item in ipairs(list) do
    if matches(item, s.filter, pi) then
      local caption = {"", rich_icon(item), item.locked and "[color=255,200,80](locked)[/color] " or "", item.title,
                       "  [color=128,128,128]", type_label(item), "[/color]"}
      local can_move_in = item.children and sel_here and s.sel ~= item.id
      row(pane, caption, {ezactions_row = item.id, ezactions_index = i}, s.sel == item.id,
          can_move_in and {ezactions_move_into = item.id} or nil, item.note ~= "" and item.note or nil)
    end
  end
  if #list == 0 then pane.add({type = "label", caption = {"ezactions.page-empty"}}) end
end

-- ---- the window -----------------------------------------------------------------------------------------------

local function button(parent, name, caption, tags, tooltip)
  local b = parent.add({type = "button", name = name, caption = caption, tags = tags, tooltip = tooltip})
  b.style.horizontally_stretchable = true
  b.style.maximal_width = 1000
  return b
end

function E.close(player)
  local s = st(player.index)
  if s and s.frame and s.frame.valid then s.frame.destroy() end
  if storage.editor then storage.editor[player.index] = nil end
end

function E.is_open(player)
  local s = st(player.index)
  return s and s.frame and s.frame.valid
end

local function show_list(player)
  local s = st(player.index)
  s.edit, s.io = nil, nil
  s.right.clear()
  s.crumb = s.right.add({type = "label", style = "caption_label"})
  local pane = s.right.add({type = "scroll-pane", style = "list_box_scroll_pane", direction = "vertical"})
  pane.style.vertically_stretchable = true
  pane.style.horizontally_stretchable = true
  pane.style.minimal_height = 400
  s.list = pane
  fill_list(player, s)
end

function E.open(player)
  if E.is_open(player) then return E.close(player) end
  local screen = player.gui.screen
  local f = screen.add({type = "frame", name = "ezactions_editor", direction = "vertical"})
  f.auto_center = true
  local bar = f.add({type = "flow", direction = "horizontal"})
  bar.drag_target = f
  bar.add({type = "label", caption = {"ezactions.editor-title"}, style = "frame_title", ignored_by_interaction = true})
  local drag = bar.add({type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true})
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  bar.add({type = "sprite-button", style = "frame_action_button", sprite = "utility/close",
           tags = {ezactions_ed = "close"}})
  local body = f.add({type = "flow", direction = "horizontal"})
  body.style.horizontal_spacing = 12
  local left = body.add({type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical"})
  left.style.width = 230
  local filter = left.add({type = "textfield", name = "ezactions_filter", tags = {ezactions_ed = "filter"}})
  filter.style.horizontally_stretchable = true
  filter.style.maximal_width = 1000
  filter.tooltip = {"ezactions.filter"}
  left.add({type = "line"})
  button(left, nil, {"ezactions.add-key"}, {ezactions_ed = "add", kind = "KEY"})
  button(left, nil, {"ezactions.add-command"}, {ezactions_ed = "add", kind = "COMMAND"})
  button(left, nil, {"ezactions.add-equip"}, {ezactions_ed = "add", kind = "EQUIP"})
  button(left, nil, {"ezactions.add-bundle"}, {ezactions_ed = "add", kind = "bundle"})
  left.add({type = "line"})
  button(left, nil, {"ezactions.edit"}, {ezactions_ed = "edit"})
  button(left, nil, {"ezactions.remove"}, {ezactions_ed = "remove"}, {"ezactions.remove-tip"})
  local ud = left.add({type = "flow", direction = "horizontal"})
  button(ud, nil, {"ezactions.up"}, {ezactions_ed = "up"})
  button(ud, nil, {"ezactions.down"}, {ezactions_ed = "down"})
  left.add({type = "line"})
  button(left, nil, {"ezactions.import"}, {ezactions_ed = "import"}, {"ezactions.import-tip"})
  button(left, nil, {"ezactions.export"}, {ezactions_ed = "export"}, {"ezactions.export-tip"})
  button(left, nil, {"ezactions.preview"}, {ezactions_ed = "preview"})
  local hint = left.add({type = "label", caption = {"ezactions.settings-hint"}})
  hint.style.single_line = false
  hint.style.font_color = {0.7, 0.7, 0.7}
  local right = body.add({type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical"})
  right.style.width = 460
  right.style.minimal_height = 470
  storage.editor = storage.editor or {}
  storage.editor[player.index] = {frame = f, right = right, filter_box = filter, path = {}, filter = ""}
  show_list(player)
end

local function refresh(player)
  local s = st(player.index)
  if s and s.list and s.list.valid and not s.edit and not s.io then fill_list(player, s) end
end
E.refresh = refresh

-- ---- editing one entry ----------------------------------------------------------------------------------------

local function signal_of(icon)
  local s = model.sprite(icon)
  if not s then return nil end
  local kind, name = s:match("^([%w%-]+)/(.+)$")
  if not kind then return nil end
  local map = {item = "item", fluid = "fluid", ["virtual-signal"] = "virtual", entity = "entity", recipe = "recipe",
               ["space-location"] = "space-location", ["asteroid-chunk"] = "asteroid-chunk", quality = "quality"}
  return map[kind] and {type = map[kind], name = name} or nil
end

local function icon_of_signal(sig)
  if not sig or not sig.name then return nil end
  local kind = ({virtual = "virtual-signal"})[sig.type or "item"] or (sig.type or "item")
  return kind .. "/" .. sig.name
end

--- the controls (FSE's input.controls), sorted; names only in multiplayer (bindings differ per computer)
local function controls()
  local out = actions.call("input", "controls", "")
  local list = out and helpers.json_to_table(out) or {}
  table.sort(list, function(a, b)
    if a.modded ~= b.modded then return not a.modded end
    return a.name < b.name
  end)
  return list
end

local function binding_text(k)
  if not k then return "" end
  local t = {}
  for _, m in ipairs(k.mods or {}) do t[#t + 1] = m:upper() end
  t[#t + 1] = k.scancode and k.scancode:gsub("^SDL_SCANCODE_", "") or k.mouse or "?"
  return table.concat(t, " + ")
end

local function control_name(c)
  local proto = c.modded and prototypes.custom_input[c.name]
  return proto and proto.localised_name or {"?", {"controls." .. c.name}, c.name}
end

--- the mod that made a control or shortcut ("core" for the game's own controls)
local function mod_of(kind, name)
  local h = prototypes.get_history(kind, name)
  return h and h.created or "core"
end

--- a control's icon: the shortcut that fires it, if one does
local function control_icon(name)
  for sc, proto in pairs(prototypes.shortcut) do
    if proto.associated_control_input == name and helpers.is_valid_sprite_path("shortcut/" .. sc) then
      return "shortcut/" .. sc
    end
  end
end

--- "@mod words": words match the internal name, @word the mod's name (any number of each, all must match)
local function parse_filter(text)
  local mods, words = {}, {}
  for w in text:lower():gmatch("%S+") do
    if w:sub(1, 1) == "@" then
      if #w > 1 then mods[#mods + 1] = w:sub(2) end
    else
      words[#words + 1] = w
    end
  end
  return function(name, mod)
    for _, m in ipairs(mods) do if not mod:lower():find(m, 1, true) then return false end end
    for _, w in ipairs(words) do if not name:find(w, 1, true) then return false end end
    return true
  end
end

local function fill_choices(player, s)
  local box = s.edit.choices
  if not (box and box.valid) then return end
  local src, ok = s.edit.source, parse_filter(s.edit.choice_filter or "")
  local items, names = {}, {}
  local function add(name, icon, label, extra, mod)
    items[#items + 1] = {"", icon and ("[img=" .. icon .. "] ") or "", label, "  [color=128,128,128]", extra,
                         " @", mod, "[/color]"}
    names[#names + 1] = name
  end
  if src == "control" then
    local mp = game.is_multiplayer()
    for _, c in ipairs(s.edit.controls) do
      local mod = c.modded and mod_of("custom-input", c.name) or "core"
      if ok(c.name, mod) then
        add(c.name, control_icon(c.name), control_name(c), mp and "" or binding_text(c.keys and c.keys[1]), mod)
      end
    end
  elseif src == "shortcut" then
    for name, proto in pairs(prototypes.shortcut) do
      local mod = mod_of("shortcut", name)
      if ok(name, mod) then
        add(name, helpers.is_valid_sprite_path("shortcut/" .. name) and ("shortcut/" .. name) or nil,
            proto.localised_name, name, mod)
      end
    end
  end
  box.items = items
  s.edit.names = names
  for i, n in ipairs(names) do
    if n == s.edit.name then box.selected_index = i box.scroll_to_item(i) end
  end
end

local function key_section(player, s, parent)
  local e = s.edit
  parent.clear()
  local line = parent.add({type = "flow", direction = "horizontal"})
  line.add({type = "label", caption = {"ezactions.source"}})
  local dd = line.add({type = "drop-down", tags = {ezactions_ed = "source"},
                       items = {{"ezactions.source-control"}, {"ezactions.source-shortcut"}, {"ezactions.source-hotkey"}}})
  for i, v in ipairs(SOURCES) do if v == e.source then dd.selected_index = i end end
  if e.source == "hotkey" then
    local f = parent.add({type = "flow", direction = "horizontal"})
    f.style.vertical_align = "center"
    local can = actions.has("std", "key_info") and not game.is_multiplayer()
    f.add({type = "button", caption = e.recording and {"ezactions.press-a-key"} or {"ezactions.record-key"},
           tags = {ezactions_ed = "record"}, enabled = can, tooltip = not can and {"ezactions.needs-fse-sp"} or nil})
    f.add({type = "label", caption = e.key and binding_text({mods = e.key.mods, scancode = e.key.name}) or {"ezactions.no-key"}})
  else
    if e.source == "control" and #e.controls == 0 then
      local l = parent.add({type = "label", caption = {"ezactions.needs-fse-controls"}})
      l.style.single_line = false
    end
    local tf = parent.add({type = "textfield", text = e.choice_filter or "", tags = {ezactions_ed = "choice_filter"},
                           tooltip = {"ezactions.choice-filter"}})
    tf.style.horizontally_stretchable = true
    tf.style.maximal_width = 1000
    local box = parent.add({type = "list-box", tags = {ezactions_ed = "choice"}})
    box.style.height = 200
    box.style.horizontally_stretchable = true
    box.style.maximal_width = 1000
    e.choices = box
    fill_choices(player, s)
  end
  parent.add({type = "checkbox", caption = {"ezactions.toggle"}, state = e.toggle == true, tags = {ezactions_ed = "toggle"},
              tooltip = {"ezactions.toggle-tip"}, enabled = e.source ~= "shortcut"})
end

local function edit(player, kind, item)
  local s = st(player.index)
  local a = item and item.action or {}
  s.io = nil
  s.edit = {kind = kind, id = item and item.id, source = a.source or "control", name = a.name, key = a.key,
            toggle = a.toggle, controls = (kind == "KEY") and controls() or {}}
  local r = s.right
  r.clear()
  r.add({type = "label", style = "caption_label",
         caption = {item and "ezactions.editing" or "ezactions.adding", kind == "bundle" and {"ezactions.type-bundle"} or {"ezactions.type-" .. kind:lower()}}})
  local t = r.add({type = "table", column_count = 2})
  t.style.horizontal_spacing = 8
  t.add({type = "label", caption = {"ezactions.title"}})
  local title = t.add({type = "textfield", name = "ezactions_title", text = item and item.title or ""})
  title.style.width = 300
  t.add({type = "label", caption = {"ezactions.note"}})
  local note = t.add({type = "textfield", name = "ezactions_note", text = item and item.note or ""})
  note.style.width = 300
  t.add({type = "label", caption = {"ezactions.icon"}})
  t.add({type = "choose-elem-button", name = "ezactions_icon", elem_type = "signal", signal = signal_of(item and item.icon)})
  s.edit.fields = {title = title, note = note}
  local section = r.add({type = "flow", direction = "vertical"})
  if kind == "KEY" then
    key_section(player, s, section)
  elseif kind == "COMMAND" then
    section.add({type = "label", caption = {"ezactions.command"}, tooltip = {"ezactions.command-tip"}})
    local box = section.add({type = "text-box", name = "ezactions_command", text = a.command or ""})
    box.style.width = 420
    box.style.height = 20 * player.mod_settings["ezactions-command-lines"].value + 8
    local f = section.add({type = "flow", direction = "horizontal"})
    f.add({type = "label", caption = {"ezactions.delay"}, tooltip = {"ezactions.delay-tip"}})
    local d = f.add({type = "textfield", name = "ezactions_delay", text = tostring(a.delay or 0), numeric = true})
    d.style.width = 60
    section.add({type = "checkbox", name = "ezactions_cycle", caption = {"ezactions.cycle"}, state = a.cycle == true,
                 tooltip = {"ezactions.cycle-tip"}})
  elseif kind == "EQUIP" then
    local g = section.add({type = "table", name = "ezactions_slots", column_count = 4})
    for _, slot in ipairs(actions.equip_slots) do
      g.add({type = "label", caption = SLOT_NAMES[slot]})
      local want = a.slots and a.slots[slot]
      g.add({type = "choose-elem-button", name = slot, elem_type = "item-with-quality",
             ["item-with-quality"] = want and {name = want.name, quality = want.quality} or nil})
    end
    section.add({type = "button", caption = {"ezactions.record-gear"}, tags = {ezactions_ed = "record_gear"},
                 tooltip = {"ezactions.record-gear-tip"}})
  elseif kind == "bundle" then
    section.add({type = "checkbox", name = "ezactions_hide", caption = {"ezactions.hide"}, state = item and item.hide == true,
                 tooltip = {"ezactions.hide-tip"}})
    local f = section.add({type = "flow", direction = "horizontal"})
    f.add({type = "label", caption = {"ezactions.keybind"}, tooltip = {"ezactions.keybind-tip"}})
    local items = {{"ezactions.keybind-none"}}
    for i = 1, 10 do items[#items + 1] = {"controls.ezactions-bundle", tostring(i)} end
    f.add({type = "drop-down", name = "ezactions_keybind", items = items, selected_index = (item and item.keybind or 0) + 1})
  end
  local bottom = r.add({type = "flow", direction = "horizontal"})
  bottom.add({type = "button", caption = {"ezactions.cancel"}, tags = {ezactions_ed = "cancel"}})
  local push = bottom.add({type = "empty-widget"})
  push.style.horizontally_stretchable = true
  bottom.add({type = "button", style = "confirm_button", caption = {"ezactions.save"}, tags = {ezactions_ed = "save"}})
end

--- opens the form for a new key action, its list on `source` and filtered by `filter` (API: open_editor's opts)
function E.add_key(player, source, filter)
  edit(player, "KEY")
  local s = st(player.index)
  s.edit.source, s.edit.choice_filter = source or "control", filter
  key_section(player, s, s.right.children[3])
end

local function find_el(root, name)
  if root.name == name then return root end
  for _, c in pairs(root.children) do
    local f = find_el(c, name)
    if f then return f end
  end
end

--- the flow under the title/note/icon table that holds the type's own fields
local function key_parent(s)
  return find_el(s.right, "ezactions_title").parent.parent.children[3]
end

local function save(player)
  local s = st(player.index)
  local e, r, pi = s.edit, s.right, player.index
  local title = e.fields.title.text
  local note = e.fields.note.text
  local icon = icon_of_signal(find_el(r, "ezactions_icon").elem_value)
  local item = e.id and model.find(pi, e.id) or nil
  local new = {id = e.id, title = title, note = note, icon = icon, locked = item and item.locked}
  if e.kind == "bundle" then
    if title == "" then return say(player, {"ezactions.need-title"}) end
    if model.title_taken(pi, title, e.id) then return say(player, {"ezactions.title-taken", title}) end
    new.children = item and item.children or {}
    new.hide = find_el(r, "ezactions_hide").state
    local k = find_el(r, "ezactions_keybind").selected_index - 1
    new.keybind = k > 0 and k or nil
  elseif e.kind == "KEY" then
    if e.source == "hotkey" then
      if not e.key then return say(player, {"ezactions.no-key"}) end
      new.action = {type = "KEY", source = "hotkey", key = e.key, toggle = e.toggle}
    else
      if not e.name then return say(player, {"ezactions.pick-one"}) end
      new.action = {type = "KEY", source = e.source, name = e.name, toggle = e.toggle}
      if new.title == "" then
        new.title = e.name
      end
      if not new.icon then
        new.icon = e.source == "control" and control_icon(e.name)
          or (helpers.is_valid_sprite_path("shortcut/" .. e.name) and ("shortcut/" .. e.name) or nil)
      end
    end
  elseif e.kind == "COMMAND" then
    new.action = {type = "COMMAND", command = find_el(r, "ezactions_command").text,
                  delay = tonumber(find_el(r, "ezactions_delay").text) or 0, cycle = find_el(r, "ezactions_cycle").state}
  elseif e.kind == "EQUIP" then
    local slots = {}
    for _, slot in ipairs(actions.equip_slots) do
      local v = find_el(r, "ezactions_slots")[slot].elem_value
      if v then slots[slot] = {name = v.name, quality = v.quality or "normal"} end
    end
    new.action = {type = "EQUIP", slots = slots}
  end
  if new.title == "" and e.kind == "KEY" and e.key then new.title = e.key.name end
  local clean, err = model.clean(pi, new)
  if not clean then return say(player, err) end
  if item then
    local _, list, i, path = model.find(pi, e.id)
    if clean.action and item.action and item.action.cursor then clean.action.cursor = item.action.cursor end
    list[i] = clean
    model.changed(pi, path, "edited")
  else
    local list = page(pi, s)
    list[#list + 1] = clean
    s.sel = clean.id
    model.changed(pi, s.path, "added")
  end
  show_list(player)
end

-- ---- import / export ------------------------------------------------------------------------------------------

local function show_io(player, text)
  local s = st(player.index)
  s.edit, s.io = nil, true
  local r = s.right
  r.clear()
  r.add({type = "label", style = "caption_label", caption = {"ezactions.io-title"}})
  local box = r.add({type = "text-box", name = "ezactions_io", text = text or ""})
  box.style.width = 430
  box.style.height = 380
  box.word_wrap = true
  if text and text ~= "" then box.select_all() box.focus() end
  local f = r.add({type = "flow", direction = "horizontal"})
  f.add({type = "button", caption = {"ezactions.back"}, tags = {ezactions_ed = "cancel"}})
  local push = f.add({type = "empty-widget"})
  push.style.horizontally_stretchable = true
  f.add({type = "button", caption = {"ezactions.replace-all"}, tags = {ezactions_ed = "replace_all"},
         tooltip = {"ezactions.replace-all-tip"}})
  f.add({type = "button", style = "confirm_button", caption = {"ezactions.import-here"}, tags = {ezactions_ed = "import_text"}})
end

local function import(player, text, replace)
  local s, pi = st(player.index), player.index
  local items, err = model.parse(pi, text)
  if not items then return say(player, {"ezactions.import-failed", err}) end
  if replace then
    model.data(pi).menu = items
    s.path = {}
  else
    model.upsert(pi, page(pi, s), items)
  end
  model.changed(pi, s.path, "imported")
  script.raise_event(model.imported_event, {player_index = pi, path = s.path, json = text, count = #items})
  say(player, {"ezactions.imported", #items})
  show_list(player)
end
E.import = import

-- ---- events ---------------------------------------------------------------------------------------------------

local function selected(player)
  local s = st(player.index)
  return s.sel and model.find(player.index, s.sel)
end

local handlers = {}

handlers.close = function(player) E.close(player) end
handlers.add = function(player, tags) edit(player, tags.kind) end
handlers.edit = function(player)
  local item = selected(player)
  if item then edit(player, item.children and "bundle" or item.action.type, item) end
end
handlers.remove = function(player)
  local s, item = st(player.index), selected(player)
  if not item then return end
  local ok, err = model.remove(player.index, item.id)
  if not ok then return say(player, {"ezactions.cant-remove", err}) end
  s.sel = nil
  show_list(player)
end
local function move(player, d)
  local s, pi = st(player.index), player.index
  if s.filter ~= "" then return say(player, {"ezactions.no-move-filtered"}) end
  local item, list, i, path = model.find(pi, s.sel or "")
  if not item or not list[i + d] then return end
  list[i], list[i + d] = list[i + d], list[i]
  model.changed(pi, path, "moved")
  refresh(player)
end
handlers.up = function(player) move(player, -1) end
handlers.down = function(player) move(player, 1) end
handlers.cancel = function(player) show_list(player) end
handlers.save = function(player) save(player) end
handlers.export = function(player)
  local text = model.export(model.data(player.index).menu)
  if actions.local_peer(player) and actions.has("std", "clipboard_set") then
    actions.call("std", "clipboard_set", text)
    say(player, {"ezactions.exported"})
  end
  show_io(player, text)
end
handlers.import = function(player)
  if not game.is_multiplayer() and actions.has("std", "clipboard_get") then
    local text = actions.call("std", "clipboard_get", "")
    if text and text:match("^%s*[%[{]") then return import(player, text) end
  end
  show_io(player, "")
end
handlers.import_text = function(player) import(player, find_el(st(player.index).right, "ezactions_io").text) end
handlers.replace_all = function(player) import(player, find_el(st(player.index).right, "ezactions_io").text, true) end
handlers.preview = function(player)
  local menu = model.data(player.index).menu
  remote.call("ezactions", "preview", player.index)
  if #menu == 0 then say(player, {"ezactions.empty"}) end
end
handlers.record = function(player)
  local s = st(player.index)
  s.edit.recording = game.tick
  storage.recording = storage.recording or {}
  storage.recording[player.index] = true
  key_section(player, s, key_parent(s))
end
handlers.record_gear = function(player)
  local g = find_el(st(player.index).right, "ezactions_slots")
  local slots = actions.record(player)
  for _, slot in ipairs(actions.equip_slots) do
    local w = slots[slot]
    g[slot].elem_value = w and {name = w.name, quality = w.quality} or nil
  end
end

function E.on_click(e)
  local el, player = e.element, game.get_player(e.player_index)
  local s = st(e.player_index)
  if not s then return end
  local tags = el.tags
  if tags.ezactions_ed and handlers[tags.ezactions_ed] then return handlers[tags.ezactions_ed](player, tags) end
  if tags.ezactions_row then
    local item = model.find(player.index, tags.ezactions_row)
    if not item then return refresh(player) end
    if e.button == defines.mouse_button_type.right then
      if item.children then
        s.path[#s.path + 1] = item.id
        s.sel = nil
      end
    elseif s.sel == item.id then
      return handlers.edit(player)
    else
      s.sel = item.id
    end
    return refresh(player)
  end
  if tags.ezactions_nav then
    for i = #s.path, tags.ezactions_nav + 1, -1 do s.path[i] = nil end
    return refresh(player)
  end
  local pi = player.index
  if tags.ezactions_move_into then
    local b = model.find(pi, tags.ezactions_move_into)
    if b and model.move_to(pi, s.sel, b.children, s.path) then s.sel = nil end
    return refresh(player)
  end
  if tags.ezactions_move_nav then
    local path = {table.unpack(s.path, 1, tags.ezactions_move_nav)}
    if model.move_to(pi, s.sel, model.resolve(pi, path), path) then s.sel = nil end
    return refresh(player)
  end
end

function E.on_text(e)
  local s = st(e.player_index)
  if not s then return end
  local tag = e.element.tags.ezactions_ed
  local player = game.get_player(e.player_index)
  if tag == "filter" then
    s.filter = e.element.text
    refresh(player)
  elseif tag == "choice_filter" and s.edit then
    s.edit.choice_filter = e.element.text
    fill_choices(player, s)
  end
end

function E.on_selection(e)
  local s = st(e.player_index)
  if not (s and s.edit) then return end
  local tag = e.element.tags.ezactions_ed
  local player = game.get_player(e.player_index)
  if tag == "source" then
    s.edit.source = SOURCES[e.element.selected_index]
    s.edit.name = nil
    key_section(player, s, key_parent(s))
  elseif tag == "choice" then
    s.edit.name = s.edit.names[e.element.selected_index]
  end
end

function E.on_checked(e)
  local s = st(e.player_index)
  if s and s.edit and e.element.tags.ezactions_ed == "toggle" then s.edit.toggle = e.element.state end
end

--- recording a direct hotkey: the first key (not a modifier, not the mouse button that clicked Record)
function E.tick()
  if not storage.recording then return end
  for pi in pairs(storage.recording) do
    local s, player = st(pi), game.get_player(pi)
    if not (s and s.edit and s.edit.recording and player) then
      storage.recording[pi] = nil
    elseif game.tick - s.edit.recording > 60 * 10 then
      storage.recording[pi], s.edit.recording = nil, nil
      key_section(player, s, key_parent(s))
    else
      local out = actions.call("std", "input", "")
      local inp = out and helpers.json_to_table(out)
      for _, vk in ipairs(inp and inp.keys or {}) do
        if vk > 2 and not (vk >= 16 and vk <= 18) and not (vk >= 160 and vk <= 165) then
          local info = helpers.json_to_table(actions.call("std", "key_info", tostring(vk)) or "{}") or {}
          local mods = {}
          for _, m in ipairs({"ctrl", "shift", "alt"}) do if inp[m] then mods[#mods + 1] = m end end
          local mouse = ({[4] = "middle", [5] = "x1", [6] = "x2"})[vk]
          s.edit.key = {vk = not mouse and vk or nil, mouse = mouse, mods = mods,
                        name = mouse and ("mouse " .. mouse) or (info.name ~= "" and info.name or ("key " .. vk))}
          if (s.edit.fields.title.text or "") == "" then s.edit.fields.title.text = s.edit.key.name end
          storage.recording[pi], s.edit.recording = nil, nil
          key_section(player, s, key_parent(s))
          break
        end
      end
    end
  end
end

function E.delete(player)
  local s = st(player.index)
  if s and E.is_open(player) and not s.edit and not s.io then handlers.remove(player) end
end

function E.focus_search(player)
  local s = st(player.index)
  if s and E.is_open(player) and s.filter_box.valid then s.filter_box.focus() end
end

function E.owns(el)
  local f = el
  while f do
    if f.name == "ezactions_editor" then return true end
    f = f.parent
  end
  return false
end

return E
