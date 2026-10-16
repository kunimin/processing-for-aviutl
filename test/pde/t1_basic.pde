// 基本: グローバル変数, int割り算, 文字列連結, for, if/else
int x = 0;
float speed = 2.5f;
int[] sizes = {10, 20, 30};
String label = "frame: ";

void setup() {
  size(200, 150);
  colorMode(HSB, 360, 100, 100);
}

void draw() {
  background(0);
  int half = width / 2;         // 100
  float r = 7 / 2;              // 3.0 (int割り算)
  noStroke();
  for (int i = 0; i < sizes.length; i++) {
    fill(i * 120, 80, 100);
    ellipse(half + (i - 1) * 50, height / 2, sizes[i] + r, sizes[i] + r);
  }
  x += speed;                    // int への複合代入は切り捨て
  if (x > width) {
    x = 0;
  } else if (x < 0) {
    x = width;
  } else {
    x = x;
  }
  fill(0, 0, 100);
  textSize(12);
  text(label + frameCount + " x=" + x, 5, 15);
  RESULT = half + "," + r + "," + x + "," + (10 % 3) + "," + (-7 / 2);
}
