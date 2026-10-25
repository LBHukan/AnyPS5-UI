import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anyps5_gui/main.dart';

void main() {
  testWidgets('Layout e navegação em janela ampla e compacta', (tester) async {
    final original = Directory.current;
    addTearDown(() {
      Directory.current = original;
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final size in [const Size(1440, 900), const Size(1050, 750)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(const AnyPS5App());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Arquivos da conversão'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Execução'));
      await tester.pumpAndSettle();
      expect(find.text('Vídeo e idioma'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(ListTile, 'Avançado'));
      await tester.pumpAndSettle();
      expect(find.text('Módulos e patches'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
}
