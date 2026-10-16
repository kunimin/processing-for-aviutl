// switch, while, do-while, continue, break, 三項演算子, ビット演算, 色リテラル, PVector, 2次元配列
color c1 = #FF8800;
float[][] grid = new float[3][4];
PVector pos = new PVector(10, 20);

int classify(int v) {
  switch (v) {
    case 0:
      return 100;
    case 1:
    case 2:
      return 200;
    default:
      return 300;
  }
}

String join2(String a, String b) { return a + "-" + b; }
float twice(float v) { return v * 2; }
float twice(float v, float w) { return (v + w) * 2; }

void setup() {
  size(200, 150);
}

void draw() {
  background(c1);
  int sum = 0;
  for (int i = 0; i < 10; i++) {
    if (i % 2 == 0) continue;
    if (i > 7) break;
    sum += i;               // 1+3+5+7 = 16
  }
  int k = 0;
  while (true) { k++; if (k >= 5) break; }
  int d = 0;
  do { d += 3; } while (d < 10);   // 12
  grid[1][2] = 5;
  int argb = 0xFF336699;
  int red = (argb >> 16) & 0xFF;     // 0x33 = 51
  PVector v = PVector.add(pos, new PVector(1, 1));
  v.mult(2);
  float m = v.mag();
  String s = "abc";
  boolean big = sum > 10 ? true : false;
  int sw = 0;
  for (int i = 0; i < 4; i++) {
    switch (i) {
      case 1: continue;
      case 2: sw += 10; break;
      default: sw += 1;
    }
    sw += 100;
  }
  fill(argb);
  rect(20, 20, 50, 50);
  stroke(255);
  strokeWeight(4);
  line(0, 0, width, height);
  RESULT = sum + " " + k + " " + d + " " + grid[1][2] + " " + red + " " + v.x + "," + v.y
    + " " + nf(m, 1, 2) + " " + s.length() + s.charAt(1) + s.toUpperCase() + " " + big
    + " " + classify(0) + classify(2) + classify(9) + " " + join2("a", "b") + " " + twice(3) + " " + twice(1, 2)
    + " " + (int) 3.9 + " " + int(-3.9) + " " + sw + " " + pos.x;
}
