import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/main.dart';

void main() {
  testWidgets('login screen renders', (tester) async {
    await tester.pumpWidget(const MeridianApp());
    expect(find.text('Giriş yap'), findsOneWidget);
  });
}
