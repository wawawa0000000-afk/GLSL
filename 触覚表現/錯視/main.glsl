// ---- カプセル(丸棒)のSDF: 2点間を結ぶだけなので回転行列が不要で安全 ----
float sdCapsule(vec3 p, vec3 a, vec3 b, float r) {
    vec3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// 正三角形の頂点(XZ平面上)
const vec2 V0 = vec2(0.0, 1.6);
const vec2 V1 = vec2(-1.3856, -0.8);
const vec2 V2 = vec2(1.3856, -0.8);

float map(vec3 p) {
    // 各辺は始点y=0 → 終点y=1.0 へ"上昇"する(この食い違いが錯視の核)
    float d0 = sdCapsule(p, vec3(V0.x, 0.0, V0.y), vec3(V1.x, 1.0, V1.y), 0.28);
    float d1 = sdCapsule(p, vec3(V1.x, 0.0, V1.y), vec3(V2.x, 1.0, V2.y), 0.28);
    float d2 = sdCapsule(p, vec3(V2.x, 0.0, V2.y), vec3(V0.x, 1.0, V0.y), 0.28);
    return min(d0, min(d1, d2));
}

vec3 calcNormal(vec3 p) {
    const float h = 0.0001;
    const vec2 k = vec2(1.0, -1.0);
    return normalize(
        k.xyy * map(p + k.xyy * h) +
        k.yyx * map(p + k.yyx * h) +
        k.yxy * map(p + k.yxy * h) +
        k.xxx * map(p + k.xxx * h)
    );
}

float rayMarch(vec3 ro, vec3 rd) {
    float t = 0.0;
    for (int i = 0; i < 100; i++) {
        vec3 p = ro + rd * t;
        float d = map(p);
        if (d < 0.001) return t;
        if (t > 50.0) break;
        t += d;
    }
    return -1.0;
}

mat3 setCamera(vec3 ro, vec3 ta, vec3 upHint) {
    vec3 cw = normalize(ta - ro);
    vec3 cu = normalize(cross(cw, upHint));
    vec3 cv = cross(cu, cw);
    return mat3(cu, cv, cw);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;

    // ---- マウス操作でカメラを軌道させる ----
    // el = 0 のとき「真上(Y軸方向)から見た正解視点」= 錯視が完成する角度
    // ドラッグして el を大きくすると視点が傾き、実際は繋がっていないことがバレる
    float az = 1.5707963;
    float el = 0.05;
    if (iMouse.z > 0.0) {
        vec2 m = iMouse.xy / iResolution.xy;
        az = m.x * 6.2831853;
        el = m.y * 1.3;
    }
    float dist = 8.0;
    vec3 ro = dist * vec3(sin(el) * cos(az), cos(el), sin(el) * sin(az));
    vec3 ta = vec3(0.0, 0.5, 0.0);
    mat3 cam = setCamera(ro, ta, vec3(0.0, 0.0, 1.0));
    // z成分を大きめにして画角を狭め、疑似的に平行投影へ近づける(軸ズレ許容度を上げる)
    vec3 rd = cam * normalize(vec3(uv, 1.8));

    vec3 col = vec3(0.05, 0.06, 0.08);

    float t = rayMarch(ro, rd);
    if (t > 0.0) {
        vec3 p = ro + rd * t;
        vec3 n = calcNormal(p);
        vec3 lightDir = normalize(vec3(0.6, 0.9, 0.4));
        float diff = clamp(dot(n, lightDir), 0.0, 1.0);
        float amb = 0.25;
        col = vec3(0.9, 0.35, 0.2) * (diff + amb);
    }

    fragColor = vec4(col, 1.0);
}