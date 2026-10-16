--[[
  processing.lua  -  Processing風 描画ライブラリ for AviUtl 1.10 + 拡張編集 0.92
  (純Lua実装 / DLL不要)

  描画はすべて拡張編集の仮想バッファ(tempbuffer)に対して
  obj.load("figure") で作った単色テクスチャを obj.drawpoly で描く方式で行う。
  使い方は README.md を参照。
  ※このファイルは Shift_JIS で保存すること（図形名 "円" などを拡張編集に渡すため）
]]

local P = {}
local API = {}          -- スケッチから見える関数・定数
P.API = API

local floor, ceil, sqrt, abs = math.floor, math.ceil, math.sqrt, math.abs
local sin, cos, atan2, pi = math.sin, math.cos, math.atan2, math.pi
local mmin, mmax = math.min, math.max
local unpack = unpack or table.unpack

local FIG_CIRCLE = "円"

local C = nil           -- 現在のスケッチの描画コンテキスト

-- Java 風の文字列化（true/false/null、整数は小数点なし）
local function jstr(v)
  local t = type(v)
  if v == nil then return "null" end
  if t == "boolean" then return v and "true" or "false" end
  if t == "number" then
    if v ~= v then return "NaN" end
    if v == floor(v) and abs(v) < 1e15 then return string.format("%d", v) end
    return string.format("%.7g", v)
  end
  return tostring(v)
end

----------------------------------------------------------------------
-- 定数
----------------------------------------------------------------------
API.PI, API.TWO_PI, API.TAU = pi, pi * 2, pi * 2
API.HALF_PI, API.QUARTER_PI = pi / 2, pi / 4
API.RGB, API.HSB = "rgb", "hsb"
API.CORNER, API.CORNERS, API.CENTER, API.RADIUS = "corner", "corners", "center", "radius"
API.LEFT, API.RIGHT, API.TOP, API.BOTTOM, API.BASELINE = "left", "right", "top", "bottom", "baseline"
API.ROUND, API.SQUARE, API.PROJECT = "round", "square", "project"
API.MITER, API.BEVEL = "miter", "bevel"
API.OPEN, API.CHORD, API.PIE = "open", "chord", "pie"
API.CLOSE = "close"
API.POINTS, API.LINES, API.TRIANGLES = "points", "lines", "triangles"
API.TRIANGLE_FAN, API.TRIANGLE_STRIP = "triangle_fan", "triangle_strip"
API.QUADS, API.QUAD_STRIP = "quads", "quad_strip"
API.BLEND, API.ADD, API.SUBTRACT, API.MULTIPLY = "blend", "add", "subtract", "multiply"
API.SCREEN, API.OVERLAY, API.LIGHTEST, API.DARKEST = "screen", "overlay", "lightest", "darkest"
API.DIFFERENCE = "difference"
API.BLUR, API.GRAY, API.INVERT, API.THRESHOLD, API.POSTERIZE = "blur", "gray", "invert", "threshold", "posterize"

-- 拡張編集の合成モード番号
local BLEND_NO = {
  blend = 0, add = 1, subtract = 2, multiply = 3, screen = 4, overlay = 5,
  lightest = 6, darkest = 7, difference = 12,
}

local MITER_LIMIT = 4

----------------------------------------------------------------------
-- 色
----------------------------------------------------------------------
local Color = {}
Color.__index = Color
Color.__tostring = function(c)
  return string.format("color(%d, %d, %d, %d)", c.r * 255, c.g * 255, c.b * 255, c.a * 255)
end

local function mkcolor(r, g, b, a)
  return setmetatable({ r = r, g = g, b = b, a = a }, Color)
end

local function clamp01(v)
  if v < 0 then return 0 elseif v > 1 then return 1 end
  return v
end

local function hsb2rgb(h, s, v)
  h = (h % 1) * 6
  local i = floor(h)
  local f = h - i
  local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
  if i == 0 then return v, t, p
  elseif i == 1 then return q, v, p
  elseif i == 2 then return p, v, t
  elseif i == 3 then return p, q, v
  elseif i == 4 then return t, p, v
  end
  return v, p, q
end

local function rgb2hsb(r, g, b)
  local mx, mn = mmax(r, g, b), mmin(r, g, b)
  local d = mx - mn
  local h = 0
  if d > 0 then
    if mx == r then h = ((g - b) / d) % 6
    elseif mx == g then h = (b - r) / d + 2
    else h = (r - g) / d + 4 end
    h = h / 6
  end
  local s = (mx > 0) and d / mx or 0
  return h, s, mx
end

local function parseHex(s)
  local hex = s:gsub("^#", "")
  local r, g, b, a = 0, 0, 0, 255
  if #hex == 6 or #hex == 8 then
    r = tonumber(hex:sub(1, 2), 16) or 0
    g = tonumber(hex:sub(3, 4), 16) or 0
    b = tonumber(hex:sub(5, 6), 16) or 0
    if #hex == 8 then a = tonumber(hex:sub(7, 8), 16) or 255 end
  elseif #hex == 3 then
    r = (tonumber(hex:sub(1, 1), 16) or 0) * 17
    g = (tonumber(hex:sub(2, 2), 16) or 0) * 17
    b = (tonumber(hex:sub(3, 3), 16) or 0) * 17
  end
  return mkcolor(r / 255, g / 255, b / 255, a / 255)
end

-- fill() / stroke() / color() などの引数を色に変換
local function toColor(...)
  local n = select("#", ...)
  local a1, a2, a3, a4 = ...
  local cm = C.colorMode
  if type(a1) == "table" then
    local c = mkcolor(a1.r, a1.g, a1.b, a1.a)
    if a2 then c.a = clamp01(a2 / cm.ma) end
    return c
  elseif type(a1) == "string" then
    local c = parseHex(a1)
    if a2 then c.a = clamp01(a2 / cm.ma) end
    return c
  end
  if n == 0 or a1 == nil then return mkcolor(0, 0, 0, 1) end
  if n <= 2 then
    -- グレー（HSBモードでも明るさとして扱う）
    local gmax = (cm.mode == "hsb") and cm.m3 or cm.m1
    if a1 == floor(a1) and (a1 < 0 or a1 > mmax(gmax, cm.m1)) then
      -- 0xAARRGGBB 形式の色（Processing の color 型の整数）
      local v = a1 % 4294967296
      local b = v % 256; v = (v - b) / 256
      local g = v % 256; v = (v - g) / 256
      local r = v % 256; v = (v - r) / 256
      local c = mkcolor(r / 255, g / 255, b / 255, (v % 256) / 255)
      if a2 then c.a = clamp01(a2 / cm.ma) end
      return c
    end
    local v = clamp01(a1 / gmax)
    local al = a2 and clamp01(a2 / cm.ma) or 1
    return mkcolor(v, v, v, al)
  end
  local x, y, z = clamp01(a1 / cm.m1), clamp01(a2 / cm.m2), clamp01(a3 / cm.m3)
  local al = a4 and clamp01(a4 / cm.ma) or 1
  if cm.mode == "hsb" then
    if a1 >= cm.m1 then x = 0 end   -- 色相は一周
    local r, g, b = hsb2rgb(x, y, z)
    return mkcolor(r, g, b, al)
  end
  return mkcolor(x, y, z, al)
end

local function colInt(c)
  return floor(c.r * 255 + 0.5) * 65536 + floor(c.g * 255 + 0.5) * 256 + floor(c.b * 255 + 0.5)
end

function API.color(...) return toColor(...) end
local function asColor(c)
  if type(c) ~= "table" then return toColor(c) end
  return c
end
function API.red(c) c = asColor(c); return c.r * C.colorMode.m1 end
function API.green(c) c = asColor(c); return c.g * C.colorMode.m2 end
function API.blue(c) c = asColor(c); return c.b * C.colorMode.m3 end
function API.alpha(c) c = asColor(c); return c.a * C.colorMode.ma end
function API.hue(c) c = asColor(c); local h = rgb2hsb(c.r, c.g, c.b); return h * C.colorMode.m1 end
function API.saturation(c) c = asColor(c); local _, s = rgb2hsb(c.r, c.g, c.b); return s * C.colorMode.m2 end
function API.brightness(c) c = asColor(c); local _, _, v = rgb2hsb(c.r, c.g, c.b); return v * C.colorMode.m3 end
function API.lerpColor(c1, c2, t)
  c1, c2 = asColor(c1), asColor(c2)
  t = clamp01(t)
  return mkcolor(c1.r + (c2.r - c1.r) * t, c1.g + (c2.g - c1.g) * t,
                 c1.b + (c2.b - c1.b) * t, c1.a + (c2.a - c1.a) * t)
end

function API.colorMode(mode, m1, m2, m3, ma)
  local cm = { mode = mode or "rgb" }
  local def = (cm.mode == "hsb") and { 360, 100, 100, 255 } or { 255, 255, 255, 255 }
  if m1 and not m2 then
    cm.m1, cm.m2, cm.m3, cm.ma = m1, m1, m1, m1
  else
    cm.m1, cm.m2, cm.m3 = m1 or def[1], m2 or def[2], m3 or def[3]
    cm.ma = ma or def[4]
  end
  C.colorMode = cm
end

function API.fill(...) C.fill = toColor(...) end
function API.noFill() C.fill = nil end
function API.stroke(...) C.stroke = toColor(...) end
function API.noStroke() C.stroke = nil end
function API.strokeWeight(w) C.sw = w end
function API.strokeCap(c) C.cap = c end
function API.strokeJoin(j) C.join = j end
function API.tint(...)
  local c = toColor(...)
  C.tint = c
end
function API.noTint() C.tint = nil end

----------------------------------------------------------------------
-- 変換行列  [a c e; b d f]
----------------------------------------------------------------------
local function M() return C.m end

local function tp(x, y)
  local m = C.m
  return m[1] * x + m[3] * y + m[5], m[2] * x + m[4] * y + m[6]
end

local function mscale()
  local m = C.m
  return sqrt(abs(m[1] * m[4] - m[2] * m[3]))
end

function API.translate(x, y)
  local m = C.m
  m[5] = m[1] * x + m[3] * y + m[5]
  m[6] = m[2] * x + m[4] * y + m[6]
end

function API.rotate(t)
  local m = C.m
  local c, s = cos(t), sin(t)
  local a, b, cc, d = m[1], m[2], m[3], m[4]
  m[1], m[2] = a * c + cc * s, b * c + d * s
  m[3], m[4] = -a * s + cc * c, -b * s + d * c
end

function API.scale(sx, sy)
  sy = sy or sx
  local m = C.m
  m[1], m[2] = m[1] * sx, m[2] * sx
  m[3], m[4] = m[3] * sy, m[4] * sy
end

function API.shearX(t)
  local m, k = C.m, math.tan(t)
  m[3], m[4] = m[1] * k + m[3], m[2] * k + m[4]
end

function API.shearY(t)
  local m, k = C.m, math.tan(t)
  m[1], m[2] = m[1] + m[3] * k, m[2] + m[4] * k
end

-- Processing と同じ並び (n00, n01, n02, n10, n11, n12)
function API.applyMatrix(n00, n01, n02, n10, n11, n12)
  local m = C.m
  local a, b, c, d, e, f = m[1], m[2], m[3], m[4], m[5], m[6]
  m[1] = a * n00 + c * n10
  m[2] = b * n00 + d * n10
  m[3] = a * n01 + c * n11
  m[4] = b * n01 + d * n11
  m[5] = a * n02 + c * n12 + e
  m[6] = b * n02 + d * n12 + f
end

function API.resetMatrix() C.m = { 1, 0, 0, 1, 0, 0 } end

local function copyMatrix(m) return { m[1], m[2], m[3], m[4], m[5], m[6] } end

local STYLE_KEYS = { "fill", "stroke", "sw", "cap", "join", "rectMode", "ellipseMode",
  "imageMode", "colorMode", "textSize", "textFont", "textAlignH", "textAlignV", "tint", "blend",
  "textLeading" }

local function saveStyle()
  local s = {}
  for _, k in ipairs(STYLE_KEYS) do s[k] = C[k] end
  return s
end

local function loadStyle(s)
  for _, k in ipairs(STYLE_KEYS) do C[k] = s[k] end
end

function API.pushMatrix() table.insert(C.mstack, copyMatrix(C.m)) end
function API.popMatrix()
  local m = table.remove(C.mstack)
  if m then C.m = m end
end
function API.pushStyle() table.insert(C.sstack, saveStyle()) end
function API.popStyle()
  local s = table.remove(C.sstack)
  if s then loadStyle(s) end
end
function API.push()
  table.insert(C.pstack, { m = copyMatrix(C.m), s = saveStyle() })
end
function API.pop()
  local t = table.remove(C.pstack)
  if t then C.m = t.m; loadStyle(t.s) end
end

----------------------------------------------------------------------
-- 描画バックエンド（拡張編集）
----------------------------------------------------------------------
local R = { tex = nil, blend = nil }

local function invalidateTex() R.tex = nil end

local function applyBlend()
  local b = BLEND_NO[C.blend] or 0
  if R.blend ~= b then
    obj.setoption("blend", b)
    R.blend = b
  end
end

local function poly(x0, y0, x1, y1, x2, y2, x3, y3, u0, v0, u1, v1, u2, v2, u3, v3, alpha)
  if C.dry then return end
  local hw, hh = C.W * 0.5, C.H * 0.5
  applyBlend()
  obj.drawpoly(x0 - hw, y0 - hh, 0, x1 - hw, y1 - hh, 0, x2 - hw, y2 - hh, 0, x3 - hw, y3 - hh, 0,
    u0, v0, u1, v1, u2, v2, u3, v3, alpha)
end

local function bucket(px)
  local s = 64
  while s < px and s < 2048 do s = s * 2 end
  return s
end

-- 塗りつぶし円のテクスチャ（中央部分は単色の四角としても使う）
local function useFillTex(col, need)
  need = need or 1
  local ci = colInt(col)
  local t = R.tex
  if t and t.kind == "fill" and t.ci == ci and t.size >= need and t.size <= mmax(64, need * 4) then
    return t
  end
  local size = bucket(need)
  obj.load("figure", FIG_CIRCLE, ci, size)
  t = { kind = "fill", ci = ci, size = size, w = obj.w, h = obj.h }
  R.tex = t
  return t
end

local function useRingTex(col, size, line)
  local ci = colInt(col)
  local t = R.tex
  if t and t.kind == "ring" and t.ci == ci and t.size == size and t.line == line then return t end
  obj.load("figure", FIG_CIRCLE, ci, size, line)
  t = { kind = "ring", ci = ci, size = size, line = line, w = obj.w, h = obj.h }
  R.tex = t
  return t
end

local function solidQuad(col, x0, y0, x1, y1, x2, y2, x3, y3)
  if C.dry or col.a <= 0 then return end
  local t = useFillTex(col, 1)
  local ua, ub = t.w * 0.4, t.w * 0.6
  local va, vb = t.h * 0.4, t.h * 0.6
  poly(x0, y0, x1, y1, x2, y2, x3, y3, ua, va, ub, va, ub, vb, ua, vb, col.a)
end

local function solidTri(col, x0, y0, x1, y1, x2, y2)
  solidQuad(col, x0, y0, x1, y1, x2, y2, x2, y2)
end

-- 画面座標の円（直径 d）
local function screenDot(col, x, y, d)
  if C.dry or col.a <= 0 or d <= 0 then return end
  local t = useFillTex(col, d)
  local r = d * 0.5
  poly(x - r, y - r, x + r, y - r, x + r, y + r, x - r, y + r, 0, 0, t.w, 0, t.w, t.h, 0, t.h, col.a)
end

-- 端の丸（半円）。(dx,dy) は外向きの単位ベクトル。線の本体と重ならない
local function halfDisc(col, x, y, dx, dy, d)
  if C.dry or col.a <= 0 or d <= 0 then return end
  local t = useFillTex(col, d)
  local r = d * 0.5
  local nx, ny = -dy * r, dx * r
  local ex, ey = dx * r, dy * r
  local hw, hh = t.w * 0.5, t.h * 0.5
  poly(x + nx, y + ny, x + nx + ex, y + ny + ey, x - nx + ex, y - ny + ey, x - nx, y - ny,
    hw * 2, hh, hw * 2, hh * 2, 0, hh * 2, 0, hh, col.a)
end

local function opaque(col) return mkcolor(col.r, col.g, col.b, 1) end

-- 半透明の複雑な図形は、別の層に不透明で描いてから一度だけ透明度をかけて合成する
-- （三角形の重なりで濃くなるのを防ぐ）
local LAYER_CACHE = "cache:processing__layer"
local function isolated(alpha, fn)
  local W, H = C.W, C.H
  obj.copybuffer(LAYER_CACHE, "tmp")
  obj.setoption("drawtarget", "tempbuffer", W, H)
  invalidateTex()
  local saved = C.blend
  C.blend = "blend"
  fn()
  C.blend = saved
  obj.copybuffer("obj", "tmp")
  invalidateTex()
  obj.setoption("drawtarget", "tempbuffer", W, H)
  obj.copybuffer("tmp", LAYER_CACHE)
  poly(0, 0, W, 0, W, H, 0, H, 0, 0, obj.w, 0, obj.w, obj.h, 0, obj.h, alpha)
  invalidateTex()
end

----------------------------------------------------------------------
-- 塗り（多角形）
----------------------------------------------------------------------
local function signedArea(xs, ys)
  local s, n = 0, #xs
  for i = 1, n do
    local j = i % n + 1
    s = s + xs[i] * ys[j] - xs[j] * ys[i]
  end
  return s * 0.5
end

local function isConvex(xs, ys)
  local n = #xs
  local sign = 0
  for i = 1, n do
    local j, k = i % n + 1, (i + 1) % n + 1
    local cr = (xs[j] - xs[i]) * (ys[k] - ys[j]) - (ys[j] - ys[i]) * (xs[k] - xs[j])
    if abs(cr) > 1e-9 then
      local s = cr > 0 and 1 or -1
      if sign == 0 then sign = s elseif s ~= sign then return false end
    end
  end
  return true
end

local function pointInTri(px, py, ax, ay, bx, by, cx, cy)
  local d1 = (px - bx) * (ay - by) - (ax - bx) * (py - by)
  local d2 = (px - cx) * (by - cy) - (bx - cx) * (py - cy)
  local d3 = (px - ax) * (cy - ay) - (cx - ax) * (py - ay)
  local neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
  local pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
  return not (neg and pos)
end

-- 耳刈り法で三角形分割。戻り値は {i1,i2,i3, ...}
local function earClip(xs, ys)
  local n = #xs
  local idx = {}
  if signedArea(xs, ys) > 0 then
    for i = 1, n do idx[i] = i end
  else
    for i = 1, n do idx[i] = n - i + 1 end
  end
  local tris = {}
  local guard = 0
  while #idx > 3 and guard < n * n do
    guard = guard + 1
    local m = #idx
    local found = false
    for i = 1, m do
      local ia, ib, ic = idx[(i - 2) % m + 1], idx[i], idx[i % m + 1]
      local ax, ay, bx, by, cx, cy = xs[ia], ys[ia], xs[ib], ys[ib], xs[ic], ys[ic]
      local cr = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
      if cr > 0 then
        local ok = true
        for j = 1, m do
          local q = idx[j]
          if q ~= ia and q ~= ib and q ~= ic and pointInTri(xs[q], ys[q], ax, ay, bx, by, cx, cy) then
            ok = false
            break
          end
        end
        if ok then
          tris[#tris + 1] = ia; tris[#tris + 1] = ib; tris[#tris + 1] = ic
          table.remove(idx, i)
          found = true
          break
        end
      end
    end
    if not found then
      -- 自己交差などで耳が見つからない場合は残りを扇形で埋める
      break
    end
  end
  for i = 2, #idx - 1 do
    tris[#tris + 1] = idx[1]; tris[#tris + 1] = idx[i]; tris[#tris + 1] = idx[i + 1]
  end
  return tris
end

-- 直線の交点（p + t*d と q + u*e）
local function intersect(px, py, dx, dy, qx, qy, ex, ey)
  local den = dx * ey - dy * ex
  if abs(den) < 1e-12 then return nil end
  local t = ((qx - px) * ey - (qy - py) * ex) / den
  return px + dx * t, py + dy * t
end

-- 凸多角形: 重心から放射状に三角形へ分け、内側の継ぎ目（放射線）だけを
-- 少し外へずらして重ねる。外周の形は変わらない
local SEAM = 0.5
local function fillConvexSeamless(col, xs, ys)
  local n = #xs
  local cx, cy = 0, 0
  for i = 1, n do cx, cy = cx + xs[i], cy + ys[i] end
  cx, cy = cx / n, cy / n
  local minR = math.huge
  for i = 1, n do minR = mmin(minR, sqrt((xs[i] - cx) ^ 2 + (ys[i] - cy) ^ 2)) end
  for i = 1, n do
    local j = i % n + 1
    local ax, ay, bx, by = xs[i], ys[i], xs[j], ys[j]
    -- 放射線 c->a を b から遠ざかる側へ、c->b を a から遠ざかる側へずらす
    local function offsetSpoke(px, py, ox, oy)
      local dx, dy = px - cx, py - cy
      local l = sqrt(dx * dx + dy * dy)
      if l < 1e-9 then return cx, cy, 1, 0 end
      dx, dy = dx / l, dy / l
      local nx, ny = -dy, dx
      if nx * (ox - cx) + ny * (oy - cy) > 0 then nx, ny = -nx, -ny end
      return cx + nx * SEAM, cy + ny * SEAM, dx, dy
    end
    local sax, say, sadx, sady = offsetSpoke(ax, ay, bx, by)
    local sbx, sby, sbdx, sbdy = offsetSpoke(bx, by, ax, ay)
    local edx, edy = bx - ax, by - ay
    local a2x, a2y = intersect(sax, say, sadx, sady, ax, ay, edx, edy)
    local b2x, b2y = intersect(sbx, sby, sbdx, sbdy, ax, ay, edx, edy)
    local c2x, c2y = intersect(sax, say, sadx, sady, sbx, sby, sbdx, sbdy)
    local el = sqrt(edx * edx + edy * edy)
    if not a2x or sqrt((a2x - ax) ^ 2 + (a2y - ay) ^ 2) > mmax(2, el) then a2x, a2y = ax, ay end
    if not b2x or sqrt((b2x - bx) ^ 2 + (b2y - by) ^ 2) > mmax(2, el) then b2x, b2y = bx, by end
    if not c2x or sqrt((c2x - cx) ^ 2 + (c2y - cy) ^ 2) > minR * 0.5 then c2x, c2y = cx, cy end
    solidTri(col, c2x, c2y, a2x, a2y, b2x, b2y)
  end
end

local function pointInPolygon(x, y, xs, ys)
  local inside, n = false, #xs
  local j = n
  for i = 1, n do
    if ((ys[i] > y) ~= (ys[j] > y)) and (x < (xs[j] - xs[i]) * (y - ys[i]) / (ys[j] - ys[i]) + xs[i]) then
      inside = not inside
    end
    j = i
  end
  return inside
end

-- 任意の三角形分割: 多角形の外周でない辺（内側の継ぎ目）だけを外へずらす
local function fillTrisSeamless(col, xs, ys, tris)
  local n = #xs
  local function isBoundary(i, j)
    return (j == i % n + 1) or (i == j % n + 1)
  end
  for t = 1, #tris, 3 do
    local id = { tris[t], tris[t + 1], tris[t + 2] }
    local px, py = { xs[id[1]], xs[id[2]], xs[id[3]] }, { ys[id[1]], ys[id[2]], ys[id[3]] }
    -- 辺 k: 頂点 k -> k%3+1
    local lx, ly, ldx, ldy, inner = {}, {}, {}, {}, {}
    for k = 1, 3 do
      local k2, k3 = k % 3 + 1, (k + 1) % 3 + 1
      local dx, dy = px[k2] - px[k], py[k2] - py[k]
      local l = sqrt(dx * dx + dy * dy)
      if l < 1e-9 then l = 1 end
      dx, dy = dx / l, dy / l
      local nx, ny = -dy, dx
      if nx * (px[k3] - px[k]) + ny * (py[k3] - py[k]) > 0 then nx, ny = -nx, -ny end
      inner[k] = not isBoundary(id[k], id[k2])
      local off = inner[k] and SEAM or 0
      lx[k], ly[k], ldx[k], ldy[k] = px[k] + nx * off, py[k] + ny * off, dx, dy
    end
    local qx, qy = {}, {}
    for k = 1, 3 do
      local ein, eout = (k + 1) % 3 + 1, k   -- 頂点 k に入る辺と出る辺
      qx[k], qy[k] = px[k], py[k]
      if inner[ein] or inner[eout] then
        local ix, iy = intersect(lx[ein], ly[ein], ldx[ein], ldy[ein], lx[eout], ly[eout], ldx[eout], ldy[eout])
        if ix then
          local d = sqrt((ix - px[k]) ^ 2 + (iy - py[k]) ^ 2)
          if inner[ein] ~= inner[eout] then
            if d <= 2 then qx[k], qy[k] = ix, iy end
          elseif d <= 1.5 and pointInPolygon(ix, iy, xs, ys) then
            -- 両側とも継ぎ目の頂点は、図形の内側に収まるときだけ動かす
            qx[k], qy[k] = ix, iy
          end
        end
      end
    end
    solidTri(col, qx[1], qy[1], qx[2], qy[2], qx[3], qy[3])
  end
end

local function fillTriList(col, xs, ys, tris, passes)
  for _ = 1, passes do
    for i = 1, #tris, 3 do
      local a, b, c = tris[i], tris[i + 1], tris[i + 2]
      solidTri(col, xs[a], ys[a], xs[b], ys[b], xs[c], ys[c])
    end
  end
end

local function fillPolygon(xs, ys)
  local col = C.fill
  if C.dry or not col or col.a <= 0 then return end
  local n = #xs
  if n < 3 then return end
  if n == 3 then
    solidTri(col, xs[1], ys[1], xs[2], ys[2], xs[3], ys[3])
    return
  elseif n == 4 and isConvex(xs, ys) then
    solidQuad(col, xs[1], ys[1], xs[2], ys[2], xs[3], ys[3], xs[4], ys[4])
    return
  end
  local convex = isConvex(xs, ys)
  local tris = (not convex) and earClip(xs, ys) or nil
  if not convex and #tris == 3 then
    fillTriList(col, xs, ys, tris, 1)
    return
  end
  local function body(c)
    if convex then fillConvexSeamless(c, xs, ys)
    else
      -- 凹多角形: 継ぎ目を外へずらした三角形を2回重ねる（不透明なので重ねても色は変わらない）
      fillTrisSeamless(c, xs, ys, tris)
      fillTrisSeamless(c, xs, ys, tris)
    end
  end
  if col.a < 0.999 then
    isolated(col.a, function() body(opaque(col)) end)
  else
    body(col)
  end
end

----------------------------------------------------------------------
-- 線（ポリライン）
----------------------------------------------------------------------
local function strokeWidth()
  return C.sw * mscale()
end

local function strokePath(xs0, ys0, closed)
  local col = C.stroke
  if C.dry or not col or col.a <= 0 then return end
  local w = strokeWidth()
  if w <= 0 then return end
  local hw = w * 0.5
  local xs, ys = {}, {}
  for i = 1, #xs0 do
    local x, y = xs0[i], ys0[i]
    local n = #xs
    if n == 0 or abs(x - xs[n]) > 1e-6 or abs(y - ys[n]) > 1e-6 then
      xs[n + 1], ys[n + 1] = x, y
    end
  end
  local n = #xs
  if closed and n > 1 and abs(xs[1] - xs[n]) < 1e-6 and abs(ys[1] - ys[n]) < 1e-6 then
    xs[n], ys[n] = nil, nil
    n = n - 1
  end
  if n == 0 then return end
  if n == 1 then
    if C.cap == "round" then
      screenDot(col, xs[1], ys[1], w)
    else
      solidQuad(col, xs[1] - hw, ys[1] - hw, xs[1] + hw, ys[1] - hw, xs[1] + hw, ys[1] + hw, xs[1] - hw, ys[1] + hw)
    end
    return
  end
  if n == 2 then closed = false end

  local segs = closed and n or n - 1
  local dx, dy, nx, ny = {}, {}, {}, {}
  local SLx, SLy, SRx, SRy, ELx, ELy, ERx, ERy = {}, {}, {}, {}, {}, {}, {}, {}
  for k = 1, segs do
    local i, j = k, k % n + 1
    local ddx, ddy = xs[j] - xs[i], ys[j] - ys[i]
    local l = sqrt(ddx * ddx + ddy * ddy)
    dx[k], dy[k] = ddx / l, ddy / l
    nx[k], ny[k] = -dy[k], dx[k]
    SLx[k], SLy[k] = xs[i] + nx[k] * hw, ys[i] + ny[k] * hw
    SRx[k], SRy[k] = xs[i] - nx[k] * hw, ys[i] - ny[k] * hw
    ELx[k], ELy[k] = xs[j] + nx[k] * hw, ys[j] + ny[k] * hw
    ERx[k], ERy[k] = xs[j] - nx[k] * hw, ys[j] - ny[k] * hw
  end

  if not closed and C.cap == "project" then
    SLx[1], SLy[1] = SLx[1] - dx[1] * hw, SLy[1] - dy[1] * hw
    SRx[1], SRy[1] = SRx[1] - dx[1] * hw, SRy[1] - dy[1] * hw
    local k = segs
    ELx[k], ELy[k] = ELx[k] + dx[k] * hw, ELy[k] + dy[k] * hw
    ERx[k], ERy[k] = ERx[k] + dx[k] * hw, ERy[k] + dy[k] * hw
  end

  local bevels, rounds = {}, {}
  local v0, v1 = 2, n - 1
  if closed then v0, v1 = 1, n end
  for v = v0, v1 do
    local kin = closed and ((v - 2) % n + 1) or (v - 1)
    local kout = v
    local x, y = xs[v], ys[v]
    if C.join == "round" then
      rounds[#rounds + 1] = v
    else
      local mx, my = nx[kin] + nx[kout], ny[kin] + ny[kout]
      local ml = sqrt(mx * mx + my * my)
      local done = false
      if C.join == "miter" and ml > 1e-6 then
        mx, my = mx / ml, my / ml
        local d = mx * nx[kout] + my * ny[kout]
        local len = hw / d
        if len <= hw * MITER_LIMIT then
          ELx[kin], ELy[kin] = x + mx * len, y + my * len
          ERx[kin], ERy[kin] = x - mx * len, y - my * len
          SLx[kout], SLy[kout] = ELx[kin], ELy[kin]
          SRx[kout], SRy[kout] = ERx[kin], ERy[kin]
          done = true
        end
      end
      if not done then
        local s = (nx[kin] * dx[kout] + ny[kin] * dy[kout] < 0) and 1 or -1
        bevels[#bevels + 1] = { x, y, x + s * nx[kin] * hw, y + s * ny[kin] * hw,
          x + s * nx[kout] * hw, y + s * ny[kout] * hw }
      end
    end
  end

  local roundCap = (not closed) and C.cap == "round"
  local function emit(c)
    for k = 1, segs do
      solidQuad(c, SLx[k], SLy[k], ELx[k], ELy[k], ERx[k], ERy[k], SRx[k], SRy[k])
    end
    for _, b in ipairs(bevels) do solidTri(c, unpack(b)) end
    for _, v in ipairs(rounds) do screenDot(c, xs[v], ys[v], w) end
    if roundCap then
      halfDisc(c, xs[1], ys[1], -dx[1], -dy[1], w)
      halfDisc(c, xs[n], ys[n], dx[segs], dy[segs], w)
    end
  end
  -- 半透明で、継ぎ目が重なる形（丸/ベベル結合）は層に分けて描く
  if col.a < 0.999 and segs >= 2 and (#rounds > 0 or #bevels > 0) then
    isolated(col.a, function() emit(opaque(col)) end)
  else
    emit(col)
  end
end

-- ローカル座標の点列 → 画面座標
local function tpList(lx, ly)
  local xs, ys = {}, {}
  for i = 1, #lx do xs[i], ys[i] = tp(lx[i], ly[i]) end
  return xs, ys
end

----------------------------------------------------------------------
-- 基本図形
----------------------------------------------------------------------
local function modeRect(mode, a, b, c, d)
  if mode == "corners" then
    return mmin(a, c), mmin(b, d), abs(c - a), abs(d - b)
  elseif mode == "center" then
    return a - c / 2, b - d / 2, c, d
  elseif mode == "radius" then
    return a - c, b - d, c * 2, d * 2
  end
  if c < 0 then a, c = a + c, -c end
  if d < 0 then b, d = b + d, -d end
  return a, b, c, d
end

local function arcPoints(cx, cy, rx, ry, a0, a1, lx, ly)
  local sr = mscale() * mmax(rx, ry)
  local span = a1 - a0
  local segs = mmax(2, mmin(256, ceil(abs(span) * sr / 3)))
  for i = 0, segs do
    local t = a0 + span * i / segs
    lx[#lx + 1] = cx + cos(t) * rx
    ly[#ly + 1] = cy + sin(t) * ry
  end
end

function API.rect(a, b, c, d, r1, r2, r3, r4)
  if C.dry then return end
  local x, y, w, h = modeRect(C.rectMode, a, b, c, d or c)
  if r1 and r1 > 0 then
    r2, r3, r4 = r2 or r1, r3 or r1, r4 or r1
    local lim = mmin(w, h) / 2
    r1, r2, r3, r4 = mmin(r1, lim), mmin(r2, lim), mmin(r3, lim), mmin(r4, lim)
    local lx, ly = {}, {}
    arcPoints(x + r1, y + r1, r1, r1, pi, pi * 1.5, lx, ly)
    arcPoints(x + w - r2, y + r2, r2, r2, pi * 1.5, pi * 2, lx, ly)
    arcPoints(x + w - r3, y + h - r3, r3, r3, 0, pi * 0.5, lx, ly)
    arcPoints(x + r4, y + h - r4, r4, r4, pi * 0.5, pi, lx, ly)
    local xs, ys = tpList(lx, ly)
    fillPolygon(xs, ys)
    strokePath(xs, ys, true)
    return
  end
  local xs, ys = tpList({ x, x + w, x + w, x }, { y, y, y + h, y + h })
  fillPolygon(xs, ys)
  strokePath(xs, ys, true)
end

function API.square(x, y, s) API.rect(x, y, s, s) end

function API.ellipse(a, b, c, d)
  if C.dry then return end
  d = d or c
  local mode = C.ellipseMode
  local x, y, w, h
  if mode == "corner" then x, y, w, h = a, b, c, d
  elseif mode == "corners" then x, y, w, h = mmin(a, c), mmin(b, d), abs(c - a), abs(d - b)
  elseif mode == "radius" then x, y, w, h = a - c, b - d, c * 2, d * 2
  else x, y, w, h = a - c / 2, b - d / 2, c, d end
  w, h = abs(w), abs(h)
  local m = C.m
  local col = C.fill
  if col and col.a > 0 then
    local sx = sqrt(m[1] * m[1] + m[2] * m[2]) * w
    local sy = sqrt(m[3] * m[3] + m[4] * m[4]) * h
    local t = useFillTex(col, mmax(sx, sy))
    local x0, y0 = tp(x, y)
    local x1, y1 = tp(x + w, y)
    local x2, y2 = tp(x + w, y + h)
    local x3, y3 = tp(x, y + h)
    poly(x0, y0, x1, y1, x2, y2, x3, y3, 0, 0, t.w, 0, t.w, t.h, 0, t.h, col.a)
  end
  local sc = C.stroke
  if sc and sc.a > 0 and C.sw > 0 then
    -- 回転・等倍拡大のみの円なら輪のテクスチャ1枚で描く
    local isSim = abs(m[1] - m[4]) < 1e-6 and abs(m[2] + m[3]) < 1e-6
    if isSim and abs(w - h) < 1e-6 then
      local s = mscale()
      local sw = C.sw * s
      local D = w * s + sw
      local size = bucket(D)
      local line = mmax(1, floor(sw * size / D + 0.5))
      local t = useRingTex(sc, size, line)
      local cx, cy = tp(x + w / 2, y + h / 2)
      local r = D / 2
      poly(cx - r, cy - r, cx + r, cy - r, cx + r, cy + r, cx - r, cy + r, 0, 0, t.w, 0, t.w, t.h, 0, t.h, sc.a)
    else
      local lx, ly = {}, {}
      arcPoints(x + w / 2, y + h / 2, w / 2, h / 2, 0, pi * 2, lx, ly)
      lx[#lx], ly[#ly] = nil, nil
      local xs, ys = tpList(lx, ly)
      strokePath(xs, ys, true)
    end
  end
end

function API.circle(x, y, d) API.ellipse(x, y, d, d) end

function API.arc(a, b, c, d, start, stop, mode)
  if C.dry then return end
  local em = C.ellipseMode
  local x, y, w, h
  if em == "corner" then x, y, w, h = a, b, c, d
  elseif em == "corners" then x, y, w, h = mmin(a, c), mmin(b, d), abs(c - a), abs(d - b)
  elseif em == "radius" then x, y, w, h = a - c, b - d, c * 2, d * 2
  else x, y, w, h = a - c / 2, b - d / 2, c, d end
  if stop < start then return end
  if stop - start > pi * 2 then stop = start + pi * 2 end
  local cx, cy, rx, ry = x + w / 2, y + h / 2, w / 2, h / 2
  local lx, ly = {}, {}
  arcPoints(cx, cy, rx, ry, start, stop, lx, ly)
  local ax, ay = tpList(lx, ly)
  if C.fill then
    local fx, fy = {}, {}
    for i = 1, #ax do fx[i], fy[i] = ax[i], ay[i] end
    if mode ~= "chord" then
      local px, py = tp(cx, cy)
      fx[#fx + 1], fy[#fy + 1] = px, py
    end
    fillPolygon(fx, fy)
  end
  if mode == "pie" then
    local px, py = tp(cx, cy)
    ax[#ax + 1], ay[#ay + 1] = px, py
    strokePath(ax, ay, true)
  elseif mode == "chord" then
    strokePath(ax, ay, true)
  else
    strokePath(ax, ay, false)
  end
end

function API.line(x1, y1, x2, y2)
  if C.dry then return end
  local ax, ay = tp(x1, y1)
  local bx, by = tp(x2, y2)
  strokePath({ ax, bx }, { ay, by }, false)
end

function API.point(x, y)
  if C.dry then return end
  local col = C.stroke
  if not col then return end
  local px, py = tp(x, y)
  local w = strokeWidth()
  if C.cap == "round" then
    screenDot(col, px, py, w)
  else
    local h = w / 2
    solidQuad(col, px - h, py - h, px + h, py - h, px + h, py + h, px - h, py + h)
  end
end

function API.triangle(x1, y1, x2, y2, x3, y3)
  if C.dry then return end
  local xs, ys = tpList({ x1, x2, x3 }, { y1, y2, y3 })
  fillPolygon(xs, ys)
  strokePath(xs, ys, true)
end

function API.quad(x1, y1, x2, y2, x3, y3, x4, y4)
  if C.dry then return end
  local xs, ys = tpList({ x1, x2, x3, x4 }, { y1, y2, y3, y4 })
  fillPolygon(xs, ys)
  strokePath(xs, ys, true)
end

----------------------------------------------------------------------
-- ベジェ / Catmull-Rom
----------------------------------------------------------------------
function API.bezierPoint(a, b, c, d, t)
  local u = 1 - t
  return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
end

function API.bezierTangent(a, b, c, d, t)
  local u = 1 - t
  return 3 * u * u * (b - a) + 6 * u * t * (c - b) + 3 * t * t * (d - c)
end

local function curveCoef(t)
  local s = (C and C.curveTightness) or 0
  -- Processing の curveTightness: s=0 で Catmull-Rom
  local k = (1 - s) / 2
  local t2, t3 = t * t, t * t * t
  return -k * t3 + 2 * k * t2 - k * t,
         (2 - k) * t3 + (k - 3) * t2 + 1,
         (k - 2) * t3 + (3 - 2 * k) * t2 + k * t,
         k * t3 - k * t2
end

function API.curvePoint(a, b, c, d, t)
  local c0, c1, c2, c3 = curveCoef(t)
  return c0 * a + c1 * b + c2 * c + c3 * d
end

function API.curveTightness(s) C.curveTightness = s end

local function bezierSegs(x1, y1, x2, y2, x3, y3, x4, y4)
  local s = mscale()
  local len = sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) + sqrt((x3 - x2) ^ 2 + (y3 - y2) ^ 2) +
              sqrt((x4 - x3) ^ 2 + (y4 - y3) ^ 2)
  return mmax(4, mmin(200, ceil(len * s / 4)))
end

function API.bezier(x1, y1, x2, y2, x3, y3, x4, y4)
  if C.dry then return end
  local n = bezierSegs(x1, y1, x2, y2, x3, y3, x4, y4)
  local lx, ly = {}, {}
  for i = 0, n do
    local t = i / n
    lx[#lx + 1] = API.bezierPoint(x1, x2, x3, x4, t)
    ly[#ly + 1] = API.bezierPoint(y1, y2, y3, y4, t)
  end
  local xs, ys = tpList(lx, ly)
  fillPolygon(xs, ys)
  strokePath(xs, ys, false)
end

function API.curve(x1, y1, x2, y2, x3, y3, x4, y4)
  if C.dry then return end
  local n = bezierSegs(x1, y1, x2, y2, x3, y3, x4, y4)
  local lx, ly = {}, {}
  for i = 0, n do
    local t = i / n
    lx[#lx + 1] = API.curvePoint(x1, x2, x3, x4, t)
    ly[#ly + 1] = API.curvePoint(y1, y2, y3, y4, t)
  end
  local xs, ys = tpList(lx, ly)
  fillPolygon(xs, ys)
  strokePath(xs, ys, false)
end

----------------------------------------------------------------------
-- beginShape / endShape
----------------------------------------------------------------------
function API.beginShape(kind)
  C.shape = { kind = kind, xs = {}, ys = {}, curve = {} }
end

local function shapeAdd(x, y)
  local s = C.shape
  if not s then return end
  local px, py = tp(x, y)
  s.xs[#s.xs + 1], s.ys[#s.ys + 1] = px, py
  s.lastx, s.lasty = x, y
end

function API.vertex(x, y)
  local s = C.shape
  if not s then return end
  s.curve = {}
  shapeAdd(x, y)
end

function API.bezierVertex(x2, y2, x3, y3, x4, y4)
  local s = C.shape
  if not s or not s.lastx then return end
  local x1, y1 = s.lastx, s.lasty
  local n = bezierSegs(x1, y1, x2, y2, x3, y3, x4, y4)
  for i = 1, n do
    local t = i / n
    shapeAdd(API.bezierPoint(x1, x2, x3, x4, t), API.bezierPoint(y1, y2, y3, y4, t))
  end
end

function API.quadraticVertex(cx, cy, x3, y3)
  local s = C.shape
  if not s or not s.lastx then return end
  local x1, y1 = s.lastx, s.lasty
  API.bezierVertex(x1 + 2 / 3 * (cx - x1), y1 + 2 / 3 * (cy - y1),
                   x3 + 2 / 3 * (cx - x3), y3 + 2 / 3 * (cy - y3), x3, y3)
end

function API.curveVertex(x, y)
  local s = C.shape
  if not s then return end
  local cv = s.curve
  cv[#cv + 1] = { x, y }
  local n = #cv
  if n >= 4 then
    local p0, p1, p2, p3 = cv[n - 3], cv[n - 2], cv[n - 1], cv[n]
    local segs = bezierSegs(p0[1], p0[2], p1[1], p1[2], p2[1], p2[2], p3[1], p3[2])
    local start = (n == 4) and 0 or 1
    for i = start, segs do
      local t = i / segs
      shapeAdd(API.curvePoint(p0[1], p1[1], p2[1], p3[1], t), API.curvePoint(p0[2], p1[2], p2[2], p3[2], t))
    end
  end
end

function API.endShape(mode)
  local s = C.shape
  C.shape = nil
  if not s or C.dry then return end
  local xs, ys, kind = s.xs, s.ys, s.kind
  local n = #xs
  local fc, sc = C.fill, C.stroke
  if kind == nil then
    if mode == "close" then
      fillPolygon(xs, ys)
      strokePath(xs, ys, true)
    else
      fillPolygon(xs, ys)
      strokePath(xs, ys, false)
    end
  elseif kind == "points" then
    local w = strokeWidth()
    if sc then
      for i = 1, n do
        if C.cap == "round" then screenDot(sc, xs[i], ys[i], w)
        else
          local h = w / 2
          solidQuad(sc, xs[i] - h, ys[i] - h, xs[i] + h, ys[i] - h, xs[i] + h, ys[i] + h, xs[i] - h, ys[i] + h)
        end
      end
    end
  elseif kind == "lines" then
    for i = 1, n - 1, 2 do strokePath({ xs[i], xs[i + 1] }, { ys[i], ys[i + 1] }, false) end
  else
    local tris = {}
    local function tri(a, b, c) tris[#tris + 1] = { a, b, c } end
    if kind == "triangles" then
      for i = 1, n - 2, 3 do tri(i, i + 1, i + 2) end
    elseif kind == "triangle_strip" then
      for i = 1, n - 2 do tri(i, i + 1, i + 2) end
    elseif kind == "triangle_fan" then
      for i = 2, n - 1 do tri(1, i, i + 1) end
    elseif kind == "quads" then
      for i = 1, n - 3, 4 do tri(i, i + 1, i + 2); tri(i, i + 2, i + 3); tris[#tris].quad = i end
    elseif kind == "quad_strip" then
      for i = 1, n - 3, 2 do tri(i, i + 1, i + 3); tri(i, i + 3, i + 2); tris[#tris].quad = i end
    end
    for _, t in ipairs(tris) do
      local a, b, c = t[1], t[2], t[3]
      if fc and fc.a > 0 then solidTri(fc, xs[a], ys[a], xs[b], ys[b], xs[c], ys[c]) end
    end
    if sc then
      if kind == "quads" then
        for i = 1, n - 3, 4 do
          strokePath({ xs[i], xs[i + 1], xs[i + 2], xs[i + 3] }, { ys[i], ys[i + 1], ys[i + 2], ys[i + 3] }, true)
        end
      elseif kind == "quad_strip" then
        for i = 1, n - 3, 2 do
          strokePath({ xs[i], xs[i + 1], xs[i + 3], xs[i + 2] }, { ys[i], ys[i + 1], ys[i + 3], ys[i + 2] }, true)
        end
      else
        for _, t in ipairs(tris) do
          local a, b, c = t[1], t[2], t[3]
          strokePath({ xs[a], xs[b], xs[c] }, { ys[a], ys[b], ys[c] }, true)
        end
      end
    end
  end
end

----------------------------------------------------------------------
-- モード系
----------------------------------------------------------------------
function API.rectMode(m) C.rectMode = m end
function API.ellipseMode(m) C.ellipseMode = m end
function API.imageMode(m) C.imageMode = m end
function API.blendMode(m) C.blend = m end
function API.smooth() obj.setoption("antialias", 1) end
function API.noSmooth() obj.setoption("antialias", 0) end

----------------------------------------------------------------------
-- 背景・キャンバス
----------------------------------------------------------------------
local function beginCanvas()
  obj.setoption("drawtarget", "tempbuffer", C.W, C.H)
  invalidateTex()
  R.blend = nil
end

function API.clear()
  if C.dry then return end
  beginCanvas()
end

function API.background(...)
  if C.dry then return end
  local col = toColor(...)
  beginCanvas()
  local saved = C.blend
  C.blend = "blend"
  local W, H = C.W, C.H
  solidQuad(col, -1, -1, W + 1, -1, W + 1, H + 1, -1, H + 1)
  C.blend = saved
end

function API.size(w, h)
  C.W, C.H = floor(w), floor(h)
  if C.env then
    rawset(C.env, "width", C.W)
    rawset(C.env, "height", C.H)
  end
  if not C.dry then beginCanvas() end
end

function API.frameRate() end
function API.noLoop() C.looping = false end
function API.loop() C.looping = true end
function API.millis() return floor((C.time or 0) * 1000) end

----------------------------------------------------------------------
-- 文字
----------------------------------------------------------------------
function API.textSize(s) C.textSize = s end
function API.textFont(f, s)
  if type(f) == "table" then
    C.textFont = f.name
    if f.size and not s then C.textSize = f.size end
  else
    C.textFont = f
  end
  if s then C.textSize = s end
end
function API.createFont(name, size) return { name = name, size = size } end
function API.textAlign(h, v) C.textAlignH = h; C.textAlignV = v or "baseline" end
function API.textLeading(l) C.textLeading = l end
function API.textAscent() return C.textSize * 0.8 end
function API.textDescent() return C.textSize * 0.2 end

function API.textWidth(s)
  obj.setfont(C.textFont, mmax(1, C.textSize))
  obj.load("text", jstr(s))
  invalidateTex()
  return obj.w
end

function API.text(s, x, y, bw, bh)
  if C.dry then return end
  local col = C.fill
  if not col or col.a <= 0 then return end
  s = jstr(s)
  local sc = mscale()
  if sc <= 0 then return end
  obj.setfont(C.textFont, mmax(1, C.textSize * sc), 0, colInt(col))
  obj.load("text", s)
  invalidateTex()
  local tw, th = obj.w, obj.h
  if tw <= 0 or th <= 0 then return end
  local lw, lh = tw / sc, th / sc
  local ah, av = C.textAlignH, C.textAlignV
  local x0, y0
  if bw and bh then
    -- 箱指定: 箱の中で揃える
    if ah == "center" then x0 = x + (bw - lw) / 2 elseif ah == "right" then x0 = x + bw - lw else x0 = x end
    if av == "center" then y0 = y + (bh - lh) / 2 elseif av == "bottom" then y0 = y + bh - lh else y0 = y end
  else
    if ah == "center" then x0 = x - lw / 2 elseif ah == "right" then x0 = x - lw else x0 = x end
    if av == "top" then y0 = y
    elseif av == "center" then y0 = y - lh / 2
    elseif av == "bottom" then y0 = y - lh
    else y0 = y - C.textSize * 0.85 end
  end
  local ax, ay = tp(x0, y0)
  local bx, by = tp(x0 + lw, y0)
  local cx, cy = tp(x0 + lw, y0 + lh)
  local dx, dy = tp(x0, y0 + lh)
  poly(ax, ay, bx, by, cx, cy, dx, dy, 0, 0, tw, 0, tw, th, 0, th, col.a)
end

----------------------------------------------------------------------
-- 画像
----------------------------------------------------------------------
local function fileExists(p)
  local f = io.open(p, "rb")
  if f then f:close() return true end
  return false
end

local function resolvePath(p)
  if p:match("^%a:[\\/]") or p:match("^[\\/]") then return p end
  local dir = C.sketchDir or ""
  -- Processing と同じく、スケッチの data フォルダも探す
  if not fileExists(dir .. p) and fileExists(dir .. "data\\" .. p) then return dir .. "data\\" .. p end
  return dir .. p
end

function API.loadImage(path)
  local full = resolvePath(path)
  obj.load("image", full)
  invalidateTex()
  return { path = full, width = obj.w, height = obj.h }
end

function API.image(img, a, b, c, d)
  if C.dry or not img then return end
  obj.load("image", img.path)
  invalidateTex()
  local tw, th = obj.w, obj.h
  if tw <= 0 then return end
  local x, y, w, h
  local mode = C.imageMode
  c, d = c or tw, d or th
  if mode == "center" then x, y, w, h = a - c / 2, b - d / 2, c, d
  elseif mode == "corners" then x, y, w, h = a, b, c - a, d - b
  else x, y, w, h = a, b, c, d end
  local alpha = C.tint and C.tint.a or 1
  local ax, ay = tp(x, y)
  local bx, by = tp(x + w, y)
  local cx, cy = tp(x + w, y + h)
  local dx, dy = tp(x, y + h)
  poly(ax, ay, bx, by, cx, cy, dx, dy, 0, 0, tw, 0, tw, th, 0, th, alpha)
end

----------------------------------------------------------------------
-- ピクセル操作（遅い。小さいキャンバス向け）
----------------------------------------------------------------------
local function packRGBA(r, g, b, a) return ((a * 256 + r) * 256 + g) * 256 + b end
local function unpackRGBA(v)
  local b = v % 256; v = (v - b) / 256
  local g = v % 256; v = (v - g) / 256
  local r = v % 256; v = (v - r) / 256
  return r, g, b, v % 256
end

function API.loadPixels()
  if C.dry then return end
  obj.copybuffer("obj", "tmp")
  invalidateTex()
  local W, H = C.W, C.H
  local px = {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local r, g, b, a = obj.getpixel(x, y, "rgb")
      px[y * W + x + 1] = packRGBA(r, g, b, a)
    end
  end
  C.env.pixels = px
end

function API.updatePixels()
  if C.dry then return end
  local px = C.env.pixels
  if not px then return end
  obj.copybuffer("obj", "tmp")
  invalidateTex()
  obj.pixeloption("type", "rgb")
  local W, H = C.W, C.H
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local r, g, b, a = unpackRGBA(px[y * W + x + 1] or 0)
      obj.putpixel(x, y, r, g, b, a)
    end
  end
  obj.copybuffer("tmp", "obj")
end

-- pixels[] の数値 <-> color
function API.pixelColor(v)
  local r, g, b, a = unpackRGBA(v)
  return mkcolor(r / 255, g / 255, b / 255, a / 255)
end
function API.colorPixel(c)
  return packRGBA(floor(c.r * 255 + 0.5), floor(c.g * 255 + 0.5), floor(c.b * 255 + 0.5), floor(c.a * 255 + 0.5))
end

function API.get(x, y)
  if C.dry then return mkcolor(0, 0, 0, 0) end
  obj.copybuffer("obj", "tmp")
  invalidateTex()
  local r, g, b, a = obj.getpixel(floor(x), floor(y), "rgb")
  return mkcolor(r / 255, g / 255, b / 255, a / 255)
end

function API.set(x, y, c)
  if C.dry then return end
  local col = toColor(c)
  local px, py = floor(x), floor(y)
  local hw, hh = C.W * 0.5, C.H * 0.5
  local t = useFillTex(col, 1)
  local ua, ub = t.w * 0.4, t.w * 0.6
  -- 行列を無視して1ピクセル塗る
  if col.a > 0 then
    applyBlend()
    obj.drawpoly(px - hw, py - hh, 0, px + 1 - hw, py - hh, 0, px + 1 - hw, py + 1 - hh, 0, px - hw, py + 1 - hh, 0,
      ua, ua, ub, ua, ub, ub, ua, ub, col.a)
  end
end

function API.filter(kind, param)
  if C.dry then return end
  if kind == "blur" then
    obj.copybuffer("obj", "tmp")
    invalidateTex()
    obj.effect("ぼかし", "範囲", param or 1, "サイズ固定", 1)
    beginCanvas()
    obj.draw()
    return
  end
  API.loadPixels()
  local px = C.env.pixels
  for i = 1, #px do
    local r, g, b, a = unpackRGBA(px[i])
    if kind == "invert" then
      r, g, b = 255 - r, 255 - g, 255 - b
    elseif kind == "gray" then
      local v = floor(0.299 * r + 0.587 * g + 0.114 * b + 0.5)
      r, g, b = v, v, v
    elseif kind == "threshold" then
      local v = (0.299 * r + 0.587 * g + 0.114 * b) / 255 >= (param or 0.5) and 255 or 0
      r, g, b = v, v, v
    elseif kind == "posterize" then
      local lv = mmax(2, param or 4) - 1
      r = floor(floor(r / 255 * lv + 0.5) * 255 / lv)
      g = floor(floor(g / 255 * lv + 0.5) * 255 / lv)
      b = floor(floor(b / 255 * lv + 0.5) * 255 / lv)
    end
    px[i] = packRGBA(r, g, b, a)
  end
  API.updatePixels()
end

----------------------------------------------------------------------
-- 乱数・ノイズ（シード固定で毎回同じ結果になる）
----------------------------------------------------------------------
local function nextRand()
  C.seed = (C.seed * 16807) % 2147483647
  return (C.seed - 1) / 2147483646
end

local function seedValue(s)
  return (floor(abs(s or 0)) % 2147483646) + 1
end

function API.randomSeed(s) C.seed = seedValue(s) end

function API.random(a, b)
  if type(a) == "table" then
    return a[floor(nextRand() * #a) + 1]
  end
  local r = nextRand()
  if a == nil then return r end
  if b == nil then return r * a end
  return a + r * (b - a)
end

function API.randomGaussian()
  local u1 = mmax(nextRand(), 1e-12)
  local u2 = nextRand()
  return sqrt(-2 * math.log(u1)) * cos(2 * pi * u2)
end

local GRAD = { { 1, 1, 0 }, { -1, 1, 0 }, { 1, -1, 0 }, { -1, -1, 0 }, { 1, 0, 1 }, { -1, 0, 1 },
  { 1, 0, -1 }, { -1, 0, -1 }, { 0, 1, 1 }, { 0, -1, 1 }, { 0, 1, -1 }, { 0, -1, -1 } }

local function makePerm(seed)
  local s = seedValue(seed)
  local p = {}
  for i = 0, 255 do p[i] = i end
  for i = 255, 1, -1 do
    s = (s * 16807) % 2147483647
    local j = s % (i + 1)
    p[i], p[j] = p[j], p[i]
  end
  local perm = {}
  for i = 0, 511 do perm[i] = p[i % 256] end
  return perm
end

function API.noiseSeed(s) C.perm = makePerm(s) end
function API.noiseDetail(oct, fall) C.noiseOct = oct or 4; C.noiseFall = fall or 0.5 end

local function fade(t) return t * t * t * (t * (t * 6 - 15) + 10) end

local function perlin(perm, x, y, z)
  local X, Y, Z = floor(x), floor(y), floor(z)
  x, y, z = x - X, y - Y, z - Z
  X, Y, Z = X % 256, Y % 256, Z % 256
  local u, v, w = fade(x), fade(y), fade(z)
  local A = perm[X] + Y
  local AA, AB = perm[A] + Z, perm[A + 1] + Z
  local B = perm[X + 1] + Y
  local BA, BB = perm[B] + Z, perm[B + 1] + Z
  local function g(h, gx, gy, gz)
    local gr = GRAD[h % 12 + 1]
    return gr[1] * gx + gr[2] * gy + gr[3] * gz
  end
  local function lerp(t, a, b) return a + t * (b - a) end
  return lerp(w,
    lerp(v, lerp(u, g(perm[AA], x, y, z), g(perm[BA], x - 1, y, z)),
            lerp(u, g(perm[AB], x, y - 1, z), g(perm[BB], x - 1, y - 1, z))),
    lerp(v, lerp(u, g(perm[AA + 1], x, y, z - 1), g(perm[BA + 1], x - 1, y, z - 1)),
            lerp(u, g(perm[AB + 1], x, y - 1, z - 1), g(perm[BB + 1], x - 1, y - 1, z - 1))))
end

function API.noise(x, y, z)
  y, z = y or 0, z or 0
  local perm = C.perm
  local total, amp, freq = 0, 0.5, 1
  for _ = 1, C.noiseOct do
    total = total + amp * (perlin(perm, x * freq, y * freq, z * freq) * 0.5 + 0.5)
    amp = amp * C.noiseFall
    freq = freq * 2
  end
  return total
end

----------------------------------------------------------------------
-- 数学
----------------------------------------------------------------------
function API.map(v, a1, b1, a2, b2) return a2 + (b2 - a2) * ((v - a1) / (b1 - a1)) end
function API.lerp(a, b, t) return a + (b - a) * t end
function API.norm(v, a, b) return (v - a) / (b - a) end
function API.constrain(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end
function API.dist(x1, y1, x2, y2, x3, y3)
  if x3 then return sqrt((y2 - x1) ^ 2 + (x3 - y1) ^ 2 + (y3 - x2) ^ 2) end
  return sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end
function API.mag(x, y, z) return sqrt(x * x + y * y + (z or 0) ^ 2) end
function API.sq(v) return v * v end
function API.radians(d) return d * pi / 180 end
function API.degrees(r) return r * 180 / pi end
function API.round(v) return floor(v + 0.5) end
function API.int(v) if v >= 0 then return floor(v) end return ceil(v) end
API.sqrt, API.abs, API.floor, API.ceil = sqrt, abs, floor, ceil
API.sin, API.cos, API.tan, API.asin, API.acos = sin, cos, math.tan, math.asin, math.acos
API.atan, API.atan2, API.exp, API.log, API.pow = math.atan, atan2, math.exp, math.log, math.pow or function(a, b) return a ^ b end
-- min/max は配列も受け付ける
local function arrayValues(t)
  local vals = {}
  if t.a and t.n then for i = 1, t.n do vals[i] = t.a[i] end
  elseif t.length then for i = 0, t.length - 1 do vals[#vals + 1] = t[i] end
  else for i = 1, #t do vals[i] = t[i] end end
  return vals
end
function API.min(a, ...)
  if type(a) == "table" then return mmin(unpack(arrayValues(a))) end
  return mmin(a, ...)
end
function API.max(a, ...)
  if type(a) == "table" then return mmax(unpack(arrayValues(a))) end
  return mmax(a, ...)
end

function API.nf(v, left, right)
  local s
  if right then s = string.format("%." .. right .. "f", v) else s = tostring(floor(v)) end
  if left then
    local neg = s:sub(1, 1) == "-"
    if neg then s = s:sub(2) end
    local ip = s:match("^(%d+)") or ""
    if #ip < left then s = string.rep("0", left - #ip) .. s end
    if neg then s = "-" .. s end
  end
  return s
end
API.str = jstr

----------------------------------------------------------------------
-- PVector
----------------------------------------------------------------------
local PVector = {}
PVector.__index = PVector

local function vec(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, PVector) end

setmetatable(PVector, { __call = function(_, x, y, z) return vec(x, y, z) end })
PVector.__add = function(a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end
PVector.__sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end
PVector.__mul = function(a, b)
  if type(a) == "number" then return vec(b.x * a, b.y * a, b.z * a) end
  return vec(a.x * b, a.y * b, a.z * b)
end
PVector.__div = function(a, b) return vec(a.x / b, a.y / b, a.z / b) end
PVector.__unm = function(a) return vec(-a.x, -a.y, -a.z) end
PVector.__tostring = function(a) return string.format("[ %g, %g, %g ]", a.x, a.y, a.z) end

function PVector:set(x, y, z)
  if type(x) == "table" then self.x, self.y, self.z = x.x, x.y, x.z
  else self.x, self.y, self.z = x or 0, y or 0, z or 0 end
  return self
end
function PVector:copy() return vec(self.x, self.y, self.z) end
function PVector:add(x, y, z)
  if type(x) == "table" then x, y, z = x.x, x.y, x.z end
  self.x, self.y, self.z = self.x + x, self.y + (y or 0), self.z + (z or 0)
  return self
end
function PVector:sub(x, y, z)
  if type(x) == "table" then x, y, z = x.x, x.y, x.z end
  self.x, self.y, self.z = self.x - x, self.y - (y or 0), self.z - (z or 0)
  return self
end
function PVector:mult(s) self.x, self.y, self.z = self.x * s, self.y * s, self.z * s; return self end
function PVector:div(s) self.x, self.y, self.z = self.x / s, self.y / s, self.z / s; return self end
function PVector:magSq() return self.x * self.x + self.y * self.y + self.z * self.z end
function PVector:mag() return sqrt(self:magSq()) end
function PVector:normalize()
  local m = self:mag()
  if m > 0 then self:div(m) end
  return self
end
function PVector:setMag(l) return self:normalize():mult(l) end
function PVector:limit(l)
  if self:magSq() > l * l then self:setMag(l) end
  return self
end
function PVector:heading() return atan2(self.y, self.x) end
function PVector:rotate(t)
  local c, s = cos(t), sin(t)
  self.x, self.y = self.x * c - self.y * s, self.x * s + self.y * c
  return self
end
function PVector:dot(v) return self.x * v.x + self.y * v.y + self.z * v.z end
function PVector:cross(v)
  return vec(self.y * v.z - self.z * v.y, self.z * v.x - self.x * v.z, self.x * v.y - self.y * v.x)
end
function PVector:dist(v) return (self - v):mag() end
function PVector:lerp(v, t)
  self.x = self.x + (v.x - self.x) * t
  self.y = self.y + (v.y - self.y) * t
  self.z = self.z + (v.z - self.z) * t
  return self
end
function PVector.angleBetween(a, b)
  local d = a:mag() * b:mag()
  if d == 0 then return 0 end
  return math.acos(API.constrain(a:dot(b) / d, -1, 1))
end
function PVector.fromAngle(t, len) len = len or 1; return vec(cos(t) * len, sin(t) * len) end
function PVector.random2D() return PVector.fromAngle(nextRand() * pi * 2) end
function PVector.random3D()
  -- 球面上に一様に分布する長さ1のベクトル
  local a = nextRand() * pi * 2
  local z = nextRand() * 2 - 1
  local r = sqrt(1 - z * z)
  return vec(cos(a) * r, sin(a) * r, z)
end

API.PVector = PVector
function API.createVector(x, y, z) return vec(x, y, z) end

----------------------------------------------------------------------
-- Processing(.pde) を変換したコード用の実行時関数
----------------------------------------------------------------------
local TWO32 = 4294967296

API.println = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = jstr((select(i, ...))) end
  local s = table.concat(parts, " ")
  if debug_print then pcall(debug_print, s) end
end
API.print = API.println
function API.exit() end
function API.fullScreen() end
function API.pixelDensity() end
function API.cursor() end
function API.noCursor() end
function API.second() return tonumber(os.date("%S")) end
function API.minute() return tonumber(os.date("%M")) end
function API.hour() return tonumber(os.date("%H")) end
function API.day() return tonumber(os.date("%d")) end
function API.month() return tonumber(os.date("%m")) end
function API.year() return tonumber(os.date("%Y")) end

function API.__cat(a, b) return jstr(a) .. jstr(b) end
function API.__add(a, b)
  if type(a) == "string" or type(b) == "string" then return jstr(a) .. jstr(b) end
  return a + b
end
function API.__idiv(a, b)
  local q = a / b
  if q >= 0 then return floor(q) end
  return ceil(q)
end
function API.__mod(a, b) return math.fmod(a, b) end
function API.__int(x)
  local t = type(x)
  if t == "number" then
    if x >= 0 then return floor(x) end
    return ceil(x)
  elseif t == "string" then
    local n = tonumber(x)
    if n then return API.__int(n) end
    if #x == 1 then return x:byte() end
    return 0
  elseif t == "boolean" then return x and 1 or 0
  elseif t == "table" and x.r then return API.colorPixel(x) end
  return 0
end
function API.__float(x)
  local t = type(x)
  if t == "number" then return x
  elseif t == "string" then return tonumber(x) or (#x == 1 and x:byte()) or 0
  elseif t == "boolean" then return x and 1 or 0 end
  return 0
end
function API.__bool(x)
  if type(x) == "number" then return x ~= 0 end
  if type(x) == "string" then return x == "true" end
  return not not x
end
function API.__char(x)
  if type(x) == "number" then return string.char(floor(x) % 256) end
  return x
end
function API.__cond(c, fa, fb)
  if c then return fa() end
  return fb()
end

-- ビット演算（32bit 符号なしとして扱う）
local function u32(x)
  if type(x) == "table" then x = API.colorPixel(x) end
  return floor(x) % TWO32
end
local function bitop(a, b, f)
  a, b = u32(a), u32(b)
  local r, bit = 0, 1
  for _ = 1, 32 do
    local x, y = a % 2, b % 2
    if f(x, y) then r = r + bit end
    a, b = (a - x) / 2, (b - y) / 2
    bit = bit * 2
  end
  return r
end
-- 結果は Java の int と同じく符号つき 32bit にする
local function s32(x)
  if x >= 2147483648 then return x - TWO32 end
  return x
end
function API.__band(a, b) return s32(bitop(a, b, function(x, y) return x == 1 and y == 1 end)) end
function API.__bor(a, b) return s32(bitop(a, b, function(x, y) return x == 1 or y == 1 end)) end
function API.__bxor(a, b) return s32(bitop(a, b, function(x, y) return x ~= y end)) end
function API.__bnot(a) return s32(TWO32 - 1 - u32(a)) end
function API.__shl(a, n) return s32((u32(a) * 2 ^ (n % 32)) % TWO32) end
function API.__sar(a, n) return floor(s32(u32(a)) / 2 ^ (n % 32)) end   -- >>
function API.__shr(a, n) return floor(u32(a) / 2 ^ (n % 32)) end         -- >>>

-- 配列（添字 0 から。length を持つ）
function API.__newArray(default, n, ...)
  n = floor(n)
  local t = { length = n }
  if select("#", ...) > 0 then
    for i = 0, n - 1 do t[i] = API.__newArray(default, ...) end
  elseif default ~= nil then
    for i = 0, n - 1 do t[i] = default end
  end
  return t
end
function API.__arr(n, ...)
  local t = { length = n }
  for i = 1, n do t[i - 1] = (select(i, ...)) end
  return t
end

local List = {}
List.__index = List
List.__list = true

function API.__each(x)
  if x == nil then error("null を for 文で回そうとしました", 2) end
  local i = -1
  if x.__sub then
    return function()
      i = i + 1
      if i < x.to - x.from then return i, x.parent.a[x.from + i + 1] end
    end
  end
  if x.__list then
    return function()
      i = i + 1
      if i < x.n then return i, x.a[i + 1] end
    end
  end
  local n = x.length or #x
  return function()
    i = i + 1
    if i < n then return i, x[i] end
  end
end

local function arrFromValues(vals, n)
  local t = { length = n }
  for i = 1, n do t[i - 1] = vals[i] end
  return t
end
local function arrValues(t)
  local vals = {}
  for i = 0, (t.length or 0) - 1 do vals[i + 1] = t[i] end
  return vals, t.length or 0
end

function API.append(arr, v)
  local vals, n = arrValues(arr)
  vals[n + 1] = v
  return arrFromValues(vals, n + 1)
end
function API.shorten(arr)
  local vals, n = arrValues(arr)
  return arrFromValues(vals, mmax(0, n - 1))
end
function API.expand(arr, size)
  local vals, n = arrValues(arr)
  return arrFromValues(vals, size or n * 2)
end
function API.concat(a, b)
  local va, na = arrValues(a)
  local vb, nb = arrValues(b)
  for i = 1, nb do va[na + i] = vb[i] end
  return arrFromValues(va, na + nb)
end
function API.subset(arr, start, count)
  local vals, n = arrValues(arr)
  count = count or (n - start)
  local out = {}
  for i = 1, count do out[i] = vals[start + i] end
  return arrFromValues(out, count)
end
function API.reverse(arr)
  local vals, n = arrValues(arr)
  local out = {}
  for i = 1, n do out[i] = vals[n - i + 1] end
  return arrFromValues(out, n)
end
function API.sort(arr, count)
  local vals, n = arrValues(arr)
  count = count or n
  local head = {}
  for i = 1, count do head[i] = vals[i] end
  table.sort(head)
  for i = 1, count do vals[i] = head[i] end
  return arrFromValues(vals, n)
end
function API.arrayCopy(src, a, b, c, d)
  if d == nil then
    -- arrayCopy(src, dst[, length])
    local dst, len = a, b or src.length
    for i = 0, len - 1 do dst[i] = src[i] end
  else
    -- arrayCopy(src, srcPos, dst, dstPos, length)
    for i = 0, d - 1 do b[c + i] = src[a + i] end
  end
end
API.arraycopy = API.arrayCopy

-- 文字列
local function plainPattern(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
local S = {}
API.__S = S
function S.length(s) return #s end
function S.charAt(s, i) return s:sub(i + 1, i + 1) end
function S.substring(s, a, b)
  if b then return s:sub(a + 1, b) end
  return s:sub(a + 1)
end
function S.indexOf(s, t, from)
  local i = s:find(t, (from or 0) + 1, true)
  return i and (i - 1) or -1
end
function S.lastIndexOf(s, t)
  local last = -1
  local i = s:find(t, 1, true)
  while i do last = i - 1; i = s:find(t, i + 1, true) end
  return last
end
function S.equals(s, t) return s == t end
function S.equalsIgnoreCase(s, t) return type(t) == "string" and s:lower() == t:lower() end
function S.toUpperCase(s) return s:upper() end
function S.toLowerCase(s) return s:lower() end
function S.trim(s) return (s:match("^%s*(.-)%s*$")) end
function S.startsWith(s, p) return s:sub(1, #p) == p end
function S.endsWith(s, p) return p == "" or s:sub(-#p) == p end
function S.contains(s, t) return s:find(t, 1, true) ~= nil end
function S.isEmpty(s) return #s == 0 end
function S.replace(s, a, b) return (s:gsub(plainPattern(a), (b:gsub("%%", "%%%%")))) end
function S.compareTo(s, t) if s < t then return -1 elseif s > t then return 1 end return 0 end
function S.toString(s) return s end
function S.split(s, d)
  local out = {}
  if d == "" then
    for i = 1, #s do out[i] = s:sub(i, i) end
  else
    local start = 1
    while true do
      local i, j = s:find(d, start, true)
      if not i then out[#out + 1] = s:sub(start); break end
      out[#out + 1] = s:sub(start, i - 1)
      start = j + 1
    end
  end
  return arrFromValues(out, #out)
end
function API.split(s, d) return S.split(s, d) end
function API.splitTokens(s, delims)
  delims = delims or " \t\n\r\f"
  local out = {}
  for w in s:gmatch("[^" .. plainPattern(delims) .. "]+") do out[#out + 1] = w end
  return arrFromValues(out, #out)
end
function API.join(arr, sep)
  local vals, n = arrValues(arr)
  for i = 1, n do vals[i] = jstr(vals[i]) end
  return table.concat(vals, sep or "")
end
function API.trim(s) return S.trim(s) end
function API.nfs(v, l, r) local s = API.nf(v, l, r); if v >= 0 then s = " " .. s end return s end
function API.nfp(v, l, r) local s = API.nf(v, l, r); if v >= 0 then s = "+" .. s end return s end
function API.nfc(v, r)
  local s = r and string.format("%." .. r .. "f", v) or tostring(floor(v))
  local ip, fp = s:match("^(%-?%d+)(.*)$")
  ip = ip:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^(%-?),", "%1")
  return ip .. fp
end
function API.hex(v, digits)
  local s = string.format("%08X", u32(v))
  if digits then s = s:sub(-digits) end
  return s
end

-- 型が分からない値の関数呼び出し（文字列なら __S を使う）
function API.__mc(o, name, ...)
  if type(o) == "string" then return S[name](o, ...) end
  return o[name](o, ...)
end

-- ArrayList（添字 0 から）
function List.new(x)
  local l = setmetatable({ a = {}, n = 0 }, List)
  if type(x) == "table" and x.__list then
    for i = 1, x.n do l.a[i] = x.a[i] end
    l.n = x.n
  end
  return l
end
local function checkIndex(l, i)
  if i < 0 or i >= l.n then error("リストの範囲外です: " .. jstr(i) .. "（要素数 " .. l.n .. "）", 3) end
end
function List:add(...)
  if select("#", ...) >= 2 then
    local i, v = ...
    table.insert(self.a, i + 1, v)
  else
    self.a[self.n + 1] = (...)
  end
  self.n = self.n + 1
  return true
end
List.append = function(self, v) self.a[self.n + 1] = v; self.n = self.n + 1 end
function List:get(i) checkIndex(self, i); return self.a[i + 1] end
function List:set(i, v) checkIndex(self, i); local old = self.a[i + 1]; self.a[i + 1] = v; return old end
function List:size() return self.n end
function List:isEmpty() return self.n == 0 end
function List:clear() self.a = {}; self.n = 0 end
function List:indexOf(v)
  for i = 1, self.n do if self.a[i] == v then return i - 1 end end
  return -1
end
function List:contains(v) return self:indexOf(v) >= 0 end
List.hasValue = List.contains
function List:remove(x)
  if type(x) == "number" and not self.__valueRemove then
    checkIndex(self, x)
    local v = table.remove(self.a, x + 1)
    self.n = self.n - 1
    return v
  end
  local i = self:indexOf(x)
  if i < 0 then return false end
  table.remove(self.a, i + 1)
  self.n = self.n - 1
  return true
end
function List:toArray() return arrFromValues(self.a, self.n) end

-- subList(from, to): 元のリストの一部を指す。clear() で元のリストから消える
local SubList = {}
SubList.__index = SubList
SubList.__sub = true
function List:subList(from, to)
  if from < 0 or to > self.n or from > to then
    error("subList の範囲が正しくありません: " .. jstr(from) .. ", " .. jstr(to), 2)
  end
  return setmetatable({ parent = self, from = from, to = to }, SubList)
end
function SubList:size() return self.to - self.from end
function SubList:isEmpty() return self.to == self.from end
function SubList:get(i) return self.parent:get(self.from + i) end
function SubList:set(i, v) return self.parent:set(self.from + i, v) end
function SubList:clear()
  local p, cnt = self.parent, self.to - self.from
  for _ = 1, cnt do table.remove(p.a, self.from + 1) end
  p.n = p.n - cnt
  self.to = self.from
end
function SubList:toArray()
  local vals = {}
  for i = self.from + 1, self.to do vals[#vals + 1] = self.parent.a[i] end
  return arrFromValues(vals, #vals)
end
List.array = List.toArray
function List:sort() table.sort(self.a) end
function List:sortReverse() table.sort(self.a, function(p, q) return p > q end) end
function List:reverse()
  local out = {}
  for i = 1, self.n do out[i] = self.a[self.n - i + 1] end
  self.a = out
end
function List:shuffle()
  for i = self.n, 2, -1 do
    local j = floor(API.random(i)) + 1
    self.a[i], self.a[j] = self.a[j], self.a[i]
  end
end
function List:sum() local s = 0; for i = 1, self.n do s = s + self.a[i] end return s end
function List:max() return mmax(unpack(self.a, 1, self.n)) end
function List:min() return mmin(unpack(self.a, 1, self.n)) end
List.__tostring = function(l)
  local parts = {}
  for i = 1, l.n do parts[i] = jstr(l.a[i]) end
  return "[" .. table.concat(parts, ", ") .. "]"
end
API.ArrayList = List

-- IntList / FloatList の add(index, amount) は値に足す
local NumList = setmetatable({}, { __index = List })
NumList.__index = NumList
NumList.__list = true
NumList.__tostring = List.__tostring
function NumList.new(arr)
  local l = setmetatable({ a = {}, n = 0 }, NumList)
  if type(arr) == "table" and arr.length then
    for i = 0, arr.length - 1 do l.a[i + 1] = arr[i] end
    l.n = arr.length
  end
  return l
end
function NumList:add(i, amount) checkIndex(self, i); self.a[i + 1] = self.a[i + 1] + amount end
function NumList:sub(i, amount) checkIndex(self, i); self.a[i + 1] = self.a[i + 1] - amount end
function NumList:mult(i, amount) checkIndex(self, i); self.a[i + 1] = self.a[i + 1] * amount end
function NumList:increment(i) self:add(i, 1) end
API.IntList, API.FloatList = NumList, NumList
local StrList = setmetatable({}, { __index = List })
StrList.__index = StrList
StrList.__list = true
StrList.__tostring = List.__tostring
function StrList.new() return setmetatable({ a = {}, n = 0 }, StrList) end
API.StringList = StrList

-- HashMap
local Map = {}
Map.__index = Map
local Entry = {}
Entry.__index = Entry
function Entry:getKey() return self.key end
function Entry:getValue() return self.value end
function Entry:setValue(v) self.map.m[self.key] = v; self.value = v end
function Map.new() return setmetatable({ m = {}, has = {}, keys = {} }, Map) end
function Map:put(k, v)
  if not self.has[k] then self.has[k] = true; self.keys[#self.keys + 1] = k end
  local old = self.m[k]
  self.m[k] = v
  return old
end
function Map:get(k) return self.m[k] end
function Map:getOrDefault(k, d) if self.has[k] then return self.m[k] end return d end
function Map:containsKey(k) return self.has[k] == true end
function Map:containsValue(v) for _, k in ipairs(self.keys) do if self.m[k] == v then return true end end return false end
function Map:size() return #self.keys end
function Map:isEmpty() return #self.keys == 0 end
function Map:clear() self.m, self.has, self.keys = {}, {}, {} end
function Map:remove(k)
  if not self.has[k] then return nil end
  local v = self.m[k]
  self.m[k], self.has[k] = nil, nil
  for i, x in ipairs(self.keys) do if x == k then table.remove(self.keys, i); break end end
  return v
end
local function listOf(vals)
  local l = List.new()
  for i, v in ipairs(vals) do l.a[i] = v end
  l.n = #vals
  return l
end
function Map:keySet() local ks = {}; for i, k in ipairs(self.keys) do ks[i] = k end return listOf(ks) end
function Map:values() local vs = {}; for i, k in ipairs(self.keys) do vs[i] = self.m[k] end return listOf(vs) end
function Map:entrySet()
  local es = {}
  for i, k in ipairs(self.keys) do es[i] = setmetatable({ key = k, value = self.m[k], map = self }, Entry) end
  return listOf(es)
end
API.HashMap = Map

-- クラス
function API.__class(name, parent)
  local cls = {}
  cls.__index = cls
  cls.__name = name
  cls.__parent = parent
  cls.__tostring = function(o)
    local f = o.toString
    if f then return f(o) end
    return name
  end
  setmetatable(cls, { __index = parent })
  cls.new = function(...)
    local o = setmetatable({}, cls)
    cls.__init(o, ...)
    return o
  end
  return cls
end
function API.__instanceof(o, cls)
  if type(o) ~= "table" or cls == nil then return false end
  local mt = getmetatable(o)
  while mt do
    if mt == cls then return true end
    mt = rawget(mt, "__parent")
  end
  return false
end

-- PVector の static 版（新しいベクトルを返す）
local PVs = setmetatable({}, { __index = PVector })
function PVs.add(a, b) return a + b end
function PVs.sub(a, b) return a - b end
function PVs.mult(a, s) return a * s end
function PVs.div(a, s) return a / s end
function PVs.lerp(a, b, t) return a:copy():lerp(b, t) end
function PVs.dist(a, b) return a:dist(b) end
function PVs.dot(a, b) return a:dot(b) end
function PVs.cross(a, b) return a:cross(b) end
API.__PV = PVs
PVector.get = PVector.copy
function PVector:array() return API.__arr(3, self.x, self.y, self.z) end

-- Math / Integer / Float
API.Math_Math = {
  abs = abs, sqrt = sqrt, floor = floor, ceil = ceil, round = function(v) return floor(v + 0.5) end,
  max = mmax, min = mmin, pow = function(a, b) return a ^ b end, sin = sin, cos = cos, tan = math.tan,
  asin = math.asin, acos = math.acos, atan = math.atan, atan2 = atan2, exp = math.exp, log = math.log,
  log10 = math.log10, random = function() return API.random() end, PI = pi, E = math.exp(1),
  signum = function(v) return (v > 0 and 1) or (v < 0 and -1) or 0 end,
  hypot = function(a, b) return sqrt(a * a + b * b) end,
  toRadians = function(d) return d * pi / 180 end, toDegrees = function(r) return r * 180 / pi end,
}
API.Math_Integer = { MAX_VALUE = 2147483647, MIN_VALUE = -2147483648,
  parseInt = function(s) return API.__int(tonumber(s) or 0) end, toString = jstr, valueOf = function(v) return API.__int(v) end }
API.Math_Float = { MAX_VALUE = 3.4028235e38, MIN_VALUE = 1.4e-45, POSITIVE_INFINITY = math.huge,
  NEGATIVE_INFINITY = -math.huge, parseFloat = function(s) return tonumber(s) or 0 end, toString = jstr,
  valueOf = function(v) return tonumber(v) end, isNaN = function(v) return v ~= v end }
API.Math_String = { valueOf = jstr }
API.Math_Character = {
  isDigit = function(c) return c:match("^%d$") ~= nil end,
  isLetter = function(c) return c:match("^%a$") ~= nil end,
  isWhitespace = function(c) return c:match("^%s$") ~= nil end,
  toUpperCase = function(c) return c:upper() end, toLowerCase = function(c) return c:lower() end,
}
API.Math_PConstants = API
function API.__newPImage() error("new PImage は未対応です。loadImage を使ってください", 2) end

----------------------------------------------------------------------
-- 実行管理
----------------------------------------------------------------------
local states = {}
local pdeCache = {}

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function newContext(opt)
  local ctx = {
    W = floor(opt.width or 640), H = floor(opt.height or 360),
    m = { 1, 0, 0, 1, 0, 0 }, mstack = {}, sstack = {}, pstack = {},
    fill = mkcolor(1, 1, 1, 1), stroke = mkcolor(0, 0, 0, 1), sw = 1,
    cap = "round", join = "miter",
    rectMode = "corner", ellipseMode = "center", imageMode = "corner",
    colorMode = { mode = "rgb", m1 = 255, m2 = 255, m3 = 255, ma = 255 },
    textSize = 24, textFont = "MS UI Gothic", textAlignH = "left", textAlignV = "baseline",
    blend = "blend", tint = nil, curveTightness = 0,
    seed = seedValue(opt.seed), noiseOct = 4, noiseFall = 0.5,
    looping = true, dry = false, sketchDir = opt.sketchDir,
  }
  ctx.perm = makePerm((opt.seed or 0) + 7919)
  return ctx
end

local envMeta = {
  __index = function(_, k)
    local v = API[k]
    if v ~= nil then return v end
    return _G[k]
  end,
}

local sketchCall

-- エラーメッセージをスケッチの行番号つきに直す
local function formatError(st, msg, line)
  msg = tostring(msg):gsub("^[^\n]-:%d+: ", "")
  if line and st.lineMap then line = st.lineMap[line] or line end
  if line then return st.name .. " の " .. line .. " 行目: " .. msg end
  return st.name .. ": " .. msg
end

-- スケッチの関数を呼ぶ。エラーが起きたらスケッチのどの行かを調べる
sketchCall = function(st, fn)
  local chunkName = "=" .. st.name
  local ok, e = xpcall(fn, function(msg)
    if type(msg) == "table" then return msg end
    local line
    if debug and debug.getinfo then
      for lv = 2, 40 do
        local info = debug.getinfo(lv, "Sl")
        if not info then break end
        if info.source == chunkName and (info.currentline or 0) > 0 then
          line = info.currentline
          break
        end
      end
    end
    return { text = formatError(st, msg, line) }
  end)
  if not ok then error(type(e) == "table" and e.text or e, 0) end
end

local function setupState(src, opt)
  local ctx = newContext(opt)
  local env = setmetatable({}, envMeta)
  ctx.env = env
  local st = { ctx = ctx, env = env, src = src, sig = opt.sig, frame = -1,
               name = opt.name or "sketch", lineMap = opt.lineMap }
  local chunk, err = loadstring(src, "=" .. st.name)
  if not chunk then
    local line = tonumber(tostring(err):match(":(%d+):"))
    error(formatError(st, err, line), 0)
  end
  setfenv(chunk, env)
  C = ctx
  sketchCall(st, chunk)
  st.setup, st.draw = rawget(env, "setup"), rawget(env, "draw")
  return st
end

local function setVars(st, frame)
  local ctx, env = st.ctx, st.env
  ctx.time = frame / (obj.framerate or 30)
  rawset(env, "width", ctx.W)
  rawset(env, "height", ctx.H)
  rawset(env, "frameCount", frame + 1)
  rawset(env, "time", ctx.time)
  rawset(env, "fps", obj.framerate or 30)
  rawset(env, "mouseX", 0)
  rawset(env, "mouseY", 0)
  rawset(env, "pmouseX", 0)
  rawset(env, "pmouseY", 0)
  rawset(env, "mousePressed", false)
  rawset(env, "keyPressed", false)
  rawset(env, "key", "")
  rawset(env, "keyCode", 0)
end

local function callSetup(st, dry)
  local ctx = st.ctx
  ctx.dry = dry
  setVars(st, 0)
  rawset(st.env, "frameCount", 0)
  local settings = rawget(st.env, "settings")
  if settings then sketchCall(st, settings) end
  if st.setup then sketchCall(st, st.setup) end
end

local function callDraw(st, frame, dry)
  local ctx = st.ctx
  ctx.dry = dry
  ctx.m = { 1, 0, 0, 1, 0, 0 }
  ctx.mstack, ctx.pstack = {}, {}
  setVars(st, frame)
  sketchCall(st, st.draw)
end

local function showError(msg)
  obj.setoption("blend", 0)
  obj.setfont("MS UI Gothic", 22, 0, 0xff5050)
  obj.load("text", "Processing エラー:\n" .. tostring(msg))
end

local function finish()
  obj.setoption("blend", 0)
  R.blend = nil
  invalidateTex()
  obj.load("tempbuffer")
end

--[[
  P.run(opt)
    opt.sketch  : スケッチファイルの絶対パス
    opt.width, opt.height : キャンバスサイズ（size() で上書き可）
    opt.mode    : 0 = 毎フレーム独立（setupから毎回やり直す）
                  1 = 連続（変数の状態を引き継ぐ。シーク時は先頭から再計算）
    opt.accum   : true なら前フレームの絵の上に描き足す（background を毎回呼ばない作品用）
    opt.seed    : 乱数シード
    opt.offset  : 開始秒（この秒数ぶん先に進めた状態から始める）
    opt.key     : 状態を保存するキー
]]
function P.run(opt)
  local src = readFile(opt.sketch)
  if not src then
    showError("スケッチが見つかりません: " .. tostring(opt.sketch))
    return
  end
  -- Processing の .pde は Lua に変換してから実行する
  if opt.sketch:lower():match("%.pde$") then
    local cached = pdeCache[src]
    if not cached then
      local okReq, PDE = pcall(require, "processing_pde")
      if not okReq then
        showError("processing_pde.lua が読み込めません: " .. tostring(PDE))
        return
      end
      local code, lineMap = PDE.transpile(src, opt.sketch:match("([^\\/]+)$"))
      if not code then
        showError(lineMap)
        return
      end
      cached = { code = code, lineMap = lineMap }
      pdeCache = { [src] = cached }
    end
    src = cached.code
    opt.lineMap = cached.lineMap
  end
  opt.sketchDir = opt.sketchDir or opt.sketch:match("^(.*[\\/])") or ""
  opt.name = opt.name or opt.sketch:match("([^\\/]+)$")
  -- 開始秒: その時間だけ先に計算しておき、続きから出す
  local fps = obj.framerate or 30
  local offsetFrames = floor((opt.offset or 0) * fps + 0.5)
  opt.sig = table.concat({ opt.width, opt.height, opt.mode, tostring(opt.accum), opt.seed or 0, offsetFrames }, ",")
  local key = opt.key or opt.sketch
  local cacheName = "cache:processing_" .. tostring(key):gsub("[^%w]", "_")
  local frame = (obj.frame or 0) + offsetFrames

  local ok, err = pcall(function()
    local st = states[key]
    local fresh = (not st) or st.src ~= src or st.sig ~= opt.sig

    if not fresh and frame == st.frame then
      -- 同じフレームの再描画: 保存してある絵をそのまま出す
      C = st.ctx
      beginCanvas()
      obj.copybuffer("tmp", cacheName)
      return
    end

    if fresh then
      st = setupState(src, opt)
      states[key] = st
    end

    -- 毎フレーム独立モード、または draw() の無い静止画スケッチ
    if opt.mode == 0 or not st.draw then
      if not fresh then
        st = setupState(src, opt)
        states[key] = st
      end
      beginCanvas()
      callSetup(st, false)
      if st.draw then callDraw(st, frame, false) end
      st.frame = frame
      obj.copybuffer(cacheName, "tmp")
      return
    end

    if not fresh and frame == st.frame + 1 then
      -- 次のフレーム: 状態を引き継いで draw を1回だけ呼ぶ
      C = st.ctx
      beginCanvas()
      if st.ctx.looping then
        if opt.accum then obj.copybuffer("tmp", cacheName) end
        callDraw(st, frame, false)
      else
        obj.copybuffer("tmp", cacheName)
      end
      st.frame = frame
      obj.copybuffer(cacheName, "tmp")
      return
    end

    -- 初回 / シーク: 先頭から再計算
    if not fresh then
      st = setupState(src, opt)
      states[key] = st
    end
    local accum = opt.accum and true or false
    -- 累積しない場合、途中のフレームは描画せず状態だけ進める
    local last = frame
    beginCanvas()
    callSetup(st, not accum)
    for f = 0, frame do
      if f > 0 and not st.ctx.looping then last = f - 1; break end
      local dry = (not accum) and f < frame
      if not dry and not accum then beginCanvas() end
      callDraw(st, f, dry)
    end
    if not accum and last < frame then
      -- noLoop() で止まった: 止まったフレームの絵を出すために、そこまで再計算し直す
      st = setupState(src, opt)
      states[key] = st
      beginCanvas()
      callSetup(st, true)
      for f = 0, last do
        if f == last then beginCanvas() end
        callDraw(st, f, f < last)
      end
    end
    st.ctx.dry = false
    st.frame = frame
    obj.copybuffer(cacheName, "tmp")
  end)

  if not ok then
    states[key] = nil
    showError(err)
    return
  end
  finish()
end

P._states = states

-- テスト用: 現在のコンテキストを差し替える
function P._setContext(ctx) C = ctx end
P._newContext = newContext

return P
