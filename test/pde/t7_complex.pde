/* よくある書き方の詰め合わせ
   複数行コメント */
final int N = 12;
float[] xs = new float[N];
String[] words = {"red", "green", "blue"};
color[] palette = {#FF0000, #00FF00, #0000FF};
boolean[] flags = new boolean[3];
HashMap<String, Integer> scores = new HashMap<String, Integer>();
IntList nums = new IntList();
Mover m;
int depthCount = 0;

class Mover {
  PVector location, velocity, acceleration;
  float topspeed = 4;
  Mover() {
    location = new PVector(width / 2, height / 2);
    velocity = new PVector(0, 0);
    acceleration = new PVector(0, 0);
  }
  void update(PVector target) {
    PVector dir = PVector.sub(target, location);
    dir.normalize();
    dir.mult(0.5);
    acceleration = dir;
    velocity.add(acceleration);
    velocity.limit(topspeed);
    location.add(velocity);
  }
  PVector getLoc() { return location; }
}

void branch(float len) {
  depthCount++;
  line(0, 0, 0, -len);
  translate(0, -len);
  if (len > 8) {
    pushMatrix();
    rotate(PI / 6);
    branch(len * 0.67);
    popMatrix();
    pushMatrix();
    rotate(-PI / 6);
    branch(len * 0.67);
    popMatrix();
  }
}

void setup() {
  size(200, 150);
  for (int i = 0; i < xs.length; i++) xs[i] = i * 10;
  scores.put("a", 1);
  scores.put("b", 2);
  nums.append(5); nums.append(7);
  m = new Mover();
}

void keyPressed() { println("never"); }

void draw() {
  background(255);
  // 地形
  noStroke();
  fill(lerpColor(palette[0], palette[2], 0.5));
  beginShape();
  vertex(0, height);
  for (int x = 0; x <= width; x += 10) {
    vertex(x, height - 30 - noise(x * 0.02) * 40);
  }
  vertex(width, height);
  endShape(CLOSE);
  // 木
  stroke(60, 40, 20);
  strokeWeight(2);
  depthCount = 0;
  pushMatrix();
  translate(50, height);
  branch(35);
  popMatrix();
  // 追いかける点
  m.update(new PVector(150, 30));
  fill(palette[frameCount % palette.length]);
  noStroke();
  ellipse(m.getLoc().x, m.getLoc().y, 12, 12);

  int total = 0;
  for (String k : scores.keySet()) total += scores.get(k);
  for (int i = 0; i < nums.size(); i++) total += nums.get(i);
  xs[3] += 0.5;
  char c = 'A';
  String s = "" + c + words.length;
  float ratio = (float) 3 / 4;
  int wrap = (width + 5) % width;
  int sgn = -abs(-4);
  String kind = total > 100 ? "big" : total > 10 ? "mid" : "small";
  if (!flags[0]) flags[1] = true;
  textAlign(CENTER, CENTER);
  fill(0);
  textSize(10);
  text(words[1], width / 2, 10);
  RESULT = total + " " + xs[3] + " " + s + " " + ratio + " " + wrap + " " + sgn + " " + kind
    + " " + flags[1] + " " + depthCount + " " + N + " " + nf(m.velocity.mag(), 1, 2);
}
