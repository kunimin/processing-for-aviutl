// 文字の表示（.pde は Processing と同じ UTF-8 のままで日本語が出せる）
String[] lines = {"こんにちは", "Processing on AviUtl", "frame "};

void draw() {
  background(255, 250, 240);
  textAlign(CENTER, CENTER);
  fill(40);
  textSize(36);
  text(lines[0], width / 2, height / 2 - 40);
  textSize(20);
  fill(200, 60, 60);
  text(lines[1], width / 2, height / 2 + 10);
  fill(120);
  textSize(16);
  text(lines[2] + frameCount, width / 2, height / 2 + 45);
  // 下に色の帯
  noStroke();
  for (int i = 0; i < 12; i++) {
    fill(lerpColor(#FF6060, #6080FF, i / 11.0));
    rect(i * width / 12.0, height - 20, width / 12.0 + 1, 20);
  }
}
