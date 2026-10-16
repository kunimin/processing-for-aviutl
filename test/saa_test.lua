local scriptDir, path, outDir = arg[1], arg[2], arg[3]
package.path = "/home/claude/ap/test/?.lua;" .. scriptDir .. "/?.lua;" .. package.path
local mock = require("mock_obj")
obj = mock.obj
local P = require("processing")
local lastText
local rawload = obj.load
obj.load = function(k, ...) if k == "text" then lastText = ... end return rawload(k, ...) end
local t = os.clock()
for f = 0, tonumber(arg[4] or 30) do
  obj.frame = f
  mock.state.final = nil
  P.run({ sketch = path, width = 600, height = 600, mode = 1, accum = true, key = "saa" })
  if not mock.state.final then print("ERROR at frame " .. f .. ": " .. tostring(lastText)); return end
end
local st = P._states["saa"]
print("ok", "particles=" .. rawget(st.env, "particles"):size(), string.format("%.1fs", os.clock() - t))
mock.savePPM(outDir .. "/saa.ppm", mock.state.final)
-- bit ops check
print(P.API.__bxor(3, 5), P.API.__band(P.API.__sar(4281558681, 16), 255), P.API.__bxor(-1, 2), P.API.__sar(-8, 1), P.API.__shr(-8, 28))
