local scriptDir, pdeDir, outDir = arg[1], arg[2], arg[3]
package.path = "/home/claude/ap/test/?.lua;" .. scriptDir .. "/?.lua;" .. package.path
local mock = require("mock_obj")
obj = mock.obj
local P = require("processing")
local PDE = require("processing_pde")
local lastText
local rawload = obj.load
obj.load = function(k, ...) if k == "text" then lastText = ... end return rawload(k, ...) end
-- RESULT を拾うため _G に書く
for _, name in ipairs({ "t1_basic", "t2_class", "t3_misc", "t4_static", "t5_err", "t6_syntax", "t7_complex" }) do
  local path = pdeDir .. "/" .. name .. ".pde"
  local src = io.open(path, "rb"):read("*a")
  local code, map = PDE.transpile(src, name .. ".pde")
  if code then
    local f = io.open(outDir .. "/" .. name .. ".lua", "w"); f:write(code); f:close()
  end
  lastText = nil
  mock.state.final = nil
  local resultBox = {}
  -- 環境の書き込みを覗くため P の内部 state を調べる代わりに RESULT を API 経由で拾う
  P.API.RESULT = nil
  for f = 0, 2 do
    obj.frame = f
    P.run({ sketch = path, width = 200, height = 150, mode = 1, key = name })
  end
  local st = P._states[name]
  local r = st and rawget(st.env, "RESULT")
  print(string.format("%-10s %s | %s | %s", name, mock.state.final and "rendered" or "NO IMAGE",
    tostring(r), mock.state.final and "" or (lastText and lastText:gsub("\n", " ") or "")))
  if mock.state.final then mock.savePPM(outDir .. "/" .. name .. ".ppm", mock.state.final) end
end
