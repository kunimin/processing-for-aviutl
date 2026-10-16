--[[
  processing_pde.lua  -  Processing (Java風) の .pde を Lua に変換する
  processing.lua から呼ばれる。対応範囲は README.md を参照。
  ※このファイルは Shift_JIS で保存すること
]]

local M = {}

local floor = math.floor
local concat = table.concat

----------------------------------------------------------------------
-- 字句解析
----------------------------------------------------------------------
local function isUTF8(s)
  local i, n = 1, #s
  local multi = false
  while i <= n do
    local c = s:byte(i)
    if c < 0x80 then
      i = i + 1
    else
      local len
      if c >= 0xC2 and c <= 0xDF then len = 2
      elseif c >= 0xE0 and c <= 0xEF then len = 3
      elseif c >= 0xF0 and c <= 0xF4 then len = 4
      else return false end
      for k = 1, len - 1 do
        local d = s:byte(i + k)
        if not d or d < 0x80 or d > 0xBF then return false end
      end
      multi = true
      i = i + len
    end
  end
  return true, multi
end

local function isSJISLead(c)
  return (c >= 0x81 and c <= 0x9F) or (c >= 0xE0 and c <= 0xFC)
end

-- UTF-8 の文字列を Shift_JIS に直す（拡張編集の文字は Shift_JIS のため）
local SJIS
local function utf8ToSjis(s)
  if not s:find("[\128-\255]") then return s end
  if SJIS == nil then
    local ok, t = pcall(require, "processing_sjis")
    SJIS = ok and t or false
  end
  if not SJIS then return s end
  local out, i, n = {}, 1, #s
  while i <= n do
    local c = s:byte(i)
    local cp, len
    if c < 0x80 then cp, len = c, 1
    elseif c < 0xE0 then cp, len = (c % 32) * 64 + (s:byte(i + 1) or 0) % 64, 2
    elseif c < 0xF0 then
      cp, len = ((c % 16) * 64 + (s:byte(i + 1) or 0) % 64) * 64 + (s:byte(i + 2) or 0) % 64, 3
    else cp, len = 0x3F, 4 end
    if cp < 0x80 then out[#out + 1] = string.char(cp)
    else out[#out + 1] = SJIS[cp] or "?" end
    i = i + len
  end
  return concat(out)
end

local OPS = {
  ">>>=", "<<=", ">>=", ">>>", "...", "++", "--", "&&", "||", "==", "!=", "<=", ">=",
  "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<", ">>", "->", "::",
}
local SINGLE = "+-*/%=<>!&|^~?:;,.(){}[]@"

local function perr(line, msg)
  error({ pde = true, line = line, msg = msg }, 0)
end

local ESC = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ["0"] = "\0",
  ['"'] = '"', ["'"] = "'", ["\\"] = "\\" }

local function tokenize(src)
  local sjis = not isUTF8(src)
  local toks = {}
  local i, n, line = 1, #src, 1
  local function push(t, v, extra)
    local tk = { t = t, v = v, line = line }
    if extra then for k, x in pairs(extra) do tk[k] = x end end
    toks[#toks + 1] = tk
  end
  while i <= n do
    local c = src:sub(i, i)
    local b = src:byte(i)
    if c == "\n" then
      line = line + 1
      i = i + 1
    elseif c == " " or c == "\t" or c == "\r" or c == "\f" or c == "\v" then
      i = i + 1
    elseif src:sub(i, i + 1) == "//" then
      local e = src:find("\n", i, true)
      i = e or (n + 1)
    elseif src:sub(i, i + 1) == "/*" then
      local e = src:find("*/", i + 2, true)
      if not e then perr(line, "コメント /* が閉じていません") end
      local body = src:sub(i, e + 1)
      for _ in body:gmatch("\n") do line = line + 1 end
      i = e + 2
    elseif c:match("[%a_%$]") or b >= 0x80 then
      local j = i
      while j <= n do
        local d = src:byte(j)
        local ch = src:sub(j, j)
        if ch:match("[%w_%$]") then
          j = j + 1
        elseif d >= 0x80 then
          if sjis and isSJISLead(d) then j = j + 2 else j = j + 1 end
        else
          break
        end
      end
      push("id", src:sub(i, j - 1))
      i = j
    elseif c:match("%d") or (c == "." and src:sub(i + 1, i + 1):match("%d")) then
      local s = src:match("^0[xX]%x+", i)
      local isInt = true
      if not s then
        s = src:match("^%d*%.?%d*[eE][%+%-]?%d+", i) or src:match("^%d*%.?%d*", i)
        if s:find("[%.eE]") then isInt = false end
      end
      local j = i + #s
      local suf = src:sub(j, j)
      if suf:match("[fFdD]") then
        isInt = false
        j = j + 1
      elseif suf:match("[lL]") then
        j = j + 1
      end
      push("num", s, { isInt = isInt })
      i = j
    elseif c == '"' or c == "'" then
      local q = c
      local j = i + 1
      local out = {}
      while true do
        if j > n then perr(line, "文字列が閉じていません") end
        local d = src:byte(j)
        local ch = src:sub(j, j)
        if ch == q then break end
        if ch == "\n" then perr(line, "文字列の途中で改行されています") end
        if ch == "\\" then
          local e = src:sub(j + 1, j + 1)
          if e == "u" then
            local hex = src:sub(j + 2, j + 5)
            local cp = tonumber(hex, 16) or 63
            if cp < 0x80 then out[#out + 1] = string.char(cp) else out[#out + 1] = "?" end
            j = j + 6
          else
            out[#out + 1] = ESC[e] or e
            j = j + 2
          end
        elseif sjis and isSJISLead(d) then
          out[#out + 1] = src:sub(j, j + 1)
          j = j + 2
        else
          out[#out + 1] = ch
          j = j + 1
        end
      end
      local val = concat(out)
      if not sjis then val = utf8ToSjis(val) end
      push(q == '"' and "str" or "char", val)
      i = j + 1
    elseif c == "#" and src:match("^#%x%x%x%x%x%x", i) then
      push("color", src:sub(i, i + 6))
      i = i + 7
    else
      local found
      for _, op in ipairs(OPS) do
        if src:sub(i, i + #op - 1) == op then found = op; break end
      end
      if not found and SINGLE:find(c, 1, true) then found = c end
      if not found then perr(line, "読めない文字があります: " .. c) end
      push("op", found)
      i = i + #found
    end
  end
  push("eof", "<終わり>")
  return toks
end

----------------------------------------------------------------------
-- 文の読み取り
----------------------------------------------------------------------
local PRIM = { int = true, float = true, double = true, long = true, short = true, byte = true,
  boolean = true, char = true, void = true, color = true, String = true, var = true }
local BUILTIN_TYPES = { PVector = true, PImage = true, PFont = true, PGraphics = true, PShape = true,
  ArrayList = true, HashMap = true, IntList = true, FloatList = true, StringList = true,
  Integer = true, Float = true, Boolean = true, Object = true, Double = true, Character = true }
local MODIFIERS = { public = true, private = true, protected = true, static = true, final = true,
  abstract = true, synchronized = true, transient = true, volatile = true }
local NUMERIC = { int = true, float = true, double = true, long = true, short = true, byte = true,
  color = false }
local INTTYPES = { int = true, long = true, short = true, byte = true }

local BIN = {
  ["||"] = 1, ["&&"] = 2, ["|"] = 3, ["^"] = 4, ["&"] = 5, ["=="] = 6, ["!="] = 6,
  ["<"] = 7, [">"] = 7, ["<="] = 7, [">="] = 7, instanceof = 7,
  ["<<"] = 8, [">>"] = 8, [">>>"] = 8, ["+"] = 9, ["-"] = 9, ["*"] = 10, ["/"] = 10, ["%"] = 10,
}
local ASSIGN = { ["="] = true, ["+="] = true, ["-="] = true, ["*="] = true, ["/="] = true,
  ["%="] = true, ["&="] = true, ["|="] = true, ["^="] = true, ["<<="] = true, [">>="] = true }

local Parser = {}
Parser.__index = Parser

local function newParser(toks)
  local p = setmetatable({ toks = toks, pos = 1, classes = {} }, Parser)
  -- class 名を先に集める（型名として使えるように）
  for i = 1, #toks - 1 do
    if toks[i].t == "id" and (toks[i].v == "class" or toks[i].v == "interface") and toks[i + 1].t == "id" then
      p.classes[toks[i + 1].v] = true
    end
  end
  return p
end

function Parser:peek(k) return self.toks[self.pos + (k or 0)] end
function Parser:next()
  local t = self.toks[self.pos]
  self.pos = self.pos + 1
  return t
end
function Parser:is(v, k)
  local t = self:peek(k)
  return (t.t == "op" or t.t == "id") and t.v == v
end
function Parser:accept(v)
  if self:is(v) then return self:next() end
end
function Parser:expect(v)
  local t = self:peek()
  if not self:is(v) then
    if v == ";" then
      -- ; の書き忘れは前の行の終わりとして知らせる
      local prev = self.toks[self.pos - 1]
      perr(prev and prev.line or t.line, "行の終わりに ; がありません（次が '" .. tostring(t.v) .. "'）")
    end
    perr(t.line, "'" .. v .. "' が必要なところに '" .. tostring(t.v) .. "' があります")
  end
  return self:next()
end
function Parser:ident()
  local t = self:peek()
  if t.t ~= "id" then perr(t.line, "名前が必要なところに '" .. tostring(t.v) .. "' があります") end
  return self:next().v
end

function Parser:isTypeName(v)
  return PRIM[v] or BUILTIN_TYPES[v] or self.classes[v]
end

-- pos から型を読めるなら、型の次の位置を返す（読み進めない）
function Parser:scanType(p)
  local toks = self.toks
  local t = toks[p]
  if not t or t.t ~= "id" or not self:isTypeName(t.v) then return nil end
  p = p + 1
  if toks[p].t == "op" and toks[p].v == "<" then
    local depth = 0
    while true do
      local x = toks[p]
      if x.t == "eof" then return nil end
      if x.t == "op" and x.v == "<" then depth = depth + 1
      elseif x.t == "op" and x.v == ">" then depth = depth - 1
      elseif x.t == "op" and x.v == ">>" then depth = depth - 2
      elseif x.t == "op" and x.v == ">>>" then depth = depth - 3
      elseif not (x.t == "id" or (x.t == "op" and (x.v == "," or x.v == "?" or x.v == "[" or x.v == "]" or x.v == "."))) then
        return nil
      end
      p = p + 1
      if depth <= 0 then break end
    end
  end
  while toks[p].t == "op" and toks[p].v == "[" and toks[p + 1].t == "op" and toks[p + 1].v == "]" do
    p = p + 2
  end
  return p
end

function Parser:skipModifiers()
  local mods = {}
  while true do
    local t = self:peek()
    if t.t == "id" and MODIFIERS[t.v] then
      mods[t.v] = true
      self:next()
    elseif t.t == "op" and t.v == "@" then
      -- @Override など
      self:next(); self:ident()
    else
      break
    end
  end
  return mods
end

function Parser:isDeclStart()
  local p = self.pos
  while self.toks[p].t == "id" and self.toks[p].v == "final" do p = p + 1 end
  local q = self:scanType(p)
  return q and self.toks[q].t == "id" and not BIN[self.toks[q].v]
end

function Parser:parseType()
  local first = self:peek()
  local name = self:ident()
  local s = name
  if self:is("<") then
    local depth = 0
    local parts = {}
    while true do
      local t = self:next()
      if t.v == "<" then depth = depth + 1
      elseif t.v == ">" then depth = depth - 1
      elseif t.v == ">>" then depth = depth - 2
      elseif t.v == ">>>" then depth = depth - 3 end
      parts[#parts + 1] = t.v
      if depth <= 0 then break end
      if t.t == "eof" then perr(first.line, "型の < > が閉じていません") end
    end
    s = s .. concat(parts)
  end
  while self:is("[") and self:is("]", 1) do
    self:next(); self:next()
    s = s .. "[]"
  end
  return s
end

-- 宣言のあと: name [= init] {, name [= init]} ;
function Parser:parseVarList(typ, line)
  local vars = {}
  repeat
    local name = self:ident()
    local t = typ
    while self:is("[") and self:is("]", 1) do self:next(); self:next(); t = t .. "[]" end
    local init
    if self:accept("=") then
      if self:is("{") then init = self:parseArrayInit(t) else init = self:parseExpr() end
    end
    vars[#vars + 1] = { name = name, type = t, init = init, line = line }
  until not self:accept(",")
  return vars
end

function Parser:parseArrayInit(typ)
  local line = self:peek().line
  self:expect("{")
  local elems = {}
  local elemType = typ and typ:gsub("%[%]$", "") or nil
  while not self:is("}") do
    if self:is("{") then elems[#elems + 1] = self:parseArrayInit(elemType)
    else elems[#elems + 1] = self:parseExpr() end
    if not self:accept(",") then break end
  end
  self:expect("}")
  return { k = "arrinit", elems = elems, type = typ, line = line }
end

function Parser:parseParams()
  self:expect("(")
  local params = {}
  if not self:is(")") then
    repeat
      self:skipModifiers()
      local t = self:parseType()
      if self:accept("...") then t = t .. "[]" end
      local name = self:ident()
      while self:is("[") and self:is("]", 1) do self:next(); self:next(); t = t .. "[]" end
      params[#params + 1] = { name = name, type = t }
    until not self:accept(",")
  end
  self:expect(")")
  return params
end

function Parser:skipThrows()
  if self:accept("throws") then
    repeat self:ident() until not self:accept(",")
  end
end

function Parser:parseProgram()
  local prog = { classes = {}, funcs = {}, globals = {}, stmts = {} }
  while self:peek().t ~= "eof" do
    local t = self:peek()
    if self:is("import") or self:is("package") then
      while not self:is(";") do self:next() end
      self:next()
    elseif self:is(";") then
      self:next()
    else
      local save = self.pos
      local mods = self:skipModifiers()
      if self:is("class") then
        prog.classes[#prog.classes + 1] = self:parseClass()
      elseif self:is("interface") or self:is("enum") then
        perr(t.line, self:peek().v .. " は未対応です")
      elseif self:isDeclStart() then
        local line = self:peek().line
        local typ = self:parseType()
        if self:is("(", 1) then
          local name = self:ident()
          local params = self:parseParams()
          self:skipThrows()
          local body = self:parseBlock()
          prog.funcs[#prog.funcs + 1] = { name = name, ret = typ, params = params, body = body, line = line }
        else
          local vars = self:parseVarList(typ, line)
          self:expect(";")
          for _, v in ipairs(vars) do prog.globals[#prog.globals + 1] = v end
        end
      else
        self.pos = save
        -- setup/draw の無い「静的モード」のスケッチ
        prog.stmts[#prog.stmts + 1] = self:parseStatement()
      end
    end
  end
  return prog
end

function Parser:parseClass()
  local line = self:expect("class").line
  local name = self:ident()
  local super
  if self:accept("extends") then super = self:parseType() end
  if self:accept("implements") then
    repeat self:parseType() until not self:accept(",")
  end
  self:expect("{")
  local cls = { name = name, super = super, fields = {}, methods = {}, ctors = {}, line = line }
  while not self:accept("}") do
    if self:accept(";") then
      -- 空文
    else
      local mline = self:peek().line
      local mods = self:skipModifiers()
      if self:is("class") then perr(mline, "クラスの中のクラスは未対応です") end
      if self:peek().t == "id" and self:peek().v == name and self:is("(", 1) then
        self:next()
        local params = self:parseParams()
        self:skipThrows()
        local body = self:parseBlock()
        cls.ctors[#cls.ctors + 1] = { name = name, params = params, body = body, line = mline }
      elseif self:is("{") then
        perr(mline, "初期化ブロック { } は未対応です")
      else
        local typ = self:parseType()
        if self:is("(", 1) then
          local mname = self:ident()
          local params = self:parseParams()
          self:skipThrows()
          local body
          if self:accept(";") then body = { k = "block", body = {} } else body = self:parseBlock() end
          cls.methods[#cls.methods + 1] = { name = mname, ret = typ, params = params, body = body,
            line = mline, static = mods.static }
        else
          local vars = self:parseVarList(typ, mline)
          self:expect(";")
          for _, v in ipairs(vars) do
            v.static = mods.static
            cls.fields[#cls.fields + 1] = v
          end
        end
      end
    end
  end
  return cls
end

function Parser:parseBlock()
  local line = self:expect("{").line
  local body = {}
  while not self:accept("}") do
    if self:peek().t == "eof" then perr(line, "{ が閉じていません") end
    body[#body + 1] = self:parseStatement()
  end
  return { k = "block", body = body, line = line }
end

function Parser:parseStatement()
  local t = self:peek()
  local line = t.line
  if self:is("{") then return self:parseBlock() end
  if self:accept(";") then return { k = "empty", line = line } end
  if t.t == "id" then
    local v = t.v
    if v == "if" then
      self:next(); self:expect("(")
      local cond = self:parseExpr()
      self:expect(")")
      local th = self:parseStatement()
      local el
      if self:accept("else") then el = self:parseStatement() end
      return { k = "if", cond = cond, th = th, el = el, line = line }
    elseif v == "while" then
      self:next(); self:expect("(")
      local cond = self:parseExpr()
      self:expect(")")
      return { k = "while", cond = cond, body = self:parseStatement(), line = line }
    elseif v == "do" then
      self:next()
      local body = self:parseStatement()
      self:expect("while"); self:expect("(")
      local cond = self:parseExpr()
      self:expect(")"); self:expect(";")
      return { k = "dowhile", cond = cond, body = body, line = line }
    elseif v == "for" then
      self:next(); self:expect("(")
      -- 拡張for文
      if self:isDeclStart() then
        local save = self.pos
        self:skipModifiers()
        local typ = self:parseType()
        local name = self:ident()
        if self:accept(":") then
          local iter = self:parseExpr()
          self:expect(")")
          return { k = "foreach", type = typ, name = name, iter = iter, body = self:parseStatement(), line = line }
        end
        self.pos = save
      end
      local init = {}
      if not self:is(";") then
        if self:isDeclStart() then
          self:skipModifiers()
          local typ = self:parseType()
          init[1] = { k = "decl", vars = self:parseVarList(typ, line), line = line }
        else
          repeat init[#init + 1] = { k = "expr", e = self:parseExpr(), line = line } until not self:accept(",")
        end
      end
      self:expect(";")
      local cond
      if not self:is(";") then cond = self:parseExpr() end
      self:expect(";")
      local update = {}
      if not self:is(")") then
        repeat update[#update + 1] = { k = "expr", e = self:parseExpr(), line = line } until not self:accept(",")
      end
      self:expect(")")
      return { k = "for", init = init, cond = cond, update = update, body = self:parseStatement(), line = line }
    elseif v == "return" then
      self:next()
      local e
      if not self:is(";") then e = self:parseExpr() end
      self:expect(";")
      return { k = "return", e = e, line = line }
    elseif v == "break" then
      self:next(); self:expect(";")
      return { k = "break", line = line }
    elseif v == "continue" then
      self:next(); self:expect(";")
      return { k = "continue", line = line }
    elseif v == "switch" then
      return self:parseSwitch()
    elseif v == "try" or v == "throw" or v == "synchronized" then
      perr(line, v .. " は未対応です")
    end
  end
  if self:isDeclStart() then
    self:skipModifiers()
    local typ = self:parseType()
    local vars = self:parseVarList(typ, line)
    self:expect(";")
    return { k = "decl", vars = vars, line = line }
  end
  local e = self:parseExpr()
  self:expect(";")
  return { k = "expr", e = e, line = line }
end

function Parser:parseSwitch()
  local line = self:expect("switch").line
  self:expect("(")
  local e = self:parseExpr()
  self:expect(")")
  self:expect("{")
  local cases = {}
  local cur
  while not self:accept("}") do
    if self:accept("case") then
      local val = self:parseTernary()
      self:expect(":")
      if cur and #cur.body == 0 and not cur.default then
        cur.vals[#cur.vals + 1] = val
      else
        cur = { vals = { val }, body = {} }
        cases[#cases + 1] = cur
      end
    elseif self:accept("default") then
      self:expect(":")
      if cur and #cur.body == 0 then cur.default = true
      else
        cur = { vals = {}, body = {}, default = true }
        cases[#cases + 1] = cur
      end
    else
      if not cur then perr(self:peek().line, "switch の中は case から始めてください") end
      cur.body[#cur.body + 1] = self:parseStatement()
    end
  end
  return { k = "switch", e = e, cases = cases, line = line }
end

-- 式
function Parser:parseExpr()
  return self:parseAssign()
end

function Parser:parseAssign()
  local left = self:parseTernary()
  local t = self:peek()
  if t.t == "op" and ASSIGN[t.v] then
    self:next()
    local right
    if self:is("{") then right = self:parseArrayInit(nil) else right = self:parseAssign() end
    return { k = "assign", op = t.v, target = left, value = right, line = t.line }
  end
  return left
end

function Parser:parseTernary()
  local c = self:parseBin(1)
  if self:is("?") then
    local line = self:next().line
    local a = self:parseAssign()
    self:expect(":")
    local b = self:parseTernary()
    return { k = "cond", c = c, a = a, b = b, line = line }
  end
  return c
end

function Parser:parseBin(minPrec)
  local left = self:parseUnary()
  while true do
    local t = self:peek()
    local op = t.v
    local prec = (t.t == "op" or (t.t == "id" and op == "instanceof")) and BIN[op]
    if not prec or prec < minPrec then break end
    self:next()
    if op == "instanceof" then
      local typ = self:parseType()
      left = { k = "instanceof", e = left, type = typ, line = t.line }
    else
      local right = self:parseBin(prec + 1)
      left = { k = "binop", op = op, a = left, b = right, line = t.line }
    end
  end
  return left
end

local CAST_FOLLOW = { id = true, num = true, str = true, char = true, color = true }

function Parser:parseUnary()
  local t = self:peek()
  if t.t == "op" then
    if t.v == "-" or t.v == "+" or t.v == "!" or t.v == "~" then
      self:next()
      return { k = "unop", op = t.v, e = self:parseUnary(), line = t.line }
    elseif t.v == "++" or t.v == "--" then
      self:next()
      return { k = "incdec", op = t.v, prefix = true, target = self:parseUnary(), line = t.line }
    elseif t.v == "(" then
      local q = self:scanType(self.pos + 1)
      if q and self.toks[q].t == "op" and self.toks[q].v == ")" then
        local nx = self.toks[q + 1]
        local typeName = self.toks[self.pos + 1].v
        if PRIM[typeName] or CAST_FOLLOW[nx.t] or (nx.t == "op" and (nx.v == "(" or nx.v == "!" or nx.v == "~")) then
          self:next()
          local typ = self:parseType()
          self:expect(")")
          return { k = "cast", type = typ, e = self:parseUnary(), line = t.line }
        end
      end
    end
  end
  return self:parsePostfix(self:parsePrimary())
end

function Parser:parseArgs()
  self:expect("(")
  local args = {}
  if not self:is(")") then
    repeat args[#args + 1] = self:parseExpr() until not self:accept(",")
  end
  self:expect(")")
  return args
end

function Parser:parsePostfix(e)
  while true do
    local t = self:peek()
    if self:is(".") then
      self:next()
      local name = self:ident()
      if self:is("(") then
        e = { k = "mcall", obj = e, name = name, args = self:parseArgs(), line = t.line }
      else
        e = { k = "field", obj = e, name = name, line = t.line }
      end
    elseif self:is("[") then
      self:next()
      local idx = self:parseExpr()
      self:expect("]")
      e = { k = "index", obj = e, idx = idx, line = t.line }
    elseif self:is("++") or self:is("--") then
      self:next()
      e = { k = "incdec", op = t.v, prefix = false, target = e, line = t.line }
    else
      return e
    end
  end
end

function Parser:parsePrimary()
  local t = self:next()
  local line = t.line
  if t.t == "num" then return { k = "num", v = t.v, isInt = t.isInt, line = line } end
  if t.t == "str" then return { k = "str", v = t.v, line = line } end
  if t.t == "char" then return { k = "char", v = t.v, line = line } end
  if t.t == "color" then return { k = "colorlit", v = t.v, line = line } end
  if t.t == "op" and t.v == "(" then
    local e = self:parseExpr()
    self:expect(")")
    return { k = "paren", e = e, line = line }
  end
  if t.t == "id" then
    local v = t.v
    if v == "true" or v == "false" then return { k = "bool", v = v, line = line } end
    if v == "null" then return { k = "null", line = line } end
    if v == "this" then
      if self:is("(") then return { k = "thiscall", args = self:parseArgs(), line = line } end
      return { k = "this", line = line }
    end
    if v == "super" then
      if self:is("(") then return { k = "supercall", args = self:parseArgs(), line = line } end
      return { k = "super", line = line }
    end
    if v == "new" then return self:parseNew(line) end
    if self:is("(") then
      return { k = "call", name = v, args = self:parseArgs(), line = line }
    end
    return { k = "name", v = v, line = line }
  end
  perr(line, "ここに '" .. tostring(t.v) .. "' は書けません")
end

function Parser:parseNew(line)
  local name = self:ident()
  local typ = name
  if self:is("<") then
    -- ジェネリクスは読み飛ばす（型名は残す）
    local depth = 0
    local parts = {}
    repeat
      local t = self:next()
      if t.v == "<" then depth = depth + 1
      elseif t.v == ">" then depth = depth - 1
      elseif t.v == ">>" then depth = depth - 2 end
      parts[#parts + 1] = t.v
    until depth <= 0
    typ = name .. concat(parts)
  end
  if self:is("[") then
    local dims, extra = {}, 0
    while self:is("[") do
      self:next()
      if self:is("]") then extra = extra + 1
      else dims[#dims + 1] = self:parseExpr() end
      self:expect("]")
    end
    local full = typ .. string.rep("[]", #dims + extra)
    local init
    if self:is("{") then init = self:parseArrayInit(full) end
    return { k = "newarr", type = typ, dims = dims, full = full, init = init, line = line }
  end
  local args = self:parseArgs()
  if self:is("{") then perr(line, "無名クラスは未対応です") end
  return { k = "new", type = typ, name = name, args = args, line = line }
end

----------------------------------------------------------------------
-- コード生成
----------------------------------------------------------------------
local LUA_KW = {}
for w in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while self")
    :gmatch("%S+") do LUA_KW[w] = true end

local function luaName(n)
  if n:find("[\128-\255]") then
    return "_u" .. n:gsub(".", function(c) return string.format("%02x", c:byte()) end)
  end
  if LUA_KW[n] then return n .. "_" end
  return n
end

local function luaStr(s)
  return '"' .. s:gsub('[%c"\\\128-\255]', function(c) return string.format("\\%03d", c:byte()) end) .. '"'
end

-- 組み込み関数の戻り値の型
local RET = {
  round = "int", floor = "int", ceil = "int", millis = "int", second = "int", minute = "int",
  hour = "int", day = "int", month = "int", year = "int",
  random = "float", noise = "float", map = "float", lerp = "float", dist = "float", mag = "float",
  sqrt = "float", sin = "float", cos = "float", tan = "float", asin = "float", acos = "float",
  atan = "float", atan2 = "float", exp = "float", log = "float", pow = "float", radians = "float",
  degrees = "float", norm = "float", randomGaussian = "float", textWidth = "float",
  textAscent = "float", textDescent = "float", bezierPoint = "float", bezierTangent = "float",
  curvePoint = "float", red = "float", green = "float", blue = "float", alpha = "float",
  hue = "float", saturation = "float", brightness = "float",
  str = "String", nf = "String", join = "String", trim = "String", hex = "String",
  color = "color", lerpColor = "color", get = "color",
  createVector = "PVector", loadImage = "PImage", createFont = "PFont",
}
local VAR_TYPES = { width = "int", height = "int", frameCount = "int", mouseX = "int", mouseY = "int",
  pmouseX = "int", pmouseY = "int", PI = "float", TWO_PI = "float", HALF_PI = "float",
  QUARTER_PI = "float", TAU = "float", time = "float", fps = "float", key = "char", keyCode = "int",
  mousePressed = "boolean", keyPressed = "boolean" }
local PV_FLOAT = { mag = true, magSq = true, heading = true, dot = true, dist = true, angleBetween = true }
local PV_VEC = { add = true, sub = true, mult = true, div = true, normalize = true, limit = true,
  setMag = true, rotate = true, copy = true, get = true, set = true, lerp = true, cross = true,
  fromAngle = true, random2D = true, random3D = true }
local STR_METHODS = { length = "int", charAt = "char", substring = "String", indexOf = "int",
  lastIndexOf = "int", equals = "boolean", equalsIgnoreCase = "boolean", toUpperCase = "String",
  toLowerCase = "String", trim = "String", startsWith = "boolean", endsWith = "boolean",
  contains = "boolean", replace = "String", split = "String[]", isEmpty = "boolean",
  compareTo = "int" }
local CAST_FN = { int = "__int", long = "__int", short = "__int", byte = "__int",
  float = "__float", double = "__float", boolean = "__bool", char = "__char", String = "str",
  str = "str", color = "color" }

local function isIntT(t) return t ~= nil and INTTYPES[t] == true end
local function isNumT(t) return t ~= nil and (NUMERIC[t] == true) end
local function isStrT(t) return t == "String" or t == "char" end
local function elemType(t)
  if t and t:sub(-2) == "[]" then return t:sub(1, -3) end
  if t then
    local g = t:match("^%a+List<(.-)>$") or t:match("^ArrayList<(.-)>$")
    if g then return g end
    if t == "IntList" then return "int" elseif t == "FloatList" then return "float"
    elseif t == "StringList" then return "String" end
  end
  return nil
end
local function baseType(t) return t and t:gsub("<.*>", ""):gsub("%[%]", "") end

local function defaultValue(t)
  if t and t:sub(-2) ~= "[]" then
    if isNumT(t) or t == "color" then return "0" end
    if t == "boolean" then return "false" end
  end
  return "nil"
end

local Gen = {}
Gen.__index = Gen

local function newGen(prog, name)
  local g = setmetatable({ prog = prog, out = {}, map = {}, indent = 0, line = 1,
    classes = {}, funcs = {}, globals = {}, scopes = {}, frames = {}, uid = 0, name = name }, Gen)
  for _, c in ipairs(prog.classes) do g.classes[c.name] = c end
  for _, f in ipairs(prog.funcs) do
    g.funcs[f.name] = g.funcs[f.name] or {}
    table.insert(g.funcs[f.name], f)
  end
  for _, v in ipairs(prog.globals) do g.globals[v.name] = v.type end
  return g
end

function Gen:emit(s, line)
  self.out[#self.out + 1] = string.rep("  ", self.indent) .. s
  self.map[#self.out] = line or self.line
end
function Gen:id() self.uid = self.uid + 1; return self.uid end

function Gen:pushScope() self.scopes[#self.scopes + 1] = {} end
function Gen:popScope() self.scopes[#self.scopes] = nil end
function Gen:declare(name, typ) self.scopes[#self.scopes][name] = typ or "?" end

function Gen:lookupLocal(name)
  for i = #self.scopes, 1, -1 do
    local t = self.scopes[i][name]
    if t then return t end
  end
end

-- クラスの継承をたどってフィールド / 関数を探す
function Gen:findField(cname, name)
  local c = self.classes[cname]
  while c do
    for _, f in ipairs(c.fields) do
      if f.name == name then return f, c end
    end
    c = c.super and self.classes[baseType(c.super)]
  end
end
function Gen:findMethod(cname, name)
  local c = self.classes[cname]
  while c do
    for _, m in ipairs(c.methods) do
      if m.name == name then return m, c end
    end
    c = c.super and self.classes[baseType(c.super)]
  end
end

-- 式の生成。戻り値: Luaコード, 型
function Gen:expr(e)
  local k = e.k
  if k == "num" then
    local v = e.v
    if v:sub(1, 1) == "." then v = "0" .. v end
    if v:sub(-1) == "." then v = v .. "0" end
    return v, e.isInt and "int" or "float"
  elseif k == "str" then return luaStr(e.v), "String"
  elseif k == "char" then return luaStr(e.v), "char"
  elseif k == "bool" then return e.v, "boolean"
  elseif k == "null" then return "nil", "null"
  elseif k == "colorlit" then return "color(" .. luaStr(e.v) .. ")", "color"
  elseif k == "paren" then
    local c, t = self:expr(e.e)
    return "(" .. c .. ")", t
  elseif k == "this" then return "self", self.cls and self.cls.name
  elseif k == "name" then return self:nameRef(e)
  elseif k == "field" then return self:fieldRef(e)
  elseif k == "index" then
    local o, ot = self:expr(e.obj)
    local i = self:expr(e.idx)
    return self:prefix(o) .. "[" .. i .. "]", elemType(ot)
  elseif k == "call" then return self:callExpr(e)
  elseif k == "mcall" then return self:methodCall(e)
  elseif k == "supercall" or k == "thiscall" then
    perr(e.line, "super(...) / this(...) はコンストラクタの最初にだけ書けます")
  elseif k == "new" then return self:newExpr(e)
  elseif k == "newarr" then
    if e.init then return self:arrInit(e.init) end
    local dims = {}
    for i, d in ipairs(e.dims) do dims[i] = self:expr(d) end
    local dv = (#e.dims == #e.full:gsub("[^%[]", "") ) and defaultValue(e.type) or "nil"
    return "__newArray(" .. dv .. ", " .. concat(dims, ", ") .. ")", e.full
  elseif k == "arrinit" then return self:arrInit(e)
  elseif k == "unop" then
    local c, t = self:expr(e.e)
    if e.op == "-" then return "(-" .. c .. ")", t
    elseif e.op == "+" then return c, t
    elseif e.op == "!" then return "(not " .. c .. ")", "boolean"
    else return "__bnot(" .. c .. ")", "int" end
  elseif k == "binop" then return self:binop(e)
  elseif k == "cond" then
    local c = self:expr(e.c)
    local a, at = self:expr(e.a)
    local b, bt = self:expr(e.b)
    local t = at
    if isNumT(at) and isNumT(bt) then t = (isIntT(at) and isIntT(bt)) and "int" or "float" end
    if isNumT(at) or isStrT(at) or e.a.k == "colorlit" then
      return "(" .. c .. " and " .. a .. " or " .. b .. ")", t
    end
    return "__cond(" .. c .. ", function() return " .. a .. " end, function() return " .. b .. " end)", t
  elseif k == "cast" then
    local c, t = self:expr(e.e)
    local fn = CAST_FN[e.type]
    if fn then return fn .. "(" .. c .. ")", e.type end
    return c, e.type
  elseif k == "instanceof" then
    local c = self:expr(e.e)
    return "__instanceof(" .. c .. ", " .. luaName(baseType(e.type)) .. ")", "boolean"
  elseif k == "assign" or k == "incdec" then
    perr(e.line, "式の途中の代入や ++ / -- は未対応です。別の行に分けてください")
  end
  perr(e.line or self.line, "未対応の式です: " .. tostring(k))
end

-- そのまま . や : を続けられる式か（名前・呼び出し・添字のつながりだけなら true）
local function isPrefixSafe(code)
  if not code:match("^[%a_]") then return false end
  local depth, i, n = 0, 1, #code
  while i <= n do
    local c = code:sub(i, i)
    if c == '"' then
      local j = i + 1
      while j <= n do
        local d = code:sub(j, j)
        if d == "\\" then j = j + 2 elseif d == '"' then break else j = j + 1 end
      end
      i = j
    elseif c == "(" or c == "[" then depth = depth + 1
    elseif c == ")" or c == "]" then depth = depth - 1
    elseif depth == 0 and not c:match("[%w_%.:]") then
      return false
    end
    i = i + 1
  end
  return depth == 0
end

function Gen:prefix(code)
  if isPrefixSafe(code) then return code end
  return "(" .. code .. ")"
end

function Gen:nameRef(e)
  local n = e.v
  local lt = self:lookupLocal(n)
  if lt then return luaName(n), lt end
  if self.cls then
    local f, owner = self:findField(self.cls.name, n)
    if f then
      if f.static then return luaName(owner.name) .. "." .. luaName(n), f.type end
      if self.static then perr(e.line, "static 関数の中でフィールド " .. n .. " は使えません") end
      return "self." .. luaName(n), f.type
    end
  end
  if self.globals[n] then return luaName(n), self.globals[n] end
  if self.classes[n] then return luaName(n), "class:" .. n end
  return luaName(n), VAR_TYPES[n]
end

function Gen:fieldRef(e)
  local obj = e.obj
  if obj.k == "name" and not self:lookupLocal(obj.v) and not self.globals[obj.v]
     and not (self.cls and self:findField(self.cls.name, obj.v)) then
    -- クラス名.static フィールド
    if self.classes[obj.v] then
      local f = self:findField(obj.v, e.name)
      return luaName(obj.v) .. "." .. luaName(e.name), f and f.type
    end
    if obj.v == "Math" or obj.v == "Integer" or obj.v == "Float" or obj.v == "PConstants" then
      local ty = (obj.v == "Integer") and "int" or "float"
      return "Math_" .. obj.v .. "." .. e.name, ty
    end
  end
  if obj.k == "super" then
    return "self." .. luaName(e.name), nil
  end
  local o, ot = self:expr(obj)
  if e.name == "length" and ot and (ot:sub(-2) == "[]") then
    return self:prefix(o) .. ".length", "int"
  end
  local ft
  local bt = baseType(ot)
  if bt and self.classes[bt] then
    local f = self:findField(bt, e.name)
    ft = f and f.type
  elseif bt == "PVector" then ft = "float"
  elseif bt == "PImage" and (e.name == "width" or e.name == "height") then ft = "int"
  end
  if e.name == "length" and not ft then ft = "int" end
  return self:prefix(o) .. "." .. luaName(e.name), ft
end

function Gen:args(list)
  local a, ts = {}, {}
  for i, x in ipairs(list) do a[i], ts[i] = self:expr(x) end
  return concat(a, ", "), ts
end

function Gen:callExpr(e)
  local n = e.name
  local args, ts = self:args(e.args)
  -- 型名を関数として使う変換関数: int(x) float(x) など
  if CAST_FN[n] and n ~= "color" and n ~= "str" then return CAST_FN[n] .. "(" .. args .. ")", n end
  if self:lookupLocal(n) then return luaName(n) .. "(" .. args .. ")", nil end
  if self.cls then
    local m, owner = self:findMethod(self.cls.name, n)
    if m then
      if m.static then return luaName(owner.name) .. "." .. luaName(n) .. "(" .. args .. ")", m.ret end
      return "self:" .. luaName(n) .. "(" .. args .. ")", m.ret
    end
  end
  local fs = self.funcs[n]
  if fs then return luaName(n) .. "(" .. args .. ")", fs[1].ret end
  local rt = RET[n]
  if n == "min" or n == "max" or n == "abs" or n == "constrain" or n == "sq" then
    local allInt = #ts > 0
    for _, t in ipairs(ts) do if not isIntT(t) then allInt = false end end
    rt = allInt and "int" or "float"
  end
  if n == "println" or n == "print" then return "println(" .. args .. ")", nil end
  return luaName(n) .. "(" .. args .. ")", rt
end

function Gen:methodCall(e)
  local obj, name = e.obj, e.name
  local args, ats = self:args(e.args)
  local function withArgs(prefix) return prefix .. (args ~= "" and (", " .. args) or "") .. ")" end
  if obj.k == "super" then
    local parent = self.cls and self.cls.super
    if not parent then perr(e.line, "super を使えるのは extends したクラスの中だけです") end
    local m = self:findMethod(baseType(parent), name)
    return withArgs(luaName(baseType(parent)) .. "." .. luaName(name) .. "(self"), m and m.ret
  end
  if obj.k == "name" and not self:lookupLocal(obj.v) and not self.globals[obj.v]
     and not (self.cls and self:findField(self.cls.name, obj.v)) then
    local cn = obj.v
    if self.classes[cn] then
      local m = self:findMethod(cn, name)
      return luaName(cn) .. "." .. luaName(name) .. "(" .. args .. ")", m and m.ret
    end
    if cn == "PVector" then
      local rt = PV_FLOAT[name] and "float" or "PVector"
      return "__PV." .. name .. "(" .. args .. ")", rt
    end
    if cn == "Math" or cn == "Integer" or cn == "Float" or cn == "String" or cn == "Character" then
      local rt = (cn == "Integer") and "int" or ((cn == "String") and "String" or "float")
      if name == "round" or name == "floor" or name == "ceil" then rt = "int" end
      return "Math_" .. cn .. "." .. name .. "(" .. args .. ")", rt
    end
  end
  local o, ot = self:expr(obj)
  local bt = baseType(ot)
  if isStrT(ot) then
    return withArgs("__S." .. name .. "(" .. o), STR_METHODS[name]
  end
  local rt
  if bt and self.classes[bt] then
    local m = self:findMethod(bt, name)
    rt = m and m.ret
  elseif bt == "PVector" then
    rt = PV_FLOAT[name] and "float" or (PV_VEC[name] and "PVector" or nil)
  elseif ot and (bt == "ArrayList" or bt:match("List$")) then
    if name == "get" or name == "remove" then rt = elemType(ot)
    elseif name == "size" or name == "indexOf" then rt = "int"
    elseif name == "isEmpty" or name == "contains" or name == "hasValue" then rt = "boolean" end
  elseif bt == "HashMap" then
    local kv = ot:match("<.-,%s*(.-)>$")
    if name == "get" then rt = kv elseif name == "size" then rt = "int"
    elseif name == "containsKey" then rt = "boolean" end
  end
  if ot == nil and STR_METHODS[name] then
    return withArgs("__mc(" .. o .. ", " .. luaStr(name)), nil
  end
  return self:prefix(o) .. ":" .. luaName(name) .. "(" .. args .. ")", rt
end

local NEW_BUILTIN = { ArrayList = "ArrayList.new", HashMap = "HashMap.new", IntList = "IntList.new",
  FloatList = "FloatList.new", StringList = "StringList.new", PVector = "PVector",
  PImage = "__newPImage", Integer = "__int", Float = "__float", String = "str" }

function Gen:newExpr(e)
  local args = self:args(e.args)
  local n = e.name
  if self.classes[n] then return luaName(n) .. ".new(" .. args .. ")", n end
  if NEW_BUILTIN[n] then return NEW_BUILTIN[n] .. "(" .. args .. ")", e.type end
  perr(e.line, "new " .. n .. " は未対応です")
end

function Gen:arrInit(e)
  local parts = { tostring(#e.elems) }
  for _, x in ipairs(e.elems) do
    if x.k == "arrinit" then
      if not x.type and e.type then x.type = elemType(e.type) end
      parts[#parts + 1] = (self:arrInit(x))
    else
      parts[#parts + 1] = (self:expr(x))
    end
  end
  return "__arr(" .. concat(parts, ", ") .. ")", e.type
end

local BITFN = { ["&"] = "__band", ["|"] = "__bor", ["^"] = "__bxor", ["<<"] = "__shl", [">>"] = "__sar",
  [">>>"] = "__shr" }

function Gen:binop(e)
  local op = e.op
  local a, at = self:expr(e.a)
  local b, bt = self:expr(e.b)
  if op == "+" then
    if isStrT(at) or isStrT(bt) then
      if at == "char" and bt == "char" then return "(" .. a .. " .. " .. b .. ")", "String" end
      return "__cat(" .. a .. ", " .. b .. ")", "String"
    end
    if at == nil or bt == nil then
      -- 型が分からないときは実行時に判定
      return "__add(" .. a .. ", " .. b .. ")", nil
    end
    return "(" .. a .. " + " .. b .. ")", (isIntT(at) and isIntT(bt)) and "int" or "float"
  elseif op == "-" or op == "*" then
    return "(" .. a .. " " .. op .. " " .. b .. ")", (isIntT(at) and isIntT(bt)) and "int" or "float"
  elseif op == "/" then
    if isIntT(at) and isIntT(bt) then return "__idiv(" .. a .. ", " .. b .. ")", "int" end
    return "(" .. a .. " / " .. b .. ")", "float"
  elseif op == "%" then
    return "__mod(" .. a .. ", " .. b .. ")", (isIntT(at) and isIntT(bt)) and "int" or "float"
  elseif op == "&&" then return "(" .. a .. " and " .. b .. ")", "boolean"
  elseif op == "||" then return "(" .. a .. " or " .. b .. ")", "boolean"
  elseif op == "==" then return "(" .. a .. " == " .. b .. ")", "boolean"
  elseif op == "!=" then return "(" .. a .. " ~= " .. b .. ")", "boolean"
  elseif op == "<" or op == ">" or op == "<=" or op == ">=" then
    return "(" .. a .. " " .. op .. " " .. b .. ")", "boolean"
  elseif BITFN[op] then
    if (op == "&" or op == "|" or op == "^") and at == "boolean" then
      local lop = (op == "&") and "and" or ((op == "|") and "or" or "~=")
      return "(" .. a .. " " .. lop .. " " .. b .. ")", "boolean"
    end
    return BITFN[op] .. "(" .. a .. ", " .. b .. ")", "int"
  end
  perr(e.line, "未対応の演算子です: " .. op)
end

-- 代入先のコードと型
function Gen:lvalue(e)
  if e.k == "name" or e.k == "field" or e.k == "index" then
    return self:expr(e)
  elseif e.k == "paren" then
    return self:lvalue(e.e)
  end
  perr(e.line, "ここには代入できません")
end

local COMPOUND = { ["+="] = "+", ["-="] = "-", ["*="] = "*", ["/="] = "/", ["%="] = "%",
  ["&="] = "&", ["|="] = "|", ["^="] = "^", ["<<="] = "<<", [">>="] = ">>" }

function Gen:assignStmt(e)
  local t, tt = self:lvalue(e.target)
  if e.op == "=" then
    if e.value.k == "arrinit" and not e.value.type then e.value.type = tt end
    local v, vt = self:expr(e.value)
    if isIntT(tt) and vt == "float" then v = "__int(" .. v .. ")" end
    self:emit(t .. " = " .. v, e.line)
    return
  end
  local op = COMPOUND[e.op]
  local fake = { k = "binop", op = op, a = { k = "__raw", code = t, type = tt }, b = e.value, line = e.line }
  local v, vt = self:expr(fake)
  if isIntT(tt) and vt ~= "int" and vt ~= nil then v = "__int(" .. v .. ")" end
  self:emit(t .. " = " .. v, e.line)
end

local rawExpr = Gen.expr
function Gen:expr(e)
  if e.k == "__raw" then return e.code, e.type end
  return rawExpr(self, e)
end

function Gen:exprStmt(e, line)
  if e.k == "assign" then return self:assignStmt(e) end
  if e.k == "incdec" then
    local t = self:lvalue(e.target)
    self:emit(t .. " = " .. t .. (e.op == "++" and " + 1" or " - 1"), e.line)
    return
  end
  if e.k == "paren" then return self:exprStmt(e.e, line) end
  if e.k == "call" or e.k == "mcall" or e.k == "new" then
    local c = self:expr(e)
    if e.k == "new" or c:sub(1, 1) == "(" then c = "local _ = " .. c end
    self:emit(c, e.line)
    return
  end
  perr(e.line or line, "この式だけでは文になりません")
end

-- break / continue 用の枠
function Gen:genBreak(line)
  local f = self.frames[#self.frames]
  if not f then perr(line, "break はループか switch の中でだけ使えます") end
  if f.kind == "switch" then self:emit("do break end", line)
  else self:emit("do " .. f.bk .. " = true; break end", line) end
end

function Gen:continueCode(d)
  local f = self.frames[d]
  if not f then return nil end
  if f.kind == "loop" then return "do break end" end
  f.needCont = true
  return "do " .. f.ct .. " = true; break end"
end

function Gen:genContinue(line)
  local d = #self.frames
  while d >= 1 and self.frames[d].kind ~= "loop" do d = d - 1 end
  if d < 1 then perr(line, "continue はループの中でだけ使えます") end
  -- 間に switch があれば、それぞれの外側で continue をやり直す
  local code = self:continueCode(#self.frames)
  self:emit(code, line)
end

function Gen:block(s)
  if s.k == "block" then
    self:pushScope()
    for _, x in ipairs(s.body) do self:stmt(x) end
    self:popScope()
  else
    self:pushScope()
    self:stmt(s)
    self:popScope()
  end
end

-- ループ本体: repeat ... until true で包んで continue を break で書く
function Gen:loopBody(body, line, update)
  local n = self:id()
  local frame = { kind = "loop", bk = "__bk" .. n }
  self:emit("local " .. frame.bk .. " = false", line)
  self:emit("repeat", line)
  self.indent = self.indent + 1
  self.frames[#self.frames + 1] = frame
  self:block(body)
  self.frames[#self.frames] = nil
  self.indent = self.indent - 1
  self:emit("until true", line)
  self:emit("if " .. frame.bk .. " then break end", line)
  if update then
    for _, u in ipairs(update) do self:exprStmt(u.e, u.line) end
  end
end

function Gen:declStmt(s, isGlobal)
  for _, v in ipairs(s.vars) do
    local init
    if v.init then
      if v.init.k == "arrinit" and not v.init.type then v.init.type = v.type end
      local c, t = self:expr(v.init)
      if isIntT(v.type) and t == "float" then c = "__int(" .. c .. ")" end
      init = c
    else
      init = defaultValue(v.type)
    end
    if isGlobal then
      self:emit(luaName(v.name) .. " = " .. init, v.line)
    else
      self:declare(v.name, v.type)
      self:emit("local " .. luaName(v.name) .. " = " .. init, v.line)
    end
  end
end

function Gen:stmt(s)
  self.line = s.line or self.line
  local k = s.k
  if k == "block" then
    self:emit("do", s.line)
    self.indent = self.indent + 1
    self:block(s)
    self.indent = self.indent - 1
    self:emit("end", s.line)
  elseif k == "empty" then
    -- 何もしない
  elseif k == "decl" then
    self:declStmt(s, false)
  elseif k == "expr" then
    self:exprStmt(s.e, s.line)
  elseif k == "if" then
    local c = self:expr(s.cond)
    self:emit("if " .. c .. " then", s.line)
    self.indent = self.indent + 1
    self:block(s.th)
    self.indent = self.indent - 1
    local el = s.el
    while el and el.k == "if" do
      local c2 = self:expr(el.cond)
      self:emit("elseif " .. c2 .. " then", el.line)
      self.indent = self.indent + 1
      self:block(el.th)
      self.indent = self.indent - 1
      el = el.el
    end
    if el then
      self:emit("else", s.line)
      self.indent = self.indent + 1
      self:block(el)
      self.indent = self.indent - 1
    end
    self:emit("end", s.line)
  elseif k == "while" then
    local c = self:expr(s.cond)
    self:emit("while " .. c .. " do", s.line)
    self.indent = self.indent + 1
    self:loopBody(s.body, s.line)
    self.indent = self.indent - 1
    self:emit("end", s.line)
  elseif k == "dowhile" then
    -- do { } while (c): 本体を実行してから判定
    self:emit("while true do", s.line)
    self.indent = self.indent + 1
    self:loopBody(s.body, s.line)
    local c = self:expr(s.cond)
    self:emit("if not " .. c .. " then break end", s.line)
    self.indent = self.indent - 1
    self:emit("end", s.line)
  elseif k == "for" then
    self:emit("do", s.line)
    self.indent = self.indent + 1
    self:pushScope()
    for _, x in ipairs(s.init) do self:stmt(x) end
    local c = s.cond and self:expr(s.cond) or "true"
    self:emit("while " .. c .. " do", s.line)
    self.indent = self.indent + 1
    self:loopBody(s.body, s.line, s.update)
    self.indent = self.indent - 1
    self:emit("end", s.line)
    self:popScope()
    self.indent = self.indent - 1
    self:emit("end", s.line)
  elseif k == "foreach" then
    local it, itT = self:expr(s.iter)
    self:emit("for _, " .. luaName(s.name) .. " in __each(" .. it .. ") do", s.line)
    self.indent = self.indent + 1
    self:pushScope()
    self:declare(s.name, s.type ~= "var" and s.type or elemType(itT))
    self:loopBody(s.body, s.line)
    self:popScope()
    self.indent = self.indent - 1
    self:emit("end", s.line)
  elseif k == "return" then
    if s.e then
      local c, t = self:expr(s.e)
      if self.ret and isIntT(self.ret) and t == "float" then c = "__int(" .. c .. ")" end
      self:emit("do return " .. c .. " end", s.line)
    else
      self:emit("do return end", s.line)
    end
  elseif k == "break" then
    self:genBreak(s.line)
  elseif k == "continue" then
    self:genContinue(s.line)
  elseif k == "switch" then
    local n = self:id()
    local sw, m, ct = "__sw" .. n, "__m" .. n, "__ct" .. n
    local frame = { kind = "switch", ct = ct }
    self:emit("local " .. ct .. " = false", s.line)
    self:emit("repeat", s.line)
    self.indent = self.indent + 1
    self:emit("local " .. sw .. " = " .. (self:expr(s.e)), s.line)
    self:emit("local " .. m .. " = false", s.line)
    -- default 用: どの case にも当たらないか
    local all = {}
    for _, c in ipairs(s.cases) do
      for _, v in ipairs(c.vals) do all[#all + 1] = sw .. " == " .. (self:expr(v)) end
    end
    local none = (#all > 0) and ("not (" .. concat(all, " or ") .. ")") or "true"
    self.frames[#self.frames + 1] = frame
    for _, c in ipairs(s.cases) do
      local conds = { m }
      for _, v in ipairs(c.vals) do conds[#conds + 1] = sw .. " == " .. (self:expr(v)) end
      if c.default then conds[#conds + 1] = none end
      self:emit("if " .. concat(conds, " or ") .. " then", s.line)
      self.indent = self.indent + 1
      self:emit(m .. " = true", s.line)
      self:pushScope()
      for _, x in ipairs(c.body) do self:stmt(x) end
      self:popScope()
      self.indent = self.indent - 1
      self:emit("end", s.line)
    end
    self.frames[#self.frames] = nil
    self.indent = self.indent - 1
    self:emit("until true", s.line)
    if frame.needCont then
      self:emit("if " .. ct .. " then " .. self:continueCode(#self.frames) .. " end", s.line)
    end
  else
    perr(s.line, "未対応の文です: " .. tostring(k))
  end
end

function Gen:funcBody(f, header, selfName)
  self:emit(header, f.line)
  self.indent = self.indent + 1
  self:pushScope()
  for _, p in ipairs(f.params) do self:declare(p.name, p.type) end
  local saveRet = self.ret
  self.ret = f.ret
  if f.preamble then f.preamble(self) end
  for _, x in ipairs(f.body.body) do self:stmt(x) end
  self.ret = saveRet
  self:popScope()
  self.indent = self.indent - 1
  self:emit("end", f.line)
end

local function paramList(params, withSelf)
  local ps = {}
  if withSelf then ps[1] = "self" end
  for _, p in ipairs(params) do ps[#ps + 1] = luaName(p.name) end
  return concat(ps, ", ")
end

-- 同じ名前で引数の数だけ違う関数（オーバーロード）
local function groupByName(list)
  local groups, order = {}, {}
  for _, f in ipairs(list) do
    if not groups[f.name] then groups[f.name] = {}; order[#order + 1] = f.name end
    table.insert(groups[f.name], f)
  end
  return groups, order
end

function Gen:emitClass(c)
  local name = luaName(c.name)
  local parent = c.super and baseType(c.super)
  if parent and not self.classes[parent] then perr(c.line, "親クラス " .. parent .. " が見つかりません") end
  self.line = c.line
  self:emit(name .. " = __class(" .. luaStr(c.name) .. ", " .. (parent and luaName(parent) or "nil") .. ")", c.line)
  self.cls = c
  -- static フィールド
  for _, f in ipairs(c.fields) do
    if f.static then
      local init = f.init and (self:expr(f.init)) or defaultValue(f.type)
      self:emit(name .. "." .. luaName(f.name) .. " = " .. init, f.line)
    end
  end
  -- フィールドの初期化
  self:emit("function " .. name .. ".__fields(self)", c.line)
  self.indent = self.indent + 1
  self:pushScope()
  for _, f in ipairs(c.fields) do
    if not f.static then
      local init
      if f.init then
        if f.init.k == "arrinit" and not f.init.type then f.init.type = f.type end
        local code, t = self:expr(f.init)
        if isIntT(f.type) and t == "float" then code = "__int(" .. code .. ")" end
        init = code
      else
        init = defaultValue(f.type)
      end
      self:emit("self." .. luaName(f.name) .. " = " .. init, f.line)
    end
  end
  self:popScope()
  self.indent = self.indent - 1
  self:emit("end", c.line)
  -- コンストラクタ
  local ctors = c.ctors
  if #ctors == 0 then
    ctors = { { name = "__init", params = {}, body = { k = "block", body = {} }, line = c.line } }
  end
  for _, ct in ipairs(ctors) do
    ct.name = "__init"
    ct.ret = nil
    local body = ct.body.body
    local superArgs, thisArgs
    if body[1] and body[1].k == "expr" and body[1].e.k == "supercall" then
      superArgs = body[1].e.args
      table.remove(body, 1)
    elseif body[1] and body[1].k == "expr" and body[1].e.k == "thiscall" then
      thisArgs = body[1].e.args
      table.remove(body, 1)
    end
    ct.preamble = function(g)
      if thisArgs then
        -- this(...) で別のコンストラクタを呼ぶ
        local a = g:args(thisArgs)
        g:emit(name .. ".__init(self" .. (a ~= "" and (", " .. a) or "") .. ")", ct.line)
        return
      end
      if parent then
        local a = superArgs and g:args(superArgs) or ""
        g:emit(luaName(parent) .. ".__init(self" .. (a ~= "" and (", " .. a) or "") .. ")", ct.line)
      end
      g:emit(name .. ".__fields(self)", ct.line)
    end
  end
  self.static = false
  self:emitOverloads(ctors, name, ":", true)
  -- 関数
  local groups, order = groupByName(c.methods)
  for _, mn in ipairs(order) do
    local fs = groups[mn]
    self.static = fs[1].static
    self:emitOverloads(fs, name, fs[1].static and "." or ":", not fs[1].static)
  end
  self.static = false
  self.cls = nil
end

function Gen:program()
  local prog = self.prog
  -- 静的モード: setup/draw の無いスケッチの文は setup にまとめる
  if #prog.stmts > 0 then
    if self.funcs.setup then
      perr(prog.stmts[1].line, "関数の外に処理を書くときは setup() などの関数を定義できません")
    end
    local f = { name = "setup", ret = "void", params = {}, body = { k = "block", body = prog.stmts },
      line = prog.stmts[1].line }
    prog.funcs[#prog.funcs + 1] = f
    self.funcs.setup = { f }
  end
  self:emit("local __pde_dummy = nil", 1)
  for _, c in ipairs(prog.classes) do self:emitClass(c) end
  local groups, order = groupByName(prog.funcs)
  for _, fname in ipairs(order) do
    self:emitOverloads(groups[fname], "", "", false)
  end
  self.scopes = {}
  for _, v in ipairs(prog.globals) do
    self:declStmt({ vars = { v } }, true)
  end
  return concat(self.out, "\n"), self.map
end

-- 関数を出す。同じ名前で引数の数が違うもの（オーバーロード）は振り分け関数を作る
function Gen:emitOverloads(fs, target, sep, withSelf)
  if target == "" then
    if #fs == 1 then
      local f = fs[1]
      self:funcBody(f, "function " .. luaName(f.name) .. "(" .. paramList(f.params) .. ")")
      return
    end
    local seen = {}
    for _, f in ipairs(fs) do
      local n = #f.params
      if seen[n] then perr(f.line, f.name .. " は引数の数が同じオーバーロードがあり、未対応です") end
      seen[n] = true
      self:funcBody(f, "function " .. luaName(f.name) .. "__" .. n .. "(" .. paramList(f.params) .. ")")
    end
    local line = fs[1].line
    self:emit("function " .. luaName(fs[1].name) .. "(...)", line)
    self:emit("  local n = select(\"#\", ...)", line)
    for n in pairs(seen) do
      self:emit("  if n == " .. n .. " then return " .. luaName(fs[1].name) .. "__" .. n .. "(...) end", line)
    end
    self:emit("  error(\"" .. fs[1].name .. ": 引数の数が合いません\")", line)
    self:emit("end", line)
    return
  end
  -- クラス
  if #fs == 1 then
    local f = fs[1]
    self:funcBody(f, "function " .. target .. sep .. luaName(f.name) .. "(" .. paramList(f.params) .. ")")
    return
  end
  local seen = {}
  for _, f in ipairs(fs) do
    local n = #f.params
    if seen[n] then perr(f.line, f.name .. " は引数の数が同じオーバーロードがあり、未対応です") end
    seen[n] = true
    self:funcBody(f, "function " .. target .. sep .. luaName(f.name) .. "__" .. n .. "(" .. paramList(f.params) .. ")")
  end
  local line = fs[1].line
  local fname = luaName(fs[1].name)
  self:emit("function " .. target .. sep .. fname .. "(...)", line)
  self:emit("  local n = select(\"#\", ...)", line)
  for n in pairs(seen) do
    if withSelf then
      self:emit("  if n == " .. n .. " then return " .. target .. "." .. fname .. "__" .. n .. "(self, ...) end", line)
    else
      self:emit("  if n == " .. n .. " then return " .. target .. "." .. fname .. "__" .. n .. "(...) end", line)
    end
  end
  self:emit("  error(\"" .. fs[1].name .. ": 引数の数が合いません\")", line)
  self:emit("end", line)
end

----------------------------------------------------------------------
-- 公開関数
----------------------------------------------------------------------
-- 戻り値: luaコード, 行の対応(生成行 -> 元の行)  /  失敗時は nil, "行: メッセージ"
function M.transpile(src, name)
  if src:sub(1, 3) == "\239\187\191" then src = src:sub(4) end
  local ok, a, b = pcall(function()
    local toks = tokenize(src)
    local p = newParser(toks)
    local prog = p:parseProgram()
    local g = newGen(prog, name)
    return g:program()
  end)
  if ok then return a, b end
  if type(a) == "table" and a.pde then
    return nil, (name or "sketch") .. " の " .. a.line .. " 行目: " .. a.msg
  end
  return nil, "変換中のエラー: " .. tostring(a)
end

M._tokenize = tokenize
return M
