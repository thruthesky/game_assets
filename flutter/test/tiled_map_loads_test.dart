import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:flutter_test/flutter_test.dart';

/// assets/map/main_map.tmx 가 실제로 파싱되고 3개 tileset 이미지가
/// 모두 로드되는지 headless 로 검증한다(맵이 게임에 실제로 붙는다는 증명).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('main_map.tmx 로드 + tileset 3개 확인', () async {
    final map = await TiledComponent.load(
      'main_map.tmx',
      Vector2(64, 32),
      prefix: 'assets/map/',
      images: Images(prefix: 'assets/map/'),
    );

    final tmx = map.tileMap.map;
    expect(tmx.width, 100, reason: '맵 가로 100 타일');
    expect(tmx.height, 100, reason: '맵 세로 100 타일');
    expect(tmx.orientation?.name, 'isometric', reason: 'isometric 맵');
    expect(tmx.tilesets.length, greaterThanOrEqualTo(3),
        reason: 'nature/tileset/town 3개 tileset');
    expect(map.size.x, greaterThan(0));
    expect(map.size.y, greaterThan(0));

    // ignore: avoid_print
    print('MAP OK: ${tmx.width}x${tmx.height} ${tmx.orientation?.name}, '
        'tilesets=${tmx.tilesets.length}, layers=${tmx.layers.length}, '
        'pixelSize=${map.size}');
  });
}
