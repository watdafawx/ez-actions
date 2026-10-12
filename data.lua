data:extend({
  {type = "custom-input", name = "ezactions-radial", key_sequence = "U", order = "a"},
  {type = "custom-input", name = "ezactions-editor", key_sequence = "SHIFT + U", order = "b"},
  -- (Escape and E close the radial through player.opened; these two only act while the editor is open)
  {type = "custom-input", name = "ezactions-delete", key_sequence = "DELETE", order = "c"},
  {type = "custom-input", name = "ezactions-focus-search", key_sequence = "", linked_game_control = "focus-search", order = "d"},
  {type = "shortcut", name = "ezactions-editor", order = "e[ezactions]", action = "lua",
   associated_control_input = "ezactions-editor",
   icon = "__ez-actions__/graphics/shortcut.png", icon_size = 64,
   small_icon = "__ez-actions__/graphics/shortcut.png", small_icon_size = 64},
})
-- a key per bundle slot: a bundle with "keybind" set to N opens on ezactions-bundle-N (unbound until set in Controls)
for i = 1, 10 do
  data:extend({{type = "custom-input", name = "ezactions-bundle-" .. i, key_sequence = "", order = "f" .. string.format("%02d", i),
                localised_name = {"controls.ezactions-bundle", tostring(i)}}})
end

-- (the editor: an entry without an icon gets this see-through one, so the titles line up)
data:extend({{type = "sprite", name = "ezactions-blank", filename = "__ez-actions__/graphics/blank.png", size = 64,
              flags = {"gui-icon"}}})

-- the drawn ring (white, tinted in game): see test/make_images.py
local function sprite(name, file)
  return {type = "sprite", name = name, filename = "__ez-actions__/graphics/ring/" .. file, size = 512}
end
data:extend({sprite("ezactions-ring", "ring.png"), sprite("ezactions-ring-outline", "outline.png"),
             {type = "sprite", name = "ezactions-glow", filename = "__ez-actions__/graphics/ring/glow.png", size = 128}})
for _, gap in pairs({"none", "small", "large"}) do
  for n = 1, 32 do
    data:extend({sprite("ezactions-sector-" .. gap .. "-" .. n, "sector-" .. gap .. "-" .. n .. ".png")})
  end
end
