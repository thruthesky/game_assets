import 'dart:ui';

import 'package:flame/components.dart';

/// 화면 상단에 고정으로 그리는 원경 하늘 — 그라디언트 + 태양 + 흐르는 구름.
///
/// 카메라 viewport 에 추가되어 화면 좌표(0,0=좌상단)에 그려지므로, 캐릭터가
/// 어디로 가든 하늘은 화면 위쪽에 머문다(스카이박스). 카메라가 캐릭터를 화면
/// 중앙에 고정하므로 캐릭터가 이 상단 밴드에 가려지지 않는다.
class SkyLayer extends PositionComponent {
  SkyLayer() : super(priority: -1000);

  Vector2 _screen = Vector2(400, 800);

  /// 하늘 밴드 높이 비율(화면 상단부터).
  static const double _bandFrac = 0.42;

  /// 구름: 정규화 x(0~1), 정규화 y(밴드 내), 스케일, 속도(정규화/초).
  final List<List<double>> _clouds = [
    [0.10, 0.30, 1.2, 0.010],
    [0.35, 0.55, 0.8, 0.016],
    [0.60, 0.25, 1.5, 0.008],
    [0.82, 0.62, 0.9, 0.013],
    [0.50, 0.78, 1.1, 0.011],
  ];

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _screen = size;
  }

  @override
  void update(double dt) {
    super.update(dt);
    for (final c in _clouds) {
      c[0] += c[3] * dt;
      if (c[0] > 1.2) c[0] = -0.2; // 화면 밖으로 나가면 왼쪽에서 재등장
    }
  }

  @override
  void render(Canvas canvas) {
    final w = _screen.x;
    final band = _screen.y * _bandFrac;

    // 하늘 그라디언트
    final sky = Paint()
      ..shader = Gradient.linear(
        Offset(0, 0),
        Offset(0, band),
        const [Color(0xFF4FA6E0), Color(0xFF9FD4F0), Color(0xFFDCEFF7)],
        const [0.0, 0.7, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, w, band), sky);

    // 태양 + glow(우상단)
    final sunC = Offset(w * 0.82, band * 0.34);
    canvas.drawCircle(
      sunC,
      band * 0.34,
      Paint()
        ..color = const Color(0x55FFF3B0)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );
    canvas.drawCircle(sunC, band * 0.17, Paint()..color = const Color(0xFFFFF0A6));

    // 구름
    final cloud = Paint()..color = const Color(0xF2FFFFFF);
    for (final c in _clouds) {
      _puff(canvas, c[0] * w, c[1] * band, 34 * c[2], cloud);
    }

    // 지평선 안개(밴드 하단을 부드럽게)
    final haze = Paint()
      ..shader = Gradient.linear(
        Offset(0, band - 40),
        Offset(0, band),
        const [Color(0x00DCEFF7), Color(0x66CFE3C0)],
      );
    canvas.drawRect(Rect.fromLTWH(0, band - 40, w, 40), haze);
  }

  void _puff(Canvas canvas, double x, double y, double r, Paint p) {
    canvas.drawCircle(Offset(x, y), r, p);
    canvas.drawCircle(Offset(x - r * 0.9, y + r * 0.2), r * 0.7, p);
    canvas.drawCircle(Offset(x + r * 0.9, y + r * 0.2), r * 0.75, p);
    canvas.drawCircle(Offset(x, y + r * 0.35), r * 0.9, p);
  }
}
