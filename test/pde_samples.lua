local scriptDir, outDir = arg[1], arg[2]
package.path = "/home/claude/ap/test/?.lua;" .. scriptDir .. "/?.lua;" .. package.path
local mock = require("mock_obj")
obj = mock.obj
local P = require("processing")
local lastText
local rawload = obj.load
obj.load = function(k, ...) if k == "text" then lastText = ... end return rawload(k, ...) end
local jobs = { { "spiral", 20 }, { "tree", 10 }, { "bounce", 10 }, { "particles", 25 }, { "flow", 15, true }, { "hello", 3 } }
for _, j in ipairs(jobs) do
  local name, frames, accum = j[1], j[2], j[3]
  local t = os.clock()
  for f = 0, frames do
    obj.frame = f
    mock.state.final = nil
    P.run({ sketch = scriptDir .. "/processing_sketches/sample_" .. name .. ".pde", width = 320, height = 180,
      mode = 1, accum = accum, key = name })
  end
  local ok = mock.state.final ~= nil
  print(name, ok and "ok" or ("ERROR " .. tostring(lastText)), string.format("%.1fs", os.clock() - t))
  if ok then mock.savePPM(outDir .. "/p_" .. name .. ".ppm", mock.state.final) end
end
-- 順送りとシークの一致（bounce）
obj.frame = 10
mock.state.final = nil
local seq = mock.copyBuf(mock.state.caches["cache:processing_bounce"])
P.run({ sketch = scriptDir .. "/processing_sketches/sample_bounce.pde", width = 320, height = 180, mode = 1, key = "bounce2" })
print("bounce seq vs seek diff", mock.bufDiff(seq, mock.state.final))
