#!/usr/bin/env python3
"""
model.dae (COLLADA) → shinkansen_geo.js
シーングラフのトランスフォームをすべて適用してワールド座標に展開し、
[-1, 1] に正規化した Float32Array (pos+nrm, stride=6) を base64 で出力する。
"""
import xml.etree.ElementTree as ET
import math, base64, struct, sys, os

BASE = os.path.dirname(os.path.abspath(__file__))
DAE  = os.path.join(BASE, "Shinkansen+N700", "model.dae")
OUT  = os.path.join(BASE, "shinkansen_geo.js")
NS   = '{http://www.collada.org/2005/11/COLLADASchema}'

# ── 行列演算 (行主要 4x4, COLLADA の <matrix> 形式) ──────────────────────────
def matmul(a, b):
    r = [0.0]*16
    for i in range(4):
        for j in range(4):
            for k in range(4):
                r[i*4+j] += a[i*4+k] * b[k*4+j]
    return r

IDENT = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]

def xform_pt(m, x, y, z):
    rx = m[0]*x+m[1]*y+m[2]*z+m[3]
    ry = m[4]*x+m[5]*y+m[6]*z+m[7]
    rz = m[8]*x+m[9]*y+m[10]*z+m[11]
    rw = m[12]*x+m[13]*y+m[14]*z+m[15]
    if abs(rw) > 1e-10: rx,ry,rz = rx/rw, ry/rw, rz/rw
    return rx, ry, rz

def xform_nv(m, x, y, z):
    rx = m[0]*x+m[1]*y+m[2]*z
    ry = m[4]*x+m[5]*y+m[6]*z
    rz = m[8]*x+m[9]*y+m[10]*z
    l = math.sqrt(rx*rx+ry*ry+rz*rz)
    if l > 1e-10: rx,ry,rz = rx/l, ry/l, rz/l
    return rx, ry, rz

# COLLADA Z_UP → WebGL Y_UP
def to_yup(x, y, z):
    return x, z, -y

# ── DAE パース ──────────────────────────────────────────────────────────────
print("Parsing", DAE, "...")
root = ET.parse(DAE).getroot()

# --- ジオメトリ収集 ---
# geoms[geometry_id] = { 'pos': [x,y,z,...], 'tris': [(vi,ni),...], 'nrm': [x,y,z,...] or [] }
geoms = {}

for geo in root.iter(NS+'geometry'):
    gid  = geo.get('id')
    mesh = geo.find(NS+'mesh')
    if mesh is None:
        continue

    # source id → float list
    srcs = {}
    for s in mesh.findall(NS+'source'):
        fa = s.find(NS+'float_array')
        if fa is not None and fa.text:
            srcs[s.get('id')] = list(map(float, fa.text.split()))

    # <vertices> → position source の解決
    verts_el = mesh.find(NS+'vertices')
    vid_raw  = verts_el.get('id') if verts_el is not None else None
    pos_data = []
    if verts_el is not None:
        for inp in verts_el.findall(NS+'input'):
            if inp.get('semantic') == 'POSITION':
                src_id = inp.get('source').lstrip('#')
                pos_data = srcs.get(src_id, [])
    if vid_raw:
        srcs[vid_raw] = pos_data   # alias: vertices-id → position array

    # <triangles> の収集
    all_vi, all_ni, nrm_data = [], [], []

    for tris_el in mesh.findall(NS+'triangles'):
        stride   = 1
        p_off    = 0
        n_off    = None
        p_src_id = None
        n_src_id = None

        for inp in tris_el.findall(NS+'input'):
            sem = inp.get('semantic')
            off = int(inp.get('offset'))
            stride = max(stride, off + 1)
            if sem == 'VERTEX':
                p_off    = off
                p_src_id = inp.get('source').lstrip('#')
            elif sem == 'NORMAL':
                n_off    = off
                n_src_id = inp.get('source').lstrip('#')

        p_el = tris_el.find(NS+'p')
        if p_el is None or not (p_el.text or '').strip():
            continue

        idx     = list(map(int, p_el.text.split()))
        n_tris  = int(tris_el.get('count'))
        pd      = srcs.get(p_src_id, pos_data)
        nd_local = srcs.get(n_src_id, []) if n_src_id else []

        if not pd:
            continue
        if nd_local and not nrm_data:
            nrm_data = nd_local

        for i in range(n_tris * 3):
            base = i * stride
            all_vi.append(idx[base + p_off])
            if n_off is not None and n_src_id:
                all_ni.append(idx[base + n_off])
            else:
                all_ni.append(-1)

    if all_vi:
        geoms[gid] = {
            'pos': pos_data,
            'nrm': nrm_data,
            'vi':  all_vi,
            'ni':  all_ni,
        }

print(f"  Geometries: {len(geoms)}")

# --- シーングラフ探索 ---
all_data = []   # list of (px,py,pz, nx,ny,nz)  ← WebGL Y_UP, ワールド空間

def traverse(node, parent_mat):
    mat = parent_mat
    me  = node.find(NS+'matrix')
    if me is not None and (me.text or '').strip():
        local = list(map(float, me.text.split()))
        mat   = matmul(parent_mat, local)

    for ig in node.findall(NS+'instance_geometry'):
        url = ig.get('url').lstrip('#')
        gd  = geoms.get(url)
        if not gd:
            continue

        pd  = gd['pos']
        nd  = gd['nrm']
        vis = gd['vi']
        nis = gd['ni']

        for k in range(len(vis)):
            vi = vis[k] * 3
            if vi + 2 >= len(pd):
                continue
            wx, wy, wz = xform_pt(mat, pd[vi], pd[vi+1], pd[vi+2])
            gx, gy, gz = to_yup(wx, wy, wz)

            ni = nis[k]
            if ni >= 0 and nd and ni*3 + 2 < len(nd):
                wnx, wny, wnz = xform_nv(mat, nd[ni*3], nd[ni*3+1], nd[ni*3+2])
                gnx, gny, gnz = to_yup(wnx, wny, wnz)
            else:
                gnx, gny, gnz = 0.0, 1.0, 0.0

            all_data.append((gx, gy, gz, gnx, gny, gnz))

    for child in node.findall(NS+'node'):
        traverse(child, mat)

print("Traversing scene graph...")
scene = root.find('.//' + NS + 'visual_scene')
if scene:
    for n in scene.findall(NS + 'node'):
        traverse(n, IDENT[:])
else:
    print("ERROR: visual_scene not found"); sys.exit(1)

n_verts = len(all_data)
n_tris  = n_verts // 3
print(f"  Vertices: {n_verts}  ({n_tris} triangles)")
if n_verts == 0:
    print("ERROR: no vertices"); sys.exit(1)

# ── 正規化 ───────────────────────────────────────────────────────────────────
xs = [v[0] for v in all_data]
ys = [v[1] for v in all_data]
zs = [v[2] for v in all_data]

cx = (min(xs)+max(xs))*0.5
cy = (min(ys)+max(ys))*0.5
cz = (min(zs)+max(zs))*0.5
sc = max(max(xs)-min(xs), max(ys)-min(ys), max(zs)-min(zs)) * 0.5

print(f"  BBox X[{min(xs):.1f},{max(xs):.1f}] Y[{min(ys):.1f},{max(ys):.1f}] Z[{min(zs):.1f},{max(zs):.1f}]")
print(f"  Center ({cx:.1f},{cy:.1f},{cz:.1f})  Scale {sc:.1f}")

# ── バイナリパック (stride = 6 × float32) ────────────────────────────────────
print("Packing binary...")
buf = bytearray()
for gx,gy,gz,gnx,gny,gnz in all_data:
    buf += struct.pack('<ffffff',
                      (gx-cx)/sc, (gy-cy)/sc, (gz-cz)/sc,
                      gnx, gny, gnz)

b64 = base64.b64encode(bytes(buf)).decode('ascii')
print(f"  Binary {len(buf)//1024} KB → Base64 {len(b64)//1024} KB")

# ── JS 出力 ───────────────────────────────────────────────────────────────────
js = f"""// Shinkansen N700S geometry — auto-generated from model.dae
// {n_tris} triangles, {n_verts} vertices (non-indexed, interleaved pos+nrm float32)
const SHINKANSEN_VERT_COUNT = {n_verts};
const SHINKANSEN_B64 = '{b64}';
function getShinkansenGeo(){{
  const raw = atob(SHINKANSEN_B64);
  const buf = new ArrayBuffer(raw.length);
  const u8  = new Uint8Array(buf);
  for (let i = 0; i < raw.length; i++) u8[i] = raw.charCodeAt(i);
  return new Float32Array(buf);
}}
"""

with open(OUT, 'w', encoding='utf-8') as f:
    f.write(js)

print(f"Written → {OUT}")
print("Done.")
