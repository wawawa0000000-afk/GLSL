// ============================================================
// CRT (ブラウン管) ポストプロセス・エフェクト単体抽出版
// ============================================================
//
// 【内容】
//   1. crtDistort()   : 魚眼(樽型)レンズ歪み。UV座標を歪ませる。
//   2. crtScanline()  : 上方向に流れる横縞スキャンライン（明暗の増減）。
//   3. crtEdgeFade()  : 画面端が黒くなるグラデーション（CRTの湾曲部分）。
//   4. applyCRT()     : 上記2,3をまとめて色に適用するヘルパー。
//
// 【使い方】
//   ■ ステップA：レイ方向を計算する前のUVを歪ませる
//     元のコード：
//         vec2 uv = (fc - .5 * iResolution.xy) / iResolution.y;
//         vec3 rd = rayDir(ro, lookAt, uv);
//     ↓ こう変更する：
//         vec2 uv0 = (fc - .5 * iResolution.xy) / iResolution.y;
//         vec2 uv  = crtDistort(uv0, 0.35); // 第2引数=歪みの強さ
//         vec3 rd  = rayDir(ro, lookAt, uv);
//
//     ※ AA(アンチエイリアス)でサンプリングをずらす場合も、
//        ずらしたUVに対して同様に crtDistort() をかけること。
//
//   ■ ステップB：最終的な色(col)に対してスキャンライン＆端の黒を適用
//     mainImage の一番最後、fragColor に代入する直前で：
//         col = applyCRT(col, fc, iResolution.xy, iTime);
//
//   ■ 個別に使いたい場合：
//         col *= crtScanline(fc, iTime, 1.15, 22.);
//         col *= crtEdgeFade(fc, iResolution.xy, 1.15, 0.5);
//
// 【パラメータの目安】
//   crtDistort  distAmt   : 0.0=歪みなし 〜 0.5(強め)。0.2〜0.4が自然。
//   crtScanline freq       : 縞の密度。値を大きくすると縞が細かくなる。
//   crtScanline speed      : 流れる速さ。大きいほど上へ速く流れる。
//   crtEdgeFade outerR     : この半径を超えると黒(0)になる。
//   crtEdgeFade innerR     : この半径までは完全に明るい(1)まま。
// ============================================================

// 中心からの距離の2乗に比例してUVを外側に押し出す樽型(魚眼)歪み
// uv     : 中心を原点とした正規化UV（例: (fc-.5*res)/res.y）
// distAmt: 歪みの強さ（0で無効）
vec2 crtDistort(vec2 uv, float distAmt) {
	float r2 = dot(uv, uv);
	return uv * (1. + distAmt * r2);
}

// 上方向に流れる横縞スキャンライン。明るさの乗算係数(0〜1)を返す。
// fc    : フラグメント座標（fragCoordそのもの）
// time  : iTime
// freq  : 縞の密度
// speed : 流れる速さ（大きいほど上へ速く流れる）
float crtScanline(vec2 fc, float time, float freq, float speed) {
	return .82 + .18 * sin(fc.y * freq - time * speed);
}

// 画面端が黒くなるグラデーション（CRT管の湾曲・光量落ち表現）。0〜1を返す。
// fc      : フラグメント座標
// res     : iResolution.xy
// outerR  : これを超えると完全に黒(0)
// innerR  : ここまでは完全に明るい(1)
float crtEdgeFade(vec2 fc, vec2 res, float outerR, float innerR) {
	vec2 qc = (fc / res) * 2. - 1.; // -1..1 の画面座標
	float r = length(qc);
	return smoothstep(outerR, innerR, r);
}

// スキャンライン＋端の黒グラデーションをまとめて適用するヘルパー
// col  : 適用前の色
// fc   : フラグメント座標
// res  : iResolution.xy
// time : iTime
vec3 applyCRT(vec3 col, vec2 fc, vec2 res, float time) {
	col *= crtScanline(fc, time, 1.15, 22.);
	col *= crtEdgeFade(fc, res, 1.15, .5);
	return col;
}

// ============================================================
// 【最小サンプル（そのまま動く単体テスト用）】
// このシェーダー単体をShaderToyの新規タブに貼れば、
// 歪み+スキャンライン+端黒グラデーションの効果だけ確認できます。
// ============================================================
/*
void mainImage(out vec4 fragColor, vec2 fragCoord) {
	vec2 uv0 = (fragCoord - .5 * iResolution.xy) / iResolution.y;
	vec2 uv  = crtDistort(uv0, 0.35);

	// テスト用の適当な画（チェッカーパターン）
	vec3 col = vec3(step(.5, fract(uv.x * 5.)) * step(.5, fract(uv.y * 5.)));

	col = applyCRT(col, fragCoord, iResolution.xy, iTime);
	fragColor = vec4(col, 1.);
}
*/
