-- The drawn ring behind the radial's icons, like EZ Actions': a translucent ring, a lit slice under the mouse, a border.
-- Factorio's GUI can't draw arcs, so the ring is world rendering: white sprites (graphics/ring, test/make_images.py)
-- tinted and turned into place, fixed to the character the camera follows, scaled by the zoom every tick so they keep
-- their size on screen. GUI sits above world rendering, so the icons (transparent buttons) show on top.
-- Single player only: the zoom is this computer's, and the sprites are redrawn from it.
local G = {}

local IMG_OUTER = 250 -- (the images' outer radius in pixels; inner 150, so the ring is 40 % of the radius thick)
G.INNER = 150 / 250
G.MAX = 32 -- (sector images exist for up to this many slices)

--- a tint for rendering: Factorio blends premultiplied, so the colour is scaled by its alpha
local function color(c, alpha_mul)
  local a = (c.a or c[4] or 1) * (alpha_mul or 1)
  return {r = (c.r or c[1] or 0) * a, g = (c.g or c[2] or 0) * a, b = (c.b or c[3] or 0) * a, a = a}
end

--- can this player have the drawn ring now?
function G.possible(player, cfg)
  return cfg.design ~= "slot" and cfg.design ~= "button" and cfg.design ~= "tool" and not game.is_multiplayer()
    and player.character ~= nil and player.controller_type == defines.controllers.character
end

local function draw(player, sprite, tint, orientation)
  return rendering.draw_sprite({sprite = sprite, target = {entity = player.character}, surface = player.surface,
                                players = {player.index}, render_layer = "cursor", tint = tint,
                                orientation = orientation or 0, x_scale = 0.01, y_scale = 0.01})
end

function G.destroy(st)
  for _, o in pairs(st.ring or {}) do
    if type(o) == "table" then
      for _, x in pairs(o) do if x.valid then x.destroy() end end
    elseif o.valid then
      o.destroy()
    end
  end
  st.ring = nil
end

--- (re)creates the sprites for st.items: slice backgrounds (segmented, or while the wipe runs), whole ring, border, hover
function G.build(player, st)
  G.destroy(st)
  local c, n = st.cfg, #st.items
  local ring = {slices = {}}
  local sectors = n <= G.MAX
  if sectors and (c.design == "segmented" or c.design == "solid" or c.design == "glass") then
    local gap = c.design == "segmented" and (c.gap ~= "none" and c.gap or "small") or "none"
    for i = 1, n do
      ring.slices[i] = draw(player, "ezactions-sector-" .. gap .. "-" .. n, color(G.bg(c)), (i - 1) / n)
    end
  end
  if c.design == "solid" or c.design == "glass" or not sectors and c.design ~= "outline" then
    ring.whole = draw(player, "ezactions-ring", color(G.bg(c)))
  end
  if c.design ~= "segmented" then ring.border = draw(player, "ezactions-ring-outline", color(c.border_color)) end
  if sectors then
    ring.hover = draw(player, "ezactions-sector-" .. (c.gap or "none") .. "-" .. n, color(c.hover_color), 0)
    ring.hover.visible = false
  end
  -- (a dark box behind the hover label, sized to the title each tick)
  ring.label = rendering.draw_rectangle({color = {0, 0, 0, 0.7}, filled = true, surface = player.surface,
                                         players = {player.index}, render_layer = "cursor",
                                         left_top = {entity = player.character}, right_bottom = {entity = player.character}})
  ring.label.visible = false
  st.ring = ring
end

function G.bg(c)
  if c.design == "glass" then return {1, 1, 1, 0.16} end
  return c.ring_color
end

--- every tick while it shows: scale for the zoom and the radius, the open animation, the lit slice
--- r_px: the ring's outer radius on screen; t: open animation 0..1; sel: lit slice or nil
function G.update(player, st, r_px, t)
  local ring, c = st.ring, st.cfg
  if not ring then return end
  local n = #st.items
  local style = c.animations and c.anim_open and c.open_style or "none"
  local fade = style == "fade" and t or 1
  local s = r_px / (IMG_OUTER * player.zoom)
  local function set(o, scale, alpha_c)
    if o and o.valid then
      o.x_scale, o.y_scale = scale, scale
      if alpha_c then o.color = color(alpha_c, fade) end
    end
  end
  local bg = G.bg(c)
  local wiping = style == "wipe" and t < 1
  for i, o in pairs(ring.slices) do
    if o.valid then
      local order = (c.direction == "ccw") and ((n - i + 1) % n) or (i - 1)
      -- (solid and glass draw the whole ring once the wipe is done: slices side by side show faint seams)
      o.visible = (c.design == "segmented" or wiping) and (not wiping or order / n < t)
      set(o, s, bg)
    end
  end
  if ring.whole and ring.whole.valid then
    ring.whole.visible = not wiping or not next(ring.slices)
    set(ring.whole, s, bg)
  end
  set(ring.border, s, c.border_color)
  if ring.border and ring.border.valid then ring.border.visible = not wiping end
  local l = ring.label
  if l and l.valid then
    local item = st.sel and st.items[st.sel]
    l.visible = item ~= nil and c.label and not wiping
    if l.visible then
      -- (the label's width guessed from its length: heading font, about 9 px a character)
      local ds = player.display_scale
      local w, ht = (#item.title * 9 + 20) * ds, 30 * ds
      local k = 1 / (32 * player.zoom)
      l.left_top = {entity = player.character, offset = {-w / 2 * k, -ht / 2 * k}}
      l.right_bottom = {entity = player.character, offset = {w / 2 * k, ht / 2 * k}}
      l.color = color({0, 0, 0, 0.7}, fade)
    end
  end
  local h = ring.hover
  if h and h.valid then
    local on = st.sel ~= nil and not wiping and (c.hover_style ~= "scale" and c.hover_style ~= "none" or not (c.animations and c.anim_hover))
    h.visible = on
    if on then
      h.orientation = (st.sel - 1) / n
      local grow = (c.animations and c.anim_hover and (c.hover_style == "fill-scale")) and (1 + c.hover_grow * 0.4) or 1
      set(h, s * grow, c.hover_color)
    end
  end
end

return G
