import 'dart:ui';

import 'package:flame/components.dart';

/// 캐릭터가 걸어다니는 야외 맵 — 잔디 지면, 도로망, 건물, 나무.
/// world 에 깔리며(priority 낮음) 카메라를 따라 스크롤된다.
/// 하늘/태양/구름은 [SkyLayer] 가 화면 상단에 고정으로 그린다.
class WorldMap extends PositionComponent {
  WorldMap() : super(priority: -1000);

  /// 맵 절반 크기(±_half 정사각). 캐릭터 이동 경계로도 쓰인다.
  static const double half = 2600;

  // ── 색 ──
  static const _grassA = Color(0xFF4C7A3A);
  static const _grassB = Color(0xFF43702F);
  static const _road = Color(0xFF6A6E73);
  static const _roadEdge = Color(0xFF5A5E63);
  static const _laneDash = Color(0xFFE7C84B);

  final Paint _p = Paint();

  /// 도로 중심선(월드 좌표). 가로/세로 큰 길 + 골목.
  static const List<double> _vRoads = [-1600, -400, 800, 2000];
  static const List<double> _hRoads = [-1400, 0, 1200];
  static const double _roadW = 150;

  /// 건물: (left, top, width, height, 벽색, 지붕색).
  static const List<(double, double, double, double, int, int)> _buildings = [
    (-1300, -1150, 420, 300, 0xFFB55D4C, 0xFF7C3B30),
    (-750, -1180, 300, 260, 0xFF6E8CB0, 0xFF445876),
    (150, -1150, 500, 320, 0xFFC7A85A, 0xFF897036),
    (-1250, 200, 360, 300, 0xFF8FA36B, 0xFF5C6B41),
    (300, 250, 460, 360, 0xFFB57FB0, 0xFF6F4A6C),
    (1150, -300, 380, 420, 0xFF5FA0A0, 0xFF3C6A6A),
    (-1900, -300, 300, 280, 0xFFC98A55, 0xFF8A5A33),
  ];

  /// 나무 위치(중심 x, 바닥 y).
  static const List<(double, double)> _trees = [
    (-2000, -900), (-1750, -700), (-2100, 400), (-1850, 800), (-1500, 1000),
    (-600, 600), (-200, 900), (250, 1100), (700, 800), (1100, 1050),
    (1500, 700), (1900, 300), (2100, -700), (1700, -900), (900, -600),
    (-100, -400), (-950, 1200), (1300, 1400), (-2200, -1200), (2200, 1100),
  ];

  @override
  void render(Canvas canvas) {
    _renderGround(canvas);
    _renderRoads(canvas);
    for (final b in _buildings) {
      _renderBuilding(canvas, b.$1, b.$2, b.$3, b.$4, Color(b.$5), Color(b.$6));
    }
    for (final t in _trees) {
      _renderTree(canvas, t.$1, t.$2);
    }
    // 맵 경계(옅은 울타리 느낌).
    _p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0x33202810);
    canvas.drawRect(Rect.fromLTRB(-half, -half, half, half), _p);
    _p.style = PaintingStyle.fill;
  }

  void _renderGround(Canvas canvas) {
    _p
      ..style = PaintingStyle.fill
      ..color = _grassA;
    canvas.drawRect(Rect.fromLTRB(-half, -half, half, half), _p);
    // 은은한 체크무늬로 이동감.
    _p.color = _grassB;
    const cell = 200.0;
    for (var y = -half; y < half; y += cell) {
      for (var x = -half; x < half; x += cell) {
        if (((x ~/ cell) + (y ~/ cell)) % 2 == 0) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), _p);
        }
      }
    }
  }

  void _renderRoads(Canvas canvas) {
    for (final x in _vRoads) {
      _p
        ..color = _roadEdge
        ..style = PaintingStyle.fill;
      canvas.drawRect(
          Rect.fromLTRB(x - _roadW / 2 - 8, -half, x + _roadW / 2 + 8, half), _p);
      _p.color = _road;
      canvas.drawRect(
          Rect.fromLTRB(x - _roadW / 2, -half, x + _roadW / 2, half), _p);
    }
    for (final y in _hRoads) {
      _p.color = _roadEdge;
      canvas.drawRect(
          Rect.fromLTRB(-half, y - _roadW / 2 - 8, half, y + _roadW / 2 + 8), _p);
      _p.color = _road;
      canvas.drawRect(
          Rect.fromLTRB(-half, y - _roadW / 2, half, y + _roadW / 2), _p);
    }
    // 차선 점선(세로 도로).
    _p
      ..color = _laneDash
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;
    for (final x in _vRoads) {
      for (var y = -half; y < half; y += 90) {
        canvas.drawLine(Offset(x, y), Offset(x, y + 45), _p);
      }
    }
    for (final y in _hRoads) {
      for (var x = -half; x < half; x += 90) {
        canvas.drawLine(Offset(x, y), Offset(x + 45, y), _p);
      }
    }
    _p.style = PaintingStyle.fill;
  }

  void _renderBuilding(Canvas canvas, double l, double t, double w, double h,
      Color wall, Color roof) {
    // 바닥 그림자
    _p.color = const Color(0x33000000);
    canvas.drawRect(Rect.fromLTWH(l + 12, t + h - 6, w, 26), _p);
    // 벽
    _p.color = wall;
    canvas.drawRect(Rect.fromLTWH(l, t, w, h), _p);
    // 지붕(상단 띠)
    _p.color = roof;
    canvas.drawRect(Rect.fromLTWH(l - 10, t - 34, w + 20, 44), _p);
    // 창문 격자
    _p.color = const Color(0xCCFCE9A6);
    const ws = 46.0, gap = 34.0;
    for (var yy = t + 40; yy < t + h - 50; yy += ws + gap) {
      for (var xx = l + 34; xx < l + w - 40; xx += ws + gap) {
        canvas.drawRect(Rect.fromLTWH(xx, yy, ws, ws), _p);
      }
    }
    // 문
    _p.color = const Color(0xFF4A342A);
    canvas.drawRect(Rect.fromLTWH(l + w / 2 - 26, t + h - 66, 52, 66), _p);
  }

  void _renderTree(Canvas canvas, double cx, double by) {
    // 그림자
    _p.color = const Color(0x33000000);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, by), width: 90, height: 30), _p);
    // 기둥
    _p.color = const Color(0xFF6B4A2B);
    canvas.drawRect(Rect.fromLTWH(cx - 12, by - 70, 24, 70), _p);
    // 잎(세 뭉치)
    _p.color = const Color(0xFF2F7D33);
    canvas.drawCircle(Offset(cx, by - 110), 52, _p);
    _p.color = const Color(0xFF37933C);
    canvas.drawCircle(Offset(cx - 34, by - 86), 40, _p);
    canvas.drawCircle(Offset(cx + 34, by - 86), 40, _p);
    // 하이라이트
    _p.color = const Color(0xFF49A84E);
    canvas.drawCircle(Offset(cx - 14, by - 122), 22, _p);
  }
}
