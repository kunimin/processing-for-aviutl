// 跳ねるボール（Processing の書き方そのまま）
ArrayList<Ball> balls = new ArrayList<Ball>();

class Ball {
  PVector pos, vel;
  float r;
  color c;

  Ball() {
    pos = new PVector(random(width), random(height));
    vel = PVector.random2D();
    vel.mult(random(2, 6));
    r = random(8, 24);
    c = color(random(360), 70, 100);
  }

  void update() {
    pos.add(vel);
    if (pos.x < r || pos.x > width - r) vel.x *= -1;
    if (pos.y < r || pos.y > height - r) vel.y *= -1;
    pos.x = constrain(pos.x, r, width - r);
    pos.y = constrain(pos.y, r, height - r);
  }

  void display() {
    fill(c);
    circle(pos.x, pos.y, r * 2);
  }
}

void setup() {
  colorMode(HSB, 360, 100, 100);
  for (int i = 0; i < 30; i++) {
    balls.add(new Ball());
  }
}

void draw() {
  background(230, 30, 12);
  noStroke();
  for (Ball b : balls) {
    b.update();
    b.display();
  }
  // 近いボール同士を線でつなぐ
  stroke(0, 0, 100, 90);
  strokeWeight(1.5);
  for (int i = 0; i < balls.size(); i++) {
    for (int j = i + 1; j < balls.size(); j++) {
      PVector a = balls.get(i).pos;
      PVector b = balls.get(j).pos;
      if (a.dist(b) < 90) line(a.x, a.y, b.x, b.y);
    }
  }
}
