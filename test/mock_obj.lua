-- 拡張編集の obj を最低限まねるテスト用モック（ソフトウェアラスタライザ）
local floor, sqrt, abs, max, min = math.floor, math.sqrt, math.abs, math.max, math.min

local FIG_CIRCLE = "\137\126"           -- "円" (Shift_JIS)
local FIG_SQUARE = "\142\108\138\112\140\96" -- "四角形"

local M = { log = {}, stats = { drawpoly = 0, load = 0 } }

local function newBuf(w, h)
  local b = { w = w, h = h, r = {}, g = {}, b = {}, a = {} }
  for i = 1, w * h do b.r[i], b.g[i], b.b[i], b.a[i] = 0, 0, 0, 0 end
  return b
end

local function copyBuf(s)
  local b = { w = s.w, h = s.h, r = {}, g = {}, b = {}, a = {} }
  for i = 1, s.w * s.h do b.r[i], b.g[i], b.b[i], b.a[i] = s.r[i], s.g[i], s.b[i], s.a[i] end
  return b
end

local function colRGB(col)
  local r = floor(col / 65536) % 256
  local g = floor(col / 256) % 256
  local b = col % 256
  return r / 255, g / 255, b / 255
end

local obj = {
  frame = 0, time = 0, framerate = 30, layer = 1, w = 0, h = 0,
  track0 = 0, track1 = 0, track2 = 0, track3 = 0,
}
M.obj = obj

local state = { target = "framebuffer", tmp = nil, objtex = nil, caches = {}, blend = 0, font = { "", 24, 0, 0xffffff } }
M.state = state

-- テクスチャ: sample(u, v) -> r,g,b,a
local function setTex(t)
  state.objtex = t
  obj.w, obj.h = t.w, t.h
end

local function bufTex(b)
  local copy = copyBuf(b)
  return { w = b.w, h = b.h, buf = copy, sample = function(u, v)
    local x, y = floor(u), floor(v)
    if x < 0 or y < 0 or x >= copy.w or y >= copy.h then return 0, 0, 0, 0 end
    local i = y * copy.w + x + 1
    return copy.r[i], copy.g[i], copy.b[i], copy.a[i]
  end }
end

function obj.load(kind, ...)
  M.stats.load = M.stats.load + 1
  if kind == "figure" then
    local name, col, size, line = ...
    col, size = col or 0xffffff, size or 100
    local r, g, b = colRGB(col)
    local S = size
    if name == FIG_CIRCLE then
      setTex({ w = S, h = S, sample = function(u, v)
        local d = sqrt((u - S / 2) ^ 2 + (v - S / 2) ^ 2)
        local a = max(0, min(1, S / 2 - d + 0.5))
        if line and line < S / 2 then
          a = a * max(0, min(1, d - (S / 2 - line) + 0.5))
        end
        return r, g, b, a
      end })
    elseif name == FIG_SQUARE then
      setTex({ w = S, h = S, sample = function() return r, g, b, 1 end })
    else
      error("mock: unknown figure " .. tostring(name))
    end
  elseif kind == "text" then
    local s = ...
    local f = state.font
    local r, g, b = colRGB(f[4] or 0xffffff)
    local lines, maxlen = 1, 0
    for l in (s .. "\n"):gmatch("(.-)\n") do maxlen = max(maxlen, #l) end
    for _ in s:gmatch("\n") do lines = lines + 1 end
    local W, H = max(1, floor(maxlen * f[2] * 0.55)), floor(f[2] * 1.25 * lines)
    -- 文字の代わりに縦縞
    setTex({ w = W, h = H, sample = function(u, v)
      local inGlyph = (floor(u / (f[2] * 0.55)) % 1 == 0) and (u % (f[2] * 0.55) < f[2] * 0.4)
        and (v % (f[2] * 1.25) > f[2] * 0.2) and (v % (f[2] * 1.25) < f[2] * 1.05)
      return r, g, b, inGlyph and 1 or 0
    end })
  elseif kind == "image" then
    local path = ...
    setTex({ w = 64, h = 48, sample = function(u, v)
      local c = ((floor(u / 8) + floor(v / 8)) % 2 == 0) and 1 or 0.3
      return c, c * 0.8, 0.2, 1
    end })
  elseif kind == "tempbuffer" then
    setTex(bufTex(state.tmp))
    state.final = state.tmp
  else
    error("mock: load " .. tostring(kind))
  end
  return true
end

function obj.setoption(name, a, b, c)
  if name == "drawtarget" then
    state.target = a
    if a == "tempbuffer" and b then state.tmp = newBuf(b, c) end
  elseif name == "blend" then
    state.blend = a
  elseif name == "antialias" then
    state.aa = a
  else
    M.log[#M.log + 1] = "setoption " .. tostring(name)
  end
end

function obj.setfont(name, size, typ, col1, col2)
  state.font = { name, size, typ or 0, col1 or 0xffffff }
end

function obj.getinfo(k)
  if k == "script_path" then return M.script_path end
end

local function blendPixel(buf, i, r, g, b, a)
  if a <= 0 then return end
  local mode = state.blend
  local dr, dg, db, da = buf.r[i], buf.g[i], buf.b[i], buf.a[i]
  if mode == 1 then
    buf.r[i] = min(1, dr + r * a); buf.g[i] = min(1, dg + g * a); buf.b[i] = min(1, db + b * a)
    buf.a[i] = min(1, da + a * (1 - da))
    return
  end
  local ao = a + da * (1 - a)
  if ao <= 0 then return end
  buf.r[i] = (r * a + dr * da * (1 - a)) / ao
  buf.g[i] = (g * a + dg * da * (1 - a)) / ao
  buf.b[i] = (b * a + db * da * (1 - a)) / ao
  buf.a[i] = ao
end

local SUB = { { 0.25, 0.25 }, { 0.75, 0.25 }, { 0.25, 0.75 }, { 0.75, 0.75 } }

local function triSetup(ax, ay, bx, by, cx, cy)
  local area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
  if abs(area) < 1e-9 then return nil end
  return { ax, ay, bx, by, cx, cy, area }
end

local function bary(t, px, py)
  local ax, ay, bx, by, cx, cy, area = t[1], t[2], t[3], t[4], t[5], t[6], t[7]
  local w0 = ((bx - px) * (cy - py) - (by - py) * (cx - px)) / area
  local w1 = ((cx - px) * (ay - py) - (cy - py) * (ax - px)) / area
  local w2 = 1 - w0 - w1
  return w0, w1, w2
end

function obj.drawpoly(x0, y0, z0, x1, y1, z1, x2, y2, z2, x3, y3, z3, u0, v0, u1, v1, u2, v2, u3, v3, alpha)
  M.stats.drawpoly = M.stats.drawpoly + 1
  local buf = state.tmp
  assert(state.target == "tempbuffer" and buf, "mock: drawpoly without tempbuffer")
  local tex = state.objtex
  assert(tex, "mock: no texture")
  u0, v0 = u0 or 0, v0 or 0
  u1, v1 = u1 or tex.w, v1 or 0
  u2, v2 = u2 or tex.w, v2 or tex.h
  u3, v3 = u3 or 0, v3 or tex.h
  alpha = alpha or 1
  local ox, oy = buf.w / 2, buf.h / 2
  x0, y0, x1, y1, x2, y2, x3, y3 = x0 + ox, y0 + oy, x1 + ox, y1 + oy, x2 + ox, y2 + oy, x3 + ox, y3 + oy
  local t1 = triSetup(x0, y0, x1, y1, x2, y2)
  local t2 = triSetup(x0, y0, x2, y2, x3, y3)
  local uvs1 = { u0, v0, u1, v1, u2, v2 }
  local uvs2 = { u0, v0, u2, v2, u3, v3 }
  local minx = max(0, floor(min(x0, x1, x2, x3)))
  local maxx = min(buf.w - 1, floor(max(x0, x1, x2, x3)))
  local miny = max(0, floor(min(y0, y1, y2, y3)))
  local maxy = min(buf.h - 1, floor(max(y0, y1, y2, y3)))
  for py = miny, maxy do
    for px = minx, maxx do
      local cov, sr, sg, sb, sa = 0, 0, 0, 0, 0
      for s = 1, 4 do
        local sx, sy = px + SUB[s][1], py + SUB[s][2]
        local hit, uv
        for _, pair in ipairs({ { t1, uvs1 }, { t2, uvs2 } }) do
          local t = pair[1]
          if t then
            local w0, w1, w2 = bary(t, sx, sy)
            if w0 >= -1e-9 and w1 >= -1e-9 and w2 >= -1e-9 then
              local q = pair[2]
              local u = w0 * q[1] + w1 * q[3] + w2 * q[5]
              local v = w0 * q[2] + w1 * q[4] + w2 * q[6]
              hit = { u, v }
              break
            end
          end
        end
        if hit then
          local r, g, b, a = tex.sample(hit[1], hit[2])
          sr, sg, sb, sa = sr + r * a, sg + g * a, sb + b * a, sa + a
        end
      end
      if sa > 0 then
        local a = sa / 4
        blendPixel(buf, py * buf.w + px + 1, sr / sa, sg / sa, sb / sa, a * alpha)
      end
    end
  end
end

function obj.draw()
  -- 現在のオブジェクトを中央に等倍で描く
  local t = state.objtex
  local hw, hh = t.w / 2, t.h / 2
  obj.drawpoly(-hw, -hh, 0, hw, -hh, 0, hw, hh, 0, -hw, hh, 0)
end

function obj.copybuffer(dst, src)
  local function get(n)
    if n == "tmp" then return state.tmp end
    if n == "obj" then return state.objtex.buf or error("mock: obj is not a buffer") end
    if n:sub(1, 6) == "cache:" then return state.caches[n] end
    error("mock: buffer " .. n)
  end
  local s = get(src)
  if not s then return false end
  local c = copyBuf(s)
  if dst == "tmp" then state.tmp = c
  elseif dst == "obj" then setTex(bufTex(c))
  else state.caches[dst] = c end
  return true
end

function obj.getpixel(x, y, typ)
  local b = state.objtex.buf
  local i = y * b.w + x + 1
  return floor(b.r[i] * 255 + 0.5), floor(b.g[i] * 255 + 0.5), floor(b.b[i] * 255 + 0.5), floor(b.a[i] * 255 + 0.5)
end

function obj.pixeloption() end

function obj.putpixel(x, y, r, g, b, a)
  local buf = state.objtex.buf
  local i = y * buf.w + x + 1
  buf.r[i], buf.g[i], buf.b[i], buf.a[i] = r / 255, g / 255, b / 255, a / 255
end

function obj.effect(name, ...)
  M.log[#M.log + 1] = "effect " .. tostring(name)
end

-- 画像保存（透明部分は市松模様）
function M.savePPM(path, buf)
  buf = buf or state.final
  local f = assert(io.open(path, "wb"))
  f:write(string.format("P6\n%d %d\n255\n", buf.w, buf.h))
  local out = {}
  for y = 0, buf.h - 1 do
    for x = 0, buf.w - 1 do
      local i = y * buf.w + x + 1
      local bg = ((floor(x / 10) + floor(y / 10)) % 2 == 0) and 0.8 or 0.6
      local a = buf.a[i]
      out[#out + 1] = string.char(
        floor((buf.r[i] * a + bg * (1 - a)) * 255 + 0.5),
        floor((buf.g[i] * a + bg * (1 - a)) * 255 + 0.5),
        floor((buf.b[i] * a + bg * (1 - a)) * 255 + 0.5))
    end
  end
  f:write(table.concat(out))
  f:close()
end

function M.bufDiff(a, b)
  if a.w ~= b.w or a.h ~= b.h then return math.huge end
  local d = 0
  for i = 1, a.w * a.h do
    d = max(d, abs(a.r[i] - b.r[i]), abs(a.g[i] - b.g[i]), abs(a.b[i] - b.b[i]), abs(a.a[i] - b.a[i]))
  end
  return d
end

M.copyBuf = copyBuf
return M
