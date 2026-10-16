# AviUtl Processing（試作版）

無印 AviUtl 1.10 + 拡張編集 0.92 で、Processing のスケッチを描画するカスタムオブジェクトです。
Processing の `.pde` ファイルをそのまま読み込み、内部で Lua に変換して描きます。Lua で直接書くこともできます。
純 Lua で書いてあるので DLL もコンパイルも不要です。

> **重要**: 作成環境では AviUtl を動かせないため、描画は拡張編集の `obj` をまねた疑似環境で検証しています（末尾の「検証状況」を参照）。

## 1. ファイル構成

```
script/
├─ @Processing.obj           … カスタムオブジェクト本体
├─ processing.lua            … 描画ライブラリ本体
├─ processing_pde.lua        … .pde を Lua に変換する部分
├─ processing_sjis.lua       … .pde の日本語の文字列を表示するための文字コード表
└─ processing_sketches/      … スケッチ置き場
   ├─ sample_bounce.pde      … 跳ねるボール（クラスと ArrayList）
   ├─ sample_particles.pde   … 噴水（粒子の追加と削除）
   ├─ sample_tree.pde        … 揺れる木（再帰関数）
   ├─ sample_spiral.pde      … 回る四角の渦
   ├─ sample_flow.pde        … ノイズで流れる線（「累積描画」をオンにして使う）
   ├─ sample_hello.pde       … 日本語の文字
   ├─ sample_shapes.lua      … 図形の見本（Lua で書いた例）
   ├─ sample_bounce.lua      … 跳ねるボール（Lua で書いた例）
   └─ sample_noise.lua       … ノイズで流れる線（Lua で書いた例）
preview/                     … 疑似環境で描いたサンプルの画像
test/                        … 検証用の疑似 obj とテスト（AviUtl には不要）
aviutl-processing.zip        … script フォルダと README をまとめたもの
```

## 2. インストール

1. `script` フォルダの中身を、拡張編集のスクリプトが入っているフォルダ（「集中線」などの `.obj` があるフォルダ）にそのままコピーします。
2. AviUtl を起動し直します。
3. タイムラインを右クリック →「メディアオブジェクトの追加」→「カスタムオブジェクト」を追加し、種類で **Processingスケッチ** を選びます。

更新するときは、`processing.lua` や `processing_pde.lua` を差し替えたあと AviUtl を再起動してください。

## 3. 設定項目

| 項目 | 内容 |
|---|---|
| 幅 / 縦 | キャンバスの大きさ（スケッチ内の `width` / `height`）。`setup()` で `size(w, h)` を呼べばそちらが優先 |
| 乱数シード | `random()` / `noise()` のシード。同じ値なら毎回同じ絵になる |
| 開始秒 | スケッチをこの秒数だけ先に動かした状態から始める（例: `5` なら、オブジェクトの先頭が 5 秒動いたあとの絵になる）。先の計算はオブジェクトの先頭を表示したときに一度だけ行う |
| 累積描画 | チェックすると前フレームの絵の上に描き足す（`background()` を毎フレーム呼ばない作品用） |
| 参照ファイル | 設定ダイアログ右上の「参照ファイル」ボタンで、スケッチ（`.pde` か `.lua`）を選ぶ。未選択のときは `sample_bounce.pde` |

オブジェクトの X/Y/拡大率/回転/透明度などは、通常のオブジェクトと同じく描いた絵全体にかかります。

## 4. スケッチの書き方（.pde）

Processing と同じ書き方で `.pde` ファイルを書き、「参照ファイル」で選びます。Processing の IDE で作ったファイルをそのまま選んでも動きます。

```java
ArrayList<Ball> balls = new ArrayList<Ball>();

class Ball {
  PVector pos = new PVector(random(width), random(height));
  PVector vel = PVector.random2D();
  void update() {
    pos.add(vel);
    if (pos.x < 0 || pos.x > width) vel.x *= -1;
    if (pos.y < 0 || pos.y > height) vel.y *= -1;
  }
}

void setup() {
  for (int i = 0; i < 20; i++) balls.add(new Ball());
}

void draw() {
  background(0);
  for (Ball b : balls) {
    b.update();
    circle(b.pos.x, b.pos.y, 10);
  }
}
```

- 保存し直すと次の描画で自動的に読み直されます。
- 文字コードは UTF-8（Processing と同じ）でも Shift_JIS でも構いません。UTF-8 の日本語の文字列は表示用に自動で変換します。
- 画像は `.pde` と同じフォルダか、その中の `data` フォルダから読み込みます。
- エラーが起きると、オブジェクトの位置に赤い文字で「〇〇.pde の N 行目: 内容」と表示されます。

### .pde で使える書き方

| 分類 | 対応しているもの |
|---|---|
| 型 | `int` `float` `double` `long` `boolean` `char` `String` `color` `PVector` `PImage` `PFont`、配列 `int[]` `float[][]`、`ArrayList<T>` `HashMap<K,V>` `IntList` `FloatList` `StringList` |
| 文 | `if` / `else`、`for`、拡張 `for (T x : list)`、`while`、`do-while`、`switch`（フォールスルー含む）、`break`、`continue`、`return` |
| 演算 | 四則演算（`int` どうしの割り算は切り捨て）、`%`、`++` `--`、`+=` などの複合代入、`&&` `\|\|` `!`、三項演算子 `? :`、ビット演算 `& \| ^ ~ << >> >>>`、キャスト `(int)`、文字列の `+` 連結 |
| リテラル | `1.5f`、`0xFF336699`、`#FF8800`、`'a'`、`"文字列"`、配列の初期化 `{1, 2, 3}` |
| クラス | フィールド、コンストラクタ（複数、`this(...)`）、メソッド、`extends` と `super`、`static` フィールドとメソッド、`this` |
| 関数 | 自作関数、再帰、引数の数が違うオーバーロード |
| その他 | `setup` / `draw` の無い静的モードのスケッチ、`settings()`、`String` のメソッド（`length` `charAt` `substring` `indexOf` `equals` `split` など）、`Math.xxx` |

### .pde で使えないもの

- `interface`、`enum`、無名クラス、ラムダ式、クラスの中のクラス、`try` / `catch`
- 引数の数が同じで型だけ違うオーバーロード
- 式の途中の代入や `++`（例: `a[i++] = 0;`、`x = y = 0;`）。別の行に分けてください
- `import` したライブラリ、P3D、シェーダー、マウス・キーボード入力（`mousePressed()` などは呼ばれません）

## 4-2. Lua で直接書く場合

`.lua` ファイルを選ぶと Lua のスケッチとして実行します。関数名は Processing と同じです。

```lua
local x = 0

function setup()
  colorMode(HSB, 360, 100, 100)
end

function draw()
  background(0)
  noStroke()
  fill(frameCount % 360, 80, 100)
  circle(x, height / 2, 80)
  x = (x + 4) % width
end
```

| Processing | Lua で書く場合 |
|---|---|
| `void draw() { ... }` | `function draw() ... end` |
| `int x = 0;` | `local x = 0` |
| `for (int i = 0; i < 10; i++)` | `for i = 0, 9 do ... end` |
| `if (a && b \|\| !c)` | `if a and b or not c then ... end` |
| `x != y` | `x ~= y` |
| `"abc" + n` | `"abc" .. n` |
| `float[] a = new float[10]; a[0]` | `local a = {}; a[1]`（Lua の配列は 1 から） |
| `v.add(w)` | `v:add(w)`（メソッド呼び出しはコロン） |
| `PVector.add(a, b)` | `a + b`（新しいベクトルを返す。`a - b`、`a * 2` も可） |
| `color c = #FF0000;` | `local c = color("#FF0000")` または `color(255, 0, 0)` |

- `.lua` のスケッチで日本語を `text()` に使う場合は、ファイルを **Shift_JIS** で保存してください。
- `print()` / `println()` は画面には出ません。値を確認したいときは `text()` で画面に出すのが簡単です。

## 5. 使える関数

**図形**: `point` `line` `rect`（角丸可）`square` `ellipse` `circle` `arc`（`OPEN`/`CHORD`/`PIE`）`triangle` `quad` `bezier` `curve`
**自由図形**: `beginShape([POINTS|LINES|TRIANGLES|TRIANGLE_STRIP|TRIANGLE_FAN|QUADS|QUAD_STRIP])` `vertex` `bezierVertex` `quadraticVertex` `curveVertex` `endShape([CLOSE])`（凹多角形も可。穴あき `beginContour` は未対応）
**曲線計算**: `bezierPoint` `bezierTangent` `curvePoint` `curveTightness`
**色**: `background` `clear` `fill` `noFill` `stroke` `noStroke` `strokeWeight` `strokeCap` `strokeJoin` `colorMode(RGB|HSB, ...)` `color` `red` `green` `blue` `alpha` `hue` `saturation` `brightness` `lerpColor`
**モード**: `rectMode` `ellipseMode` `imageMode`（`CORNER` `CORNERS` `CENTER` `RADIUS`）、`blendMode(BLEND|ADD|SUBTRACT|MULTIPLY|SCREEN|OVERLAY|LIGHTEST|DARKEST|DIFFERENCE)`、`smooth` `noSmooth`
**変換**: `translate` `rotate` `scale` `shearX` `shearY` `applyMatrix` `resetMatrix` `push` `pop` `pushMatrix` `popMatrix` `pushStyle` `popStyle`
**文字**: `text(s, x, y [, w, h])` `textSize` `textFont(名前 | createFont(名前, サイズ))` `textAlign` `textWidth` `textAscent` `textDescent`
**画像**: `loadImage(パス)`（スケッチからの相対パス可）`image(img, x, y [, w, h])` `tint`（透明度のみ反映）`noTint`
**ピクセル**: `loadPixels` `pixels[]` `updatePixels` `get` `set` `filter(BLUR|GRAY|INVERT|THRESHOLD|POSTERIZE)`、補助関数 `pixelColor(数値)` `colorPixel(color)`
**乱数・ノイズ**: `random` `randomSeed` `randomGaussian` `noise` `noiseSeed` `noiseDetail`
**数学**: `map` `lerp` `norm` `constrain` `dist` `mag` `sq` `sqrt` `abs` `floor` `ceil` `round` `int` `min` `max` `pow` `exp` `log` `sin` `cos` `tan` `asin` `acos` `atan` `atan2` `radians` `degrees` `nf` `str`
**ベクトル**: `createVector(x, y)` / `PVector(x, y)`、メソッド `add` `sub` `mult` `div` `mag` `magSq` `normalize` `setMag` `limit` `heading` `rotate` `dot` `cross` `dist` `lerp` `copy` `set`、`PVector.fromAngle` `PVector.random2D` `PVector.angleBetween`
**変数・定数**: `width` `height` `frameCount`（1 から）`time`（秒）`fps` `PI` `TWO_PI` `TAU` `HALF_PI` `QUARTER_PI`
**その他**: `size` `noLoop` `loop` `millis`

### Processing との動作の違い

- 背景の初期値は **透明** です（Processing は灰色）。下のレイヤーと重ねられます。
- `frameRate()` は何もしません。速さは AviUtl のプロジェクトのフレームレートで決まります（`fps` で取得可）。
- マウス・キーボード入力は使えません（`mouseX` などは常に 0）。
- P3D の 3D、シェーダー、Java のクラスやライブラリは対象外です。
- `random()` / `noise()` は Processing とは別の実装なので、同じシードでも Processing と同じ値にはなりません。

## 6. 動作モードと速さ

AviUtl は好きなフレームに飛んで描画するので、Processing のように「前のフレームの続き」を作るために次の動きをします。

- **連続モードで次のフレームへ進んだとき**: 前のフレームの状態から `draw()` を1回だけ呼ぶので速いです。
- **シークしたとき / スケッチを書き換えたとき**: `setup()` からそのフレームまで `draw()` を全部呼び直します。
  - 累積描画なし: 途中のフレームは描画せず計算だけ進めるので比較的速いです。
  - 累積描画あり: 途中のフレームもすべて描くので、後ろのフレームほど重くなります。
- 同じフレームを再描画するときは、保存してある絵をそのまま出します。
- スケッチファイルを保存し直すと、次の描画で自動的に読み直されます。`processing.lua` 自体を書き換えたときは AviUtl の再起動が必要です。

「開始秒」を大きくすると、オブジェクトの先頭を表示するときにその分の計算が入ります（累積描画ありだと途中も全部描くので重くなります）。

## 7. 仕組みと既知の制限

- すべての図形は仮想バッファ（tempbuffer）に `obj.load("figure", "円")` で作った単色テクスチャを `obj.drawpoly` で貼って描いています。四角や線は円の中央の単色部分を使い、楕円は円のテクスチャを引き伸ばしています。
- 多角形は三角形に分けて描きます。継ぎ目が目立たないよう内側の辺だけを少し重ねていますが、実機のアンチエイリアス次第では細い線が見える可能性があります。
- 半透明の複雑な図形（多角形・丸結合の折れ線など）は、一度別の層に描いてから透明度をかけて合成するので、重なり部分が濃くならない代わりに少し重くなります。
- キャンバスは AviUtl の「システムの設定」の最大画像サイズより大きくできません。
- `loadPixels` / `updatePixels` / `filter`（BLUR 以外）は 1 ピクセルずつ Lua で処理するので、大きなキャンバスではかなり遅いです。
- `text()` のベースライン位置は文字サイズからの概算です。
- `tint()` は透明度だけが反映され、色は変わりません。

## 8. 検証状況

| 項目 | 状態 |
|---|---|
| ライブラリの文法（Lua 5.1） | 確認済み |
| 図形・線・結合・端・変換・HSB・半透明の描画結果 | 疑似 `obj`（自作のソフトウェアラスタライザ）で画像を出して目視確認済み |
| 連続モードで順に進めた絵と、シークした絵が一致するか | 疑似環境で一致を確認（ずれ 0） |
| 累積描画の順送り／シークの一致 | 疑似環境で一致を確認 |
| `@Processing.obj` からの呼び出し、エラー表示 | 疑似環境で確認 |
| `.pde` の変換（クラス、継承、ArrayList、HashMap、switch、continue、整数の割り算、ビット演算、静的モード、エラー行番号など） | テスト用スケッチ7本で、計算結果と描画を疑似環境で確認済み |
| `.pde` のサンプル6本 | 疑似環境で描画を確認済み（preview/pde_samples.png） |
| 実際の AviUtl / 拡張編集での動作 | Lua 版は動作報告あり。**`.pde` 版は未確認** |
| `text()` の見た目、`image()`、`filter(BLUR)`、`get/set/pixels` の実機での挙動 | **未確認**（疑似環境では文字や画像を仮の模様で代用） |
| 実機での速度 | **未確認** |

実機で試して表示がおかしい場合は、どのスケッチでどう見えたか（スクリーンショットがあれば一番助かります）を教えてください。
