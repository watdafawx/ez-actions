-- headless: the menu model through the remote API (no player needed); results to script-output/ez-test.txt
local out = {}
local function check(name, ok, extra)
  out[#out + 1] = (ok and "PASS " or "FAIL ") .. name .. (extra and (" :: " .. tostring(extra)) or "")
end
local function R(fn, ...) return remote.call("ezactions", fn, ...) end

script.on_event(defines.events.on_tick, function(e)
  if e.tick ~= 1 then return end
  local pi = 1
  local changes = 0
  script.on_event(R("events").menu_changed, function() changes = changes + 1 end)
  local key = R("add_action", pi, {}, "Inventory", "open it", "item/wooden-chest",
                {type = "KEY", source = "control", name = "open-character-gui"}, false)
  check("add a key action", type(key) == "string" and #R("list", pi, {}) == 1, key)
  local bad, err = R("add_action", pi, {}, "x", "", nil, {type = "NOPE"}, false)
  check("bad action refused", bad == nil and err ~= nil, err)
  local b = R("add_bundle", pi, {}, "Utilities", "", "item/iron-chest", false, 3, true)
  check("add a locked bundle with key 3", R("find_by_id", pi, b).keybind == 3 and R("find_by_id", pi, b).locked)
  check("duplicate bundle title refused", R("add_bundle", pi, {}, "Utilities", "", nil, false, nil, false) == nil)
  local c = R("add_action", pi, {"Utilities"}, "Day/night", "", nil,
              {type = "COMMAND", command = "/time day\ntime night", cycle = true}, false)
  check("action into a bundle by title", #R("list", pi, {"Utilities"}) == 1 and R("find_by_id", pi, c).action_type == "COMMAND")
  R("ensure_bundles", pi, {"Utilities", "Deep", "Deeper"})
  check("ensure_bundles makes the chain", R("exists_path", pi, {"Utilities", "Deep", "Deeper"}))
  check("move_within", R("move_within", pi, {}, 2, 1) and R("list", pi, {})[1].id == b)
  check("move_to a bundle", R("move_to", pi, key, {"Utilities", "Deep"}) and #R("list", pi, {"Utilities", "Deep"}) == 2)
  check("locked bundle stays", not R("remove_by_id", pi, b))
  local json = R("export_all_json", pi)
  check("export", type(json) == "string" and json:find("Day/night", 1, true) ~= nil)
  check("validate good", R("validate", pi, json))
  local ok, verr = R("validate", pi, "{not json")
  check("validate bad JSON", not ok, verr)
  check("validate not array", not R("validate", pi, "42"))
  check("validate bad entry", not R("validate", pi, '[{"title": "x"}]'))
  local n = R("replace_all", pi, "[]")
  check("replace_all empties", n == 0 and #R("list", pi, {}) == 0)
  check("import back", R("import_into", pi, {}, json) == 1 and R("exists_path", pi, {"Utilities", "Deep", "Deeper"}))
  check("import again replaces by id", R("import_into", pi, {}, json) == 1 and #R("list", pi, {}) == 1)
  check("ids kept", R("find_by_id", pi, c) ~= nil)
  check("remove with ignore_lock", R("remove_by_id", pi, b, true) and #R("list", pi, {}) == 0)
  -- EZ Actions' own field names import too
  local ez = '[{"id":"bundle_abc","title":"Utils","hideFromMainRadial":true,"bundleKeybindEnabled":true,"children":[' ..
             '{"id":"c1","title":"Cmds","action":{"type":"COMMAND","command":"a\nb","delayTicks":5,"cycleCommands":false}}]}]'
  check("EZ Actions field names", R("import_into", pi, {}, ez) == 1 and R("find_by_id", pi, "bundle_abc").hide == true
        and R("find_by_id", pi, "c1").action_json:find('"delay":5', 1, true) ~= nil)
  check("menu_changed raised", changes > 5, changes)
  helpers.write_file("ez-test.txt", table.concat(out, "\n"))
end)
