import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/services.dart';

import 'actor_animation_set.dart';
import 'actor_contract.dart';

/// 게임 표시 크기(라리엔 kActorDisplaySize=128 과 동일).
const double kDisplaySize = 128;

/// 이동 속도(스크린 px/초).
const double _walkSpeed = 130;
const double _runSpeed = 260;

/// 논루프 액션을 잡아두는 fallback 시간(초) — placeholder(클립 길이 모를 때)용.
const Map<ActorState, double> _actionHold = {
  ActorState.attack: 0.4,
  ActorState.hit: 0.35,
  ActorState.death: 1.2,
};

/// WASD/클릭 이동 + 16방향 facing 캐릭터.
///
/// [animSet] 이 있으면 수동 파싱한 atlas 프레임을 직접 렌더하고, 없으면 방향
/// 삼각형 placeholder 를 그린다. [tint] 로 같은 스프라이트를 색만 바꿔 몬스터로도 쓴다.
class ActorComponent extends PositionComponent with KeyboardHandler {
  ActorComponent({this.animSet, this.tint, this.maxHp = 100})
      : super(
          size: Vector2.all(kDisplaySize),
          // 발(bottom center) 기준 — sheet.py 발 정렬(0.85)과 맞물린다.
          anchor: Anchor.bottomCenter,
        ) {
    hp = maxHp;
    if (tint != null) {
      _spritePaint.colorFilter = ColorFilter.mode(tint!, BlendMode.modulate);
    }
  }

  final ActorAnimationSet? animSet;

  /// 스프라이트 색조(몬스터 구분용). null 이면 원색.
  final Color? tint;

  /// 전투 체력.
  final double maxHp;
  late double hp;

  bool get isDead => state == ActorState.death;

  /// 논루프 액션(attack/hit/death) 재생 중이라 새 입력을 막아야 하는지.
  bool get isBusy => _hold > 0;

  /// 클릭/추적 이동 목표를 즉시 해제(사정거리 진입 시 멈춤).
  void stopMoving() => _clickTarget = null;

  /// 체력을 채우고 idle 로 되살린다(자동 배틀 데모의 PC 부활).
  void revive() {
    hp = maxHp;
    state = ActorState.idle;
    _hold = 0;
    _clickTarget = null;
  }

  /// 피해를 입는다 — 죽으면 death, 아니면 hit 리액션.
  void takeDamage(double dmg) {
    if (isDead) return;
    hp -= dmg;
    if (hp <= 0) {
      hp = 0;
      _trigger(ActorState.death);
    } else {
      _trigger(ActorState.hit);
    }
  }

  final Set<LogicalKeyboardKey> _pressed = {};

  int facing = kDir16South;
  ActorState state = ActorState.idle;
  double _hold = 0; // 논루프 액션 잔여 시간

  /// 클릭(탭)으로 지정한 이동 목표(월드 좌표). null 이면 클릭 이동 없음.
  Vector2? _clickTarget;
  static const double _arriveEps = 2;

  // 현재 재생 중인 클립 추적.
  ActorState? _shownState;
  int? _shownDir;
  double _clipElapsed = 0;

  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.none;

  bool get _hasSprites => animSet != null;

  /// HUD·마커용 현재 클릭 이동 목표(없으면 null).
  Vector2? get moveTarget => _clickTarget;

  /// 클릭한 월드 지점으로 걸어가게 한다. 죽은 상태면 무시.
  void moveToward(Vector2 target) {
    if (state == ActorState.death) return;
    _clickTarget = target.clone();
  }

  /// HUD 표시용 현재 모드 문자열.
  String get modeLabel =>
      _hasSprites ? 'SPRITE (g.atlas)' : 'PLACEHOLDER (atlas 대기)';

  /// HUD 표시용 상태 라인.
  String get statusLine =>
      'state: ${state.name}   facing: ${kDir16Labels[facing]}'
      '${_clickTarget != null ? '   → 클릭 이동 중' : ''}';

  /// 외부(배틀 로직)에서 액션을 강제로 트리거한다.
  void trigger(ActorState s) => _trigger(s);

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    _pressed
      ..clear()
      ..addAll(keysPressed);

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        _trigger(ActorState.attack);
      } else if (event.logicalKey == LogicalKeyboardKey.keyH) {
        _trigger(ActorState.hit);
      } else if (event.logicalKey == LogicalKeyboardKey.keyX) {
        _trigger(ActorState.death);
      } else if (event.logicalKey == LogicalKeyboardKey.keyR) {
        _hold = 0;
        state = ActorState.idle;
      }
    }
    return true;
  }

  void _trigger(ActorState s) {
    if (state == ActorState.death && s != ActorState.death) return;
    state = s;
    // 스프라이트가 있으면 클립 전체 길이만큼 재생하고, 없으면 fallback 시간.
    _hold = animSet?.get(s, facing)?.duration ?? (_actionHold[s] ?? 0.4);
    _clickTarget = null;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (_hold > 0) {
      _hold -= dt;
      if (_hold <= 0 && state != ActorState.death) {
        state = ActorState.idle;
      }
    } else {
      final dir = _inputDirection();
      if (dir.length2 >= kDeadZoneSq) {
        _clickTarget = null;
        final running = _pressed.contains(LogicalKeyboardKey.shiftLeft) ||
            _pressed.contains(LogicalKeyboardKey.shiftRight);
        state = running ? ActorState.run : ActorState.walk;
        facing = dir16FromVelocity(dir, facing);
        final speed = running ? _runSpeed : _walkSpeed;
        position += dir.normalized() * speed * dt;
      } else if (_clickTarget != null) {
        _advanceToClickTarget(dt);
      } else {
        state = ActorState.idle;
      }
    }

    _advanceClip(dt);
  }

  /// 스프라이트 프레임 진행 — 클립이 바뀌면 처음부터, 아니면 경과 누적.
  void _advanceClip(double dt) {
    if (!_hasSprites) return;
    if (state != _shownState || facing != _shownDir) {
      _shownState = state;
      _shownDir = facing;
      _clipElapsed = 0;
    } else {
      _clipElapsed += dt;
    }
  }

  void _advanceToClickTarget(double dt) {
    final target = _clickTarget!;
    final toTarget = target - position;
    final dist = toTarget.length;
    final step = _walkSpeed * dt;
    if (dist <= _arriveEps || dist <= step) {
      position.setFrom(target);
      _clickTarget = null;
      state = ActorState.idle;
      return;
    }
    state = ActorState.walk;
    facing = dir16FromVelocity(toTarget, facing);
    position += toTarget.normalized() * step;
  }

  /// 눌린 WASD → 스크린 방향 벡터(y 아래 양수). 대각선 허용.
  Vector2 _inputDirection() {
    var x = 0.0, y = 0.0;
    if (_pressed.contains(LogicalKeyboardKey.keyA)) x -= 1;
    if (_pressed.contains(LogicalKeyboardKey.keyD)) x += 1;
    if (_pressed.contains(LogicalKeyboardKey.keyW)) y -= 1;
    if (_pressed.contains(LogicalKeyboardKey.keyS)) y += 1;
    return Vector2(x, y);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (_hasSprites) {
      _renderSprite(canvas);
    } else {
      _renderPlaceholder(canvas);
    }
    _renderHealthBar(canvas);
  }

  /// 머리 위 체력바 — PC 는 초록, 몬스터(tint 있음)는 빨강. 죽으면 숨김.
  void _renderHealthBar(Canvas canvas) {
    if (isDead || hp >= maxHp) return;
    const barW = 66.0, barH = 6.0;
    final x = (size.x - barW) / 2, y = size.y * 0.06;
    canvas.drawRect(
      Rect.fromLTWH(x - 1, y - 1, barW + 2, barH + 2),
      Paint()..color = const Color(0xCC000000),
    );
    canvas.drawRect(
      Rect.fromLTWH(x, y, barW * (hp / maxHp).clamp(0, 1), barH),
      Paint()
        ..color = tint != null ? const Color(0xFFE53935) : const Color(0xFF66BB6A),
    );
  }

  /// 현재 (state·facing) 클립의 프레임을 원본 128 박스 기준 offset 렌더.
  void _renderSprite(Canvas canvas) {
    final clip = animSet!.get(state, facing);
    if (clip == null || clip.frames.isEmpty) return;
    final frame = clip.frameAt(_clipElapsed);
    canvas.drawImageRect(
      animSet!.image,
      frame.src,
      frame.dstIn(size.x, size.y),
      _spritePaint,
    );
  }

  // ── placeholder 렌더(atlas 없을 때) ──────────────────────────────────────
  static const Map<ActorState, Color> _stateColor = {
    ActorState.idle: Color(0xFF9E9E9E),
    ActorState.walk: Color(0xFF4CAF50),
    ActorState.run: Color(0xFF2196F3),
    ActorState.attack: Color(0xFFF44336),
    ActorState.hit: Color(0xFFFF9800),
    ActorState.death: Color(0xFF37474F),
  };

  void _renderPlaceholder(Canvas canvas) {
    final feet = Offset(size.x / 2, size.y);
    final center = Offset(size.x / 2, size.y * 0.55);
    final color = tint ?? _stateColor[state] ?? const Color(0xFF9E9E9E);

    canvas.drawOval(
      Rect.fromCenter(center: feet, width: size.x * 0.5, height: size.y * 0.12),
      Paint()..color = const Color(0x33000000),
    );
    canvas.drawCircle(center, size.x * 0.30, Paint()..color = color);
    canvas.drawCircle(
      center,
      size.x * 0.30,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF000000),
    );

    final angle = facing * (math.pi / 8);
    final dirV = Offset(math.cos(angle), math.sin(angle));
    final tip = center + dirV * (size.x * 0.42);
    final perp = Offset(-dirV.dy, dirV.dx) * (size.x * 0.12);
    final baseC = center + dirV * (size.x * 0.20);
    final tri = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((baseC + perp).dx, (baseC + perp).dy)
      ..lineTo((baseC - perp).dx, (baseC - perp).dy)
      ..close();
    canvas.drawPath(tri, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawPath(
      tri,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF000000),
    );
  }
}
