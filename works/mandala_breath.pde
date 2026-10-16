// 呼吸する曼荼羅 (Breathing Mandala) / by Claude
// frameCount だけで絵が決まるので「連続動作」0（独立）でも 1 でも同じ絵になる。
// おすすめ: 幅 640 / 縦 360。TRANSPARENT を true にすると背景が透明になり、下の映像に光として重なる。

int PETALS = 12;      // 対称の数
int RINGS = 7;        // 花弁の層
boolean TRANSPARENT = false;

void setup() {
  colorMode(HSB, 360, 100, 100, 100);
}

// 1 枚の花弁（原点から外へ伸びる、ベジェの葉形）
void petal(float s, float len, float w, float bend) {
  translate(0, -s);   // 中心から少し離して始める（中心が白飛びしないように）
  beginShape();
  vertex(0, 0);
  bezierVertex(w + bend, -len * 0.30, w * 0.6 + bend, -len * 0.80, bend * 0.5, -len);
  bezierVertex(-w * 0.6 + bend, -len * 0.80, -w + bend, -len * 0.30, 0, 0);
  endShape(CLOSE);
  translate(0, s);
}

void draw() {
  if (TRANSPARENT) {
    clear();
  } else {
    background(232, 70, 9);
  }
  float t = frameCount / 60.0;
  float breath = 0.5 + 0.5 * sin(t * 1.3);     // 0..1 の呼吸
  float R = min(width, height) * 0.46;

  translate(width / 2, height / 2);
  blendMode(ADD);
  noStroke();

  // 外側の層から順に
  for (int r = RINGS - 1; r >= 0; r--) {
    float k = (r + 1) / (float) RINGS;             // 0..1 (外ほど 1)
    float n = noise(r * 0.7, t * 0.4);
    float len = R * k * (0.65 + 0.35 * breath) * (0.8 + 0.4 * n);
    float w = len * (0.22 + 0.10 * sin(t * 2 + r));
    float bend = len * 0.18 * sin(t * 0.9 + r * 0.8);
    float hue = (200 + r * 22 + t * 25) % 360;
    float spin = t * 0.15 * ((r % 2 == 0) ? 1 : -1) + r * PI / PETALS;

    pushMatrix();
    rotate(spin);
    for (int i = 0; i < PETALS; i++) {
      fill(hue, 80 - r * 4, 8 + 20 * k, 60);
      petal(R * 0.07, len, w, bend);
      rotate(TWO_PI / PETALS);
    }
    popMatrix();
  }

  // 細い光の筋
  strokeWeight(0.8);
  for (int i = 0; i < PETALS * 2; i++) {
    float a = TWO_PI * i / (PETALS * 2) - t * 0.05;
    float l = R * (0.75 + 0.25 * noise(i * 0.3, t * 0.5));
    stroke(190, 40, 30, 50);
    line(cos(a) * R * 0.12, sin(a) * R * 0.12, cos(a) * l, sin(a) * l);
  }
  noStroke();

  // 花芯：脈打つ点の輪
  for (int j = 0; j < 3; j++) {
    float rr = R * (0.06 + j * 0.05) * (0.8 + 0.4 * breath);
    int dots = 6 + j * 6;
    for (int i = 0; i < dots; i++) {
      float a = TWO_PI * i / dots + t * (j % 2 == 0 ? 0.6 : -0.6);
      fill((40 + j * 15 + t * 25) % 360, 50, 90, 60);
      circle(cos(a) * rr, sin(a) * rr, 3 + 2 * breath + j);
    }
  }
  fill(45, 20, 100, 80);
  circle(0, 0, 6 + 6 * breath);

  blendMode(BLEND);
}
