import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:laryen_actor_viewer/main.dart';

void main() {
  testWidgets('뷰어 앱이 빌드된다', (WidgetTester tester) async {
    await tester.pumpWidget(ViewerApp());
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
