// 風に揺れる木（再帰関数）
float sway;

void setup() {
}

void draw() {
  background(210, 230, 255);
  sway = sin(frameCount * 0.04) * 0.15;
  stroke(70, 45, 25);
  translate(width / 2, height);
  branch(height * 0.3, 10);
}

void branch(float len, float weight) {
  strokeWeight(weight);
  line(0, 0, 0, -len);
  translate(0, -len);
  if (len > 6) {
    pushMatrix();
    rotate(PI / 7 + sway);
    branch(len * 0.7, weight * 0.7);
    popMatrix();
    pushMatrix();
    rotate(-PI / 6 + sway);
    branch(len * 0.68, weight * 0.7);
    popMatrix();
  } else {
    noStroke();
    fill(80, 170, 90, 200);
    ellipse(0, 0, 10, 10);
    stroke(70, 45, 25);
  }
}
