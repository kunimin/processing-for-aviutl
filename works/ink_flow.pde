// 墨流し (Suminagashi) / by Claude
// 和紙の上をノイズの流れに沿って墨と朱がにじんでいく。
// 「累積描画」にチェック、「連続動作」1 で使う。おすすめ: 640 x 360。

int N = 420;
float[] px = new float[N];
float[] py = new float[N];
float[] life = new float[N];
int[] kind = new int[N];     // 0 = 墨, 1 = 薄墨, 2 = 朱

void spawn(int i) {
  // 中心付近から湧き出す
  float a = random(TWO_PI);
  float r = randomGaussian() * min(width, height) * 0.12;
  px[i] = width / 2 + cos(a) * r;
  py[i] = height / 2 + sin(a) * r;
  life[i] = random(60, 220);
  float k = random(1);
  if (k < 0.08) {
    kind[i] = 2;
  } else if (k < 0.45) {
    kind[i] = 0;
  } else {
    kind[i] = 1;
  }
}

void setup() {
  background(238, 232, 218);   // 和紙
  noiseDetail(3, 0.5);
  for (int i = 0; i < N; i++) {
    spawn(i);
    life[i] = random(0, 220);
  }
}

void draw() {
  // 紙色をごくうっすら重ねて、古い線を退色させる
  noStroke();
  fill(238, 232, 218, 6);
  rect(0, 0, width, height);

  float z = frameCount * 0.003;
  for (int i = 0; i < N; i++) {
    float sc = 0.0045;
    float a = noise(px[i] * sc, py[i] * sc, z) * TWO_PI * 2.5;
    // 中心からゆるく外へ押し出す（墨が広がる感じ）
    float dx = px[i] - width / 2;
    float dy = py[i] - height / 2;
    float d = max(1, sqrt(dx * dx + dy * dy));
    float nx = px[i] + cos(a) * 1.6 + dx / d * 0.35;
    float ny = py[i] + sin(a) * 1.6 + dy / d * 0.35;

    float fade = constrain(life[i] / 60.0, 0, 1);
    if (kind[i] == 2) {
      stroke(190, 40, 30, 70 * fade);
      strokeWeight(1.6);
    } else if (kind[i] == 0) {
      stroke(20, 20, 26, 55 * fade);
      strokeWeight(1.3);
    } else {
      stroke(60, 62, 70, 22 * fade);
      strokeWeight(2.4);
    }
    line(px[i], py[i], nx, ny);
    px[i] = nx;
    py[i] = ny;
    life[i] -= 1;
    if (life[i] <= 0 || px[i] < -5 || px[i] > width + 5 || py[i] < -5 || py[i] > height + 5) {
      spawn(i);
    }
  }
}
