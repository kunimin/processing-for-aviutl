-- 図形の見本（draw のたびに少しずつ回転する）
function setup()
  colorMode(HSB, 360, 100, 100)
end

function draw()
  background(220, 20, 15)

  -- 基本図形
  strokeWeight(4)
  stroke(0, 0, 100)
  fill(0, 80, 95)
  rect(30, 30, 100, 70)
  fill(40, 80, 95)
  rect(150, 30, 100, 70, 16)            -- 角丸
  fill(120, 70, 80)
  ellipse(330, 65, 110, 70)
  fill(200, 70, 90)
  circle(440, 65, 70)
  fill(280, 60, 90)
  triangle(500, 100, 550, 30, 600, 100)

  -- 線と端の形
  strokeWeight(12)
  stroke(50, 90, 100)
  strokeCap(ROUND);   line(40, 140, 160, 140)
  strokeCap(SQUARE);  line(40, 170, 160, 170)
  strokeCap(PROJECT); line(40, 200, 160, 200)
  strokeCap(ROUND)

  -- 円弧
  strokeWeight(3)
  stroke(0, 0, 100)
  fill(330, 70, 95)
  arc(250, 175, 90, 90, 0, PI + QUARTER_PI, PIE)
  noFill()
  arc(350, 175, 90, 90, 0, PI + QUARTER_PI, OPEN)

  -- beginShape と曲線
  fill(180, 60, 90, 180)
  stroke(0, 0, 100)
  strokeWeight(2)
  beginShape()
  vertex(420, 140)
  bezierVertex(480, 110, 560, 150, 600, 200)
  vertex(560, 230)
  vertex(470, 210)
  vertex(500, 180)
  endShape(CLOSE)

  -- 星（凹多角形）を回転
  push()
  translate(90, 290)
  rotate(frameCount * 0.03)
  fill(55, 90, 100)
  noStroke()
  beginShape()
  for i = 0, 9 do
    local r = (i % 2 == 0) and 50 or 22
    local a = i * TWO_PI / 10 - HALF_PI
    vertex(cos(a) * r, sin(a) * r)
  end
  endShape(CLOSE)
  pop()

  -- 半透明の重ね
  noStroke()
  fill(0, 90, 100, 140);   circle(230, 300, 80)
  fill(120, 90, 100, 140); circle(270, 300, 80)
  fill(240, 90, 100, 140); circle(250, 265, 80)

  -- 文字
  fill(0, 0, 100)
  textSize(28)
  textAlign(LEFT, BASELINE)
  text("Processing on AviUtl", 340, 300)
  textSize(16)
  text("frame " .. frameCount, 340, 330)
end
