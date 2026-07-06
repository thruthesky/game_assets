#!/usr/bin/env python3
"""
packed atlas 페이지 PNG 후처리 — vivid(밝기·대비·채도) + 256색 컬러 압축(알파 보존).
sheet.py 의 compress_pages(q256) + vivid(color_level) 를 통합해 최종 atlas 에 in-place 적용.
🛑 in-place 라야 .atlas 의 페이지 basename 참조가 유지된다.

실행:  uv run --with pillow python3 postprocess.py <page.png> [<page2.png> ...] --vivid 5
"""
import sys, os
from PIL import Image, ImageEnhance

args = [a for a in sys.argv[1:]]
vivid = 5
if "--vivid" in args:
    i = args.index("--vivid")
    vivid = int(args[i + 1])
    del args[i:i + 2]
pages = args
k = (vivid - 1) / 8.0  # 0~1

# vivid 부스트 계수(5 → 중간).
BR = 1.0 + 0.15 * k   # 밝기
CO = 1.0 + 0.20 * k   # 대비
SA = 1.0 + 0.55 * k   # 채도

for p in pages:
    before = os.path.getsize(p)
    img = Image.open(p).convert("RGBA")
    alpha = img.getchannel("A")
    rgb = img.convert("RGB")
    # vivid: 밝기 → 대비 → 채도.
    rgb = ImageEnhance.Brightness(rgb).enhance(BR)
    rgb = ImageEnhance.Contrast(rgb).enhance(CO)
    rgb = ImageEnhance.Color(rgb).enhance(SA)
    # 256색 양자화(FASTOCTREE) — 색 종류를 줄여 PNG 압축률↑, 알파는 원본 유지.
    q = rgb.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    out = q.convert("RGBA")
    out.putalpha(alpha)
    out.save(p, "PNG", optimize=True)
    after = os.path.getsize(p)
    pct = 100 * (before - after) / before if before else 0
    print(f"  {os.path.basename(p)}: {before/1e6:.2f}MB → {after/1e6:.2f}MB "
          f"({pct:+.0f}%)  vivid={vivid}(br={BR:.2f} co={CO:.2f} sa={SA:.2f})")
