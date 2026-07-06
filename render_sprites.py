#!/usr/bin/env python3
"""
g.blend 캐릭터 + attack/idle/walk 애니메이션 → 16방향 스프라이트 낱장 렌더.
sheet.py 파이프라인(_sheet_render.py 역할)의 독립 재구현.

- 캐릭터: g.blend (Tripo 메쉬 + Mixamo rig 'mixamorig:')
- 애니: attack.fbx / idle.fbx / walk.fbx (idle 만 'mixamorig1:' → prefix 치환)
- 방향: 카메라 궤도(empty 부모 Z회전) 16방향, 조명 월드 고정
- 셰이딩: EEVEE + compositor vivid(밝기·대비·채도) 부스트
- 출력: <out>/frames/{action}_{dir:02d}_{frame}.png  (TexturePacker useIndexes 대응)

실행:  blender -b -P render_sprites.py -- <config.json>
"""
import bpy, sys, json, os, math
from mathutils import Vector

# ── config 로드 ──────────────────────────────────────────────────────────────
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
CFG = json.load(open(argv[0], encoding="utf-8"))
BASE       = CFG["base"]
BLEND      = os.path.join(BASE, CFG["blend"])
ANIMS      = CFG["anims"]                       # {"attack": "attack.fbx", ...}
OUT_FRAMES = CFG["out_frames"]
DIRECTIONS = int(CFG.get("directions", 16))
FPA        = int(CFG.get("frames_per_anim", 8))
RES        = int(CFG.get("render_res", 256))
ELEV       = float(CFG.get("elev", 30.0))
MARGIN     = float(CFG.get("margin", 1.5))
VIVID      = int(CFG.get("vivid", 5))
SAMPLES    = int(CFG.get("samples", 24))
DIR0_OFF   = float(CFG.get("dir0_offset_deg", 0.0))   # 정면 보정(테스트 후 조정)
MODE       = CFG.get("mode", "full")                  # full | test
TEST_ACT   = CFG.get("test_actions", ["attack"])
TEST_DIRS  = CFG.get("test_dirs", [0])
TEST_FRAMES= CFG.get("test_frames", [0])
CHAR_PREFIX= "mixamorig:"
LOOP_ACTS  = set(CFG.get("loop_actions", ["idle", "walk"]))
# viewer actor_contract.dart 와 1:1 계약 — region 접미사 라벨과 방향 순서.
# index 0=E, 4=S(정면·카메라쪽), 8=W, 12=N(뒤). region 이름 = "{action}_{label}".
DIR16_LABELS = ['E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW',
                'W', 'WNW', 'NW', 'NNW', 'N', 'NNE', 'NE', 'ENE']
SOUTH_IDX  = 4                                   # 정면(S) — pivot 각도 0
ORBIT_SIGN = float(CFG.get("orbit_sign", 1.0))   # 카메라 궤도 부호(좌우 반전 보정)

os.makedirs(OUT_FRAMES, exist_ok=True)


def log(*a):
    print("####", *a, flush=True)


# ── 씬 열기 ──────────────────────────────────────────────────────────────────
bpy.ops.wm.open_mainfile(filepath=BLEND)
scene = bpy.context.scene

# g.blend 안의 기존 Camera/Light 는 우리가 새로 배치하므로 제거(중복 조명 방지).
for o in list(bpy.data.objects):
    if o.type in ("CAMERA", "LIGHT"):
        bpy.data.objects.remove(o, do_unlink=True)

# 캐릭터 armature + 메쉬 수집.
char_arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
if char_arm is None:
    sys.exit("ERROR: g.blend 에서 Armature 를 찾지 못함")
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
log(f"캐릭터 armature={char_arm.name}  메쉬={len(meshes)}개")

# 애니 적용 전 rest pose 로 두고 bbox 계산.
char_arm.animation_data_clear()
for m in meshes:
    m.animation_data_clear()
scene.frame_set(1)
bpy.context.view_layer.update()


def world_bbox(objs):
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            for i in range(3):
                mn[i] = min(mn[i], w[i]); mx[i] = max(mx[i], w[i])
    return mn, mx


bmn, bmx = world_bbox(meshes)
center = (bmn + bmx) * 0.5
height = bmx.z - bmn.z
width  = max(bmx.x - bmn.x, bmx.y - bmn.y)
fit    = max(height, width)
log(f"bbox min={tuple(round(v,3) for v in bmn)} max={tuple(round(v,3) for v in bmx)}")
log(f"height={height:.3f} width={width:.3f} center={tuple(round(v,3) for v in center)}")

# ── 카메라 궤도 리그: target empty + 카메라(자식) + Track To ────────────────────
pivot = bpy.data.objects.new("CamPivot", None)
scene.collection.objects.link(pivot)
pivot.location = center

cam_data = bpy.data.cameras.new("SpriteCam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = fit * MARGIN
cam = bpy.data.objects.new("SpriteCam", cam_data)
scene.collection.objects.link(cam)
cam.parent = pivot
dist = fit * 3.0
el = math.radians(ELEV)
# pivot 로컬 좌표: 정면(-Y)에서 elev 만큼 위. Track To 가 pivot 을 겨냥.
cam.location = (0.0, -dist * math.cos(el), dist * math.sin(el))
trk = cam.constraints.new("TRACK_TO")
trk.target = pivot
trk.track_axis = "TRACK_NEGATIVE_Z"
trk.up_axis = "UP_Y"
scene.camera = cam

# ── 조명 3점(월드 고정) ──────────────────────────────────────────────────────
def add_sun(name, rot_deg, energy):
    d = bpy.data.lights.new(name, "SUN")
    d.energy = energy
    o = bpy.data.objects.new(name, d)
    o.rotation_euler = [math.radians(a) for a in rot_deg]
    scene.collection.objects.link(o)
    return o

# key(앞위 좌), fill(앞 우 약), back(뒤 상단 rim)
add_sun("Key",  (55, 0, -35), 4.0)
add_sun("Fill", (60, 0,  55), 1.6)
add_sun("Back", (-50, 0, 180), 3.0)

# ── 렌더 설정(EEVEE + 투명배경) ──────────────────────────────────────────────
try:
    scene.render.engine = "BLENDER_EEVEE_NEXT"
except TypeError:
    scene.render.engine = "BLENDER_EEVEE"
eng = scene.render.engine
log(f"render engine={eng}")
scene.render.resolution_x = RES
scene.render.resolution_y = RES
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
try:
    ev = scene.eevee
    ev.taa_render_samples = SAMPLES
except Exception:
    pass

# ── 컬러 매니지먼트: Standard view transform(선명한 색) + 약간의 노출 ──────────
# Blender 5.x 는 compositor 노드 트리 API 가 바뀌어(scene.node_tree 없음) 후처리(PIL)로
# vivid(밝기·대비·채도)를 최종 atlas 에 적용한다. 렌더 단계에서는 AgX 톤매핑(칙칙함)을 끄고
# Standard 로 두어 스프라이트 색이 선명하게 나오도록만 한다.
vs = scene.view_settings
try:
    vs.view_transform = "Standard"   # AgX/Filmic 끔 → 원색 유지(sprite 필수)
except Exception as e:
    log(f"view_transform 설정 경고: {e}")
try:
    vs.look = "None"
except Exception:
    pass
k = (VIVID - 1) / 8.0                 # 0(부스트없음)~1(최대)
vs.exposure = 0.35 * k               # 렌더 노출 약간만; 세부 vivid 는 PIL 후처리
log(f"view_transform=Standard exposure={vs.exposure:.2f} (vivid={VIVID} → PIL 후처리)")


# ── 애니 action 로드 + prefix 치환 + 캐릭터에 assign ─────────────────────────
import re


def iter_fcurves(act):
    """legacy(action.fcurves) 와 slotted(Blender 4.4+ layers/strips/channelbags) 모두 대응."""
    if hasattr(act, "fcurves"):
        try:
            fcs = list(act.fcurves)
            if fcs:
                return fcs
        except Exception:
            pass
    out = []
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for cbag in getattr(strip, "channelbags", []):
                out.extend(list(cbag.fcurves))
    return out


def load_action(fbx_path):
    """fbx import → action 을 캐릭터 prefix(mixamorig:)로 정규화해 반환. import 잔재는 삭제."""
    before = set(bpy.data.objects)
    before_act = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=fbx_path)
    new_objs = [o for o in bpy.data.objects if o not in before]
    new_acts = [a for a in bpy.data.actions if a not in before_act]
    act = new_acts[0] if new_acts else None
    if act is None:
        sys.exit(f"ERROR: {fbx_path} 에서 action 을 찾지 못함")
    # data_path 의 본 prefix 를 캐릭터(mixamorig:)로 통일.
    # fcurve data_path 예: pose.bones["mixamorig1:Hips"].location
    changed = 0
    for fc in iter_fcurves(act):
        dp = fc.data_path
        new = re.sub(r'mixamorig\d*:', CHAR_PREFIX, dp)
        if new != dp:
            fc.data_path = new
            changed += 1
    act.use_fake_user = True
    log(f"  action='{act.name}' fcurves={len(iter_fcurves(act))} prefix치환={changed}")
    # import 로 생긴 armature/objects 제거(action 은 유지).
    for o in new_objs:
        bpy.data.objects.remove(o, do_unlink=True)
    return act


def assign_action(arm, act):
    """캐릭터 armature 에 action assign(slotted 면 slot 도 연결)."""
    arm.animation_data_clear()
    ad = arm.animation_data_create()
    ad.action = act
    slots = getattr(act, "slots", None)
    if slots:
        # armature(OBJECT) 대상 slot 우선, 없으면 첫 slot.
        target = None
        for s in slots:
            if getattr(s, "target_id_type", "OBJECT") in ("OBJECT", "ARMATURE"):
                target = s; break
        target = target or slots[0]
        try:
            ad.action_slot = target
        except Exception as e:
            log(f"  slot 연결 경고: {e}")


def sample_frames(a0, a1, n, loop):
    """[a0,a1] 에서 n 프레임 균등 샘플. loop=True 면 끝 제외(순환 이음새)."""
    a0, a1 = float(a0), float(a1)
    if n <= 1:
        return [a0]
    if loop:
        return [a0 + (a1 - a0) * i / n for i in range(n)]
    return [a0 + (a1 - a0) * i / (n - 1) for i in range(n)]


def neutralize_root(arm):
    """현재 프레임의 hips world XY 를 원점으로 상쇄(루트모션 제자리 고정)."""
    bpy.context.view_layer.update()
    pb = arm.pose.bones.get(CHAR_PREFIX + "Hips")
    if pb is None:
        return
    world = arm.matrix_world @ pb.head
    arm.location.x -= (world.x - center.x)
    arm.location.y -= (world.y - center.y)
    bpy.context.view_layer.update()


# ── 렌더 루프 ────────────────────────────────────────────────────────────────
if MODE == "test":
    act_list = [(a, ANIMS[a]) for a in TEST_ACT if a in ANIMS]
else:
    act_list = list(ANIMS.items())

total = 0
for action, fbx in act_list:
    path = os.path.join(BASE, fbx)
    act = load_action(path)
    a0, a1 = act.frame_range
    loop = action in LOOP_ACTS
    sframes = sample_frames(a0, a1, FPA, loop)
    log(f"[{action}] {os.path.basename(fbx)} range=({a0:.0f},{a1:.0f}) "
        f"loop={loop} samples={[round(f,1) for f in sframes]}")
    # action 을 캐릭터에 assign.
    assign_action(char_arm, act)

    dirs   = TEST_DIRS if MODE == "test" else range(DIRECTIONS)
    fidxs  = TEST_FRAMES if MODE == "test" else range(FPA)
    for di in dirs:
        label = DIR16_LABELS[di]
        # 정면(S=index4) 이 pivot 0 이 되도록 SOUTH 기준 오프셋. 카메라 궤도.
        az = DIR0_OFF + (di - SOUTH_IDX) * (360.0 / DIRECTIONS) * ORBIT_SIGN
        pivot.rotation_euler = (0.0, 0.0, math.radians(az))
        for fi in fidxs:
            fval = sframes[fi]
            # 정수 프레임으로 set(서브프레임은 무시). 원본이 정수 키라 충분.
            char_arm.location = (0.0, 0.0, 0.0)
            scene.frame_set(int(round(fval)))
            neutralize_root(char_arm)
            fn = f"{action}_{label}_{fi}.png"
            scene.render.filepath = os.path.join(OUT_FRAMES, fn)
            bpy.ops.render.render(write_still=True)
            total += 1
            if total % 16 == 0:
                log(f"progress {total} 장")

log(f"RENDER_DONE total={total} → {OUT_FRAMES}")
