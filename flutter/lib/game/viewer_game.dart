import 'dart:math' as math;

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:flutter/material.dart';

import 'actor_animation_set.dart';
import 'actor_component.dart';
import 'actor_contract.dart';
import 'monster_component.dart';
import 'world_map.dart';

/// girl.blend 캐릭터 뷰어 + 배틀 시뮬레이션. WASD/클릭 이동, 16방향 facing,
/// 텍스처 팩 자동 로드, 몬스터 추격·전투. 잔디·도로·건물·나무 맵 + 하늘/태양/구름.
class ViewerGame extends FlameGame with HasKeyboardHandlerComponents {
  ViewerGame({this.autoBattle = false, this.debugSoloPc = false});

  /// true 면 PC 를 AI 로 조종해 키 입력 없이 자동으로 배틀한다(데모·녹화용).
  final bool autoBattle;

  /// true 면 몬스터 없이 PC 만 idle 로 띄운다(렌더 진단용).
  final bool debugSoloPc;

  ActorComponent? _actor;
  ActorAnimationSet? _animSet; // PC(g)
  ActorAnimationSet? _hellionAnimSet; // 몬스터 kind: hellion
  ActorAnimationSet? _dreyerAnimSet; // 몬스터 kind: dreyer
  late final TextComponent _hud;
  final _TargetMarker _marker = _TargetMarker();
  final List<MonsterComponent> _monsters = [];

  double _pcAtkCd = 0; // 자동 배틀 시 PC 공격 쿨다운
  double _pcReviveTimer = 0; // 자동 배틀 시 PC 사망 후 부활 카운트다운

  /// 사용자가 마우스 클릭/WASD 로 개입하면 이 시간(초) 동안 자동 배틀을 멈추고
  /// 수동 조작을 우선한다. 0 이 되면 다시 자동 배틀로 복귀한다.
  double _manualTimer = 0;
  static const double _manualHoldAfterClick = 6;
  static const double _manualHoldWhileKeys = 1;

  /// PC 공격 판정 사거리와 데미지.
  static const double _pcAttackRange = 155;
  static const double _pcDamage = 30;
  bool _pcWasAttacking = false;

  /// 몬스터가 전멸하면 이 시간 뒤 다음 웨이브를 스폰.
  double _respawnTimer = 0;

  @override
  Color backgroundColor() => const Color(0xFF2E4020); // 맵 경계 밖 중립 지면색

  @override
  Future<void> onLoad() async {
    // 텍스처 팩이 번들돼 있으면 스프라이트, 없으면 null → placeholder.
    _animSet = await ActorAnimationSet.tryLoad();
    // kind 별 몬스터 atlas 를 각각 로드(idle/walk/attack/hit/death). 실패하면 null
    // → 그 kind 몬스터는 붉은 placeholder. 둘 다 sheet.py --kind mob 산출물.
    _hellionAnimSet = await ActorAnimationSet.loadFrom(
      'assets/mob/hellion/hellion.atlas',
      'assets/mob/hellion/hellion.png',
    );
    _dreyerAnimSet = await ActorAnimationSet.loadFrom(
      'assets/mob/dreyer/dreyer.atlas',
      'assets/mob/dreyer/dreyer.png',
    );

    final actor = ActorComponent(animSet: _animSet, maxHp: 200)
      ..position = Vector2.zero();
    _actor = actor;

    // assets/map/main_map.tmx (isometric 100x100, tile 64x32) 를 로드해 배경으로 깐다.
    // tileset 이미지(tileset.png·town.png·nature/tree.png)는 prefix 기준 상대경로로 로드된다.
    // 맵 중앙이 원점(캐릭터 시작점) 근처에 오도록 절반 크기만큼 왼쪽 위로 이동.
    final tiledMap = await TiledComponent.load(
      'main_map.tmx',
      Vector2(64, 32),
      prefix: 'assets/map/',
      images: Images(prefix: 'assets/map/'),
    );
    tiledMap.priority = -1000;
    tiledMap.position = Vector2(-tiledMap.size.x / 2, -tiledMap.size.y / 2);

    world
      ..add(tiledMap)
      ..add(_marker)
      ..add(actor);

    camera.follow(actor);
    camera.viewfinder.zoom = 2.2; // 128px 캐릭터를 크게.

    if (!debugSoloPc) _spawnWave(); // 첫 몬스터 웨이브

    // ── HUD(카메라 viewport 고정) — 반투명 배경 박스로 가독성 확보 ──
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
    _manualTimer = _manualHoldAfterClick; // 클릭하면 자동 배틀을 잠시 멈춘다
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

  /// PC 주변에 kind 별 몬스터를 1마리씩 스폰 — hellion 1(왼쪽) + dreyer 1(오른쪽).
  void _spawnWave() {
    final pc = _actor;
    if (pc == null) return;
    // (해당 kind 애님셋, PC 기준 오프셋 dx, dy). kind 당 정확히 1마리.
    final specs = <(ActorAnimationSet?, double, double)>[
      (_hellionAnimSet, -240, 40), // hellion — PC 왼쪽
      (_dreyerAnimSet, 240, 40), // dreyer — PC 오른쪽
    ];
    for (final (animSet, dx, dy) in specs) {
      final m = MonsterComponent(
        prey: pc,
        animSet: animSet, // 해당 kind 스프라이트(있으면), 없으면 placeholder
        // atlas 있으면 원색, 없으면(placeholder) 붉은 tint.
        tint: animSet == null ? const Color(0xFFE05A5A) : null,
      )..position = pc.position + Vector2(dx, dy);
      _monsters.add(m);
      world.add(m);
    }
  }

  /// 몬스터들이 같은 지점(PC)으로 몰려들어 한 몸처럼 겹쳐 보이는 것을 막는다.
  /// 추격·이동 로직과 독립적으로, 매 프레임 서로 [_monsterSep] 보다 가까운 쌍을
  /// 반대 방향으로 부드럽게(glide) 밀어내 나란히 서게 한다. 위치는 발 기준.
  void _separateMonsters(double dt) {
    final live = _monsters
        .where((m) => m.isMounted && !m.isDead)
        .toList(growable: false);
    if (live.length < 2) return;

    // 각 몬스터가 이번 프레임에 물러날 누적 벡터(먼저 전부 계산 후 한꺼번에 적용).
    final push = List.generate(live.length, (_) => Vector2.zero());
    for (var i = 0; i < live.length; i++) {
      for (var j = i + 1; j < live.length; j++) {
        final away = live[i].position - live[j].position;
        var d = away.length;
        Vector2 dir;
        if (d < 0.01) {
          // 거의 완전히 겹침 — 인덱스로 결정적 분리 방향을 준다(황금각).
          final ang = i * 2.39996;
          dir = Vector2(math.cos(ang), math.sin(ang));
          d = 0;
        } else {
          dir = away / d;
        }
        if (d < _monsterSep) {
          // 겹친 만큼의 절반씩 서로 반대로 물러난다.
          final force = dir * ((_monsterSep - d) * 0.5);
          push[i] += force;
          push[j] -= force;
        }
      }
    }

    // 한 프레임 이동량을 제한해 순간이동이 아니라 부드럽게 미끄러지게 한다.
    final maxStep = _monsterGlideSpeed * dt;
    for (var i = 0; i < live.length; i++) {
      var p = push[i];
      if (p.length2 == 0) continue;
      if (p.length > maxStep) p = p.normalized() * maxStep;
      live[i].position += p;
    }
  }

  /// 몬스터끼리 유지할 최소 간격(px). 이보다 가까우면 밀어낸다.
  static const double _monsterSep = 104;

  /// 겹침 해소 시 한 몬스터가 초당 미끄러질 수 있는 최대 거리(px/s).
  static const double _monsterGlideSpeed = 170;

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

    // PC 완만한 체력 재생(초당 9) — 배틀 중에도 안정적으로 생존.
    if (!pc.isDead && pc.hp < pc.maxHp) {
      pc.hp = (pc.hp + 9 * dt).clamp(0, pc.maxHp);
    }

    // 사용자가 WASD 를 누르고 있으면 수동 우선 타이머 갱신.
    if (pc.hasMoveKeyPressed) {
      _manualTimer = _manualHoldWhileKeys;
    }
    if (_manualTimer > 0) _manualTimer -= dt;

    // ── 자동 배틀(데모): PC 를 AI 로 조종 + 사망 시 자동 부활 ──
    // 단, 사용자가 방금 마우스/WASD 로 개입했으면(=_manualTimer>0) 자동 조종을 멈춘다.
    if (autoBattle && _manualTimer <= 0) {
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

    // 겹쳐 쌓인 몬스터를 서로 밀어내 나란히 세운다.
    _separateMonsters(dt);

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
    final control = !autoBattle
        ? '수동 조작'
        : (_manualTimer > 0 ? '수동 조작 (클릭/WASD)' : '자동 배틀 (AI)');
    _hud.text = 'girl.blend Actor Viewer — 배틀 시뮬레이션\n'
        '${pc.modeLabel}   [$control]\n'
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
