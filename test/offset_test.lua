local scriptDir = arg[1]
package.path = "/home/claude/ap/test/?.lua;" .. scriptDir .. "/?.lua;" .. package.path
local mock = require("mock_obj")
obj = mock.obj
local P = require("processing")
local sk = scriptDir .. "/processing_sketches/sample_particles.pde"
-- A: 開始秒 1 秒 (30fps) で 0 フレーム目 → 通常の 30 フレーム目と同じになるはず
obj.frame = 30
P.run({ sketch = sk, width = 160, height = 90, mode = 1, key = "plain" })
local plain = mock.copyBuf(mock.state.final)
obj.frame = 0
P.run({ sketch = sk, width = 160, height = 90, mode = 1, offset = 1, key = "off" })
local off = mock.copyBuf(mock.state.final)
print("offset 1s @frame0 vs frame30 diff:", mock.bufDiff(plain, off))
-- 続けて順送り
obj.frame = 1
P.run({ sketch = sk, width = 160, height = 90, mode = 1, offset = 1, key = "off" })
local off1 = mock.copyBuf(mock.state.final)
obj.frame = 31
P.run({ sketch = sk, width = 160, height = 90, mode = 1, key = "plain" })
print("offset next frame vs frame31 diff:", mock.bufDiff(off1, mock.state.final))
print("frameCount", rawget(P._states["off"].env, "frameCount"))
