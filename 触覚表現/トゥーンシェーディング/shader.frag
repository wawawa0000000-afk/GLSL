#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 resolution;

// 3D空間の回転（ライトの円運動用）
vec3 rotateY(vec3 p, float a) {
    float s = sin(a), c = cos(a);
    return vec3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
}

// 球体のSDF（距離関数）
float map(vec3 p) {
    float sphereRadius = 0.65;
    return length(p) - sphereRadius;
}

void main(void) {
    vec2 uv = (gl_FragCoord.xy * 2.0 - resolution.xy) / min(resolution.x, resolution.y);
    
    vec3 ro = vec3(0.0, 0.0, -3.0); 
    vec3 rd = normalize(vec3(uv, 1.8));
    
    vec3 bgColor = vec3(0.75, 0.88, 0.82);
    vec3 color = bgColor;
    
    float d = 0.0;
    float t = 0.0;
    vec3 p = ro;
    
    for(int i = 0; i < 40; i++) {
        p = ro + rd * t;
        d = map(p);
        if(d < 0.001 || t > 5.0) break;
        t += d;
    }
    
    if(t < 5.0) {
        vec2 e = vec2(0.001, 0.0);
        vec3 norm = normalize(vec3(
            map(p+e.xyy) - map(p-e.xyy),
            map(p+e.yxy) - map(p-e.yxy),
            map(p+e.yyx) - map(p-e.yyx)
        ));
        
        vec3 viewDir = -rd;
        vec3 lightDir = normalize(vec3(1.0, 0.8, -1.0));
        lightDir = rotateY(lightDir, time * 1.5); 
        
        vec3 baseColor = vec3(1.0, 0.45, 0.55);
        vec3 shadowColor1 = vec3(0.7, 0.22, 0.35);
        vec3 shadowColor2 = vec3(0.4, 0.12, 0.28);
        
        float dotNL = dot(norm, lightDir);
        float halfLambert = dotNL * 0.5 + 0.5;
        
        float shadowMask1 = smoothstep(0.48, 0.495, halfLambert);
        float shadowMask2 = smoothstep(0.23, 0.245, halfLambert);
        
        vec3 diffuseComponent = mix(shadowColor1, baseColor, shadowMask1);
        diffuseComponent = mix(shadowColor2, diffuseComponent, shadowMask2);
        
        color = diffuseComponent;
        
        vec3 halfDir = normalize(lightDir + viewDir);
        float spec = pow(max(0.0, dot(norm, halfDir)), 120.0);
        float specMask = smoothstep(0.3, 0.35, spec);
        vec3 highlightColor = vec3(1.0, 0.98, 0.95);
        color = mix(color, highlightColor, specMask);
        
        float ndotv = dot(norm, viewDir);
        float outline = smoothstep(0.23, 0.25, ndotv);
        
        vec3 inkColor = vec3(0.08, 0.08, 0.15);
        color = mix(inkColor, color, outline);
    }
    
    gl_FragColor = vec4(color, 1.0);
}
