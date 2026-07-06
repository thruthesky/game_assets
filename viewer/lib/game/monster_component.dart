import 'package:flutter/services.dart';

import 'actor_component.dart';
import 'actor_contract.dart';

/// 배틀 시뮬레이션용 몬스터 — PC 를 추격하다 사정거리에서 공격한다.
///
/// PC 와 같은 g 스프라이트를 [tint] 로 색만 바꿔 재사용한다(전용 몬스터 atlas 가
/// 없어도 배틀 테스트가 가능). 이동은 부모 [ActorComponent] 의 클릭 이동 경로
/// ([moveToward]/[stopMoving])를 그대로 써서 애니메이션·발 정렬을 공유한다.
class MonsterComponent extends ActorComponent {
  MonsterComponent({
    required this.prey,
    super.animSet,
    super.tint,
    super.maxHp = 60,
  });

  /// 추격 대상(PC).
  final ActorComponent prey;

  /// 이 거리 안으로 들어오면 멈추고 공격한다.
  static const double _reach = 120;

  /// 공격 쿨다운(초)과 한 대 데미지.
  static const double _attackCd = 1.3;
  static const double _damage = 7;

  double _cd = 0;

  /// death 애니메이션을 보여준 뒤 제거하기까지 남은 시간.
  double _corpse = 2.5;

  // 몬스터는 키보드 입력을 무시한다(WASD 는 PC 전용).
  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) => false;

  @override
  void update(double dt) {
    if (isDead) {
      super.update(dt);
      _corpse -= dt;
      if (_corpse <= 0) removeFromParent();
      return;
    }

    _cd -= dt;
    if (!isBusy && !prey.isDead) {
      final toPrey = prey.position - position;
      final dist = toPrey.length;
      if (dist > _reach) {
        moveToward(prey.position); // 부모가 그쪽으로 walk
      } else {
        stopMoving();
        facing = dir16FromVelocity(toPrey, facing);
        if (_cd <= 0) {
          trigger(ActorState.attack);
          prey.takeDamage(_damage); // 근접 타격
          _cd = _attackCd;
        }
      }
    }

    super.update(dt);
  }
}
