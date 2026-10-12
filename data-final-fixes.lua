-- Every shortcut's icon with its colours inverted, for the editor's lists: the game draws a shortcut's icon black on a
-- light button (style "default") or white on a coloured one (blue, red, green), so on a window of the other kind it
-- all but vanishes. ezactions-scb-<name>: a black icon made white (dark themes); ezactions-scw-<name>: a white one
-- made black (light themes).
local function layers(sc)
  local out = {}
  if sc.icons then
    for _, ic in ipairs(sc.icons) do
      local size = ic.icon_size or 64
      local sh = ic.shift and {(ic.shift[1] or ic.shift.x or 0) / 32, (ic.shift[2] or ic.shift.y or 0) / 32}
      if ic.icon then
        out[#out + 1] = {filename = ic.icon, size = size, tint = ic.tint, shift = sh, invert_colors = true,
                         scale = ic.scale or (32 / size), flags = {"gui-icon"}}
      end
    end
  elseif sc.icon then
    local size = sc.icon_size or 64
    out[1] = {filename = sc.icon, size = size, scale = 32 / size, invert_colors = true, flags = {"gui-icon"}}
  end
  return #out > 0 and out or nil
end

for name, sc in pairs(data.raw.shortcut or {}) do
  local l = layers(sc)
  if l then
    local white = sc.style == "blue" or sc.style == "red" or sc.style == "green"
    data:extend({{type = "sprite", name = (white and "ezactions-scw-" or "ezactions-scb-") .. name, layers = l,
                  flags = {"gui-icon"}}})
  end
end
