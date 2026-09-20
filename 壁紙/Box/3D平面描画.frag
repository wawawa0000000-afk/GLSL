precision mediump float;
uniform float time;
uniform vec2 resolution;

// 空間の位置を回転させる関数
vec3 rotate(vec3 pos) {
    float angleX = time * 0.5;
    float angleY = time * 0.8;
    
    // X軸回転
    float sX = sin(angleX), cX = cos(angleX);
    vec3 rotatedX = vec3(pos.x, pos.y * cX - pos.z * sX, pos.y * sX + pos.z * cX);
    
    // Y軸回転
    float sY = sin(angleY), cY = cos(angleY);
    return vec3(rotatedX.x * cY + rotatedX.z * sY, rotatedX.y, -rotatedX.x * sY + rotatedX.z * cY);
}

// 物体の形状（地図）を定義する関数
float map(vec3 worldPos) {
    // 空間を回転させて物体の向きに合わせる
    vec3 localPos = rotate(worldPos);

    // Z=0の面からの距離
    float planeDist = abs(localPos.z);

    // 正方形の範囲（1.6x1.6サイズ）からはみ出ている距離
    float squareEdge = max(abs(localPos.x), abs(localPos.y)) - 0.8;

    // 面の距離と範囲を組み合わせて正方形を作る
    return max(planeDist, squareEdge);
}

void main(void) {
    // 画面中央を(0,0)とした座標系
    vec2 uv = (gl_FragCoord.xy * 2.0 - resolution) / min(resolution.x, resolution.y);

    // カメラの位置(ro)と光線の向き(rd)
    vec3 rayOrigin = vec3(0.0, 0.0, -1.5);
    vec3 rayDirection = normalize(vec3(uv,1.0));

    float totalDist = 0.0;
    float currentDist = 0.0;

    // レイマーチング：光線を13回進める
    const int maxSteps = 13;
    for(int i = 0; i < maxSteps; i++) {
        currentDist = map(rayOrigin + rayDirection * totalDist);
        totalDist += currentDist;
        if(currentDist < 0.0001 || totalDist > 10.0) break;
    }

    // 物体に衝突した場合
    if(currentDist < 0.001) {
        float brightness = exp(-totalDist * 0.2); // 距離に応じた減衰（霧）
        gl_FragColor = vec4(vec3(0.5, 0.9, 1.0) * brightness, 1.0);
    } else {
        gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0); // 背景は黒
    }
}