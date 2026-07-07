import 'package:flame/components.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:laryen_actor_viewer/game/actor_component.dart';
import 'package:laryen_actor_viewer/game/actor_contract.dart';

/// WASD 키 → 이동/16방향 facing/상태 전환을 컴포넌트 레벨에서 직접 검증한다.
/// (시뮬레이터 하드웨어 키 자동화는 환경 권한에 막히므로, 로직은 여기서 확정 검증한다.)
KeyDownEvent _down(LogicalKeyboardKey k, PhysicalKeyboardKey p) =>
    KeyDownEvent(logicalKey: k, physicalKey: p, timeStamp: Duration.zero);

/// key: WASD 한 글자 → (논리키, 물리키).
final _keys = <String, (LogicalKeyboardKey, PhysicalKeyboardKey)>{
  'w': (LogicalKeyboardKey.keyW, PhysicalKeyboardKey.keyW),
  'a': (LogicalKeyboardKey.keyA, PhysicalKeyboardKey.keyA),
  's': (LogicalKeyboardKey.keyS, PhysicalKeyboardKey.keyS),
  'd': (LogicalKeyboardKey.keyD, PhysicalKeyboardKey.keyD),
};

/// 한 키를 누른 채 한 프레임 진행시키고, 결과 actor 를 돌려준다.
ActorComponent _press(String key) {
  final (lk, pk) = _keys[key]!;
  final actor = ActorComponent(); // animSet 없음 → placeholder 로직만.
  actor.onKeyEvent(_down(lk, pk), {lk});
  actor.update(0.1);
  return actor;
}

void main() {
  test('D(오른쪽) → facing E(0), walk, +x 이동', () {
    final a = _press('d');
    expect(a.state, ActorState.walk);
    expect(a.facing, 0); // E
    expect(kDir16Labels[a.facing], 'E');
    expect(a.position.x, greaterThan(0));
    expect(a.position.y, closeTo(0, 1e-6));
  });

  test('W(위) → facing N(12), walk, -y 이동', () {
    final a = _press('w');
    expect(a.state, ActorState.walk);
    expect(kDir16Labels[a.facing], 'N');
    expect(a.position.y, lessThan(0));
  });

  test('S(아래) → facing S(4), walk, +y 이동', () {
    final a = _press('s');
    expect(kDir16Labels[a.facing], 'S');
    expect(a.position.y, greaterThan(0));
  });

  test('A(왼쪽) → facing W(8), walk, -x 이동', () {
    final a = _press('a');
    expect(kDir16Labels[a.facing], 'W');
    expect(a.position.x, lessThan(0));
  });

  test('Shift+D → run 이 walk 보다 빠르다', () {
    final (lk, pk) = _keys['d']!;
    final actor = ActorComponent();
    actor.onKeyEvent(
      _down(lk, pk),
      {lk, LogicalKeyboardKey.shiftLeft},
    );
    actor.update(0.1);
    expect(actor.state, ActorState.run);
    // 같은 dt(0.1) 동안 run(260)이 walk(130)의 2배 거리를 이동.
    final walkActor = _press('d');
    expect(actor.position.x, greaterThan(walkActor.position.x));
  });

  test('키 없음 → idle, 이동 없음', () {
    final actor = ActorComponent();
    actor.update(0.1);
    expect(actor.state, ActorState.idle);
    expect(actor.position, Vector2.zero());
  });

  test('WD 대각선 → facing NE 계열, x 증가·y 감소', () {
    final (dl, dp) = _keys['d']!;
    final (wl, wp) = _keys['w']!;
    final actor = ActorComponent();
    actor.onKeyEvent(_down(dl, dp), {dl, wl});
    actor.update(0.1);
    expect(actor.state, ActorState.walk);
    expect(kDir16Labels[actor.facing], 'NE'); // 오른쪽+위 = 북동
    expect(actor.position.x, greaterThan(0));
    expect(actor.position.y, lessThan(0));
  });

  test('클릭 이동 → 목표 방향 walk, facing 전환, 목표로 접근', () {
    final actor = ActorComponent();
    actor.moveToward(Vector2(100, 0)); // 오른쪽 지점 클릭
    actor.update(0.1);
    expect(actor.state, ActorState.walk);
    expect(kDir16Labels[actor.facing], 'E');
    expect(actor.position.x, greaterThan(0));
    expect(actor.position.x, lessThan(100)); // 아직 도착 전
    expect(actor.moveTarget, isNotNull);
  });

  test('클릭 이동 → 충분히 진행하면 목표에 스냅하고 idle', () {
    final actor = ActorComponent();
    actor.moveToward(Vector2(20, 0));
    for (var i = 0; i < 60; i++) {
      actor.update(0.1); // 130px/s × 6s ≫ 20px → 도착
    }
    expect(actor.position.x, closeTo(20, 1e-6));
    expect(actor.position.y, closeTo(0, 1e-6));
    expect(actor.state, ActorState.idle);
    expect(actor.moveTarget, isNull);
  });

  test('WASD 입력이 클릭 이동보다 우선(클릭 목표 취소)', () {
    final (lk, pk) = _keys['a']!; // 왼쪽
    final actor = ActorComponent();
    actor.moveToward(Vector2(100, 0)); // 오른쪽 목표
    actor.onKeyEvent(_down(lk, pk), {lk});
    actor.update(0.1);
    expect(actor.moveTarget, isNull); // 키가 목표를 취소
    expect(kDir16Labels[actor.facing], 'W'); // 키 방향(왼쪽)으로
    expect(actor.position.x, lessThan(0));
  });

  test('죽은 상태에서는 클릭 이동 무시', () {
    final actor = ActorComponent();
    actor.onKeyEvent(
      _down(LogicalKeyboardKey.keyX, PhysicalKeyboardKey.keyX),
      {LogicalKeyboardKey.keyX},
    );
    actor.update(0.1); // death 상태
    actor.moveToward(Vector2(100, 0));
    expect(actor.moveTarget, isNull);
    expect(actor.state, ActorState.death);
  });

  test('Space → attack 상태로 잠기고 이동 정지', () {
    final actor = ActorComponent();
    actor.onKeyEvent(
      _down(LogicalKeyboardKey.space, PhysicalKeyboardKey.space),
      {LogicalKeyboardKey.space},
    );
    actor.update(0.1);
    expect(actor.state, ActorState.attack);
    expect(actor.position, Vector2.zero()); // 논루프 액션 중 정지
  });
}
