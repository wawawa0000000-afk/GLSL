#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 resolution;

// 3D空間の回転
mat2 rot(float a) {
    float s = sin(a), c = cos(a);
    return mat2(c, s, -s, c);
}

// 塊の定義（変形トーラス）
float map(vec3 p) {
    p.xy *= rot(time * 0.1); 
    p.xz *= rot(time * 0.15);
    
    vec2 q = vec2(length(p.xz) - 1.0, p.y);
    float d = length(q) - 0.5;
    
    // 表面のねっとりとした波
    float waves = sin(p.x * 4.0 + time) * sin(p.y * 3.0 + time) * sin(p.z * 5.0 + time);
    d += waves * 0.15;
    
    // 微細なザラつき（密度の表現）
    d += sin(p.x * 20.0) * sin(p.y * 20.0) * 0.01;

    return d;
}

void main(void) {
    vec2 uv = (gl_FragCoord.xy * 2.0 - resolution.xy) / min(resolution.x, resolution.y);
    
    vec3 ro = vec3(0.0, 0.0, -4.0); // カメラ位置
    vec3 rd = normalize(vec3(uv, 1.5)); // 視線

    // 背景のグラデーション
    vec3 backColor = mix(vec3(0.01, 0.02, 0.05), vec3(0.08, 0.1, 0.2), uv.y * 0.5 + 0.5);

    float d = 0.0;
    float t = 0.0;
    vec3 p = ro;
    
    // レイマーチング
    for(int i = 0; i < 70; i++) {
        p = ro + rd * t;
        d = map(p);
        
        if(d < 0.001 || t > 10.0) break;
        t += d * 0.6;
    }

    vec3 color = backColor;

    if(t < 10.0) {
        // 法線の計算
        vec2 e = vec2(0.01, 0.0);
        vec3 norm = normalize(vec3(
            map(p+e.xyy) - map(p-e.xyy),
            map(p+e.yxy) - map(p-e.yxy),
            map(p+e.yyx) - map(p-e.yyx)
        ));
        
        // 屈折
        float refractionStrength = 1.2; 
        vec3 refractedRd = refract(rd, norm, 1.0 / refractionStrength);
        
        vec2 refractedUv = refractedRd.xy;
        vec3 refractedBackColor = mix(vec3(1.0,1.0,1.0), vec3(0.4, 0.6, 0.7), refractedUv.y * 1.0 + 0.5);
        
        vec3 glassColor = vec3(0.5, 0.6, 0.7) * 0.2;
        color = mix(glassColor, refractedBackColor, 0.8);
        
        // 色収差（RGBをわずかにズラす）
        float abberation = 0.05;
        color.r = mix(glassColor.r, mix(vec3(0.0), vec3(0.2, 0.4, 0.7), (refractedRd.xy + abberation).y).r, 0.8);
        color.b = mix(glassColor.b, mix(vec3(0.0), vec3(0.2, 0.4, 0.7), (refractedRd.xy - abberation).y).b, 0.8);

        // スペキュラ（ハイライト）
        vec3 sunDir = normalize(vec3(1.0, 1.0, -1.0));
        float spec = pow(max(0.0, dot(reflect(-sunDir, norm), rd)), 30.0);
        color += vec3(spec) * 0.5;
        
        // フォグ（奥への自然な減衰）
        color = mix(color, refractedBackColor, 1.0 - exp(-0.05 * t * t));
    }

    gl_FragColor = vec4(color, 1.0);
}
