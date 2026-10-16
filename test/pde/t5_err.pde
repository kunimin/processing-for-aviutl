void setup() {
  size(100, 100);
}

void draw() {
  int[] a = new int[3];
  a[1] = 5;
  Ball b = null;
  b.move();
}
class Ball { void move() {} }
