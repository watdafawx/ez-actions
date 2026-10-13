-- The menu editor: the current page's entries (root or a bundle). Click selects, clicking the selected row again
-- edits it, right-click opens a bundle. With an entry selected, the arrow beside a bundle or a "back" row moves it
-- there. Delete removes the selected entry (after asking), Ctrl+F jumps to the filter.
-- With fse-std's layouts (0.7+), the window as our other mods' (fse/README.md, "A window's layout"): the Add buttons
-- on a tools rail out of its right edge, a dock below it with the selected entry's tools (Edit, Remove, Up, Down) and,
-- apart from them, the menu's (Import, Export, Preview), the look and feel behind the gear by the close button
-- ("Docked" first there: unticked, all inside). Without fse-std: the game's styles, all inside.
local model = require("scripts.model")
local actions = require("scripts.actions")
local E = {}
local WIN = "ezactions_editor"

-- drag & drop rows (fse-std with the FSE loader, single player): onto a bundle moves into it, onto a row takes its
-- place, onto a "back" row moves up. Without it the arrow buttons do the same.
local dnd, input
if script.active_mods["fse-std"] then dnd, input = require("__fse-std__/dnd"), require("__fse-std__/input") end
local function can_drag() return dnd ~= nil and input.native() end
-- themes (fse-std 0.6+, optional): the editor in the player's theme (E.adopt). Layouts (0.7+): window.create, its
-- gear and theme.menu, rails, docks and theme.confirm.
local theme, window
if script.active_mods["fse-std"] then
  local ok, t = pcall(require, "__fse-std__/theme")
  theme = ok and t.adopt and t or nil
  if theme and theme.menu and theme.dock and theme.attach and theme.confirm then
    local ok2, w = pcall(require, "__fse-std__/window")
    window = ok2 and w or nil
  end
end
E.dnd, E.theme, E.window, E.input = dnd, theme, window, input

local SOURCES = {"control", "shortcut", "hotkey"}
local OUTLINES = {false, "off", "stroke", "glow", "both"} -- (the editor's choices; false: the player's setting)
local SLOT_NAMES = {armor = {"ezactions.slot-armor"}, gun1 = {"ezactions.slot-gun", 1}, gun2 = {"ezactions.slot-gun", 2},
                    gun3 = {"ezactions.slot-gun", 3}, ammo1 = {"ezactions.slot-ammo", 1}, ammo2 = {"ezactions.slot-ammo", 2},
                    ammo3 = {"ezactions.slot-ammo", 3}, hand = {"ezactions.slot-hand"}}
-- the look and feel in the gear's panel: the per-player mod settings (settings.lua), by group
local LOOK = {
  {"ezactions.look-general", {"hold-release", "show-hover-label", "command-lines"}, true},
  {"ezactions.look-ring", {"design", "radius", "button-size", "scale-start", "scale-per-item", "slice-gap", "icon-outline",
                           "deadzone"}},
  {"ezactions.look-colours", {"ring-color", "hover-color", "border-color", "text-color"}},
  {"ezactions.look-animations", {"animations", "anim-open", "anim-hover", "open-style", "direction", "hover-style",
                                 "hover-grow", "open-ms"}},
}

local INSIDE_EXTRA = 280  -- (the window's width less its list column's, all inside: buttons, gaps, borders)

local function st(pi)
  storage.editor = storage.editor or {}
  return storage.editor[pi]
end

local function say(player, text)
  player.create_local_flying_text({text = text, create_at_cursor = true})
end

--- the layout with fse-std 0.7+ unless the player unticked "Docked"
local function docked(pi)
  return window ~= nil and not (storage.editor_inside and storage.editor_inside[pi])
end

--- the frames stuck to the window (rail, dock, settings): fse-std's theme.attach
local function attached(player, keep_menu)
  local out = {}
  for _, c in pairs(player.gui.screen.children) do
    local a = c.tags.fstd_attach
    if a and a.owner == WIN and c.get_mod() == script.mod_name and not (keep_menu and c.name == WIN .. "__menu") then
      out[#out + 1] = c
    end
  end
  return out
end

--- themes what the editor built with the game's styles (its window and the frames stuck to it)
function E.adopt(player)
  if not (theme and player) then return end
  local f = player.gui.screen[WIN]
  if f then theme.adopt(f) end
  for _, c in pairs(attached(player)) do theme.adopt(c) end
end

local TYPE_KEYS = {"ezactions.type-bundle", "ezactions.type-key-control", "ezactions.type-key-shortcut",
                   "ezactions.type-key-hotkey", "ezactions.type-command", "ezactions.type-equip"}

local function type_key(item)
  if item.children then return "ezactions.type-bundle" end
  local a = item.action
  if a.type == "KEY" then return "ezactions.type-key-" .. a.source end
  return "ezactions.type-" .. a.type:lower()
end

--- the type badge after a title, unless the title already says it ("Loadout  Loadout"): nil then. The type names in
--- the player's language come from E.translate (until they're in, the badge shows).
local function type_badge(pi, item)
  local key = type_key(item)
  local names = storage.type_names and storage.type_names[pi]
  local name = names and names[key]
  if name and name:lower() == (item.title or ""):lower() then return nil end
  return {key}
end

--- asks for the type names in the player's language (model.translated stores them)
function E.translate(player)
  if not player.connected then return end
  storage.translating = storage.translating or {}
  for _, key in ipairs(TYPE_KEYS) do
    local id = player.request_translation({key})
    if id then storage.translating[id] = {pi = player.index, type_key = key} end
  end
end

--- is the player's fse-std theme a light one?
local function light(player)
  local th = theme and theme.of(player)
  local t = th and theme.themes and theme.themes.by_name[th.carrier]
  return t and t.light or false
end

--- a sprite for the editor's lists: a shortcut's icon in the colour that shows on the window (data-final-fixes.lua:
--- the game draws them black on light buttons or white on coloured ones)
local function gui_icon(player, sprite)
  local name = sprite and sprite:match("^shortcut/(.+)$")
  if name then
    local alt = (light(player) and "ezactions-scw-" or "ezactions-scb-") .. name
    if helpers.is_valid_sprite_path(alt) then return alt end
  end
  return sprite
end
E.gui_icon = gui_icon

--- the entry's icon as rich text (its kind's when it has none; a blank one of the same size as the last resort, so
--- the titles line up)
local function rich_icon(player, item)
  return "[img=" .. (gui_icon(player, model.icon_of(item)) or "ezactions-blank") .. "] "
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
  if can_drag() then dnd.droppable(b, "ezactions-row") end
  if move_tags then
    flow.add({type = "sprite-button", style = "mini_button", sprite = "utility/enter", tags = move_tags,
              tooltip = {"ezactions.move-here"}})
  end
  return b
end

--- Edit, Remove, Up and Down: only with an entry selected on the list (Up/Down only where it can go)
local function update_tools(pi, s)
  local tools = s.tools or {}
  local item, list, i = nil, nil, nil
  if s.sel and not s.edit and not s.io then item, list, i = model.find(pi, s.sel) end
  local here = item and list == page(pi, s)
  local function set(name, on)
    local b = tools[name]
    if b and b.valid then b.enabled = on and true or false end
  end
  set("edit", item)
  set("remove", item)
  set("up", here and i > 1)
  set("down", here and list[i + 1] ~= nil)
  set("import", not s.edit)  -- (the menu's tools wait while an entry's form is open)
  set("export", not s.edit)
  set("preview", not s.edit)
  local rm = tools.remove
  if rm and rm.valid then  -- (without fse-std's question: the second click removes)
    rm.caption = (item and s.arm == item.id) and {"ezactions.remove-again"} or {"ezactions.remove"}
  end
end

local function fill_list(player, s)
  local pi = player.index
  local pane = s.list
  if not (pane and pane.valid) then return end
  pane.clear()
  local list = page(pi, s)
  local names = titles(pi, s.path)
  s.crumb.caption = #names > 0 and {"", {"ezactions.all-actions"}, " / " .. table.concat(names, " / ")}
                    or {"ezactions.all-actions"}
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
      local badge = type_badge(pi, item)
      local caption = {"", rich_icon(player, item),
                       item.locked and {"", "[color=255,200,80]", {"ezactions.locked"}, "[/color] "} or "", item.title,
                       badge and {"", "  [color=128,128,128]", badge, "[/color]"} or ""}
      local can_move_in = item.children and sel_here and s.sel ~= item.id
      local b = row(pane, caption, {ezactions_row = item.id, ezactions_index = i}, s.sel == item.id,
                    can_move_in and {ezactions_move_into = item.id} or nil, item.note ~= "" and item.note or nil)
      if can_drag() then
        dnd.draggable(b, {kind = "ezactions-row", id = item.id, sprite = model.sprite(item.icon), caption = item.title})
      end
    end
  end
  if #list == 0 then
    local l = pane.add({type = "label", caption = {"ezactions.page-empty"}})
    l.style.single_line = false
  end
  update_tools(pi, s)
end

-- ---- the window -----------------------------------------------------------------------------------------------

local function button(parent, caption, tags, tooltip, width)
  local b = parent.add({type = "button", caption = caption, tags = tags, tooltip = tooltip})
  if width and theme then  -- (themed now: a size set on the game's style would be lost when adopt() themes it)
    theme.apply(b, "button", {width = width})
  elseif width then
    b.style.width = width
  else
    b.style.horizontally_stretchable = true
    b.style.maximal_width = 1000
  end
  return b
end

function E.close(player)
  local s = st(player.index)
  local f = player.gui.screen[WIN]
  if f then f.destroy() end
  for _, c in pairs(attached(player)) do c.destroy() end
  local q = player.gui.screen["fstd_confirm_ezactions_remove"]
  if q and q.get_mod() == script.mod_name then q.destroy() end
  if s and s.frame and s.frame.valid then s.frame.destroy() end
  if storage.editor then storage.editor[player.index] = nil end
end

function E.is_open(player)
  local s = st(player.index)
  return s and s.frame and s.frame.valid
end

--- the filter's icon: dark on a light theme
local function search_sprite(player)
  if light(player) and helpers.is_valid_sprite_path("fstd-black-search") then return "fstd-black-search" end
  return "utility/search"
end

--- a text fse-std's locale has for every mod's windows (fse/README.md), else this mod's own
local function shared(key, own)
  return {"?", {"fstd." .. key}, {"ezactions." .. own}}
end

local function show_list(player)
  local s = st(player.index)
  s.edit, s.io = nil, nil
  s.right.clear()
  local top = s.right.add({type = "flow", direction = "horizontal"})
  top.style.vertical_align = "center"
  top.style.horizontal_spacing = 6
  local icon = top.add({type = "sprite", sprite = search_sprite(player), tooltip = {"ezactions.filter"},
                        tags = {ezactions_search_icon = true}})
  icon.style.size = 16
  icon.style.stretch_image_to_widget_size = true
  local filter = top.add({type = "textfield", name = "ezactions_filter", text = s.filter, tags = {ezactions_ed = "filter"},
                          tooltip = {"ezactions.filter"}, lose_focus_on_confirm = true})
  filter.style.horizontally_stretchable = true
  filter.style.maximal_width = 1000
  s.filter_box = filter
  s.crumb = s.right.add({type = "label", style = "caption_label"})
  local pane = s.right.add({type = "scroll-pane", style = "list_box_scroll_pane", direction = "vertical"})
  pane.style.vertically_stretchable = true
  pane.style.horizontally_stretchable = true
  if not window then pane.style.minimal_height = 400 end
  s.list = pane
  fill_list(player, s)
end

--- builds the window (again: the state in storage stays, so a rebuild keeps the page, the selection and the filter)
local function build(player)
  local pi = player.index
  local s = st(pi)
  local screen = player.gui.screen
  for _, c in pairs(attached(player, true)) do c.destroy() end  -- (the rail and dock it had; its settings stay)
  local dock = docked(pi)
  local f, content
  if window then
    f, content = window.create(player, {name = WIN, title = {"ezactions.editor-title"}, themed = true, settings = true,
                                        width = dock and 600 or 780, height = 620, min_width = dock and 600 or 700,
                                        min_height = 420})
  else  -- (the game's styles: a title bar, the content below)
    if screen[WIN] then screen[WIN].destroy() end
    f = screen.add({type = "frame", name = WIN, direction = "vertical"})
    f.auto_center = true
    local bar = f.add({type = "flow", direction = "horizontal"})
    bar.drag_target = f
    bar.add({type = "label", caption = {"ezactions.editor-title"}, style = "frame_title", ignored_by_interaction = true})
    local drag = bar.add({type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true})
    drag.style.horizontally_stretchable = true
    drag.style.height = 24
    bar.add({type = "sprite-button", style = "frame_action_button", sprite = "utility/close",
             tags = {ezactions_ed = "close"}, tooltip = {"gui.close"}})
    content = f
  end
  s.frame, s.tools = f, {}
  local function tool(parent, name, caption, tooltip, width)
    local b = button(parent, caption, {ezactions_ed = name}, tooltip, width)
    s.tools[name] = b
    return b
  end
  local ADDS = {{"KEY", "ezactions.add-key"}, {"COMMAND", "ezactions.add-command"}, {"EQUIP", "ezactions.add-equip"},
                {"bundle", "ezactions.add-bundle"}}
  if dock then
    -- the Add buttons on a tools rail out of the right edge
    local RAIL_W, BH = 148, 30
    local rail = theme.attach(f, "right", {size = {RAIL_W, #ADDS * (BH + 4) + 4}, along = 48, overlap = 6, role = "inset",
                                           direction = "vertical", padding = 4})
    local rf = rail.add({type = "flow", direction = "vertical"})
    rf.style.vertical_spacing = 4
    for _, a in ipairs(ADDS) do
      theme.add(rf, {type = "button", caption = {a[2]}, tags = {ezactions_ed = "add", kind = a[1]}}, "rtab",
                {width = RAIL_W - 8, height = BH})
    end
    -- a dock below: the selected entry's tools, apart from them the menu's (Import, Export, Preview), clear of its ends
    local d = theme.dock(f, {size = {590, 44}})
    local df = d.add({type = "flow", direction = "horizontal"})
    df.style.horizontally_stretchable = true
    df.style.vertical_align = "center"
    df.style.horizontal_spacing = 0  -- (the gaps are its spacers)
    local function group()
      local g = df.add({type = "flow", direction = "horizontal"})
      g.style.horizontal_spacing = 4
      return g
    end
    df.add({type = "empty-widget"}).style.width = 6
    local sel = group()
    tool(sel, "edit", {"ezactions.edit"}, {"ezactions.edit-tip"}, 60)
    tool(sel, "remove", {"ezactions.remove"}, {"ezactions.remove-tip"}, 80)
    tool(sel, "up", {"ezactions.up"}, nil, 64)
    tool(sel, "down", {"ezactions.down"}, nil, 84)
    local gap = df.add({type = "empty-widget"})
    gap.style.horizontally_stretchable = true
    gap.style.minimal_width = 16
    local file = group()
    tool(file, "import", {"ezactions.import"}, {"ezactions.import-tip"}, 76)
    tool(file, "export", {"ezactions.export"}, {"ezactions.export-tip"}, 76)
    tool(file, "preview", {"ezactions.preview"}, {"ezactions.preview-tip"}, 84)
    df.add({type = "empty-widget"}).style.width = 6
    s.right = content
  else
    -- all inside: the buttons in a column on the left, the list on the right
    local body = content.add({type = "flow", direction = "horizontal"})
    body.style.horizontal_spacing = 12
    body.style.vertically_stretchable = true
    body.style.horizontally_stretchable = true
    local left
    if window then
      left = body.add({type = "flow", direction = "vertical"})
      left.style.vertical_spacing = 4
    else
      left = body.add({type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical"})
    end
    left.style.width = 220
    for _, a in ipairs(ADDS) do button(left, {a[2]}, {ezactions_ed = "add", kind = a[1]}) end
    left.add({type = "line"})
    tool(left, "edit", {"ezactions.edit"}, {"ezactions.edit-tip"})
    tool(left, "remove", {"ezactions.remove"}, {"ezactions.remove-tip"})
    local ud = left.add({type = "flow", direction = "horizontal"})
    tool(ud, "up", {"ezactions.up"})
    tool(ud, "down", {"ezactions.down"})
    left.add({type = "line"})
    tool(left, "import", {"ezactions.import"}, {"ezactions.import-tip"})
    tool(left, "export", {"ezactions.export"}, {"ezactions.export-tip"})
    tool(left, "preview", {"ezactions.preview"}, {"ezactions.preview-tip"})
    if not window then  -- (with fse-std the look and feel is behind the gear)
      local hint = left.add({type = "label", caption = {"ezactions.settings-hint"}})
      hint.style.single_line = false
      hint.style.font_color = {0.7, 0.7, 0.7}
    end
    local right
    if window then
      -- (its width follows the window's: a stretchable flow here stopped short of the window's edge)
      right = body.add({type = "flow", direction = "vertical", name = "ezactions_right"})
      right.style.width = math.max(300, (window.size(player, WIN) or 780) - INSIDE_EXTRA)
      right.style.vertically_stretchable = true
    else
      right = body.add({type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical"})
      right.style.width = 460
      right.style.minimal_height = 470
    end
    s.right = right
  end
  show_list(player)
  E.adopt(player)
  if window then
    theme.follow(f)
    -- (made again from the gear's panel, Docked or Reset: the panel gives Esc back to this window, not the old one)
    local m = screen[WIN .. "__menu"]
    if m and m.valid and m.tags.fstd_return then
      local tags = m.tags
      tags.fstd_return = f.index
      m.tags = tags
    end
  end
end

function E.open(player)
  if E.is_open(player) then return E.close(player) end
  storage.editor = storage.editor or {}
  storage.editor[player.index] = {path = {}, filter = ""}
  E.translate(player)
  build(player)
end

--- the gear's "Docked": the window made again, at its new layout's first size
local function set_docked(player, on)
  storage.editor_inside = storage.editor_inside or {}
  storage.editor_inside[player.index] = (not on) or nil
  local w = storage.fstd_windows and storage.fstd_windows[player.index]
  if w and w[WIN] then w[WIN].width, w[WIN].height = nil, nil end
  build(player)
end

local function refresh(player)
  local s = st(player.index)
  if s and s.list and s.list.valid and not s.edit and not s.io then fill_list(player, s) end
end
E.refresh = refresh

-- ---- the look and feel (the gear's panel) ---------------------------------------------------------------------

local function hex(c)
  local function b(v) return math.floor(math.max(0, math.min(1, v or 1)) * 255 + 0.5) end
  return string.format("%02X%02X%02X%02X", b(c.r or c[1]), b(c.g or c[2]), b(c.b or c[3]), b(c.a or c[4]))
end

local function setting_control(parent, player, name)
  local full = "ezactions-" .. name
  local proto = prototypes.mod_setting[full]
  if not proto then return end
  local tip = {"?", {"mod-setting-description." .. full}, ""}
  local value = player.mod_settings[full].value
  local tags = {ezactions_set = full}
  local t = proto.type
  if t == "bool-setting" then  -- (the box before its text, as everywhere else; nothing in the second column)
    parent.add({type = "checkbox", caption = {"mod-setting-name." .. full}, state = value == true, tags = tags,
                tooltip = tip}).style.minimal_width = 170
    parent.add({type = "empty-widget"})
    return
  end
  parent.add({type = "label", caption = {"mod-setting-name." .. full}, tooltip = tip}).style.minimal_width = 170
  if t == "string-setting" then
    local items, sel = {}, 1
    for i, v in ipairs(proto.allowed_values or {}) do
      items[i] = {"?", {"string-mod-setting." .. full .. "-" .. v}, v}
      if v == value then sel = i end
    end
    parent.add({type = "drop-down", items = items, selected_index = sel, tags = tags, tooltip = tip}).style.width = 150
  elseif t == "color-setting" then
    parent.add({type = "textfield", text = hex(value), tags = tags, tooltip = {"ezactions.colour-tip"}}).style.width = 100
  else
    local tf = parent.add({type = "textfield", text = tostring(value), numeric = true, allow_negative = false,
                           allow_decimal = t == "double-setting", tags = tags,
                           tooltip = {"", tip, "\n", {"ezactions.range", tostring(proto.minimum_value),
                                                         tostring(proto.maximum_value)}}})
    tf.style.width = 80
  end
end

--- the gear: the window's settings (Docked, Theme..., reset) and the look and feel, in fse-std's theme.menu
local function open_settings(player)
  local f = player.gui.screen[WIN]
  local m = f and theme.menu(f, {size = {400, 480}})
  if not m then return end
  theme.apply(m.add({type = "label", caption = {"ezactions.editor-title"}}), "caption")
  local scroll = m.add({type = "scroll-pane", horizontal_scroll_policy = "never", vertical_scroll_policy = "auto"})
  scroll.style.vertically_stretchable = true
  scroll.style.horizontally_stretchable = true
  -- (the window's own setting first, as in our other mods' panels; then the look and feel)
  local dk = scroll.add({type = "checkbox", name = "ezactions_docked", caption = shared("docked", "docked"),
                         state = docked(player.index), tags = {ezactions_ed = "docked"},
                         tooltip = shared("docked-tooltip", "docked-tip")})
  dk.style.bottom_margin = 6
  if window.size_setting then  -- (the window's own Size, fse-std 0.8: after Docked)
    window.size_setting(scroll, WIN).parent.style.bottom_margin = 6
  end
  for _, g in ipairs(LOOK) do
    local body = theme.fold(scroll, {g[1]}, g[3] == true)
    theme.apply(body.parent, "section", {horizontally_stretchable = true})
    local t = body.add({type = "table", column_count = 2})
    t.style.vertical_align = "center"
    t.style.horizontal_spacing = 12
    t.style.vertical_spacing = 4
    for _, name in ipairs(g[2]) do setting_control(t, player, name) end
  end
  local foot = m.add({type = "flow", direction = "horizontal"})
  foot.style.horizontal_spacing = 6
  local i = remote.interfaces["fse-std"]
  if i and i.open_theme then
    button(foot, shared("theme-button", "theme"), {ezactions_ed = "theme"}, shared("theme-button-tooltip", "theme-tip"), 100)
  end
  button(foot, shared("reset-place", "reset-place"), {ezactions_ed = "reset_place"},
         shared("reset-place-tooltip", "reset-place-tip"), 180)
  theme.adopt(m)
end
E.open_settings = open_settings

--- a look-and-feel control changed: the player's mod setting (checkbox, drop-down, or a valid number / colour)
local function set_setting(player, el)
  local full = el.tags.ezactions_set
  local proto = prototypes.mod_setting[full]
  if not proto then return end
  local value
  if el.type == "checkbox" then
    value = el.state
  elseif el.type == "drop-down" then
    value = proto.allowed_values[el.selected_index]
  elseif proto.type == "color-setting" then
    local h = el.text:gsub("^#", "")
    if not (h:match("^%x%x%x%x%x%x$") or h:match("^%x%x%x%x%x%x%x%x$")) then return end
    local function c(k) return tonumber(h:sub(k, k + 1), 16) / 255 end
    value = {r = c(1), g = c(3), b = c(5), a = #h == 8 and c(7) or 1}
  else
    value = tonumber(el.text)
    if not value or value < proto.minimum_value or value > proto.maximum_value then return end
    if proto.type == "int-setting" then value = math.floor(value) end
  end
  if value ~= nil then player.mod_settings[full] = {value = value} end
end


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
    icon = gui_icon(player, icon)
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
  r.add({type = "label", style = "caption_label", caption = {(item and "ezactions.form-edit-" or "ezactions.form-add-") .. kind}})
  -- (the fields scroll; Cancel and Save stay pinned below them)
  local form = r.add({type = "scroll-pane", horizontal_scroll_policy = "never", vertical_scroll_policy = "auto"})
  form.style.vertically_stretchable = true
  form.style.horizontally_stretchable = true
  local t = form.add({type = "table", column_count = 2})
  t.style.horizontal_spacing = 8
  t.add({type = "label", caption = {"ezactions.title"}})
  local title = t.add({type = "textfield", name = "ezactions_title", text = item and item.title or ""})
  title.style.width = 300
  t.add({type = "label", caption = {"ezactions.note"}})
  local note = t.add({type = "textfield", name = "ezactions_note", text = item and item.note or ""})
  note.style.width = 300
  t.add({type = "label", caption = {"ezactions.icon"}})
  t.add({type = "choose-elem-button", name = "ezactions_icon", elem_type = "signal", signal = signal_of(item and item.icon)})
  t.add({type = "label", caption = {"ezactions.outline"}, tooltip = {"ezactions.outline-tip"}})
  local oi = 1
  for i, v in ipairs(OUTLINES) do if item and item.outline == v then oi = i end end
  t.add({type = "drop-down", name = "ezactions_outline", selected_index = oi,
         items = {{"ezactions.outline-default"}, {"string-mod-setting.ezactions-icon-outline-off"},
                  {"string-mod-setting.ezactions-icon-outline-stroke"}, {"string-mod-setting.ezactions-icon-outline-glow"},
                  {"string-mod-setting.ezactions-icon-outline-both"}}})
  local section = form.add({type = "flow", direction = "vertical"})
  s.edit.fields, s.edit.section = {title = title, note = note}, section
  if kind == "KEY" then
    key_section(player, s, section)
  elseif kind == "COMMAND" then
    section.add({type = "label", caption = {"ezactions.command"}, tooltip = {"ezactions.command-tip"}})
    local box = section.add({type = "text-box", name = "ezactions_command", text = a.command or ""})
    box.style.width = 400
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
    section.add({type = "checkbox", name = "ezactions_hide", caption = {"ezactions.hide"}, state = (item and item.hide) == true,
                 tooltip = {"ezactions.hide-tip"}})
    local f = section.add({type = "flow", direction = "horizontal"})
    f.add({type = "label", caption = {"ezactions.keybind"}, tooltip = {"ezactions.keybind-tip"}})
    local items = {{"ezactions.keybind-none"}}
    for i = 1, 10 do items[#items + 1] = {"controls.ezactions-bundle", tostring(i)} end
    f.add({type = "drop-down", name = "ezactions_keybind", items = items, selected_index = (item and item.keybind or 0) + 1})
  end
  local bottom = r.add({type = "flow", direction = "horizontal"})
  bottom.style.top_margin = 6
  bottom.add({type = "button", caption = {"ezactions.cancel"}, tags = {ezactions_ed = "cancel"}})
  local push = bottom.add({type = "empty-widget"})
  push.style.horizontally_stretchable = true
  bottom.add({type = "button", style = "confirm_button", caption = {"ezactions.save"}, tags = {ezactions_ed = "save"}})
  update_tools(player.index, s)
end

--- opens the form for a new entry (kind: KEY, COMMAND, EQUIP or bundle); a key action's list on `source`, filtered by
--- `filter` (API: open_editor's opts)
function E.add(player, kind, source, filter)
  edit(player, kind)
  if kind ~= "KEY" then return end
  local s = st(player.index)
  s.edit.source, s.edit.choice_filter = source or "control", filter
  key_section(player, s, s.edit.section)
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
  return s.edit.section
end

local function save(player)
  local s = st(player.index)
  local e, r, pi = s.edit, s.right, player.index
  local title = e.fields.title.text
  local note = e.fields.note.text
  local icon = icon_of_signal(find_el(r, "ezactions_icon").elem_value)
  local item = e.id and model.find(pi, e.id) or nil
  local new = {id = e.id, title = title, note = note, icon = icon, locked = item and item.locked,
               outline = OUTLINES[find_el(r, "ezactions_outline").selected_index]}
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
  model.name_later(player, clean)  -- (no title: the game's name for what it fires, not its internal name)
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
  if window then  -- (the window can be resized: the box takes what there is)
    box.style.horizontally_stretchable, box.style.vertically_stretchable = true, true
    box.style.maximal_width, box.style.minimal_height = 1000, 120
  else
    box.style.width = 430
    box.style.height = 380
  end
  box.word_wrap = true
  if text and text ~= "" then box.select_all() box.focus() end
  local f = r.add({type = "flow", direction = "horizontal"})
  f.add({type = "button", caption = {"ezactions.back"}, tags = {ezactions_ed = "cancel"}})
  local push = f.add({type = "empty-widget"})
  push.style.horizontally_stretchable = true
  f.add({type = "button", caption = {"ezactions.replace-all"}, tags = {ezactions_ed = "replace_all"},
         tooltip = {"ezactions.replace-all-tip"}})
  f.add({type = "button", style = "confirm_button", caption = {"ezactions.import-here"}, tags = {ezactions_ed = "import_text"}})
  update_tools(player.index, s)
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
local function remove_now(player, id)
  local s = st(player.index)
  local ok, err = model.remove(player.index, id)
  if not ok then return say(player, {"ezactions.cant-remove", err}) end
  if s then s.sel, s.arm = nil, nil end
  refresh(player)
end
-- Remove and Delete ask first: fse-std's question (Esc = no), else a second click (or Delete) removes
handlers.remove = function(player)
  local s, item = st(player.index), selected(player)
  if not item then return end
  local n, locked = 0, item.locked
  model.walk(item.children or {}, function(c)
    n = n + 1
    if c.locked then locked = true end
  end)
  if locked then return say(player, {"ezactions.cant-remove-locked", item.title}) end
  local question = n > 0 and {"ezactions.remove-bundle-q", item.title, n} or {"ezactions.remove-q", item.title}
  if window then
    return theme.confirm(player, {name = "ezactions_remove", title = {"ezactions.remove-title"}, text = question,
                                  yes = {"ezactions.remove"}, no = {"ezactions.cancel"}, data = {id = item.id},
                                  danger = true})
  end
  if s.arm == item.id then return remove_now(player, item.id) end
  s.arm = item.id
  say(player, {"", question, " ", {"ezactions.remove-again-tip"}})
  update_tools(player.index, s)
end
if window then
  theme.on_confirm(function(player, name, yes, data)
    if name == "ezactions_remove" and yes and data and data.id then
      remove_now(player, data.id)
      E.adopt(player)
    end
  end)
  window.on_resize(function(player, name, w)
    local s = name == WIN and st(player.index)
    local right = s and s.right
    if not (right and right.valid and right.name == "ezactions_right") then return end
    -- (given at 100 %: fse-std 0.8 writes it at the window's scale and keeps it through a rescale)
    local width = math.max(300, w - INSIDE_EXTRA)
    if theme.style then theme.style(right, {width = width}) else right.style.width = width end
  end)
  window.on_close(function(player, name)  -- (the title bar's X: fse-std destroyed the window and what's stuck to it)
    if name ~= WIN then return end
    if storage.editor then storage.editor[player.index] = nil end
    local q = player.gui.screen["fstd_confirm_ezactions_remove"]  -- (an open "Remove?" goes with it)
    if q and q.get_mod() == script.mod_name then q.destroy() end
  end)
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
handlers.theme = function(player)
  local m = player.gui.screen[WIN .. "__menu"]
  if m then m.destroy() end
  remote.call("fse-std", "open_theme", player.index)
end
handlers.reset_place = function(player)
  if window.reset_place then
    window.reset_place(player, WIN)
  else
    local w = storage.fstd_windows and storage.fstd_windows[player.index]
    if w then w[WIN] = nil end
  end
  build(player)
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
  if window and tags.fstd_settings == WIN then return open_settings(player) end
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
      s.sel, s.arm = item.id, nil
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
  if e.element.tags.ezactions_set then return set_setting(player, e.element) end
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
  if s and e.element.tags.ezactions_set then return set_setting(game.get_player(e.player_index), e.element) end
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
  local s, el = st(e.player_index), e.element
  if not s then return end
  local player = game.get_player(e.player_index)
  if el.tags.ezactions_set then return set_setting(player, el) end
  if el.tags.ezactions_ed == "docked" then return set_docked(player, el.state) end
  if s.edit and el.tags.ezactions_ed == "toggle" then s.edit.toggle = el.state end
end

--- the theme changed: the filter's icon (dark on light themes)
function E.on_theme(player)
  local s = player and st(player.index)
  local box = s and s.filter_box
  if box and box.valid then box.parent.children[1].sprite = search_sprite(player) end
  refresh(player)  -- (shortcut icons: black or white)
  if s and s.edit and s.edit.choices and s.edit.choices.valid then fill_choices(player, s) end
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

--- a row dropped on a row: into a bundle, to a "back" row's page, or into the target's place
function E.drop(player, id, tags)
  local s, pi = st(player.index), player.index
  if not s or not id or id == tags.ezactions_row then return end
  if tags.ezactions_nav then
    local path = {table.unpack(s.path, 1, tags.ezactions_nav)}
    model.move_to(pi, id, model.resolve(pi, path), path)
  elseif tags.ezactions_row then
    local target = model.find(pi, tags.ezactions_row)
    if target and target.children then
      model.move_to(pi, id, target.children, s.path)
    elseif s.filter ~= "" then
      return say(player, {"ezactions.no-move-filtered"})
    else
      model.move_before(pi, id, tags.ezactions_row)
    end
  end
  refresh(player)
end

if dnd then
  dnd.on_drop(function(player, payload, target)
    if type(payload) == "table" and payload.kind == "ezactions-row" and target and target.valid then
      E.drop(player, payload.id, target.tags)
    end
  end)
end

function E.delete(player)
  local s = st(player.index)
  if s and E.is_open(player) and not s.edit and not s.io then handlers.remove(player) end
end

function E.focus_search(player)
  local s = st(player.index)
  if s and E.is_open(player) and s.filter_box.valid then s.filter_box.focus() end
end

--- (tests) drives the editor as its buttons would; returns its state: the selection, which tools are enabled, the
--- breadcrumb, the layout and the frames stuck to the window
function E.test(player, what, arg)
  local s = st(player.index)
  if what == "select" and s then
    for _, item in ipairs(page(player.index, s)) do if item.title == arg then s.sel, s.arm = item.id, nil end end
    refresh(player)
  elseif what == "remove" and s then
    handlers.remove(player)
  elseif what == "answer_yes" then  -- (the question's Remove button)
    local q = player.gui.screen["fstd_confirm_ezactions_remove"]
    local tags = q and q.tags
    local data = tags and tags.data
    if q then q.destroy() end
    if tags and window and window.give_back then window.give_back(player, tags) end  -- (as fse-std's answer does)
    if data and data.id then remove_now(player, data.id) end
  elseif what == "settings" and s and window then
    open_settings(player)
  elseif what == "docked" and s and window then
    set_docked(player, arg)
  end
  s = st(player.index)
  if not (s and E.is_open(player)) then return {open = false} end
  local tools = {}
  for name, b in pairs(s.tools or {}) do if b.valid then tools[name] = b.enabled end end
  local frames = {}
  for _, c in pairs(attached(player)) do frames[#frames + 1] = c.name end
  local sel = s.sel and model.find(player.index, s.sel)
  local badges = {}
  for _, item in ipairs(page(player.index, s)) do badges[item.title] = type_badge(player.index, item) ~= nil end
  return {open = true, badges = badges, sel = sel and sel.title, tools = tools, crumb = s.crumb and s.crumb.valid and s.crumb.caption,
          docked = docked(player.index), frames = frames, layouts = window ~= nil,
          asking = player.gui.screen["fstd_confirm_ezactions_remove"] ~= nil}
end

--- the editor's window, or a frame stuck to it (rail, dock, settings)
function E.owns(el)
  local f = el
  while f do
    if f.name == WIN or f.name:sub(1, #WIN + 2) == WIN .. "__" then return true end
    f = f.parent
  end
  return false
end

return E
