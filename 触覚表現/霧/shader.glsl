#ifdef GL_ES
precision mediump float;
#endif

// ============================================================
// 「霧」の触覚表現 - Fog / Mist (Tactile Expression)
// ------------------------------------------------------------
// ・3Dのノイズ密度場をレイマーチングし、光の透過率・散乱量を積分
//   するボリューメトリックフォグ。実体を持たない「触れられない」
//   質感を、厚み・霞み・木漏れ日のような光の筋で表現する。
// ・マウス（指）でなぞると、その軌跡の中心がふっと晴れ、周囲は
//   渦を巻くようにかき乱される。触れるのをやめるとゆっくり元の
//   均一な霧に戻る（disturb を時間経過で減衰させる）。
// ============================================================

uniform float time;
uniform vec2  resolution;
uniform vec2  mouse;    // マウス/タッチ座標（ピクセル, 下原点）
uniform float disturb;  // 0=静か 〜 1=強くかき乱している（JS側で更新・減衰）

// ---------------- 3Dノイズ ----------------
float hash13(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

float noise3(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
    float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
    float nx00 = mix(n000, n100, f.x);
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);
    float nxy0 = mix(nx00, nx10, f.y);
    float nxy1 = mix(nx01, nx11, f.y);
    return mix(nxy0, nxy1, f.z);
}

float fbm3(vec3 p) {
    float s = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        s += a * noise3(p);
        p = p * 2.05 + vec3(11.0, 7.0, 5.0);
        a *= 0.5;
    }
    return s;
}

// 触れた場所を中心に空間そのものを渦状にかき乱す（ドメインワープ）
vec3 stir(vec3 p, vec3 touch) {
    vec2 d = p.xz - touch.xz;
    float r = length(d) + 0.0001;
    float falloff = disturb * exp(-r * r * 0.9);
    vec2 tangent = vec2(-d.y, d.x) / r;
    vec2 radial = d / r;
    vec2 warped = p.xz + tangent * falloff * 1.4 - radial * falloff * 0.6;
    return vec3(warped.x, p.y, warped.y);
}

float density(vec3 p, vec3 touch) {
    vec3 q = stir(p, touch);
    q += vec3(time * 0.05, -time * 0.02, time * 0.035);
    float n = fbm3(q * 0.4);
    float base = smoothstep(0.32, 0.78, n);
    float heightFalloff = smoothstep(1.8, -0.6, p.y);
    float d = base * heightFalloff;

    // 触れた中心はさっと晴れる
    vec2 dd = p.xz - touch.xz;
    float clearAmt = disturb * exp(-dot(dd, dd) * 1.6);
    d *= (1.0 - clearAmt * 0.85);
    return d;
}

void main(void) {
    vec2 uv = (gl_FragCoord.xy * 2.0 - resolution.xy) / min(resolution.x, resolution.y);

    vec3 ro = vec3(0.0, 0.5, -6.0);
    vec3 rd = normalize(vec3(uv, 1.6));
    float ca = -0.12;
    float sa = sin(ca);
    float co = cos(ca);
    rd.yz = mat2(co, -sa, sa, co) * rd.yz;

    vec3 lightDir = normalize(vec3(0.4, 0.25, 0.9));

    // マウス座標を z = 1.2 の面へ投影し、「なでる」中心点とする
    vec2 muv = (mouse * 2.0 - resolution.xy) / min(resolution.x, resolution.y);
    vec3 rdm = normalize(vec3(muv, 1.6));
    rdm.yz = mat2(co, -sa, sa, co) * rdm.yz;
    float tt = (1.2 - ro.z) / rdm.z;
    vec3 touch = ro + rdm * tt;

    // 空と沈む陽光
    float sunAmt = pow(max(dot(rd, lightDir), 0.0), 8.0);
    vec3 skyLow = vec3(0.62, 0.66, 0.72);
    vec3 skyHigh = vec3(0.30, 0.34, 0.44);
    vec3 skyCol = mix(skyLow, skyHigh, clamp(uv.y * 0.6 + 0.5, 0.0, 1.0));
    skyCol += vec3(1.0, 0.9, 0.75) * sunAmt * 0.9;

    // 地面（うっすら見える下草地、霧の向こうに沈む）
    vec3 groundColor = vec3(0.09, 0.11, 0.10);
    float tGround = (rd.y < -0.001) ? ((-1.5 - ro.y) / rd.y) : -1.0;

    float maxDist = 9.0;
    vec3 backgroundCol = skyCol;
    float hardStop = maxDist;
    if (tGround > 0.0 && tGround < maxDist) {
        backgroundCol = groundColor;
        hardStop = tGround;
    }

    // ボリューメトリックなレイマーチング（密度を積分して光の透過・散乱を求める）
    const int STEPS = 48;
    float stepSize = maxDist / float(STEPS);
    float trans = 1.0;
    vec3 scatterAccum = vec3(0.0);
    float t = 0.2;

    for (int i = 0; i < STEPS; i++) {
        if (t > hardStop) break;
        vec3 p = ro + rd * t;
        float dens = density(p, touch);
        if (dens > 0.003) {
            float ext = dens * 0.8;
            float atten = exp(-ext * stepSize);
            float sunLift = clamp(p.y * 0.3 + 0.6, 0.0, 1.0);
            vec3 litColor = mix(vec3(0.55, 0.58, 0.66), vec3(1.0, 0.93, 0.8), sunAmt * 0.6 + 0.1 * sunLift);
            scatterAccum += trans * (1.0 - atten) * litColor * dens;
            trans *= atten;
            if (trans < 0.03) break;
        }
        t += stepSize;
    }

    vec3 col = backgroundCol * trans + scatterAccum;
    gl_FragColor = vec4(col, 1.0);
}
