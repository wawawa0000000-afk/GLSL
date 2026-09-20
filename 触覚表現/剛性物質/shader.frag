#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 resolution;

mat2 rot(float a) {
    float s = sin(a), c = cos(a);
    return mat2(c, s, -s, c);
}

float sdRigidBox(vec3 p, vec3 size) {
    vec3 d = abs(p) - size;
    float box1 = min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0));
    
    vec3 pCut = p;
    pCut.xz *= rot(0.785398);
    vec3 dCut = abs(pCut) - size * 1.12;
    float box2 = min(max(dCut.x, max(dCut.y, dCut.z)), 0.0) + length(max(dCut, 0.0));
    
    return max(box1, box2) - 0.01;
}

float map(vec3 p) {
    p.xz *= rot(time * 0.5);
    p.yz *= rot(time * 0.3);
    return sdRigidBox(p, vec3(0.42));
}

vec3 getMetallicEnv(vec3 rd) {
    vec3 color = mix(vec3(0.03, 0.05, 0.1), vec3(0.12, 0.15, 0.22), rd.y * 0.5 + 0.5);
    float stripe1 = step(0.94, cos(rd.x * 5.0 + rd.y * 2.0));
    float stripe2 = step(0.96, sin(rd.z * 6.0 - rd.y * 3.0));
    color += vec3(stripe1 * 0.6) + vec3(stripe2 * 0.4);
    return color;
}

void main(void) {
    vec2 uv = (gl_FragCoord.xy * 2.0 - resolution.xy) / min(resolution.x, resolution.y);
    
    vec3 ro = vec3(0.0, 0.6, -2.5); 
    vec3 rd = normalize(vec3(uv, 1.4));
    rd.yz *= rot(-0.2);
    
    vec3 color = getMetallicEnv(rd) + vec3(smoothstep(0.7, 0.0, length(uv)) * 0.12);
    
    float d = 0.0;
    float t = 0.0;
    vec3 p = ro;
    
    for(int i = 0; i < 75; i++) {
        p = ro + rd * t;
        d = map(p);
        if(d < 0.0005 || t > 6.0) break;
        t += d;
    }
    
    if(t < 6.0) {
        vec2 e = vec2(0.001, 0.0);
        vec3 norm = normalize(vec3(
            map(p+e.xyy) - map(p-e.xyy),
            map(p+e.yxy) - map(p-e.yxy),
            map(p+e.yyx) - map(p-e.yyx)
        ));
        
        vec3 viewDir = -rd;
        vec3 refDir = reflect(rd, norm);
        vec3 reflectionColor = getMetallicEnv(refDir);
        
        vec3 lightDir = normalize(vec3(1.5, 3.5, -2.0));
        float dotNL = dot(norm, lightDir);
        float diffuseStep = step(0.0, dotNL) * 0.5 + 0.35;
        
        vec3 chromeMetal = vec3(0.9, 0.92, 0.96);
        vec3 surfaceColor = mix(reflectionColor, chromeMetal, 0.4) * diffuseStep;
        
        float spec = pow(max(0.0, dot(reflect(-lightDir, norm), viewDir)), 300.0);
        surfaceColor += vec3(smoothstep(0.3, 0.35, spec) * 0.6);
        
        float ndotv = dot(norm, viewDir);
        float outlineMask = smoothstep(0.24, 0.26, ndotv);
        vec3 inkLineColor = vec3(0.02, 0.03, 0.06);
        
        color = mix(inkLineColor, surfaceColor, outlineMask);
    }
    
    gl_FragColor = vec4(color, 1.0);
}
