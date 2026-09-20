// 2D回転行列の生成
mat2 rot(float a) {
    float s = sin(a), c = cos(a);
    return mat2(c, s, -s, c);
}

// 空間内の各点における距離関数（Distance Field）
float map(vec3 p) {
    // 時間経過で空間を回転させる
    p.xy *= rot(iTime * 0.1);
    p.xz *= rot(iTime * 0.15);

    // トーラス（ドーナツ型）の距離計算
    vec2 q = vec2(length(p.xz) - 1.0, p.y);
    float d = length(q) - 0.5;

    // 表面を歪ませる
    float waves = sin(p.x * 4.0 + iTime)
                * sin(p.y * 3.0 + iTime)
                * sin(p.z * 5.0 + iTime);
    d += waves * 0.15;

    // 細かなザラつき
    d += sin(p.x * 20.0) * sin(p.y * 20.0) * 0.01;

    return d;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    // スクリーン座標
    vec2 uv = (fragCoord * 2.0 - iResolution.xy)
            / min(iResolution.x, iResolution.y);

    // カメラ
    vec3 ro = vec3(0.0, 0.0, -4.0);
    vec3 rd = normalize(vec3(uv, 1.5));

    //--------------------------------------------------
    // 背景（白と濃い灰色の市松模様）
    //--------------------------------------------------
    float checkerScale = 5.5;

    vec2 checkerUV = fragCoord.xy / iResolution.y * checkerScale;

    float checker = mod(
        floor(checkerUV.x) + floor(checkerUV.y),
        2.0
    );

    vec3 backColor = mix(
        vec3(1.0),
        vec3(0.55),
        checker
    );

    //--------------------------------------------------

    float d = 0.0;
    float t = 0.0;
    vec3 p = ro;

    // レイマーチング
    for(int i = 0; i < 70; i++)
    {
        p = ro + rd * t;
        d = map(p);

        if(d < 0.001 || t > 10.0)
            break;

        t += d * 0.6;
    }

    vec3 color = backColor;

    if(t < 10.0)
    {
        // 法線
        vec2 e = vec2(0.01, 0.0);

        vec3 norm = normalize(vec3(
            map(p + e.xyy) - map(p - e.xyy),
            map(p + e.yxy) - map(p - e.yxy),
            map(p + e.yyx) - map(p - e.yyx)
        ));

        //--------------------------------------------------
        // 屈折
        //--------------------------------------------------
        float ior = 1.2;

        vec3 refractedRd = refract(rd, norm, 1.0 / ior);

        // 屈折した背景も市松模様
        vec2 refrUV = refractedRd.xy * 3.0 + 0.5;

        float refrChecker = mod(
            floor(refrUV.x * checkerScale)
          + floor(refrUV.y * checkerScale),
            2.0
        );

        vec3 refractedBackColor = mix(
            vec3(1.0),
            vec3(0.55),
            refrChecker
        );

        //--------------------------------------------------
        // ガラス色
        //--------------------------------------------------
        vec3 glassColor = vec3(0.5, 0.6, 0.7) * 0.2;

        // ===== フレネル反射を追加 =====
        float fresnel = pow(
            1.0 - max(dot(-rd, norm), 0.0),
            5.0
        );

        vec3 reflectionColor = vec3(1.0);

        color = mix(
            refractedBackColor,
            reflectionColor,
            fresnel * 0.6
        );

        // ガラス色を少し乗せる
        color = mix(
            color,
            glassColor,
            0.15
        );

        //--------------------------------------------------
        // 色収差
        //--------------------------------------------------
                float aberration = 0.03;

        vec2 uvR = (refractedRd.xy + vec2(aberration, 0.0)) * 3.0 + 0.5;
        vec2 uvB = (refractedRd.xy - vec2(aberration, 0.0)) * 3.0 + 0.5;

        float checkR = mod(
            floor(uvR.x * checkerScale) +
            floor(uvR.y * checkerScale),
            2.0
        );

        float checkB = mod(
            floor(uvB.x * checkerScale) +
            floor(uvB.y * checkerScale),
            2.0
        );

        color.r = mix(
            color.r,
            mix(1.0, 0.55, checkR),
            0.15
        );

        color.b = mix(
            color.b,
            mix(1.0, 0.55, checkB),
            0.15
        );
        
        //--------------------------------------------------
        // 環境光
        //--------------------------------------------------
vec3 ambient = vec3(0.9, 0.95, 1.0) * 0.15;

float upLight = norm.y * 0.5 + 0.5;
ambient *= mix(0.6, 1.2, upLight);

color += ambient;

        //--------------------------------------------------
        // スペキュラ
        //--------------------------------------------------
        vec3 sunDir = normalize(vec3(1.0, 1.0, -1.0));

        float spec = pow(
            max(dot(reflect(-sunDir, norm), rd), 0.0),
            30.0
        );

        color += vec3(spec) * 0.5;

        //--------------------------------------------------
        // フォグ
        //--------------------------------------------------
        color = mix(
            color,
            refractedBackColor,
            1.0 - exp(-0.05 * t * t)
        );
    }

    fragColor = vec4(color, 1.0);
}