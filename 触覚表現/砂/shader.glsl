#ifdef GL_ES
precision mediump float;
#endif

// ============================================================
// 「砂」の触覚表現 - Sand (Tactile Expression)
// ------------------------------------------------------------
// ・砂丘の高さ場をレイマーチングし、細かい粒のバンプマッピングと
//   ハイライトの「きらめき」でザラザラした乾いた質感を表現。
// ・マウス（指）で押すと、その場所がじわっとへこみ、周囲がわずかに
//   盛り上がる（砂が押しのけられて堆積する）ことで「柔らかく沈み
//   込む」触感を表現する。押すのをやめるとゆっくり元に戻る。
// ============================================================

uniform float time;
uniform vec2  resolution;
uniform vec2  mouse;   // マウス/タッチ座標（ピクセル, 下原点）
uniform float press;   // 0=触れていない 〜 1=しっかり押し込んでいる（JS側で滑らかに補間）

// ---------------- ノイズ ----------------
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 x) {
    vec2 i = floor(x);
    vec2 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2(vec2 p) {
    float s = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        s += a * noise2(p);
        p = p * 2.03 + 11.7;
        a *= 0.5;
    }
    return s;
}

// ---------------- 砂丘（大局的な高さ場） ----------------
float duneHeight(vec2 p) {
    vec2 q = p + vec2(time * 0.02, 0.0); // 風でゆっくり移ろう砂丘
    float macro = fbm2(q * 0.18);
    float ridge = sin(p.x * 0.6 + macro * 3.0) * 0.5 + 0.5; // 風紋の筋
    ridge = pow(ridge, 2.0);
    return macro * 0.55 + ridge * 0.18;
}

// ---------------- 押し込みによるくぼみ ----------------
float indent(vec2 p, vec2 touch) {
    float d = length(p - touch);
    float basin = -0.5 * press * exp(-d * d * 2.2);
    float rim   =  0.12 * press * exp(-pow(d - 0.62, 2.0) * 9.0);
    return basin + rim;
}

float terrain(vec2 p, vec2 touch) {
    return duneHeight(p) + indent(p, touch);
}

void main(void) {
    vec2 uv = (gl_FragCoord.xy * 2.0 - resolution.xy) / min(resolution.x, resolution.y);

    // カメラ（少し見下ろす角度で固定）
    vec3 ro = vec3(0.0, 1.6, -3.4);
    vec3 rd = normalize(vec3(uv, 1.35));
    float ca = -0.55;
    float sa = sin(ca);
    float co = cos(ca);
    rd.yz = mat2(co, -sa, sa, co) * rd.yz;

    // マウス座標を同じカメラで飛ばし、地面(y=0近辺)との交点を「触れている場所」とする
    vec2 muv = (mouse * 2.0 - resolution.xy) / min(resolution.x, resolution.y);
    vec3 rdm = normalize(vec3(muv, 1.35));
    rdm.yz = mat2(co, -sa, sa, co) * rdm.yz;
    float tTouch = (rdm.y < -0.0001) ? (-ro.y / rdm.y) : 1000.0;
    vec2 touch = (ro + rdm * tTouch).xz;

    // 空（暖色の砂漠の空気感）
    vec3 skyTop = vec3(0.98, 0.85, 0.62);
    vec3 skyBot = vec3(1.0, 0.93, 0.78);
    vec3 col = mix(skyBot, skyTop, clamp(uv.y * 0.5 + 0.5, 0.0, 1.0));

    // 高さ場のレイマーチング
    float t = 0.1;
    vec3 p = ro;
    bool hit = false;
    for (int i = 0; i < 90; i++) {
        p = ro + rd * t;
        float h = terrain(p.xz, touch);
        float diffH = p.y - h;
        if (diffH < 0.002) { hit = true; break; }
        t += diffH * 0.55;
        if (t > 14.0) break;
    }

    if (hit) {
        vec2 e = vec2(0.03, 0.0);
        float hL = terrain(p.xz - e.xy, touch);
        float hR = terrain(p.xz + e.xy, touch);
        float hD = terrain(p.xz - e.yx, touch);
        float hU = terrain(p.xz + e.yx, touch);
        vec3 norm = normalize(vec3(hL - hR, 2.0 * e.x, hD - hU));

        // 細かい粒のバンプ（法線を高周波ノイズで揺らす）
        vec2 ge = vec2(0.006, 0.0);
        vec2 gp = p.xz * 140.0 + vec2(time * 0.6, 0.0);
        float gL = noise2(gp - ge.xy * 140.0);
        float gR = noise2(gp + ge.xy * 140.0);
        float gD = noise2(gp - ge.yx * 140.0);
        float gU = noise2(gp + ge.yx * 140.0);
        vec3 grainNorm = normalize(vec3((gL - gR) * 1.4, 1.0, (gD - gU) * 1.4));
        vec3 bumpNorm = normalize(mix(norm, normalize(norm + grainNorm * 0.6), 0.85));

        vec3 lightDir = normalize(vec3(0.55, 0.35, -0.75));
        float diff = max(dot(bumpNorm, lightDir), 0.0);
        float wrap = max(dot(norm, lightDir) * 0.5 + 0.5, 0.0);

        // くぼみの内側は湿ったように暗い色に
        float ind = indent(p.xz, touch);
        float wetMask = clamp(-ind / 0.4, 0.0, 1.0);
        vec3 dryColor = mix(vec3(0.86, 0.66, 0.40), vec3(0.96, 0.80, 0.55), wrap);
        vec3 wetColor = vec3(0.45, 0.32, 0.20);
        vec3 base = mix(dryColor, wetColor, wetMask * 0.85);

        col = base * (0.35 + diff * 0.85);

        // きらめき：微細な法線の揺らぎがハイライト方向と揃った粒だけ光る
        vec3 viewDir = -rd;
        vec3 halfDir = normalize(lightDir + viewDir);
        float sparkle = pow(max(dot(bumpNorm, halfDir), 0.0), 60.0);
        sparkle *= smoothstep(0.55, 0.95, noise2(gp * 0.64 + 4.0));
        col += vec3(1.0, 0.95, 0.8) * sparkle * 1.6;

        // 空気遠近
        col = mix(col, skyBot, 1.0 - exp(-0.045 * t * t));
    }

    gl_FragColor = vec4(col, 1.0);
}
