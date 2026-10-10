local order = 0
local function s(t)
  order = order + 1
  t.setting_type, t.order = "runtime-per-user", string.format("%02d", order)
  t.name = "ezactions-" .. t.name
  data:extend({t})
end
-- General
s({type = "bool-setting", name = "hold-release", default_value = true})
s({type = "bool-setting", name = "show-hover-label", default_value = true})
s({type = "int-setting", name = "command-lines", default_value = 5, minimum_value = 1, maximum_value = 20})
-- Animations
s({type = "bool-setting", name = "animations", default_value = true})
s({type = "bool-setting", name = "anim-open", default_value = true})
s({type = "bool-setting", name = "anim-hover", default_value = true})
s({type = "string-setting", name = "open-style", default_value = "wipe", allowed_values = {"wipe", "grow", "none"}})
s({type = "string-setting", name = "direction", default_value = "cw", allowed_values = {"cw", "ccw"}})
s({type = "string-setting", name = "hover-style", default_value = "fill-scale", allowed_values = {"fill-scale", "fill", "scale", "none"}})
s({type = "double-setting", name = "hover-grow", default_value = 0.15, minimum_value = 0, maximum_value = 0.5})
s({type = "int-setting", name = "open-ms", default_value = 125, minimum_value = 0, maximum_value = 2000})
-- Design
s({type = "int-setting", name = "deadzone", default_value = 18, minimum_value = 0, maximum_value = 90})
s({type = "int-setting", name = "radius", default_value = 100, minimum_value = 24, maximum_value = 512})
s({type = "int-setting", name = "button-size", default_value = 40, minimum_value = 24, maximum_value = 128})
s({type = "int-setting", name = "scale-start", default_value = 8, minimum_value = 0, maximum_value = 128})
s({type = "int-setting", name = "scale-per-item", default_value = 6, minimum_value = 0, maximum_value = 100})
s({type = "string-setting", name = "design", default_value = "slot", allowed_values = {"slot", "button", "tool"}})
s({type = "color-setting", name = "text-color", default_value = {1, 1, 1}})
