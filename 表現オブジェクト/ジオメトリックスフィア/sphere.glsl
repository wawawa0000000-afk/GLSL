// ============================================================
//  Random Point Cluster "Skeleton" - GLSL Shaders
//  (WebGL2 / GLSL ES 3.00)
//
//  クラスターの中心のまわりにランダムに散らばる点の集まりを、
//  それぞれ独自のノイズパラメータで有機的に変形させる。
//  点同士は「今この瞬間、実際に近づいている」ときだけ
//  (JS側の動的な距離判定によって)線で繋がる。
// ============================================================
//
// このファイルには頂点シェーダーとフラグメントシェーダーの
// 2つをまとめて記述しています。index.html 側で下にある
// VERTEXマーカー行 と FRAGMENTマーカー行 を目印にテキストを
// 分割し、それぞれ個別にコンパイルして使用します(このコメント
// ブロックや区切り行はJS側で取り除かれるため、GPUのシェーダー
// コンパイラには渡りません)。
//
// 全クラスターの点を1つの頂点バッファにまとめ、点ごとの
// 中心位置・半径・ノイズの種/強さ/粗さを頂点属性として渡す
// ことで、1回の描画で点ごとに異なる変形をさせています。
//
//   - uMode = 0 : gl.LINES  で"今つながっている"点同士を結ぶ線
//   - uMode = 1 : gl.POINTS で点をグロー付きの点として描画
//                 (aBridge = 1.0 の点は接続中として強調表示)
//
// 見やすさのため、点の大きさはノイズや接続状態で変動させず、
// カメラからの距離による自然な遠近感だけで決まる一定サイズに
// 統一している(uPointSize を参照)。
// ============================================================

// ---VERTEX---
#version 300 es

in vec3  aPosition; // クラスター中心から見た、この点のランダムな方向ベクトル
in vec3  aCenter;   // この点が属するクラスターの中心位置(ワールド座標)
in vec3  aSeed;     // クラスターごとに異なるノイズの"種"
in vec4  aParams;   // x: 中心からの距離(半径)  y: 変形の強さ(個別)  z: ノイズの粗さ(個別)  w: ジッター種
in float aBridge;   // 1.0 = 他の点と現在つながっている接続点

uniform mat4  uProjectionMatrix;
uniform mat4  uModelViewMatrix;
uniform float uTime;
uniform float uAmpMultiplier;  // 全体の変形強さ倍率(スライダーで操作)
uniform float uFreqMultiplier; // 全体のノイズ粗さ倍率(スライダーで操作)
uniform float uSpikiness;      // 追加のランダムな"暴れ"(カオス度)
uniform float uPulse;          // 形状を再生成した瞬間の演出用パルス(1→0)
uniform float uPointSize;

out float vDisplacement;
out float vBridge;
out vec3  vViewPosition;

// ---- 3D Simplex Noise (Ashima Arts / Ian McEwan, MIT License) ----
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289(((x * 34.0) + 1.0) * x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
    const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
    const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

    vec3 i  = floor(v + dot(v, C.yyy));
    vec3 x0 = v - i + dot(i, C.xxx);

    vec3 g = step(x0.yzx, x0.xyz);
    vec3 l = 1.0 - g;
    vec3 i1 = min(g.xyz, l.zxy);
    vec3 i2 = max(g.xyz, l.zxy);

    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + C.yyy;
    vec3 x3 = x0 - D.yyy;

    i = mod289(i);
    vec4 p = permute(permute(permute(
              i.z + vec4(0.0, i1.z, i2.z, 1.0))
            + i.y + vec4(0.0, i1.y, i2.y, 1.0))
            + i.x + vec4(0.0, i1.x, i2.x, 1.0));

    float n_ = 0.142857142857;
    vec3 ns = n_ * D.wyz - D.xzx;

    vec4 j = p - 49.0 * floor(p * ns.z * ns.z);

    vec4 x_ = floor(j * ns.z);
    vec4 y_ = floor(j - 7.0 * x_);

    vec4 x = x_ * ns.x + ns.yyyy;
    vec4 y = y_ * ns.x + ns.yyyy;
    vec4 h = 1.0 - abs(x) - abs(y);

    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);

    vec4 s0 = floor(b0) * 2.0 + 1.0;
    vec4 s1 = floor(b1) * 2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));

    vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

    vec3 p0 = vec3(a0.xy, h.x);
    vec3 p1 = vec3(a0.zw, h.y);
    vec3 p2 = vec3(a1.xy, h.z);
    vec3 p3 = vec3(a1.zw, h.w);

    vec4 norm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;

    vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// フラクタルブラウン運動(オクターブを重ねてより有機的なノイズにする)
float fbm(vec3 p) {
    float sum = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < 4; i++) {
        sum += amp * snoise(p * freq);
        amp *= 0.5;
        freq *= 2.0;
    }
    return sum;
}

void main() {
    vec3 dir = normalize(aPosition);

    float scale = aParams.x;
    float amp   = aParams.y * uAmpMultiplier;
    float freq  = aParams.z * uFreqMultiplier;
    float jseed = aParams.w;

    // クラスターごとに異なる"種"を使うので、同じ時刻でもクラスター
    // ごとにまったく違う変形パターンになる
    vec3 samplePoint = dir * freq + aSeed;
    samplePoint += vec3(uTime * 0.10, uTime * 0.08, uTime * 0.13);
    float n = fbm(samplePoint);

    // さらに局所的でランダムな"暴れ"(鋭いスパイク状の凹凸)を加えて、
    // 滑らかなうねりだけでない、より無秩序な構造変形にする
    float turb = snoise(dir * 5.0 + aSeed * 2.3 + vec3(jseed) + uTime * 0.6);
    float spike = sign(turb) * pow(abs(turb), 3.0);
    n += spike * uSpikiness;

    float radius = scale * (1.0 + n * amp) * (1.0 + uPulse * 0.15);
    vec3 localPos = dir * radius;
    vec3 worldPos = localPos + aCenter;

    vDisplacement = n;
    vBridge = aBridge;

    vec4 viewPosition = uModelViewMatrix * vec4(worldPos, 1.0);
    vViewPosition = viewPosition.xyz;
    gl_Position = uProjectionMatrix * viewPosition;

    // 点の大きさは、ノイズによる変形量や接続状態には左右されない
    // 一定サイズにする(見やすさ優先)。カメラからの距離による
    // 自然な遠近感だけを反映する。
    float dist = max(-viewPosition.z, 0.5);
    gl_PointSize = clamp(uPointSize * (6.0 / dist), 2.0, 40.0);
}

// ---FRAGMENT---
#version 300 es
precision highp float;

in float vDisplacement;
in float vBridge;
in vec3  vViewPosition;

uniform int   uMode;      // 0 = ライン描画 / 1 = ポイント描画
uniform vec3  uColorLow;  // へこんでいる部分の色
uniform vec3  uColorHigh; // 膨らんでいる部分の色
uniform float uOpacity;
uniform float uPulse;

out vec4 outColor;

void main() {
    float t = clamp(vDisplacement * 1.4 + 0.5, 0.0, 1.0);
    vec3 baseColor = mix(uColorLow, uColorHigh, t);
    float alpha = uOpacity + uPulse * 0.25;

    if (uMode == 1) {
        // 点を円形のソフトなグローとして描画(点=ノードを強調)
        vec2 uv = gl_PointCoord * 2.0 - 1.0;
        float d = dot(uv, uv);
        if (d > 1.0) discard;
        float glow = smoothstep(1.0, 0.0, d);
        alpha *= glow;
        baseColor += vec3(glow * 0.5); // 中心を白っぽく明るくする

        // 現在つながっている接続点は暖色の輝きで際立たせる
        baseColor = mix(baseColor, vec3(1.0, 0.92, 0.7), vBridge * glow);
        alpha = max(alpha, vBridge * glow * 0.9);
    }

    outColor = vec4(baseColor, alpha);
}
