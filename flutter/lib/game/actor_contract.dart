import 'dart:math' as math;

import 'package:flame/components.dart';

/// 라리엔 게임 스프라이트 아틀라스 "계약"을 이 뷰어에 이식한 것.
///
/// 이 값들은 sheet.py(scripts/_sheet_render.py) 가 굽는 atlas 의 region 이름·
/// 프레임 순서와 1:1 로 맞물린다. 팀원이 만든 g.atlas 가 이 규칙대로 나오므로,
/// 여기서 규칙을 바꾸면 스프라이트가 어긋난다. SSOT 는 라리엔 리포의
/// lib/features/game/render/direction8.dart · actor_animation_set.dart.

/// 16방향 index → region 접미사 라벨. index 0=E, 4=S, 8=W, 12=N.
/// sheet.py `--directions 16` 의 row 순서(FLARE 22.5°)와 동일.
const List<String> kDir16Labels = [
  'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW',
  'W', 'WNW', 'NW', 'NNW', 'N', 'NNE', 'NE', 'ENE',
];

/// 정면(S) index — facing 초기값/fallback.
const int kDir16South = 4;

/// 이동 데드존(스크린 px²). 이보다 느리면 방향을 유지하고 idle 로 본다.
const double kDeadZoneSq = 0.0004;

/// velocity(스크린 px) → 16방향 index(0~15). 데드존이면 [fallback] 유지.
/// atan2 에 π/16 offset 을 더해 π/8(22.5°) 간격으로 floor 양자화.
/// v=(+x,0) → E(0), v=(0,+y)=화면 아래 → S(4). 라리엔 dir16FromVelocity 와 동일.
int dir16FromVelocity(Vector2 v, int fallback) {
  if (v.length2 < kDeadZoneSq) return fallback;
  final shifted = math.atan2(v.y, v.x) + math.pi / 16;
  final normalized = (shifted + math.pi * 2) % (math.pi * 2);
  return (normalized / (math.pi / 8)).floor() % 16;
}

/// 액터 상태. 라리엔 protocol/actor_state.dart 의 부분집합(뷰어에 필요한 것만).
enum ActorState { idle, walk, run, attack, hit, death }

/// (상태, atlas action 이름, stepTime 초, loop 여부).
/// 라리엔 actor_animation_set.dart `_atlasActions` 와 동일한 타이밍.
const List<(ActorState, String, double, bool)> kAtlasActions = [
  (ActorState.idle, 'idle', 0.12, true),
  (ActorState.walk, 'walk', 0.08, true),
  (ActorState.run, 'run', 0.05, true),
  (ActorState.attack, 'attack', 0.05, false),
  (ActorState.hit, 'hit', 0.07, false),
  (ActorState.death, 'death', 0.10, false),
];

/// 텍스처 팩 식별자 — 팀원이 `sheet.py --kind pc --name g` 로 구우면
/// assets/pc/g/g.{png,atlas} 가 된다. 다른 이름으로 구웠다면 여기만 바꾸면 된다.
const String kActorKind = 'g';
const String kActorCategory = 'pc';

/// rootBundle 로 직접 읽을 asset 경로(수동 atlas 파서용).
String get kAtlasAssetPath =>
    'assets/$kActorCategory/$kActorKind/$kActorKind.atlas';
String get kImageAssetPath =>
    'assets/$kActorCategory/$kActorKind/$kActorKind.png';
