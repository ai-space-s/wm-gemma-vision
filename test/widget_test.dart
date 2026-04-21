import 'package:flutter_test/flutter_test.dart';
import 'package:gemma_chat/download_page/config/constants.dart';
import 'package:gemma_chat/main.dart';

void main() {
  testWidgets('renders the Gemma 4 model download entry point', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text(modelFullName), findsOneWidget);
  });
}
