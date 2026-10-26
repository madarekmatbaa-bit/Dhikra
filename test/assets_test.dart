import 'package:dhikra/db/adhkar_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ملف الأذكار مضمّن في التطبيق ويُقرأ', () async {
    final d = AdhkarData();
    await d.load();
    for (final set in AdhkarSet.values) {
      expect(d.sets[set], isNotEmpty);
    }
  });
}
