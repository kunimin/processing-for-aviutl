// 回る四角の渦（frameCount だけで決まるので「連続動作」0 でもよい）
void setup() {
  colorMode(HSB, 360, 100, 100);
  rectMode(CENTER);
}

void draw() {
  background(240, 40, 10);
  translate(width / 2, height / 2);
  noFill();
  strokeWeight(2);
  for (int i = 0; i < 30; i++) {
    stroke((i * 12 + frameCount * 2) % 360, 70, 100);
    pushMatrix();
    rotate(frameCount * 0.01 + i * 0.12);
    float s = 20 + i * 10;
    rect(0, 0, s, s);
    popMatrix();
  }
}
