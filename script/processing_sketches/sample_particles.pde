// 噴水（粒子を ArrayList で管理。「連続動作」1 で使う）
ArrayList<Particle> ps = new ArrayList<Particle>();

class Particle {
  PVector pos, vel;
  float life = 90;
  float hue;

  Particle(float x, float y, float h) {
    pos = new PVector(x, y);
    vel = PVector.fromAngle(-HALF_PI + random(-0.35, 0.35));
    vel.mult(random(6, 10));
    hue = h;
  }

  void update() {
    vel.y += 0.18;   // 重力
    pos.add(vel);
    life--;
  }

  boolean isDead() {
    return life <= 0 || pos.y > height;
  }

  void display() {
    fill(hue, 60, 100, 255 * life / 90);
    circle(pos.x, pos.y, 8);
  }
}

void setup() {
  colorMode(HSB, 360, 100, 100, 255);
}

void draw() {
  background(250, 40, 8);
  for (int i = 0; i < 4; i++) {
    ps.add(new Particle(width / 2, height - 20, (frameCount * 3) % 360));
  }
  noStroke();
  for (int i = ps.size() - 1; i >= 0; i--) {
    Particle p = ps.get(i);
    p.update();
    if (p.isDead()) {
      ps.remove(i);
    } else {
      p.display();
    }
  }
}
