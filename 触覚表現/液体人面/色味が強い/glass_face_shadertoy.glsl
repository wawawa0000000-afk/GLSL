/*
  Glass Face — Liquid Wobble
  --------------------------
  ジオメトリ: 顔のSDF（楕円blendとsmin/smaxによる頭部造形手法）。
  元資料は Creative Commons Attribution-NonCommercial (CC BY-NC 4.0)
  の表記があったため、本シェーダーもその条件（表示・非営利）を
  継承しています。商用利用の際は元資料のライセンスを確認してください。

  マテリアル: 市松模様の背景・IOR屈折・フレネル反射・色収差・
  環境光・スペキュラ・指数フォグによる「粘性ガラス」シェーディング。

  追加: 呼吸するようなパルス、表面のドメインワープ、高周波リップルによる
  液体的な揺らぎ。

  ShaderToyの Image タブにそのまま貼り付けて実行できます。
*/

#define PI 3.14159265359

// ---------- 基本ユーティリティ ----------
void pR(inout vec2 p, float a) {
    p = cos(a)*p + sin(a)*vec2(p.y, -p.x);
}
vec2 pRi(vec2 p, float a) { pR(p, a); return p; }

float vmax(vec2 v) { return max(v.x, v.y); }
float vmax(vec3 v) { return max(max(v.x, v.y), v.z); }
float vmin(vec3 v) { return min(min(v.x, v.y), v.z); }
float vmin(vec2 v) { return min(v.x, v.y); }

float fBox(vec3 p, vec3 b) {
    vec3 d = abs(p) - b;
    return length(max(d, vec3(0.0))) + vmax(min(d, vec3(0.0)));
}
float fCorner2(vec2 p) {
    return length(max(p, vec2(0.0))) + vmax(min(p, vec2(0.0)));
}
float fDisc(vec3 p, float r) {
    float l = length(p.xz) - r;
    return l < 0.0 ? abs(p.y) : length(vec2(p.y, l));
}
float sdRoundCone(vec3 p, float r1, float r2, float h) {
    vec2 q = vec2(length(p.xz), p.y);
    float b = (r1-r2)/h;
    float a = sqrt(1.0-b*b);
    float k = dot(q, vec2(-b,a));
    if (k < 0.0) return length(q) - r1;
    if (k > a*h) return length(q - vec2(0.0,h)) - r2;
    return dot(q, vec2(a,b)) - r1;
}
float smin2(float a, float b, float r) {
    vec2 u = max(vec2(r - a, r - b), vec2(0.0));
    return max(r, min(a, b)) - length(u);
}
float smax2(float a, float b, float r) {
    vec2 u = max(vec2(r + a, r + b), vec2(0.0));
    return min(-r, max(a, b)) + length(u);
}
float smin(float a, float b, float k) {
    float f = clamp(0.5 + 0.5 * ((a - b) / k), 0.0, 1.0);
    return (1.0 - f) * a + f * b - f * (1.0 - f) * k;
}
float smax(float a, float b, float k) { return -smin(-a, -b, k); }
float smin3(float a, float b, float k) { return min(smin(a,b,k), smin2(a,b,k)); }
float smax3(float a, float b, float k) { return max(smax(a,b,k), smax2(a,b,k)); }

float ellip(vec3 p, vec3 s) {
    float r = vmin(s);
    p *= r / s;
    return length(p) - r;
}
float ellip(vec2 p, vec2 s) {
    float r = vmin(s);
    p *= r / s;
    return length(p) - r;
}

bool isEye = false;

// ---------- 頭部 SDF ----------
float mHead(vec3 p) {
    pR(p.yz, -0.1);
    p.y -= 0.11;

    vec3 pa = p;
    vec3 ps = p;
    ps.x = sqrt(ps.x * ps.x + 0.0005);
    p.x = abs(p.x);
    vec3 pp = p;

    float d = 1e12;

    p += vec3(0.0,-0.135,0.09);
    d = ellip(p, vec3(0.395, 0.385, 0.395));

    p = pp;
    p += vec3(0.0,-0.135,0.09) + vec3(0.0,0.1,0.07);
    d = smin(d, ellip(p, vec3(0.38, 0.36, 0.35)), 0.05);

    p = pp;
    p += vec3(0.0,-0.145,-0.175);
    d = smin(d, ellip(p, vec3(0.315, 0.3, 0.33)), 0.18);

    p = pp;
    pR(p.yz, -0.5);
    float bb = fBox(p, vec3(0.5,0.67,0.7));
    d = smax(d, bb, 0.2);

    p = pp;
    p += vec3(0.0,0.25,-0.13);
    d = smin(d, length(p) - 0.28, 0.1);

    p = ps;
    p += vec3(-0.15,0.13,0.06);
    d = smin(d, ellip(p, vec3(0.15,0.15,0.15)), 0.15);

    p = ps;
    p += vec3(-0.07,0.18,0.1);
    d = smin(d, length(p) - 0.2, 0.18);

    p = pp;
    p += vec3(-0.2,0.12,-0.14);
    d = smin(d, ellip(p, vec3(0.15,0.22,0.2) * 0.8), 0.15);

    p = pp;
    p += vec3(0.0,0.475,-0.16);
    pR(p.yz, 0.8);
    d = smin(d, ellip(p, vec3(0.19,0.1,0.2)), 0.1);

    p = pp;
    p += vec3(0.0,-0.0,-0.18);
    vec3 bp = p;
    float brow = length(p) - 0.36;
    p.x -= 0.37;
    brow = smax(brow, dot(p, normalize(vec3(1.0,0.2,-0.2))), 0.2);
    p = bp;
    brow = smax(brow, dot(p, normalize(vec3(0.0,0.6,1.0))) - 0.43, 0.25);
    p = bp;
    pR(p.yz, -0.5);
    float peak = -p.y - 0.165;
    peak += smoothstep(0.0, 0.2, p.x) * 0.01;
    peak -= smoothstep(0.12, 0.29, p.x) * 0.025;
    brow = smax(brow, peak, 0.07);
    p = bp;
    pR(p.yz, 0.5);
    brow = smax(brow, -p.y - 0.06, 0.15);
    d = smin(d, brow, 0.06);

    vec3 jo = vec3(-0.25,0.4,-0.07);
    p = ps + jo;
    float jaw = dot(p, normalize(vec3(1.0,-0.2,-0.05))) - 0.069;
    jaw = smax(jaw, dot(p, normalize(vec3(0.5,-0.25,0.35))) - 0.13, 0.12);
    jaw = smax(jaw, dot(p, normalize(vec3(-0.0,-1.0,-0.8))) - 0.12, 0.15);
    jaw = smax(jaw, dot(p, normalize(vec3(0.98,-1.0,0.15))) - 0.13, 0.08);
    jaw = smax(jaw, dot(p, normalize(vec3(0.6,-0.2,-0.45))) - 0.19, 0.15);
    jaw = smax(jaw, dot(p, normalize(vec3(0.5,0.1,-0.5))) - 0.26, 0.15);
    jaw = smax(jaw, dot(p, normalize(vec3(1.0,0.2,-0.3))) - 0.22, 0.15);

    p = pp;
    p += vec3(0.0,0.63,-0.2);
    pR(p.yz, 0.15);
    float cr = 0.5;
    jaw = smax(jaw, length(p.xy - vec2(0.0,cr)) - cr, 0.05);

    p = pp + jo;
    jaw = smax(jaw, dot(p, normalize(vec3(0.0,-0.4,1.0))) - 0.35, 0.1);
    jaw = smax(jaw, dot(p, normalize(vec3(0.0,1.5,2.0))) - 0.3, 0.2);
    jaw = max(jaw, length(pp + vec3(0.0,0.6,-0.3)) - 0.7);

    p = pa;
    p += vec3(0.2,0.5,-0.1);
    float jb = length(p);
    jb = smoothstep(0.0, 0.4, jb);
    float js = mix(0.0, -0.005, jb);
    jb = mix(0.01, 0.04, jb);

    d = smin(d, jaw - js, jb);

    p = pp;
    p += vec3(0.0,0.585,-0.395);
    p.x *= 0.7;
    d = smin(d, ellip(p, vec3(0.028,0.028,0.028)*1.2), 0.15);

    p = pp;
    p += vec3(0.0,0.03,-0.45);
    pR(p.yz, 3.0);
    d = smin(d, sdRoundCone(p, 0.008, 0.05, 0.18), 0.1);

    p = pp;
    p += vec3(0.0,0.06,-0.47);
    pR(p.yz, 2.77);
    d = smin(d, sdRoundCone(p, 0.005, 0.04, 0.225), 0.05);

    p = pp;
    p += vec3(-0.2,0.2,-0.28);
    pR(p.xz, 0.5);
    pR(p.yz, 0.4);
    float ch = ellip(p, vec3(0.1,0.1,0.12)*1.05);
    d = smin(d, ch, 0.1);

    p = pp;
    p += vec3(-0.26,0.02,-0.1);
    pR(p.xz, 0.13);
    pR(p.yz, 0.5);
    float temple = ellip(p, vec3(0.1,0.1,0.15));
    temple = smax(temple, p.x - 0.07, 0.1);
    d = smin(d, temple, 0.1);

    p = pp;
    p += vec3(0.0,0.2,-0.32);
    ch = ellip(p, vec3(0.1,0.08,0.1));
    d = smin(d, ch, 0.1);

    p = pp;
    p += vec3(-0.17,0.31,-0.17);
    ch = ellip(p, vec3(0.1));
    d = smin(d, ch, 0.1);

    p = pp;
    p += vec3(-0.0,0.29,-0.29);
    pR(p.yz, -0.3);
    d = smin(d, ellip(p, vec3(0.13,0.15,0.1)), 0.18);

    p = pp;
    p += vec3(0.0,0.37,-0.4);
    d = smin(d, ellip(p, vec3(0.03,0.03,0.02) * 0.5), 0.1);

    p = pp;
    p += vec3(-0.09,0.37,-0.31);
    d = smin(d, ellip(p, vec3(0.04)), 0.18);

    p = pp;
    p += vec3(0.0,0.455,-0.455);
    p.z += smoothstep(0.0, 0.2, p.x) * 0.05;
    float lb = mix(0.035, 0.03, smoothstep(0.05, 0.15, length(p)));
    vec3 ls = vec3(0.055,0.028,0.022) * 1.25;
    float w = 0.192;
    vec2 pl2 = vec2(p.x, length(p.yz * vec2(0.79,1.0)));
    float bottomlip = length(pl2 + vec2(0.0,w-ls.z)) - w;
    bottomlip = smax(bottomlip, length(pl2 - vec2(0.0,w-ls.z)) - w, 0.055);
    d = smin(d, bottomlip, lb);

    p = pp;
    p += vec3(0.0,0.38,-0.45);
    pR(p.xz, -0.3);
    ls = vec3(0.065,0.03,0.05);
    w = ls.x * (-log(ls.y/ls.x) + 1.0);
    vec3 pl = p * vec3(0.78,1.0,1.0);
    float toplip = length(pl + vec3(0.0,w-ls.y,0.0)) - w;
    toplip = smax(toplip, length(pl - vec3(0.0,w-ls.y,0.0)) - w, 0.065);
    p = pp;
    p += vec3(0.0,0.33,-0.45);
    pR(p.yz, 0.7);
    float cut;
    cut = dot(p, normalize(vec3(0.5,0.25,0.0))) - 0.056;
    float dip = smin(
        dot(p, normalize(vec3(-0.5,0.5,0.0))) + 0.005,
        dot(p, normalize(vec3(0.5,0.5,0.0))) + 0.005,
        0.025
    );
    cut = smax(cut, dip, 0.04);
    cut = smax(cut, p.x - 0.1, 0.05);
    toplip = smax(toplip, cut, 0.02);
    d = smin(d, toplip, 0.07);

    p = pp;
    p += vec3(0.0,0.425,-0.44);
    lb = length(p);
    float lr = mix(0.04, 0.02, smoothstep(0.05, 0.12, lb));
    pR(p.yz, 0.1);
    p.y -= smoothstep(0.0, 0.03, p.x) * 0.002;
    p.y += smoothstep(0.03, 0.1, p.x) * 0.007;
    p.z -= 0.133;
    float seam = fDisc(p, 0.2);
    seam = smax(seam, -d - 0.015, 0.01);
    d = mix(d, smax(d, -seam, lr), 0.65);

    p = pp;
    p += vec3(0.0,0.3,-0.43);
    d = smin(d, length(p) - 0.05, 0.07);

    p = pp;
    p += vec3(0.0,0.27,-0.52);
    pR(p.yz, 0.2);
    float nostrils = ellip(p, vec3(0.055,0.05,0.06));

    p = pp;
    p += vec3(-0.043,0.28,-0.48);
    pR(p.xy, 0.15);
    p.z *= 0.8;
    nostrils = smin(nostrils, sdRoundCone(p, 0.042, 0.0, 0.12), 0.02);
    d = smin(d, nostrils, 0.02);

    p = pp;
    p += vec3(-0.033,0.3,-0.515);
    pR(p.xz, 0.5);
    d = smax(d, -ellip(p, vec3(0.011,0.03,0.025)), 0.015);

    p = pp;
    p += vec3(-0.16,0.07,-0.34);
    float eyelids = ellip(p, vec3(0.08,0.1,0.1));

    p = pp;
    p += vec3(-0.16,0.09,-0.35);
    float eyelids2 = ellip(p, vec3(0.09,0.1,0.07));

    p = pp;
    p += vec3(-0.173,0.148,-0.43);
    p.x *= 0.97;
    float et = length(p.xy) - 0.09;

    p = pp;
    p += vec3(-0.168,0.105,-0.43);
    p.x *= 0.9;
    float eb = dot(p, normalize(vec3(-0.1,-1.0,-0.2))) + 0.001;
    eb = smin(eb, dot(p, normalize(vec3(-0.3,-1.0,0.0))) - 0.006, 0.01);
    eb = smax(eb, dot(p, normalize(vec3(0.5,-1.0,-0.5))) - 0.018, 0.05);

    float edge = max(max(eb, et), -d);

    d = smin(d, eyelids, 0.01);
    d = smin(d, eyelids2, 0.03);
    d = smax(d, -edge, 0.005);

    p = pp;
    p += vec3(-0.165,0.0715,-0.346);
    float eyeball = length(p) - 0.088;
    isEye = eyeball < d;
    d = min(d, eyeball);

    p = pp;
    p += vec3(-0.075,0.1,-0.37);
    d = min(d, length(p) - 0.05);

    p = pp;
    p += vec3(-0.405,0.12,0.10);
    pR(p.xy, -0.12);
    pR(p.xz, 0.35);
    pR(p.yz, -0.3);
    vec3 pe = p;

    float ear = p.x + smoothstep(-0.05, 0.1, p.y) * 0.015 - 0.005;
    float earback = -ear - mix(0.001, 0.025, smoothstep(0.3, -0.2, p.y));

    pR(p.xz, -0.5);
    float iear = ellip(p.zy - vec2(0.01,-0.03), vec2(0.045,0.05));
    iear = smin(iear, length(p.zy - vec2(0.04,-0.09)) - 0.02, 0.09);
    float ridge = iear;
    iear = smin(iear, length(p.zy - vec2(0.1,-0.03)) - 0.06, 0.07);
    ear = smax2(ear, -iear, 0.04);
    earback = smin(earback, iear - 0.04, 0.02);

    p = pe;
    pR(p.xz, 0.2);
    ridge = ellip(p.zy - vec2(0.01,-0.03), vec2(0.045,0.055));
    ridge = smin3(ridge, -pRi(p.zy, 0.2).x - 0.01, 0.015);
    ridge = smax3(ridge, -ellip(p.zy - vec2(-0.01,0.1), vec2(0.12,0.08)), 0.02);

    float ridger = 0.01;
    ridge = max(-ridge, ridge - ridger);
    ridge = smax2(ridge, abs(p.x) - ridger/2.0, ridger/2.0);
    ear = smin(ear, ridge, 0.045);

    p = pe;
    float outline = ellip(pRi(p.yz, 0.2), vec2(0.12,0.09));
    outline = smin(outline, ellip(p.yz + vec2(0.155,-0.02), vec2(0.035, 0.03)), 0.14);

    float eedge = p.x + smoothstep(0.2, -0.4, p.y) * 0.06 - 0.03;

    float edgeo = ellip(pRi(p.yz, 0.1), vec2(0.095,0.065));
    edgeo = smin(edgeo, length(p.zy - vec2(0.0,-0.1)) - 0.03, 0.1);
    float edgeoin = smax(abs(pRi(p.zy, 0.15).y + 0.035) - 0.01, -p.z-0.01, 0.01);
    edgeo = smax(edgeo, -edgeoin, 0.05);

    float eedent = smoothstep(-0.05, 0.05, -p.z) * smoothstep(0.06, 0.0, fCorner2(vec2(-p.z, p.y)));
    eedent += smoothstep(0.1, -0.1, -p.z) * 0.2;
    eedent += smoothstep(0.1, -0.1, p.y) * smoothstep(-0.03, 0.0, p.z) * 0.3;
    eedent = min(eedent, 1.0);

    eedge += eedent * 0.06;
    eedge = smax(eedge, -edgeo, 0.01);
    ear = smin(ear, eedge, 0.01);
    ear = max(ear, earback);
    ear = smax2(ear, outline, 0.015);
    d = smin(d, ear, 0.015);

    p = pp;
    p += vec3(-0.34,0.2,0.02);
    d = smin2(d, ellip(p, vec3(0.015,0.025,0.015)), 0.035);
    p = pp;
    p += vec3(-0.37,0.18,0.03);
    pR(p.xz, 0.5);
    pR(p.yz, -0.4);
    d = smin(d, ellip(p, vec3(0.01,0.03,0.015)), 0.015);

    return d;
}

float sstep(float t) { return sin(t * PI - PI / 2.0) * 0.5 + 0.5; }

// 液状の揺らぎ（粘性ガラス資料の waves ディストーションを流用。
// 振幅を大きくして、はっきり波打つ／ぶよぶよ動く見た目にしている）
vec3 liquidWobble(vec3 p, float t) {
    vec3 q = p;
    float w1 = sin(q.x * 3.5 + t * 1.6) * sin(q.y * 3.0 - t * 1.3) * sin(q.z * 4.0 + t * 1.1);
    float w2 = sin(q.y * 6.0 + t * 2.1) * sin(q.z * 5.0 - t * 1.7);
    float w3 = sin(q.x * 2.0 - t * 0.9) * sin(q.z * 2.5 + t * 1.2);
    vec3 n = normalize(q + 0.001);
    return n * (w1 * 0.05 + w2 * 0.025 + w3 * 0.035);
}

float map(vec3 p) {
    float scale = 1.0;

    // 固定の視点角度（回転させない）
    float ry = 0.0;
    float rx = 0.0;

    // 呼吸するような全体の脈動（液体の塊が大きく膨張収縮する感じ）
    float breathe = 1.0 + sin(iTime * 0.7) * 0.05 + sin(iTime * 1.9 + 1.0) * 0.02;
    scale *= breathe;

    pR(p.yz, rx);
    pR(p.xz, ry);
    p /= scale;

    // 表面の液体的な波打ち（座標そのものを歪ませるドメインワープ）
    p += liquidWobble(p, iTime);

    float d = mHead(p) * scale;

    // 距離場自体にも高周波の細かい波を重ねてテカり方に揺らぎを出す
    float ripple = sin(p.x * 18.0 + iTime * 2.5) * sin(p.y * 16.0 - iTime * 2.0) * sin(p.z * 20.0 + iTime * 1.8);
    d += ripple * 0.006 * scale;

    return d;
}

const int NORMAL_STEPS = 6;
vec3 calcNormal(vec3 pos) {
    vec3 eps = vec3(0.0005,0.0,0.0);
    vec3 nor = vec3(0.0);
    float invert = 1.0;
    for (int i = 0; i < NORMAL_STEPS; i++) {
        nor += map(pos + eps * invert) * eps * invert;
        eps = eps.zxy;
        invert *= -1.0;
    }
    return normalize(nor);
}

// ---------- 解析的アンチエイリアス市松模様 (Inigo Quilez の checkersGrad 手法) ----------
// floor/mod によるハードな境界だとモアレ（模様が塊に潰れる）が出るため、
// 画面空間の微分(fwidth相当)を使って境界をなめらかにする。
float checkersGrad(vec2 p) {
    vec2 ddx = dFdx(p);
    vec2 ddy = dFdy(p);
    vec2 w = max(abs(ddx), abs(ddy)) + 0.0001;
    vec2 i = 2.0 * (abs(fract((p - 0.5 * w) * 0.5) - 0.5) - abs(fract((p + 0.5 * w) * 0.5) - 0.5)) / w;
    return clamp(0.5 - 0.5 * i.x * i.y, 0.0, 1.0);
}

// ---------- 市松模様の背景（粘性ガラス資料より） ----------
vec3 checkerBg(vec2 fragCoord, float scale, float lowVal) {
    vec2 checkerUV = fragCoord / iResolution.y * scale;
    float checker = checkersGrad(checkerUV);
    return mix(vec3(1.0), vec3(lowVal), checker);
}

// 屈折方向（-1〜1程度のベクトル）から市松模様を得る。
// 解像度で拡大せず、参照プログラムと同じ「方向を直接3倍してマッピング」する方式にすることで、
// 顔のように曲率が大きい形状でもモアレを防ぐ（さらに checkersGrad でエッジをなめらかに）。
float dirChecker(vec2 dirXY, float scale) {
    vec2 uv = dirXY * 3.0 + 0.5;
    return checkersGrad(uv * scale);
}
vec3 dirCheckerColor(vec2 dirXY, float scale, float lowVal) {
    return mix(vec3(1.0), vec3(lowVal), dirChecker(dirXY, scale));
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    vec2 p = (-iResolution.xy + 2.0 * fragCoord) / iResolution.y;

    vec3 camPos = vec3(0.0,0.0,3.2);
    vec3 rayDirection = normalize(vec3(p,-4.0));

    float checkerScale = 5.5;
    vec3 backColor = checkerBg(fragCoord, checkerScale, 0.55);

    vec3 rayPosition = camPos;
    float rayLength = 0.0;
    float dist = 0.0;
    bool bg = false;

    for (int i = 0; i < 150; i++) {
        rayLength += dist;
        rayPosition = camPos + rayDirection * rayLength;
        dist = map(rayPosition);
        if (abs(dist) < 0.001) break;
        if (rayLength > 6.0) { bg = true; break; }
    }

    vec3 color = backColor;
    float t = rayLength;

    if (!bg) {
        vec3 n = calcNormal(rayPosition);
        vec3 rd = rayDirection;

        // ---------- ガラス／粘性マテリアルシェーディング（透け感を強めた版） ----------
        float ior = 1.2;
        vec3 refractedRd = refract(rd, n, 1.0 / ior);
        if (dot(refractedRd, refractedRd) < 0.0001) refractedRd = reflect(rd, n);

        // 屈折で見える市松模様はコントラストを上げて、はっきり透けて見えるようにする
        vec3 refractedBackColor = dirCheckerColor(refractedRd.xy, checkerScale, 0.12);

        vec3 glassColor = vec3(0.5, 0.6, 0.7) * 0.2;

        float fresnel = pow(1.0 - max(dot(-rd, n), 0.0), 5.0);
        vec3 reflectionColor = vec3(1.0);

        // 反射(白)の混ざる量を抑え、屈折した背景（＝透けて見える模様）を主体にする
        color = mix(refractedBackColor, reflectionColor, fresnel * 0.35);
        color = mix(color, glassColor, 0.08);

        // 色収差
        float aberration = 0.04;
        float checkR = dirChecker(refractedRd.xy + vec2(aberration, 0.0), checkerScale);
        float checkB = dirChecker(refractedRd.xy - vec2(aberration, 0.0), checkerScale);
        color.r = mix(color.r, mix(1.0, 0.12, checkR), 0.15);
        color.b = mix(color.b, mix(1.0, 0.12, checkB), 0.15);

        // 環境光（弱め。強すぎると白飛びして透明感が消える）
        vec3 ambient = vec3(0.9, 0.95, 1.0) * 0.06;
        float upLight = n.y * 0.5 + 0.5;
        ambient *= mix(0.6, 1.2, upLight);
        color += ambient;

        // スペキュラ（縁のハイライトのみ、面全体を白くしない）
        vec3 sunDir = normalize(vec3(1.0,1.0,-1.0));
        float spec = pow(max(dot(reflect(-sunDir, n), rd), 0.0), 40.0);
        color += vec3(spec) * 0.4;

        // フォグ（遠くまで届いた部分だけ、透けて見える模様側へ寄せる）
        color = mix(color, refractedBackColor, (1.0 - exp(-0.05 * t * t)) * 0.3);

        // ガンマ補正は行わない（コントラストが薄まり白っぽく見えてしまうため）
        color = clamp(color, 0.0, 1.0);
    }

    fragColor = vec4(color, 1.0);
}
