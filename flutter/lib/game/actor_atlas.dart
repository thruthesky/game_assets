import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

/// libGDX TexturePacker `.atlas` 한 프레임(region 엔트리).
///
/// sheet.py 는 가로(X)만 trim 하고 세로(Y)는 유지하므로(발 정렬 0.85 보존),
/// 실측 프레임은 `size: <=128, 128`, `offset: <ox>, 0` 형태다. 원본 박스(orig,
/// 보통 128×128) 안의 어디에 trim 된 [src] 를 그릴지는 [offX]/[offY] 로 정한다.
class AtlasFrame {
  const AtlasFrame({
    required this.src,
    required this.offX,
    required this.offY,
    required this.origW,
    required this.origH,
    required this.index,
  });

  /// png 안에서 이 프레임이 차지하는 픽셀 사각형(xy + size).
  final ui.Rect src;

  /// 원본 박스 좌하단 기준 trim 여백(libGDX offset).
  final double offX;
  final double offY;

  /// 원본 프레임 크기(orig). 보통 128×128.
  final double origW;
  final double origH;

  /// 같은 이름 프레임들의 재생 순서.
  final int index;

  /// 원본 박스(0..origW, 0..origH) 안에서 [src] 를 그릴 위치(top-left 기준).
  /// libGDX: 위쪽 여백 = origH - offY - src.height.
  ui.Rect dstIn(double boxW, double boxH) {
    final sx = boxW / origW;
    final sy = boxH / origH;
    final left = offX * sx;
    final top = (origH - offY - src.height) * sy;
    return ui.Rect.fromLTWH(left, top, src.width * sx, src.height * sy);
  }
}

/// `.atlas` 텍스트 + page png 를 직접 파싱한 팩(flame_texturepacker 미사용).
class ActorAtlas {
  ActorAtlas(this.image, this.frames);

  /// page 이미지(모든 프레임이 공유하는 단일 ui.Image).
  final ui.Image image;

  /// region 이름(예 `walk_E`) → index 정렬된 프레임 리스트.
  final Map<String, List<AtlasFrame>> frames;

  /// [atlasAsset](예 `assets/pc/g/g.atlas`) + [imageAsset](`assets/pc/g/g.png`)
  /// 로드·파싱. 실패하면 null.
  static Future<ActorAtlas?> load(String atlasAsset, String imageAsset) async {
    try {
      final text = await rootBundle.loadString(atlasAsset);
      final bytes = await rootBundle.load(imageAsset);
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(),
      );
      final image = (await codec.getNextFrame()).image;

      final map = <String, List<AtlasFrame>>{};
      String? name;
      double x = 0, y = 0, w = 0, h = 0, ox = 0, oy = 0, origW = 128, origH = 128;
      int index = 0;

      void flush() {
        final n = name;
        if (n == null) return;
        (map[n] ??= []).add(AtlasFrame(
          src: ui.Rect.fromLTWH(x, y, w, h),
          offX: ox,
          offY: oy,
          origW: origW,
          origH: origH,
          index: index,
        ));
      }

      for (final raw in text.split('\n')) {
        if (raw.trim().isEmpty) continue;
        final indented = raw.startsWith(' ') || raw.startsWith('\t');
        if (!indented) {
          // page 파일명(.png)·page 헤더(key: value)·주입 메타(laryen.*: v)는 스킵.
          if (raw.endsWith('.png') || raw.contains(':')) continue;
          // 새 region 시작 — 이전 프레임 저장 후 기본값 리셋.
          flush();
          name = raw.trim();
          x = y = w = h = ox = oy = 0;
          origW = origH = 128;
          index = 0;
          continue;
        }
        // 들여쓴 속성 라인: "key: v1, v2".
        final c = raw.indexOf(':');
        if (c < 0) continue;
        final key = raw.substring(0, c).trim();
        final vals = raw
            .substring(c + 1)
            .split(',')
            .map((s) => s.trim())
            .toList();
        double v(int i) => double.tryParse(vals[i]) ?? 0;
        switch (key) {
          case 'xy':
            x = v(0);
            y = v(1);
          case 'size':
            w = v(0);
            h = v(1);
          case 'orig':
            origW = v(0);
            origH = v(1);
          case 'offset':
            ox = v(0);
            oy = v(1);
          case 'index':
            index = v(0).toInt();
        }
      }
      flush();

      // 각 region 프레임을 index 오름차순 정렬(index -1 은 뒤로).
      for (final list in map.values) {
        list.sort((a, b) {
          final ai = a.index < 0 ? 1 << 30 : a.index;
          final bi = b.index < 0 ? 1 << 30 : b.index;
          return ai.compareTo(bi);
        });
      }
      if (map.isEmpty) return null;
      return ActorAtlas(image, map);
    } catch (_) {
      return null;
    }
  }
}
