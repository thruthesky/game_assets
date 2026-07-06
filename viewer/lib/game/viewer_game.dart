import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/material.dart';

import 'actor_animation_set.dart';
import 'actor_component.dart';
import 'actor_contract.dart';
import 'monster_component.dart';
import 'sky_layer.dart';
import 'world_map.dart';

/// g.blend 캐릭터 뷰어 + 배틀 시뮬레이션. WASD/클릭 이동, 16방향 facing,
/// 텍스처 팩 자동 로드, 몬스터 추격·전투. 잔디·도로·건물·나무 맵 + 하늘/태양/구름.
class ViewerGame extends FlameGame with HasKeyboardHandlerComponents {
  ViewerGame({this.autoBattle = false});

  /// true 면 PC 를 AI 로 조종해 키 입력 없이 자동으로 배틀한다(데모·녹화용).
  final bool autoBattle;

  ActorComponent? _actor;
  ActorAnimationSet? _animSet;
  late final TextComponent _hud;
  final _TargetMarker _marker = _TargetMarker();
  final List<MonsterComponent> _monsters = [];

  double _pcAtkCd = 0; // 자동 배틀 시 PC 공격 쿨다운
  double _pcReviveTimer = 0; // 자동 배틀 시 PC 사망 후 부활 카운트다운

  /// PC 공격 판정 사거리와 데미지.
  static const double _pcAttackRange = 155;
  static const double _pcDamage = 30;
  bool _pcWasAttacking = false;

  /// 몬스터가 전멸하면 이 시간 뒤 다음 웨이브를 스폰.
  double _respawnTimer = 0;

  /// PC(0,0) 기준 몬스터 스폰 오프셋(고정 배치).
  static const List<(double, double)> _spawnOffsets = [
    (520, -260), (-480, 200), (300, 520), (-360, -420), (600, 260),
  ];

  @override
  Color backgroundColor() => const Color(0xFF9FD4F0);

  @override
  Future<void> onLoad() async {
    // 텍스처 팩이 번들돼 있으면 스프라이트, 없으면 null → placeholder.
    _animSet = await ActorAnimationSet.tryLoad();

    final actor = ActorComponent(animSet: _animSet, maxHp: 200)
      ..position = Vector2.zero();
    _actor = actor;

    world
      ..add(WorldMap())
      ..add(_marker)
      ..add(actor);

    camera.follow(actor);
    camera.viewfinder.zoom = 2.2; // 128px 캐릭터를 크게.

    _spawnWave(); // 첫 몬스터 웨이브

    // 하늘/태양/구름 — viewport 고정(원경 스카이박스).
    camera.viewport.add(SkyLayer());

    // ── HUD(카메라 viewport 고정) — 하늘 위 가독성 위해 반투명 배경 박스 ──
    camera.viewport.add(
      RectangleComponent(
        position: Vector2(6, 6),
        size: Vector2(360, 156),
        paint: Paint()..color = const Color(0x99101820),
      ),
    );
    _hud = TextComponent(
      text: '',
      position: Vector2(14, 12),
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
    camera.viewport.add(_hud);
  }

  /// 화면(픽셀) 좌표 탭 → 월드 좌표로 변환해 캐릭터 이동 목표로 준다.
  /// main.dart 의 GestureDetector 가 호출한다.
  void onScreenTap(Vector2 screenPixel) {
    final worldPos = camera.globalToLocal(screenPixel);
    _actor?.moveToward(worldPos);
  }

  /// PC 에게 가장 가까운 살아있는 몬스터(없으면 null).
  MonsterComponent? _nearestMonster() {
    final pc = _actor;
    if (pc == null) return null;
    MonsterComponent? best;
    var bestD = double.infinity;
    for (final m in _monsters) {
      if (m.isDead) continue;
      final d = pc.position.distanceToSquared(m.position);
      if (d < bestD) {
        bestD = d;
        best = m;
      }
    }
    return best;
  }

  /// PC 주변에 몬스터 한 웨이브를 스폰.
  void _spawnWave() {
    final pc = _actor;
    if (pc == null) return;
    for (final off in _spawnOffsets) {
      final m = MonsterComponent(
        prey: pc,
        animSet: _animSet,
        tint: const Color(0xFFB25FE0), // 보라색 몬스터
      )..position = pc.position + Vector2(off.$1, off.$2);
      _monsters.add(m);
      world.add(m);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    final pc = _actor;
    if (pc == null) return;

    // 맵 경계 제한.
    const b = WorldMap.half - 40;
    pc.position.setValues(
      pc.position.x.clamp(-b, b),
      pc.position.y.clamp(-b, b),
    );
    _marker.target = pc.moveTarget;

    // ── 자동 배틀(데모): PC 를 AI 로 조종 + 사망 시 자동 부활 ──
    if (autoBattle) {
      if (pc.isDead) {
        _pcReviveTimer -= dt;
        if (_pcReviveTimer <= 0) {
          pc.revive();
          _pcReviveTimer = 2.5;
        }
      } else if (!pc.isBusy) {
        _pcReviveTimer = 2.5;
        final target = _nearestMonster();
        if (target != null) {
          final d = target.position - pc.position;
          _pcAtkCd -= dt;
          if (d.length > _pcAttackRange * 0.8) {
            pc.moveToward(target.position); // 가장 가까운 몬스터로 접근
          } else {
            pc.stopMoving();
            pc.facing = dir16FromVelocity(d, pc.facing);
            if (_pcAtkCd <= 0) {
              pc.trigger(ActorState.attack);
              _pcAtkCd = 0.55;
            }
          }
        }
      }
    }

    // ── 배틀: PC 공격 시작 프레임에 사거리 내 몬스터 타격 ──
    final attacking = pc.state == ActorState.attack;
    if (attacking && !_pcWasAttacking) {
      for (final m in _monsters) {
        if (!m.isDead && pc.position.distanceTo(m.position) < _pcAttackRange) {
          m.takeDamage(_pcDamage);
        }
      }
    }
    _pcWasAttacking = attacking;

    // 제거된 몬스터 정리 + 전멸 시 리스폰.
    _monsters.removeWhere((m) => !m.isMounted);
    if (_monsters.isEmpty) {
      _respawnTimer -= dt;
      if (_respawnTimer <= 0) {
        _spawnWave();
        _respawnTimer = 3;
      }
    } else {
      _respawnTimer = 3;
    }

    final alive = _monsters.where((m) => !m.isDead).length;
    _hud.text = 'g.blend Actor Viewer — 배틀 시뮬레이션\n'
        '${pc.modeLabel}\n'
        'HP ${pc.hp.toInt()}/${pc.maxHp.toInt()}   '
        '${pc.statusLine.replaceFirst('state: ', '')}\n'
        '몬스터: $alive 마리\n'
        '\n'
        '[클릭/탭] 이동   [WASD] 이동/[Shift] 달리기\n'
        '[Space] 공격  [H] 피격  [X] 죽음  [R] 부활';
  }
}

/// 클릭 이동 목표를 표시하는 링 마커([target] 이 null 이면 안 그린다).
class _TargetMarker extends PositionComponent {
  _TargetMarker() : super(priority: -50);

  Vector2? target;

  final Paint _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..color = const Color(0xFFFFD54F);

  @override
  void render(Canvas canvas) {
    final t = target;
    if (t == null) return;
    canvas.drawCircle(Offset(t.x, t.y), 14, _ring);
    canvas.drawCircle(Offset(t.x, t.y), 3, _ring);
  }
}
