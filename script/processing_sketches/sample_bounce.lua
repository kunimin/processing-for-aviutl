-- 跳ねるボール（変数の状態をフレーム間で引き継ぐ例。動作=1 連続 で使う）
local balls = {}

function setup()
  colorMode(HSB, 360, 100, 100)
  for i = 1, 30 do
    balls[i] = {
      pos = createVector(random(width), random(height)),
      vel = PVector.random2D() * random(2, 6),
      r = random(8, 24),
      hue = random(360),
    }
  end
end

function draw()
  background(230, 30, 12)
  noStroke()
  for _, b in ipairs(balls) do
    b.pos:add(b.vel)
    if b.pos.x < b.r or b.pos.x > width - b.r then b.vel.x = -b.vel.x end
    if b.pos.y < b.r or b.pos.y > height - b.r then b.vel.y = -b.vel.y end
    b.pos.x = constrain(b.pos.x, b.r, width - b.r)
    b.pos.y = constrain(b.pos.y, b.r, height - b.r)
    fill(b.hue, 70, 100)
    circle(b.pos.x, b.pos.y, b.r * 2)
  end
  -- ボール同士を近いものだけ線でつなぐ
  stroke(0, 0, 100, 90)
  strokeWeight(1.5)
  for i = 1, #balls do
    for j = i + 1, #balls do
      local a, c = balls[i].pos, balls[j].pos
      if a:dist(c) < 90 then line(a.x, a.y, c.x, c.y) end
    end
  end
end
