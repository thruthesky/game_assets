import 'dart:ui' as ui;

import 'actor_atlas.dart';
import 'actor_contract.dart';

/// 한 (상태·방향) 애니메이션 클립 — index 정렬된 프레임 + 타이밍.
class ActorClip {
  const ActorClip(this.frames, this.stepTime, this.loop);

  final List<AtlasFrame> frames;
  final double stepTime;
  final bool loop;

  double get duration => frames.length * stepTime;

  /// 경과 시간 → 현재 프레임. loop 면 순환, 아니면 마지막에서 정지.
  AtlasFrame frameAt(double elapsed) {
    final n = frames.length;
    if (n == 0) throw StateError('빈 클립');
    var i = (elapsed / stepTime).floor();
    if (loop) {
      i %= n;
    } else if (i >= n) {
      i = n - 1;
    }
    return frames[i];
  }
}

/// g.atlas → `_table[state][dir16]` 클립 세트. page 이미지 한 장을 공유한다.
///
/// flame_texturepacker 대신 [ActorAtlas] 수동 파서를 쓴다(로드 실패 없이 결정론적).
class ActorAnimationSet {
  ActorAnimationSet._(this.image, this._table);

  /// 모든 프레임이 참조하는 page 이미지.
  final ui.Image image;

  /// [state.index][dir16] → 클립(없으면 null → idle fallback).
  final List<List<ActorClip?>> _table;

  /// g.atlas + g.png 로드·파싱. 없거나 계약 불일치면 null(→ placeholder).
  static Future<ActorAnimationSet?> tryLoad() async {
    final atlas = await ActorAtlas.load(kAtlasAssetPath, kImageAssetPath);
    if (atlas == null) return null;
    return build(atlas);
  }

  /// 이미 로드한 [atlas] 로 세트를 구성(몬스터가 PC 이미지를 재사용할 때도 씀).
  static ActorAnimationSet? build(ActorAtlas atlas) {
    final table = List<List<ActorClip?>>.generate(
      ActorState.values.length,
      (_) => List<ActorClip?>.filled(16, null),
    );

    var matched = false;
    for (var dir = 0; dir < 16; dir++) {
      final suffix = kDir16Labels[dir];
      for (final (state, action, step, loop) in kAtlasActions) {
        final frames = atlas.frames['${action}_$suffix'];
        if (frames == null || frames.isEmpty) continue;
        table[state.index][dir] = ActorClip(frames, step, loop);
        matched = true;
      }
    }
    if (!matched) return null;

    // run 미포함 자산은 walk 로 대체(제자리 멈춤 방지).
    for (var dir = 0; dir < 16; dir++) {
      table[ActorState.run.index][dir] ??= table[ActorState.walk.index][dir];
    }
    return ActorAnimationSet._(atlas.image, table);
  }

  /// state·16방향 클립. 비면 같은 방향 idle 로 fallback.
  ActorClip? get(ActorState state, int dir16) =>
      _table[state.index][dir16] ?? _table[ActorState.idle.index][dir16];
}
