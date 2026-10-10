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
