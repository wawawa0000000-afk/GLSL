const canvas = document.getElementById('glCanvas');
const gl = canvas.getContext('webgl');

const fragmentSource = `
precision highp float;
uniform float u_time;
uniform vec2 u_resolution;

#define g_Time u_time
#define g_TexelSize vec4(0, 0, u_resolution.x, u_resolution.y)
#define time g_Time
#define resolution g_TexelSize.zw

// ==========================================
// ユーティリティ関数
// ==========================================

// 2D回転行列の生成
mat2 rot(float a) {
    float s = sin(a), c = cos(a);
    return mat2(c, s, -s, c);
}

// ==========================================
// アニメーション設定（動きのカスタマイズ）
// ==========================================
vec3 rotate(vec3 pos, float t) {
    // ▼【調整可能】1つのアニメーション周期（秒）
    // 大きくするほど、次のアクションまでの「待機時間（停止状態）」が長くなります。
    float cycle = 1.6; 
    
    // 現在の周期における進行度（0.0 ~ 1.0）
    float phase = fract(t / cycle);
    
    // ▼【調整可能】周期内で「動いている時間」の割合 (0.0 〜 1.0)
    // 大きくする（1.0に近づける）と、ゆっくり動き続けます。
    // 小さくする（0.0に近づける）と、一瞬でシュッと動き、長くピタッと止まります。
    float moveRatio = 0.7; 
    
    // 滑らかな動き出しと停止の計算（イージング）
    float move = smoothstep(0.0, moveRatio, phase);
    
    // 累計の移動量
    float effectTime = floor(t / cycle) + move;
    
    // ▼【調整可能】回転の激しさ（移動距離）
    // 数値を大きくすると、1回のアクションでより激しく回転します。
    float speedMulti = 3.0; 
    
    // X軸、Y軸の回転量を計算
    float angleX = effectTime * 0.5 * speedMulti;
    float angleY = effectTime * 0.8 * speedMulti;
    
    vec3 p = pos;
    p.yz *= rot(angleX);
    p.xz *= rot(angleY);
    return p;
}

// ==========================================
// 形状設定（モデリング）
// ==========================================

// 骨組み（ワイヤーフレーム）を作る数式
float sdWireframeBox(vec3 p, vec3 b, float e) {
    p = abs(p) - b;
    vec3 q = abs(p + e) - e;
    return min(min(
        length(max(vec3(p.x, q.y, q.z), 0.0)) + min(max(p.x, max(q.y, q.z)), 0.0),
        length(max(vec3(q.x, p.y, q.z), 0.0)) + min(max(q.x, max(p.y, q.z)), 0.0)),
        length(max(vec3(q.x, q.y, p.z), 0.0)) + min(max(q.x, max(q.y, p.z)), 0.0));
}

// 空間全体のマップ定義
float map(vec3 worldPos, float t) {
    // 空間を回転させる
    vec3 localPos = rotate(worldPos, t);
    
    // ▼【調整可能】ボックスのサイズ
    vec3 boxSize = vec3(0.7);
    
    // ▼【調整可能】ワイヤーフレームの線の太さ
    float lineThickness = 0.015;
    
    return sdWireframeBox(localPos, boxSize, lineThickness);
}

// ==========================================
// レンダリング設定（光と影）
// ==========================================

// 表面の向き（法線）を計算
vec3 getNormal(vec3 p, float t) {
    const float e = 0.0001;
    return normalize(vec3(
        map(p + vec3(e, 0, 0), t) - map(p - vec3(e, 0, 0), t),
        map(p + vec3(0, e, 0), t) - map(p - vec3(0, e, 0), t),
        map(p + vec3(0, 0, e), t) - map(p - vec3(0, 0, e), t)
    ));
}

// 指定した時間(t)におけるシーンの明るさ（モノクロ）を計算
float renderScene(vec2 uv, float t) {
    // ▼【調整可能】カメラの位置（Z軸の数値を下げると遠ざかる）
    vec3 rayOrigin = vec3(0.0, 0.0, -3.0);
    // カメラの向きと視野角
    vec3 rayDirection = normalize(vec3(uv, 2.0)); 

    float totalDist = 0.0;
    float currentDist = 0.0;
    const int maxSteps = 64; 
    int hitStep = 0;

    // レイマーチングによる衝突判定
    for(int i = 0; i < maxSteps; i++) {
        currentDist = map(rayOrigin + rayDirection * totalDist, t);
        totalDist += currentDist;
        if(currentDist < 0.001 || totalDist > 20.0) break;
        hitStep++;
    }

    // 物体に当たった場合の色の計算
    if(currentDist < 0.001) {
        vec3 p = rayOrigin + rayDirection * totalDist;
        vec3 normal = getNormal(p, t);
        
        // ▼【調整可能】光の当たる方向
        vec3 lightDir = normalize(vec3(1.0, 1.0, -1.0));
        
        // 拡散反射、鏡面反射、グロー効果の計算
        float diff = max(dot(normal, lightDir), 0.0);
        vec3 viewDir = normalize(rayOrigin - p);
        vec3 reflectDir = reflect(-lightDir, normal);
        float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32.0);
        float glow = pow(1.0 - (float(hitStep) / float(maxSteps)), 4.0) * 2.0;
        
        // 奥行きによる減衰（奥に行くほど暗くなる）
        float attenuation = exp(-totalDist * 0.1);

        return (diff * 0.4 + spec + glow) * attenuation;
    } 
    return 0.0; // 背景は真っ黒
}

// ==========================================
// 最終出力（エフェクト合成）
// ==========================================
void main(void) {
    // 画面座標の正規化
    vec2 uv = (gl_FragCoord.xy * 2.0 - resolution) / min(resolution.x, resolution.y);

    // ▼【調整可能】RGBの色ズレ（残像）の強さ
    // 数値を大きくすると、動いた時に色がより広く分離します。0.0にすると白黒になります。
    float timeOffset = 0.045; 

    // 時間を少しずつ過去にずらして、赤・緑・青の明るさを個別に計算
    float r = renderScene(uv, time);               // 現在
    float g = renderScene(uv, time - timeOffset);        // 少し過去
    float b = renderScene(uv, time - timeOffset * 2.0);  // もっと過去

    vec3 finalColor = vec3(r, g, b);

    // ▼【調整可能】ブラウン管風の横縞（スキャンライン）
    // 現在は背景を真っ黒にするため無効化（コメントアウト）しています。
    // 復活させたい場合は、以下の2行の先頭にある「//」を消してください。
    // float scanline = sin(gl_FragCoord.y * 3.0) * 0.05;
    // finalColor -= scanline;

    gl_FragColor = vec4(finalColor, 1.0);
}
`;

// --- WebGL初期化・描画処理（以下は基本触らなくてOK） ---
const vertexSource = `
attribute vec2 position;
void main() { gl_Position = vec4(position, 0.0, 1.0); }
`;

function createShader(gl, type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    return shader;
}

const program = gl.createProgram();
gl.attachShader(program, createShader(gl, gl.VERTEX_SHADER, vertexSource));
gl.attachShader(program, createShader(gl, gl.FRAGMENT_SHADER, fragmentSource));
gl.linkProgram(program);
gl.useProgram(program);

const buffer = gl.createBuffer();
gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, -1,1, -1,1, 1,-1, 1,1]), gl.STATIC_DRAW);

const posLoc = gl.getAttribLocation(program, 'position');
gl.enableVertexAttribArray(posLoc);
gl.vertexAttribPointer(posLoc, 2, gl.FLOAT, false, 0, 0);

const timeLoc = gl.getUniformLocation(program, 'u_time');
const resLoc = gl.getUniformLocation(program, 'u_resolution');

function render(now) {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.uniform1f(timeLoc, now * 0.001);
    gl.uniform2f(resLoc, canvas.width, canvas.height);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
    requestAnimationFrame(render);
}
requestAnimationFrame(render);