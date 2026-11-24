import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puitstrack/core/widgets/app_toast.dart';

void main() {
  testWidgets('le toast s\'affiche puis disparaît tout seul', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(), builder: _host));
    AppToast.show('Analyse enregistrée', type: ToastType.success);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Analyse enregistrée'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Analyse enregistrée'), findsNothing);
  });
}

Widget _host(BuildContext context, Widget? child) => AppToastHost(child: child!);
