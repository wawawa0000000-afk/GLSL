// ============================================================
// 「ディミニッシュ7th（減七の和音）」— CRTエフェクト・サンプルシーン
// ============================================================
// CRT(ブラウン管)ポストプロセス（魚眼歪み／上に流れる走査線／端の黒
// グラデーション）を、回転するトーラス+床グリッドの簡単な3Dシーンに
// 適用したサンプルです。ShaderToyの新規タブにそのまま貼れば動きます。
//
// フォルダ名「ディミニッシュ7th」について：
//   減七の和音は主音を持たず、どの音にも解決しうる宙ぶらりんで
//   不安定・緊張感のある響きが特徴。CRTの歪み・チラつき・走査線が
//   生む「落ち着かない揺らぎ」の質感がこれに近いと考え命名しました。
//
// 【CRT部分の使い方（他のシーンへ移植する場合）】
//   1. crtDistort(uv, amt) をレイ方向計算前のUVに適用
//   2. 最終色に applyCRT(col, fragCoord, iResolution.xy, iTime) を適用
//   詳しくは各関数のコメントを参照。
// ============================================================

// ---------------- CRT エフェクト部分 ----------------

// 中心からの距離の2乗に比例してUVを外側に押し出す樽型(魚眼)歪み
vec2 crtDistort(vec2 uv, float distAmt) {
	float r2 = dot(uv, uv);
	return uv * (1. + distAmt * r2);
}

// 上方向に流れる横縞スキャンライン（明るさの乗算係数 0〜1）
float crtScanline(vec2 fc, float time, float freq, float speed) {
	return .82 + .18 * sin(fc.y * freq - time * speed);
}

// 画面端が黒くなるグラデーション（CRT管の湾曲・光量落ち表現）
float crtEdgeFade(vec2 fc, vec2 res, float outerR, float innerR) {
	vec2 qc = (fc / res) * 2. - 1.;
	float r = length(qc);
	return smoothstep(outerR, innerR, r);
}

// スキャンライン＋端の黒グラデーションをまとめて適用
vec3 applyCRT(vec3 col, vec2 fc, vec2 res, float time) {
	col *= crtScanline(fc, time, 1.15, 22.);
	col *= crtEdgeFade(fc, res, 1.15, .5);
	return col;
}

// ---------------- 3D シーン（レイマーチング）部分 ----------------

#define sat(x) clamp(x, 0., 1.)

// トーラス（ドーナツ型）のSDF
float sdTorus(vec3 p, vec2 t) {
	vec2 q = vec2(length(p.xz) - t.x, p.y);
	return length(q) - t.y;
}

float sdPlane(vec3 p) { return p.y + 1.2; }

// シーン全体のSDF（トーラス + 床）。x=距離, y=マテリアルID(0:床,1:トーラス)
vec2 map(vec3 p) {
	vec3 q = p;
	float a = iTime * .6;
	// トーラスをゆっくり回転
	mat2 rot = mat2(cos(a), -sin(a), sin(a), cos(a));
	q.xz = rot * q.xz;
	q.xy = mat2(cos(a * .7), -sin(a * .7), sin(a * .7), cos(a * .7)) * q.xy;

	float torus = sdTorus(q, vec2(1.0, .35));
	float plane = sdPlane(p);

	if (torus < plane) return vec2(torus, 1.);
	return vec2(plane, 0.);
}

vec3 calcNormal(vec3 p) {
	vec2 e = vec2(.001, 0);
	return normalize(vec3(
		map(p + e.xyy).x - map(p - e.xyy).x,
		map(p + e.yxy).x - map(p - e.yxy).x,
		map(p + e.yyx).x - map(p - e.yyx).x
	));
}

float softShadow(vec3 ro, vec3 rd) {
	float res = 1., t = .05;
	for (int i = 0; i < 24; i++) {
		float h = map(ro + rd * t).x;
		res = min(res, 12. * h / t);
		t += clamp(h, .02, .3);
		if (h < .001 || t > 8.) break;
	}
	return sat(res);
}

vec3 shade(vec3 p, vec3 rd, float matId) {
	vec3 n = calcNormal(p);
	vec3 lightDir = normalize(vec3(.6, .8, -.4));
	float diff = sat(dot(n, lightDir));
	float sh = softShadow(p + n * .02, lightDir);
	float spec = pow(sat(dot(reflect(-lightDir, n), -rd)), 24.);

	vec3 baseCol;
	if (matId < .5) {
		// 床：チェッカーパターン
		vec2 c = floor(p.xz * 1.5);
		float checker = mod(c.x + c.y, 2.0);
		baseCol = mix(vec3(.05, .06, .09), vec3(.15, .16, .2), checker);
	} else {
		// トーラス：青緑がかった金属っぽい色
		baseCol = vec3(.15, .65, .75);
	}

	vec3 col = baseCol * (.15 + diff * sh) + spec * sh * .8;
	return col;
}

// レイマーチングでシーンをたどり、色を返す
vec3 render(vec3 ro, vec3 rd) {
	float t = 0.;
	vec3 col = vec3(.02, .02, .04); // 背景色（暗いブラウン管の地色）

	for (int i = 0; i < 90; i++) {
		vec3 p = ro + rd * t;
		vec2 h = map(p);
		if (h.x < .001) {
			col = shade(p, rd, h.y);
			// ほのかなフォグでCRTらしい沈み込みを演出
			col = mix(col, vec3(.02, .02, .04), sat(t / 14.));
			break;
		}
		t += h.x;
		if (t > 14.) break;
	}
	return col;
}

// ---------------- mainImage ----------------

void mainImage(out vec4 fragColor, vec2 fragCoord) {
	// --- CRT歪み：レイ方向計算前のUVに適用 ---
	vec2 uv0 = (fragCoord - .5 * iResolution.xy) / iResolution.y;
	vec2 uv  = crtDistort(uv0, .35);

	// カメラ設定（固定気味に、わずかに揺れるブラウン管の据え置きカメラ風）
	vec3 ro = vec3(0., 1.4, -4.2);
	vec3 lookAt = vec3(0., .2, 0.);
	vec3 f = normalize(lookAt - ro);
	vec3 r = normalize(cross(vec3(0, 1, 0), f));
	vec3 u = cross(f, r);
	vec3 rd = normalize(f * 1.6 + r * uv.x + u * uv.y);

	vec3 col = render(ro, rd);

	// --- CRT後処理：走査線＋端の黒グラデーション ---
	col = applyCRT(col, fragCoord, iResolution.xy, iTime);

	// 軽いガンマ補正
	col = pow(max(col, 0.), vec3(.4545));

	fragColor = vec4(col, 1.);
}
