// ノイズで流れる線（「累積描画」にチェックを入れて使う）
int N = 300;
float[] px = new float[N];
float[] py = new float[N];

void setup() {
  background(10);
  for (int i = 0; i < N; i++) {
    px[i] = random(width);
    py[i] = random(height);
  }
}

void draw() {
  noStroke();
  fill(10, 12);              // うっすら黒を重ねて古い線を消す
  rect(0, 0, width, height);
  stroke(255, 200, 80, 120);
  strokeWeight(1.2);
  for (int i = 0; i < N; i++) {
    float a = noise(px[i] * 0.005, py[i] * 0.005, frameCount * 0.004) * TWO_PI * 2;
    float nx = px[i] + cos(a) * 2;
    float ny = py[i] + sin(a) * 2;
    line(px[i], py[i], nx, ny);
    px[i] = nx;
    py[i] = ny;
    if (px[i] < 0 || px[i] > width || py[i] < 0 || py[i] > height) {
      px[i] = random(width);
      py[i] = random(height);
    }
  }
}
