// Aurora Weave / by Claude
// ノイズの流れ場（flow field）に沿って数千の粒子が泳ぎ、
// 加算合成で重なった軌跡がオーロラの織物のように光る。
// Processing でそのまま実行できる。AviUtl では「累積描画」オン・「連続動作」1 で使う。
// キー: s = PNG 保存, r = 描き直し（Processing のみ）

int N = 2400;
Mover[] movers = new Mover[N];
float zoff = 0;
float FADE = 1.2;     // 軌跡を消す速さ。小さいほど長く残る（0 で消えない）

class Mover {
  PVector pos, prev, vel;
  float hue;
  float speed;

  Mover() {
    reset();
  }

  void reset() {
    pos = new PVector(random(width), random(height));
    prev = pos.copy();
    vel = new PVector(0, 0);
    speed = random(1.2, 2.6);
    hue = (map(pos.y, 0, height, 150, 300) + random(-15, 15)) % 360;
  }

  void update() {
    // ノイズで決めた角度に向かってなめらかに曲がる
    float sc = 0.0022;
    float a = noise(pos.x * sc, pos.y * sc, zoff) * TWO_PI * 3;
    PVector f = PVector.fromAngle(a);
    f.mult(0.25);
    vel.add(f);
    vel.limit(speed);
    prev.set(pos);
    pos.add(vel);
    if (pos.x < 0 || pos.x > width || pos.y < 0 || pos.y > height) {
      reset();
    }
  }

  void display() {
    float h = (hue + frameCount * 0.15) % 360;
    stroke(h, 65, 100, 22);
    line(prev.x, prev.y, pos.x, pos.y);
  }
}

void setup() {
  size(1280, 720);
  colorMode(HSB, 360, 100, 100, 100);
  background(235, 60, 6);
  for (int i = 0; i < N; i++) {
    movers[i] = new Mover();
  }
}

void draw() {
  // 夜空色をうっすら重ねて古い軌跡を沈める
  blendMode(BLEND);
  noStroke();
  fill(235, 60, 6, FADE);
  rect(0, 0, width, height);

  blendMode(ADD);
  strokeWeight(1.6);
  for (int i = 0; i < N; i++) {
    movers[i].update();
    movers[i].display();
  }
  zoff += 0.0016;
}

void keyPressed() {
  if (key == 's') {
    saveFrame("aurora-####.png");
  }
  if (key == 'r') {
    noiseSeed((int) random(100000));
    background(235, 60, 6);
  }
}
