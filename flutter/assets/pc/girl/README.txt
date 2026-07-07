텍스처 팩(atlas) 투입 위치
==========================

팀원이 girl.blend 로부터 sheet.py 로 구운 TexturePacker atlas 를 이 폴더에 넣으세요.

  laryen/scripts/sheet.py --kind pc --name girl \
    --character /Users/thruthesky/Downloads/girl/girl.blend --animations default \
    --idle 8 --walk 12 --run 12 --attack 16 --hit 8 --death 8

결과물:
  assets/pc/girl/girl.png      (아틀라스 페이지, 멀티페이지면 girl2.png, girl3.png …)
  assets/pc/girl/girl.atlas    (region 정의: idle_E, walk_E, attack_S … {action}_{16방향라벨})

이 폴더에 girl.atlas + girl.png 를 복사한 뒤 `flutter run` 을 다시 하면(hot reload 아님, 재빌드),
앱이 자동으로 placeholder 대신 진짜 스프라이트로 캐릭터를 표시합니다.

region 계약(라리엔 SSOT):
  - 방향 라벨 16개: E ESE SE SSE S SSW SW WSW W WNW NW NNW N NNE NE ENE
  - 액션: idle walk run attack hit death
  - region 이름 = {action}_{라벨}  (예: walk_E), TexturePacker useIndexes 로 프레임 자동 정렬
