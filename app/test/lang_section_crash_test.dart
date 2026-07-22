import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:jobradar/screens/profile_section_screen.dart';
import 'package:jobradar/services/profile_service.dart';

Future<void> _pump(WidgetTester tester, dynamic initial) async {
  await tester.pumpWidget(
    Provider<ProfileService>(
      create: (_) => ProfileService(),
      child: MaterialApp(
        home: ProfileSectionScreen(
          uid: 'test',
          section: const ProfileSection(
              'languages', 'Langues', Icons.translate, SectionKind.languages),
          initialValue: initial,
        ),
      ),
    ),
  );
}

void main() {
  // Viewport téléphone étroit.
  setUp(() {});

  testWidgets('langues: rendu + ouverture du dropdown (écran étroit)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester, [
      {'language': 'Anglais', 'level': 'C1-C2'},
      {'language': 'Tchèque', 'level': 'A2 solide, proche B1'},
    ]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'rendu');

    // Ouvrir le premier menu déroulant.
    final dd = find.byType(DropdownButton<String>).first;
    await tester.tap(dd);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'ouverture dropdown');
  });

  testWidgets('langues: dropdown avec valeur CEFR valide, ouverture', (tester) async {
    await _pump(tester, [
      {'language': 'Anglais', 'level': 'C1'},
      {'language': 'Tchèque', 'level': 'B1'},
    ]);
    await tester.pumpAndSettle();
    final dd = find.byType(DropdownButton<String>).first;
    await tester.tap(dd);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
