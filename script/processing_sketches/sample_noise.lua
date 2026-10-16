-- ノイズで流れる線（前の絵に描き足していく例。「累積描画」にチェックを入れて使う）
local particles = {}

function setup()
  background(10)
  for i = 1, 300 do
    particles[i] = { x = random(width), y = random(height) }
  end
end

function draw()
  noStroke()
  fill(10, 10, 10, 12)          -- うっすら黒を重ねて古い線を消していく
  rect(0, 0, width, height)
  stroke(255, 200, 80, 120)
  strokeWeight(1.2)
  for _, p in ipairs(particles) do
    local a = noise(p.x * 0.005, p.y * 0.005, frameCount * 0.004) * TWO_PI * 2
    local nx, ny = p.x + cos(a) * 2, p.y + sin(a) * 2
    line(p.x, p.y, nx, ny)
    p.x, p.y = nx, ny
    if p.x < 0 or p.x > width or p.y < 0 or p.y > height then
      p.x, p.y = random(width), random(height)
    end
  end
end
