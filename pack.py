#!/usr/bin/env python3
"""
output/frames 의 낱장 PNG → TexturePacker packed atlas → viewer/assets/pc/g/g.{png,atlas}.
sheet.py 의 packing 단계(ensure_packer_classpath/write_pack_json/run_texture_packer) 재현.

region 이름은 낱장 파일명 '{action}_{LABEL}_{frame}.png' 에서 useIndexes 로 마지막 _{frame}
을 index 로 떼어 '{action}_{LABEL}' 이 된다 → viewer findSpritesByName('{action}_{LABEL}') 계약.
"""
import os, json, subprocess, urllib.request, glob, sys

BASE   = "/Users/thruthesky/Downloads/g"
FRAMES = os.path.join(BASE, "output", "frames")
OUTDIR = os.path.join(BASE, "viewer", "assets", "pc", "g")
NAME   = "g"
TOOLS  = os.path.join(BASE, "tools")
JAVA   = "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java"

GDX_VERSION = "1.13.1"
GDX_MAVEN = "https://repo1.maven.org/maven2/com/badlogicgames/gdx"
GDX_JARS = {
    f"gdx-{GDX_VERSION}.jar": f"{GDX_MAVEN}/gdx/{GDX_VERSION}/gdx-{GDX_VERSION}.jar",
    f"gdx-tools-{GDX_VERSION}.jar": f"{GDX_MAVEN}/gdx-tools/{GDX_VERSION}/gdx-tools-{GDX_VERSION}.jar",
    f"gdx-platform-{GDX_VERSION}-natives-desktop.jar":
        f"{GDX_MAVEN}/gdx-platform/{GDX_VERSION}/gdx-platform-{GDX_VERSION}-natives-desktop.jar",
}
TP_MAIN = "com.badlogic.gdx.tools.texturepacker.TexturePacker"


def download(url, dest):
    tmp = dest + ".part"
    req = urllib.request.Request(url, headers={"User-Agent": "sheet-pack/1.0"})
    with urllib.request.urlopen(req, timeout=180) as r, open(tmp, "wb") as f:
        while True:
            c = r.read(1 << 16)
            if not c:
                break
            f.write(c)
    os.replace(tmp, dest)


def ensure_jars():
    os.makedirs(TOOLS, exist_ok=True)
    cp = []
    for name, url in GDX_JARS.items():
        dest = os.path.join(TOOLS, name)
        if not os.path.isfile(dest):
            print(f"  ⬇️  {name} 다운로드 …", flush=True)
            download(url, dest)
            print(f"     ✓ {os.path.getsize(dest)/1e6:.1f}MB")
        cp.append(dest)
    return os.pathsep.join(cp)


def write_pack_json():
    settings = {
        "stripWhitespaceX": True,
        "stripWhitespaceY": False,      # 발 y 정렬 보존(sheet.py 규정)
        "rotation": False,              # viewer 계약(회전 off)
        "pot": False,
        "maxWidth": 4096, "maxHeight": 4096,
        "scale": [0.5],                 # render 256 → atlas cell 128px
        "scaleSuffix": [""], "scaleResampling": ["bicubic"],
        "premultiplyAlpha": False,
        "edgePadding": True, "bleed": True,
        "paddingX": 2, "paddingY": 2, "duplicatePadding": True,
        "filterMin": "Nearest", "filterMag": "Nearest",
        "format": "RGBA8888",
        "ignoreBlankImages": True,
        "useIndexes": True,             # 파일명 끝 _{frame} → index
        "alias": True, "square": False,
        "fast": True,
        "outputFormat": "png",
        "atlasExtension": ".atlas",
        "prettyPrint": True,
    }
    p = os.path.join(FRAMES, "pack.json")
    json.dump(settings, open(p, "w"), indent=2)
    return settings


def main():
    n = len(glob.glob(os.path.join(FRAMES, "*.png")))
    print(f"낱장 PNG {n}개 → packing")
    if n == 0:
        sys.exit("frames 가 비었습니다")
    cp = ensure_jars()
    s = write_pack_json()
    print(f"  설정: scale={s['scale'][0]} rotation={s['rotation']} "
          f"maxPage={s['maxWidth']}x{s['maxHeight']} useIndexes={s['useIndexes']}")
    os.makedirs(OUTDIR, exist_ok=True)
    cmd = [JAVA, "-Djava.awt.headless=true", "-cp", cp, TP_MAIN, FRAMES, OUTDIR, NAME]
    out = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    if out.returncode != 0:
        print(out.stdout[-1500:]); print(out.stderr[-2000:])
        sys.exit("TexturePacker 실패")
    atlas = os.path.join(OUTDIR, NAME + ".atlas")
    pages = sorted(glob.glob(os.path.join(OUTDIR, NAME + "*.png")))
    print(f"  ✓ atlas → {atlas}")
    for pg in pages:
        print(f"    page: {os.path.basename(pg)}  {os.path.getsize(pg)/1e6:.2f}MB")
    # region 개수 확인.
    txt = open(atlas, encoding="utf-8").read()
    print(f"  atlas 크기: {len(txt)} bytes, 'idle_S' 포함={'idle_S' in txt}, "
          f"'attack_E' 포함={'attack_E' in txt}")


if __name__ == "__main__":
    main()
