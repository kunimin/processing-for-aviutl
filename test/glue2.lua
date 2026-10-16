local scriptDir, outDir = arg[1], arg[2]
package.path = "test/?.lua;" .. scriptDir .. "/?.lua;" .. package.path
local mock = require("mock_obj")
obj = mock.obj
mock.script_path = scriptDir .. "/"
local rawopen = io.open
io.open = function(p, m) return rawopen((p:gsub("\\", "/")), m) end
local src = rawopen(scriptDir .. "/@Processing.obj", "rb"):read("*a"):gsub("\r", "")
local body = src:gsub("^@[^\n]*\n", ""):gsub("%-%-[%a]+%d*:[^\n]*\n", "")
for _, c in ipairs({ { nil, "default" }, { scriptDir .. "/processing_sketches/sample_shapes.lua", "chosen" } }) do
  file = c[1]
  obj.frame, obj.track0, obj.track1, obj.track2, obj.track3, obj.check0, obj.layer = 2, 320, 180, 0, 1, false, 1
  mock.state.final = nil
  assert(loadstring(body))()
  print(c[2], mock.state.final and (mock.state.final.w .. "x" .. mock.state.final.h) or "FAILED")
end
