# girl.blend Actor Viewer (Flutter + Flame)

`girl.blend` 캐릭터를 iOS 시뮬레이터에서 표시하고 **마우스 클릭 / WASD 로 이동**시키는 데모
앱입니다. 잔디·도로·건물·나무가 있는 야외 맵 위를 걸어다니며, 하늘·태양·흐르는 구름이 상단에
원경으로 뜹니다. 캐릭터 스프라이트는 라리엔 게임과 **동일한 TexturePacker 텍스처 팩**
(`sheet.py` 산출물)으로 로드합니다. 텍스처 팩이 없으면 방향이 보이는 **placeholder** 로
대신 뜨고, 팩을 넣고 재빌드하면 조작감 그대로 진짜 스프라이트로 바뀝니다.

## 실행

```bash
cd viewer
flutter run -d <iOS-시뮬레이터>   # 예: flutter run -d "iPhone 17 Pro Max"
```

## 조작

| 입력 | 동작 |
|------|------|
| **마우스 클릭 / 탭** | 그 지점으로 걸어감(point-and-click) |
| `W` `A` `S` `D` | 이동 (대각선 가능, 클릭 이동보다 우선) |
| `Shift` + 이동 | 달리기(run) |
| `Space` | 공격(attack) |
| `H` | 피격(hit) |
| `X` | 죽음(death) |
| `R` | 부활/idle 복귀 |

시뮬레이터에서 하드웨어 키보드 입력이 안 잡히면 메뉴의 **I/O → Keyboard → Connect Hardware
Keyboard** 를 켜세요. 마우스 클릭 이동은 별도 설정 없이 동작합니다.

화면 좌상단 HUD 에 현재 모드(`SPRITE` / `PLACEHOLDER`), 상태, 16방향 facing 라벨이 표시됩니다.

## 맵

`lib/game/world_map.dart` — 잔디 지면 + 도로망 + 건물 7채 + 나무 20그루(고정 배치, ±2600 경계).
`lib/game/sky_layer.dart` — 화면 상단에 고정되는 하늘 그라디언트 + 태양 + 흐르는 구름
(카메라가 캐릭터를 화면 중앙에 두므로 캐릭터를 가리지 않는 원경 스카이박스).

## 배틀 시뮬레이션

`lib/game/monster_component.dart` — 몬스터는 **hellion**(`mob/hellion.blend` 를 sheet.py 로 구운
`assets/mob/hellion/hellion.atlas`, idle/walk/attack 16방향)을 스프라이트로 씁니다. PC 를 추격하다
사거리(120px)에서 공격합니다. hellion atlas 가 없으면 붉은 tint placeholder 로 대체됩니다.

- `main.dart` 의 `ViewerGame(autoBattle: true)` 면 PC 가 AI 로 가장 가까운 몬스터를 자동 추격·공격합니다
  (키 입력 없이 배틀 데모/녹화). `autoBattle: false` 로 두면 순수 수동 조작만 됩니다.
- **Space** 공격 시 사거리(155px) 안 몬스터 체력이 깎이고 0 이 되면 사라집니다(HUD 몬스터 수 감소).
- 몬스터가 근접하면 PC 를 때려 PC 체력(머리 위 초록 바)이 줄고, **X** 로 죽고 **R** 로 부활합니다.
- 한 웨이브(3마리)를 전멸시키면 3초 뒤 다음 웨이브가 스폰됩니다.
- 이 atlas 들에는 hit/death/run 이 없어(idle/walk/attack 만) 해당 상태는 idle 로 fallback 하며,
  hit 리액션으로 멈추지 않아 배틀 흐름이 유지됩니다.

## hellion 몬스터 굽기

```bash
cd /Users/thruthesky/apps/game/laryen   # sheet.py 의존 스크립트(_sheet_render.py 등)가 있는 곳
./scripts/sheet.py --kind mob --name hellion \
  --character /Users/thruthesky/Downloads/g/mob/hellion.blend \
  --animations default --actions idle,walk,attack \
  --idle 8 --walk 12 --attack 16 --texture-pack true
# 산출물 laryen/assets/mob/hellion/hellion.{png,atlas} 을 viewer/assets/mob/hellion/ 로 복사 후 재빌드
```

## 스프라이트 로딩 (수동 atlas 파서)

`lib/game/actor_atlas.dart` 가 `g.atlas` 텍스트를 직접 파싱하고 `g.png` 를 디코드해, region
(`{action}_{방향}`)별 프레임을 잘라 씁니다. sheet.py 의 trim 규칙(가로만 trim·세로 128 고정·
`offset` 으로 원본 128 박스 배치)을 그대로 재현하므로 발 정렬(anchor 0.5,0.85)이 유지됩니다.
`flame_texturepacker` 에 의존하지 않아 로드 실패 없이 결정론적으로 동작합니다.

## 텍스처 팩 투입 (팀원이 굽는 중)

`girl.blend` 로부터 라리엔 `scripts/sheet.py` 로 atlas 를 굽습니다:

```bash
laryen/scripts/sheet.py --kind pc --name girl \
  --character /Users/thruthesky/Downloads/girl/girl.blend --animations default \
  --idle 8 --walk 12 --run 12 --attack 16 --hit 8 --death 8
```

산출물 `girl.png`(+ 멀티페이지 `girl2.png`…) 과 `girl.atlas` 를 다음 경로에 복사하고 재빌드합니다:

```
viewer/assets/pc/girl/girl.png
viewer/assets/pc/girl/girl.atlas
```

```bash
flutter run -d <시뮬레이터>   # hot reload 가 아니라 재빌드해야 asset 이 번들됨
```

이름을 `girl` 이 아닌 다른 값으로 구웠다면 `lib/game/actor_contract.dart` 의
`kActorKind` / `kActorCategory` 만 바꾸면 됩니다.

## 텍스처 팩 계약 (라리엔 SSOT 그대로)

`lib/game/actor_contract.dart` 에 이식돼 있으며, `sheet.py` 산출물과 1:1 로 맞물립니다.

- **방향 라벨 16개**: `E ESE SE SSE S SSW SW WSW W WNW NW NNW N NNE NE ENE` (index 0=E, 4=S, 8=W, 12=N)
- **액션**: `idle walk run attack hit death`
- **region 이름**: `{action}_{라벨}` (예: `walk_E`, `attack_S`) — TexturePacker `useIndexes` 로 프레임 자동 정렬
- **stepTime/loop**: idle 0.12·loop, walk 0.08·loop, run 0.05·loop, attack 0.05, hit 0.07, death 0.10
- **velocity→방향**: `atan2(y,x)+π/16` 를 π/8(22.5°) 간격으로 floor 양자화
- **표시 크기**: 128px, anchor (0.5, 0.85) 발 기준

## 소스 구조

| 파일 | 역할 |
|------|------|
| `lib/main.dart` | 앱 진입점, `GameWidget` |
| `lib/game/viewer_game.dart` | `FlameGame` — 카메라 추적, 격자 배경, HUD |
| `lib/game/actor_component.dart` | WASD 이동·16방향 facing 캐릭터 (sprite / placeholder 양쪽) |
| `lib/game/actor_animation_set.dart` | atlas 로드 → 상태×방향 애니메이션 테이블 (없으면 null) |
| `lib/game/actor_contract.dart` | 라리엔 계약 상수(방향·액션·경로) |
