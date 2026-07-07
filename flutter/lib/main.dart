import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'game/viewer_game.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ViewerApp());
}

class ViewerApp extends StatelessWidget {
  ViewerApp({super.key});

  // autoBattle: PC 가 AI 로 자동 전투(키 입력 없이 배틀 데모/녹화). 수동 조작만
  // 원하면 false 로. WASD/클릭/Space 는 autoBattle 여부와 무관하게 항상 동작한다.
  final ViewerGame _game = ViewerGame(autoBattle: true);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'girl.blend Actor Viewer',
      home: Scaffold(
        // 마우스 클릭(시뮬레이터) = 탭 → 그 지점으로 캐릭터 이동.
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _game.onScreenTap(
            Vector2(d.localPosition.dx, d.localPosition.dy),
          ),
          child: GameWidget(game: _game),
        ),
      ),
    );
  }
}
