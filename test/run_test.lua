-- 使い方: lua5.1 test/run_test.lua <build/script dir> <out dir>
local scriptDir, outDir = arg[1], arg[2]
package.path = "test/?.lua;" .. scriptDir .. "/?.lua;" .. package.path
local mock = require("mock_obj")
obj = mock.obj
mock.script_path = scriptDir .. "/"
local P = require("processing")
local sk = scriptDir .. "/processing_sketches/"

local function run(name, frame, opt)
  opt = opt or {}
  obj.frame = frame
  mock.state.final = nil
  P.run({ sketch = sk .. name .. ".lua", width = opt.w or 640, height = opt.h or 360, seed = opt.seed or 0,
          mode = opt.mode or 1, accum = opt.accum, key = opt.key or name })
  return mock.state.final
end

local t0 = os.clock()
-- 1. 図形見本
local b = run("sample_shapes", 0, { mode = 0 })
mock.savePPM(outDir .. "/shapes.ppm", b)
print("shapes drawpoly:", mock.stats.drawpoly, "load:", mock.stats.load, string.format("%.2fs", os.clock() - t0))

-- 2. 連続モード: 順に進めた結果とシークの結果が一致するか
local seq
for f = 0, 20 do seq = run("sample_bounce", f, { key = "seq" }) end
seq = mock.copyBuf(seq)
mock.savePPM(outDir .. "/bounce_40.ppm", seq)
local jump = mock.copyBuf(run("sample_bounce", 20, { key = "jump" }))
print("bounce seq vs seek diff:", mock.bufDiff(seq, jump))
local again = mock.copyBuf(run("sample_bounce", 20, { key = "jump" }))
print("bounce same-frame rerender diff:", mock.bufDiff(seq, again))

-- 3. 累積モード
local acc
for f = 0, 25 do acc = run("sample_noise", f, { accum = true, key = "acc" }) end
acc = mock.copyBuf(acc)
mock.savePPM(outDir .. "/noise_60.ppm", acc)
local accj = mock.copyBuf(run("sample_noise", 25, { accum = true, key = "accj" }))
print("noise seq vs seek diff:", mock.bufDiff(acc, accj))

print("total", string.format("%.2fs", os.clock() - t0))

-- 4. 半透明の複雑な図形・エラー表示
local f = io.open(sk .. "_t_alpha.lua", "w")
f:write([[
function draw()
  background(255)
  noStroke()
  fill(0, 0, 255, 120)
  beginShape()
  for i = 0, 9 do
    local r = (i % 2 == 0) and 120 or 50
    local a = i * TWO_PI / 10 - HALF_PI
    vertex(160 + cos(a) * r, 150 + sin(a) * r)
  end
  endShape(CLOSE)
  fill(255, 0, 0, 120)
  rect(250, 40, 200, 200, 40)
  stroke(0, 160, 0, 120)
  strokeWeight(20)
  strokeJoin(ROUND)
  noFill()
  beginShape()
  vertex(470, 40) vertex(600, 120) vertex(480, 200) vertex(610, 270)
  endShape()
  strokeWeight(14)
  stroke(0, 120)
  line(40, 300, 300, 330)
end
]])
f:close()
mock.savePPM(outDir .. "/alpha.ppm", run("_t_alpha", 0, { mode = 0 }))
f = io.open(sk .. "_t_err.lua", "w"); f:write("function draw() rect(nil) end"); f:close()
local eb = run("_t_err", 0, { mode = 1 })
print("error output is text:", eb == nil, mock.obj.w, mock.obj.h)
os.remove(sk .. "_t_alpha.lua"); os.remove(sk .. "_t_err.lua")
print("total", string.format("%.2fs", os.clock() - t0))

