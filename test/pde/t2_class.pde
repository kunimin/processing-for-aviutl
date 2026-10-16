// クラス, ArrayList, 拡張for, 継承, オーバーロード, static
ArrayList<Ball> balls = new ArrayList<Ball>();

class Ball {
  float x, y, vx, vy;
  float r = 8;
  static int count = 0;

  Ball(float x, float y) {
    this.x = x;
    this.y = y;
    vx = random(-2, 2);
    vy = random(-2, 2);
    count++;
  }

  Ball() {
    this(0, 0);
  }

  void move() {
    x += vx;
    y += vy;
    if (x < r || x > width - r) vx = -vx;
    if (y < r || y > height - r) vy *= -1;
  }

  void display() {
    ellipse(x, y, r * 2, r * 2);
  }
}

class BigBall extends Ball {
  BigBall(float x, float y) {
    super(x, y);
    r = 16;
  }
  void display() {
    fill(255, 0, 0);
    super.display();
  }
}

void setup() {
  size(200, 150);
  for (int i = 0; i < 5; i++) {
    balls.add(new Ball(random(20, 180), random(20, 130)));
  }
  balls.add(new BigBall(100, 75));
}

void draw() {
  background(30);
  noStroke();
  for (Ball b : balls) {
    fill(255);
    b.move();
    b.display();
  }
  for (int i = balls.size() - 1; i >= 0; i--) {
    Ball b = balls.get(i);
    if (b.r > 100) balls.remove(i);
  }
  RESULT = "n=" + balls.size() + " count=" + Ball.count;
}
