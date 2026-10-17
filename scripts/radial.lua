-- The radial: one sprite button per slice in a ring around where the key was pressed, a label in the middle.
-- With FSE in single player the mouse direction picks the slice (no need to touch a button) and letting go of the key
-- runs it (or a click anywhere on the screen, inside a bundle); otherwise hovering picks, and a click, or the key
-- again, runs it. Escape, E or right-click closes or goes back out of a bundle.
local model = require("scripts.model")
local actions = require("scripts.actions")
local ring = require("scripts.ring")
local R = {}

local DESIGN = {slot = "slot_button", button = "slot_sized_button", tool = "tool_button"}
local MODIFIER_VKS = {[16] = true, [17] = true, [18] = true, [160] = true, [161] = true, [162] = true, [163] = true,
                      [164] = true, [165] = true}
-- (API style names, EZ Actions' and ours)
local STYLE_KEYS = {deadzone = "deadzone", baseOuterRadius = "radius", radius = "radius",
                    ringThickness = "button_size", button_size = "button_size", scaleStartThreshold = "scale_start",
                    scalePerItem = "scale_per_item", designStyle = "design", design = "design",
                    textColor = "text_color", animationsEnabled = "animations", animOpenClose = "anim_open",
                    animHover = "anim_hover", openCloseMs = "open_ms", hoverGrowPct = "hover_grow",
                    openStyle = "open_style", openDirection = "direction", hoverStyle = "hover_style",
                    ringColor = "ring_color", ring_color = "ring_color", hoverColor = "hover_color",
                    hover_color = "hover_color", borderColor = "border_color", border_color = "border_color",
                    sliceGapDeg = "gap", gap = "gap", iconOutline = "outline", outline = "outline"}

-- (a key binding as a virtual-key code, to see when it is let go: letters and digits are their ASCII codes)
local VK = {SPACE = 32, TAB = 9, RETURN = 13, ESCAPE = 27, BACKSPACE = 8, GRAVE = 192, MINUS = 189, EQUALS = 187,
            LEFTBRACKET = 219, RIGHTBRACKET = 221, BACKSLASH = 220, SEMICOLON = 186, APOSTROPHE = 222, COMMA = 188,
            PERIOD = 190, SLASH = 191, CAPSLOCK = 20, LSHIFT = 160, RSHIFT = 161, LCTRL = 162, RCTRL = 163, LALT = 164,
            RALT = 165, INSERT = 45, DELETE = 46, HOME = 36, END = 35, PAGEUP = 33, PAGEDOWN = 34, UP = 38, DOWN = 40,
            LEFT = 37, RIGHT = 39}
local MOUSE_VK = {["button-1"] = 1, ["button-2"] = 2, ["button-3"] = 4, ["button-4"] = 5, ["button-5"] = 6}

local function vk_of(key)
  if key.mouse then return MOUSE_VK[key.mouse] end
  local n = (key.scancode or ""):gsub("^SDL_SCANCODE_", "")
  if n:match("^[A-Z0-9]$") then return n:byte() end
  local f = n:match("^F(%d+)$")
  if f then return 0x6F + tonumber(f) end
  local kp = n:match("^KP_(%d)$")
  if kp then return 0x60 + tonumber(kp) end
  return VK[n]
end

--- the virtual key of what a control (the radial's own) is bound to, from FSE's control list
local function bound_vk(control)
  local out = control and actions.call("input", "controls", "")
  for _, c in ipairs(out and helpers.json_to_table(out) or {}) do
    if c.name == control then
      for _, k in ipairs(c.keys or {}) do
        local vk = vk_of(k)
        if vk then return vk end
      end
    end
  end
end

local function config(player, style)
  local s = player.mod_settings
  local function v(name) return s["ezactions-" .. name].value end
  local c = {deadzone = v("deadzone"), radius = v("radius"), button_size = v("button-size"),
             scale_start = v("scale-start"), scale_per_item = v("scale-per-item"), design = v("design"),
             text_color = v("text-color"), animations = v("animations"), anim_open = v("anim-open"),
             anim_hover = v("anim-hover"), open_ms = v("open-ms"), hover_grow = v("hover-grow"),
             open_style = v("open-style"), direction = v("direction"), hover_style = v("hover-style"),
             label = v("show-hover-label"), hold = v("hold-release"), gap = v("slice-gap"),
             ring_color = v("ring-color"), hover_color = v("hover-color"), border_color = v("border-color"),
             outline = v("icon-outline")}
  for k, val in pairs(style or {}) do
    local key = STYLE_KEYS[k]
    if key then
      if type(val) == "string" then val = val:lower():gsub("_", "-") end
      if key == "button_size" and k == "ringThickness" then val = math.max(24, val) end
      c[key] = val
    end
  end
  for _, k in ipairs({"text_color", "ring_color", "hover_color", "border_color"}) do
    if type(c[k]) == "number" then -- (ARGB int, as EZ Actions stores colours)
      local n = c[k] % 0x100000000
      c[k] = {r = math.floor(n / 0x10000) % 256 / 255, g = math.floor(n / 0x100) % 256 / 255, b = n % 256 / 255,
              a = math.floor(n / 0x1000000) / 255}
    end
  end
  if type(c.gap) == "number" then c.gap = c.gap <= 0 and "none" or (c.gap <= 3 and "small" or "large") end
  if c.hover_style == "fill-only" then c.hover_style = "fill" elseif c.hover_style == "scale-only" then c.hover_style = "scale" end
  return c
end

local function state(pi)
  storage.radial = storage.radial or {}
  return storage.radial[pi]
end

--- the mouse through FSE (single player only: input differs per computer)
local function mouse_mode()
  return not game.is_multiplayer() and actions.has("std", "input")
end

local function std_input()
  local out = actions.call("std", "input", "")
  return out and helpers.json_to_table(out)
end

local function visible(st)
  local page = st.pages[#st.pages]
  if #st.pages > 1 or not st.root_filter then return page end
  local out = {}
  for _, item in ipairs(page) do
    if not (item.children and item.hide) then out[#out + 1] = item end
  end
  return out
end

local icon_of = model.icon_of

local function tooltip(item)
  local t = {"", "[font=default-bold]", item.title, "[/font]"}
  if item.note and item.note ~= "" then t[#t + 1] = "\n" .. item.note end
  return t
end

local function destroy(st)
  for _, b in pairs(st.buttons or {}) do if b.valid then b.destroy() end end
  if st.center and st.center.valid then st.center.destroy() end
  if st.catch and st.catch.valid then st.catch.destroy() end
  ring.destroy(st)
  st.buttons, st.center, st.catch = {}, nil, nil
end

local function ease(t) return 1 - (1 - t) * (1 - t) end

--- where every button goes this tick (animation and the hovered one's growth)
--- the ring's outer radius in pixels and the open animation's progress (0..1)
local function geometry(player, st)
  local c, n = st.cfg, #st.items
  local r = (c.radius + math.max(0, n - c.scale_start) * c.scale_per_item) * player.display_scale
  local dur = math.max(1, c.open_ms / 1000 * 60)
  local t = (c.animations and c.anim_open and c.open_style ~= "none") and math.min(1, (game.tick - st.opened) / dur) or 1
  return r, t
end

local function layout(player, st)
  local c, n = st.cfg, #st.items
  local scale = player.display_scale
  local r, t = geometry(player, st)
  st.animating = t < 1
  local grow = (c.open_style == "grow") and (0.35 + 0.65 * ease(t)) or 1
  local outer = r
  if st.drawn then r = r * (1 + ring.INNER) / 2 end -- (icons on the middle of the drawn ring)
  for i, b in ipairs(st.buttons) do
    if b.valid then
      local order = (c.direction == "ccw") and ((n - i + 1) % n) or (i - 1)
      b.visible = c.open_style ~= "wipe" or t >= 1 or order / n < t
      local size = c.button_size
      local hovered = st.sel == i and c.animations and c.anim_hover
      if hovered and (c.hover_style == "fill-scale" or c.hover_style == "scale") then
        size = math.floor(size * (1 + c.hover_grow))
      end
      b.style.size = size
      b.toggled = st.sel == i and (c.hover_style ~= "scale" and c.hover_style ~= "none" or not (c.animations and c.anim_hover))
      local a = (i - 1) / n * 2 * math.pi
      local px = size * scale
      b.location = {math.floor(st.x + math.sin(a) * r * grow - px / 2), math.floor(st.y - math.cos(a) * r * grow - px / 2)}
    end
  end
  if st.center and st.center.valid then
    local w, h = st.center_w * scale, st.center_h * scale
    st.center.location = {math.floor(st.x - w / 2), math.floor(st.y - h / 2)}
  end
  if st.drawn then ring.update(player, st, outer * grow, t) end
end

local function set_label(st)
  if not (st.center and st.center.valid) then return end
  local item = st.sel and st.items[st.sel]
  local title, note = st.center.ezactions_title, st.center.ezactions_note
  title.caption = (item and st.cfg.label) and (st.drawn and ring.title(item, st.r_px or 0, st.ds or 1) or item.title) or ""
  note.caption = (item and st.cfg.label) and (item.note or "") or ""
  note.visible = note.caption ~= ""
end

local function select(player, st, i)
  if st.sel == i then return end
  st.sel = i
  set_label(st)
  layout(player, st)
end

local function build(player, st)
  destroy(st)
  st.items = visible(st)
  st.sel = nil
  st.opened = game.tick
  local screen, c = player.gui.screen, st.cfg
  local n = #st.items
  local style = st.drawn and "transparent_slot" or DESIGN[c.design] or "slot_button"
  if st.mouse then
    -- (the mouse direction picks, so a click anywhere runs the lit slice: a screen-wide catcher under the buttons, which
    -- also keeps the click off the world)
    local res, ds = player.display_resolution, player.display_scale
    local w = screen.add({type = "empty-widget", tags = {ezactions_slice = 0}})
    w.location = {0, 0}
    w.style.width, w.style.height = math.ceil(res.width / ds), math.ceil(res.height / ds)
    st.catch = w
  end
  for i, item in ipairs(st.items) do
    local b = screen.add({type = "sprite-button", style = style, sprite = icon_of(item),
                          tooltip = not st.drawn and tooltip(item) or nil, -- (the drawn ring's label says it)
                          raise_hover_events = true, tags = {ezactions_slice = i},
                          number = item.children and #item.children or nil})
    if st.drawn then  -- (the icon fills its button: as big as the outlines drawn behind it)
      b.style.padding = 0
    end
    st.buttons[i] = b
  end
  local r = c.radius + math.max(0, n - c.scale_start) * c.scale_per_item
  st.icons = {}
  for i, item in ipairs(st.items) do st.icons[i] = icon_of(item) end
  if st.drawn then ring.build(player, st) end
  st.center_w = math.max(120, st.drawn and 2 * r * ring.INNER - 12 or 2 * r - c.button_size - 8)
  st.center_h = #st.pages > 1 and 84 or 52
  local f = screen.add({type = "frame", name = "ezactions_radial_" .. player.index, style = "invisible_frame",
                        direction = "vertical"})
  f.style.width, f.style.height = st.center_w, st.center_h
  f.style.horizontal_align, f.style.vertical_align = "center", "center"
  if #st.pages > 1 then
    f.add({type = "sprite-button", style = "frame_action_button", sprite = "utility/left_arrow",
           tooltip = {"ezactions.back"}, tags = {ezactions_back = true}})
  end
  st.r_px, st.ds = (c.radius + math.max(0, n - c.scale_start) * c.scale_per_item) * player.display_scale, player.display_scale
  local title = f.add({type = "label", name = "ezactions_title", style = st.drawn and "bold_label" or "heading_2_label"})
  title.style.font_color = c.text_color
  local note = f.add({type = "label", name = "ezactions_note"})
  note.style.font_color = c.text_color
  note.style.single_line = false
  note.style.maximal_width = st.center_w
  st.center = f
  set_label(st)
  layout(player, st)
  if st.ret then f.tags = {fstd_return = st.ret} end  -- (fse-std keeps the window that had Esc: see R.open)
  st.guard = true
  player.opened = f
  st.guard = false
end

function R.close(player)
  local st = state(player.index)
  if not st then return end
  storage.radial[player.index] = nil
  st.guard = true
  if player.opened == st.center then player.opened = nil end
  destroy(st)
  -- (Esc back to the window the radial took it from, fse-std's give_back)
  if st.ret and player.opened_gui_type == defines.gui_type.none then
    for _, c in pairs(player.gui.screen.children) do
      if c.index == st.ret and c.valid and c.visible then player.opened = c break end
    end
  end
end

function R.is_open(player)
  return state(player.index) ~= nil
end

--- opts: {pages = {list}, root_filter = bool, style = {}, x, y (pixels), hold = bool, control = the custom input that
--- opened it (its key is the one to let go of), preview = bool, temp = bool}
function R.open(player, opts)
  R.close(player)
  local res = player.display_resolution
  local st = {pages = opts.pages, root_filter = opts.root_filter, cfg = config(player, opts.style), buttons = {},
              x = opts.x or res.width / 2, y = opts.y or res.height / 2, preview = opts.preview, temp = opts.temp}
  if #visible(st) == 0 then
    player.create_local_flying_text({text = {"ezactions.empty"}, create_at_cursor = true})
    return false
  end
  -- (the whole ring on screen, even when the key is pressed near an edge)
  local n, c, scale = #visible(st), st.cfg, player.display_scale
  local m = ((c.radius + math.max(0, n - c.scale_start) * c.scale_per_item) + c.button_size) * scale
  st.x = math.max(m, math.min(res.width - m, st.x))
  st.y = math.max(m, math.min(res.height - m, st.y))
  st.drawn = ring.possible(player, st.cfg)
  if st.drawn then
    -- (the drawn ring hangs on the character, which the camera keeps in the middle of the screen)
    st.x, st.y = res.width / 2, res.height / 2
  end
  -- (over a window of this mod that has Esc, fse-std's editor: it stays open while the radial takes Esc, and gets it
  -- back after, as fse-std's open_child / give_back do)
  local was = player.opened_gui_type == defines.gui_type.custom and player.opened
  if was and was.valid and was.tags.fstd_window and was.get_mod() == script.mod_name then st.ret = was.index end
  storage.radial = storage.radial or {}
  storage.radial[player.index] = st
  st.mouse = mouse_mode()
  if opts.hold and st.cfg.hold and st.mouse then
    -- (the keys held now, the radial's own: letting go of them runs the slice under the mouse)
    local inp = std_input()
    local keys, mods = {}, {}
    for _, vk in ipairs(inp and inp.keys or {}) do
      if vk > 2 then
        local t = MODIFIER_VKS[vk] and mods or keys
        t[#t + 1] = vk
      end
    end
    st.hold = #keys > 0 and keys or (#mods > 0 and mods or nil)
    -- (better: the key the radial is bound to, while it is still down; after a quick tap it stays open for a click)
    local vk = bound_vk(opts.control)
    if vk then
      for _, k in ipairs(inp and inp.keys or {}) do
        if k == vk then st.hold = {vk} end
      end
    end
  end
  build(player, st)
  return true
end

function R.back(player)
  local st = state(player.index)
  if not st then return end
  if #st.pages <= 1 then return R.close(player) end
  table.remove(st.pages)
  build(player, st)
end

function R.activate(player, i)
  local st = state(player.index)
  local item = st and i and st.items[i]
  if not item then return R.close(player) end
  if item.children then
    st.pages[#st.pages + 1] = item.children
    st.hold = nil -- (inside a bundle: pick with a click or the key)
    build(player, st)
    return
  end
  if st.preview then return end
  R.close(player)
  actions.run(player, item)
end

--- the radial key pressed again while open (click mode): run what is hovered
function R.key(player)
  local st = state(player.index)
  if st then R.activate(player, st.sel) end
end

function R.tick()
  if not storage.radial then return end
  for pi, st in pairs(storage.radial) do
    local player = game.get_player(pi)
    if not player or not (st.center and st.center.valid) then
      storage.radial[pi] = nil
    else
      if st.mouse then
        local inp = std_input()
        if inp then
          local dx, dy = inp.x - st.x, inp.y - st.y
          local dz = st.cfg.deadzone * player.display_scale
          local sel
          if dx * dx + dy * dy >= dz * dz and #st.items > 0 then
            local a = math.atan2(dx, -dy) % (2 * math.pi)
            local step = 2 * math.pi / #st.items
            sel = math.floor((a + step / 2) / step) % #st.items + 1
          end
          select(player, st, sel)
          if st.hold then
            local down = {}
            for _, vk in ipairs(inp.keys or {}) do down[vk] = true end
            local any = false
            for _, vk in ipairs(st.hold) do if down[vk] then any = true end end
            if not any then
              st.hold = nil
              R.activate(player, st.sel)
            end
          end
        end
      end
      st = state(pi)
      if st then
        if st.preview and game.tick - st.opened > st.cfg.open_ms / 1000 * 60 + 60 then st.opened = game.tick end
        if st.animating or st.preview then
          layout(player, st)
        elseif st.drawn then
          ring.update(player, st, (geometry(player, st)), 1)
        end
      end
    end
  end
end

function R.on_click(e)
  local tags = e.element.tags
  local player = game.get_player(e.player_index)
  if tags.ezactions_back then return R.back(player) end
  if not tags.ezactions_slice then return end
  if e.button == defines.mouse_button_type.right then return R.back(player) end
  local st = state(e.player_index)
  -- (with the mouse direction picking, run the picked slice even if the click landed on a neighbour)
  R.activate(player, st and st.mouse and st.sel or tags.ezactions_slice)
end

function R.on_hover(e, entering)
  local st = state(e.player_index)
  local i = e.element.tags.ezactions_slice
  if not st or st.mouse or not i then return end
  local player = game.get_player(e.player_index)
  if entering then select(player, st, i) elseif st.sel == i then select(player, st, nil) end
end

function R.on_closed(e)
  local st = state(e.player_index)
  if st and not st.guard and e.element == st.center then
    local player = game.get_player(e.player_index)
    -- (Escape inside a bundle steps back out; at the top it closes)
    if #st.pages > 1 then
      R.back(player)
    else
      R.close(player)
    end
  end
end

R.config = config
return R
