import 'package:dhikra/db/user_db.dart';
import 'package:dhikra/screens/book_reader.dart';
import 'package:dhikra/util/pdf_arabic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('الأشكال العرضية تعود حروفاً أصلية', () {
    // «العلم» مكتوبة بأشكال العرض: ا ل ع ل م
    expect(normalizePdfArabic('ﺍﻟﻌﻠﻢ'), 'العلم');
    expect(normalizePdfArabic('ﻻ'), 'لا');
    expect(normalizePdfArabic('نص عادي'), 'نص عادي');
  });

  test('وصل أسطر الفقرة', () {
    expect(tidyPageText('قال الشيخ\r\nرحمه الله:\r\nالعلم نور.\r\n\r\nفصل'), 'قال الشيخ رحمه الله:\nالعلم نور.\nفصل');
  });

  test('فرز الفوائد حسب المصدر', () {
    const b = Benefit(title: '', body: 'x', sourceType: 'book', sourceRef: 'الأربعين النووية · ص 12', createdAt: '');
    expect(b.sourceGroup, 'الأربعين النووية');
    const h = Benefit(title: '', body: 'x', sourceType: 'hadith', sourceRef: '1', createdAt: '');
    expect(h.sourceGroup, 'صحيح البخاري');
  });
}
