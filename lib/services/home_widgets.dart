import 'package:home_widget/home_widget.dart';

import '../db/bukhari_db.dart';
import '../db/user_db.dart';

/// يحدّث ويدجت الشاشة الرئيسية (ورد الحديث، وفائدة اليوم).
class HomeWidgets {
  static Future<void> update({
    required BukhariDb bukhari,
    required int position,
    required bool finished,
    required WirdLog? today,
    required int perDay,
    required Benefit? benefit,
  }) async {
    if (finished) {
      await HomeWidget.saveWidgetData('wird_progress', '');
      await HomeWidget.saveWidgetData('wird_sub', 'ختمت صحيح البخاري، الحمد لله');
      await HomeWidget.saveWidgetData('wird_text', '');
    } else {
      final h = await bukhari.hadith(position);
      final book = bukhari.bookOf(position);
      final target = today?.target ?? perDay;
      final read = (today?.readCount ?? 0).clamp(0, target);
      final done = today?.done ?? false;
      final text = h.text.isEmpty ? 'مدمج مع الحديث ${h.mergedInto}' : h.text;
      await HomeWidget.saveWidgetData('wird_progress', done ? '✓ $read/$target' : '$read/$target');
      await HomeWidget.saveWidgetData('wird_sub', 'الحديث التالي: $position · كتاب ${book.title}');
      await HomeWidget.saveWidgetData('wird_text', text.length > 260 ? '${text.substring(0, 260)}…' : text);
    }
    if (benefit == null) {
      await HomeWidget.saveWidgetData('benefit_title', 'دفتر الفوائد');
      await HomeWidget.saveWidgetData('benefit_body', 'لا فوائد بعد. حدد جملة أثناء القراءة واحفظها فائدة.');
      await HomeWidget.saveWidgetData('benefit_source', '');
    } else {
      await HomeWidget.saveWidgetData('benefit_title', benefit.title.isEmpty ? 'فائدة' : benefit.title);
      await HomeWidget.saveWidgetData('benefit_body', benefit.body);
      await HomeWidget.saveWidgetData('benefit_source', benefit.sourceLabel);
    }
    await HomeWidget.updateWidget(qualifiedAndroidName: 'com.dhikra.app.WirdWidget');
    await HomeWidget.updateWidget(qualifiedAndroidName: 'com.dhikra.app.BenefitWidget');
  }
}
