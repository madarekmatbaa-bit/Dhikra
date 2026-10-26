import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class WirdPlan {
  final int id;
  final String kind; // bukhari | book (لاحقاً)
  final int perDay;
  final int startPos;
  final int endPos;
  final String startDate;
  final String? reminder; // HH:mm أو null
  const WirdPlan({
    required this.id,
    required this.kind,
    required this.perDay,
    required this.startPos,
    required this.endPos,
    required this.startDate,
    this.reminder,
  });

  factory WirdPlan.fromRow(Map<String, Object?> r) => WirdPlan(
        id: r['id'] as int,
        kind: r['kind'] as String,
        perDay: r['per_day'] as int,
        startPos: r['start_pos'] as int,
        endPos: r['end_pos'] as int,
        startDate: r['start_date'] as String,
        reminder: r['reminder'] as String?,
      );
}

class WirdLog {
  final String date;
  final int fromPos;
  final int toPos;
  final int readCount;
  final bool done;
  final bool excused;
  const WirdLog(this.date, this.fromPos, this.toPos, this.readCount, this.done, this.excused);

  int get target => toPos - fromPos + 1;

  factory WirdLog.fromRow(Map<String, Object?> r) => WirdLog(
        r['date'] as String,
        r['from_pos'] as int,
        r['to_pos'] as int,
        r['read_count'] as int,
        (r['done'] as int) == 1,
        (r['excused'] as int) == 1,
      );
}

class Benefit {
  final int? id;
  final String title;
  final String body;
  final String sourceType; // hadith | free | book
  final String? sourceRef;
  final bool pinned;
  final String createdAt;
  final List<String> tags;
  const Benefit({
    this.id,
    required this.title,
    required this.body,
    required this.sourceType,
    this.sourceRef,
    this.pinned = false,
    required this.createdAt,
    this.tags = const [],
  });

  String get sourceLabel => switch (sourceType) {
        'hadith' => 'البخاري · حديث $sourceRef',
        'book' => sourceRef ?? 'كتاب',
        _ => 'ملاحظة حرة',
      };
}

/// بيانات المستخدم: الأوراد وسجل الأيام والموضع والفوائد.
/// الجداول مصممة لتتسع لورد الكتب والمكتبة في المرحلة الثانية.
class UserDb {
  late final Database db;

  Future<void> open() async {
    final path = p.join(await getDatabasesPath(), 'user.db');
    db = await openDatabase(path, version: 1, onCreate: (db, v) async {
      final b = db.batch();
      b.execute('''CREATE TABLE wird_plans(
        id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, source_id INTEGER, unit TEXT NOT NULL,
        per_day INTEGER NOT NULL, start_pos INTEGER NOT NULL, end_pos INTEGER NOT NULL,
        start_date TEXT NOT NULL, reminder TEXT, active INTEGER NOT NULL DEFAULT 1)''');
      b.execute('''CREATE TABLE wird_logs(
        plan_id INTEGER NOT NULL, date TEXT NOT NULL, from_pos INTEGER NOT NULL, to_pos INTEGER NOT NULL,
        read_count INTEGER NOT NULL DEFAULT 0, done INTEGER NOT NULL DEFAULT 0, excused INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(plan_id, date))''');
      b.execute('''CREATE TABLE progress(
        plan_id INTEGER PRIMARY KEY, current_pos INTEGER NOT NULL, updated_at TEXT NOT NULL)''');
      b.execute('''CREATE TABLE benefits(
        id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT NOT NULL,
        source_type TEXT NOT NULL, source_ref TEXT, pinned INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL)''');
      b.execute('CREATE TABLE tags(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)');
      b.execute('''CREATE TABLE benefit_tags(benefit_id INTEGER NOT NULL, tag_id INTEGER NOT NULL,
        PRIMARY KEY(benefit_id, tag_id))''');
      await b.commit(noResult: true);
    });
  }

  // ---------- الأوراد ----------

  Future<WirdPlan?> activePlan(String kind) async {
    final r = await db.query('wird_plans', where: 'kind = ? AND active = 1', whereArgs: [kind], limit: 1);
    return r.isEmpty ? null : WirdPlan.fromRow(r.first);
  }

  Future<int> createPlan({
    required String kind,
    required int perDay,
    required int startPos,
    required int endPos,
    required String startDate,
    String? reminder,
  }) async {
    await db.update('wird_plans', {'active': 0}, where: 'kind = ?', whereArgs: [kind]);
    final id = await db.insert('wird_plans', {
      'kind': kind,
      'unit': kind == 'bukhari' ? 'hadith' : 'page',
      'per_day': perDay,
      'start_pos': startPos,
      'end_pos': endPos,
      'start_date': startDate,
      'reminder': reminder,
      'active': 1,
    });
    await setPosition(id, startPos);
    return id;
  }

  Future<void> updatePlan(int id, Map<String, Object?> values) =>
      db.update('wird_plans', values, where: 'id = ?', whereArgs: [id]);

  Future<int?> position(int planId) async {
    final r = await db.query('progress', where: 'plan_id = ?', whereArgs: [planId]);
    return r.isEmpty ? null : r.first['current_pos'] as int;
  }

  Future<void> setPosition(int planId, int pos) => db.insert(
        'progress',
        {'plan_id': planId, 'current_pos': pos, 'updated_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<WirdLog>> logs(int planId) async {
    final r = await db.query('wird_logs', where: 'plan_id = ?', whereArgs: [planId], orderBy: 'date');
    return r.map(WirdLog.fromRow).toList();
  }

  Future<void> putLog(int planId, WirdLog l) => db.insert(
        'wird_logs',
        {
          'plan_id': planId,
          'date': l.date,
          'from_pos': l.fromPos,
          'to_pos': l.toPos,
          'read_count': l.readCount,
          'done': l.done ? 1 : 0,
          'excused': l.excused ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  // ---------- الفوائد ----------

  Future<List<Benefit>> benefits() async {
    final rows = await db.query('benefits', orderBy: 'pinned DESC, created_at DESC');
    final tagRows = await db.rawQuery(
        'SELECT bt.benefit_id AS b, t.name AS n FROM benefit_tags bt JOIN tags t ON t.id = bt.tag_id ORDER BY t.name');
    final tagMap = <int, List<String>>{};
    for (final t in tagRows) {
      tagMap.putIfAbsent(t['b'] as int, () => []).add(t['n'] as String);
    }
    return [
      for (final r in rows)
        Benefit(
          id: r['id'] as int,
          title: r['title'] as String,
          body: r['body'] as String,
          sourceType: r['source_type'] as String,
          sourceRef: r['source_ref'] as String?,
          pinned: (r['pinned'] as int) == 1,
          createdAt: r['created_at'] as String,
          tags: tagMap[r['id']] ?? const [],
        ),
    ];
  }

  Future<List<String>> allTags() async {
    final r = await db.rawQuery(
        'SELECT name FROM tags WHERE id IN (SELECT tag_id FROM benefit_tags) ORDER BY name');
    return r.map((e) => e['name'] as String).toList();
  }

  Future<int> saveBenefit(Benefit b) async {
    return db.transaction((tx) async {
      final values = {
        'title': b.title,
        'body': b.body,
        'source_type': b.sourceType,
        'source_ref': b.sourceRef,
        'pinned': b.pinned ? 1 : 0,
        'created_at': b.createdAt,
      };
      int id;
      if (b.id == null) {
        id = await tx.insert('benefits', values);
      } else {
        id = b.id!;
        await tx.update('benefits', values, where: 'id = ?', whereArgs: [id]);
        await tx.delete('benefit_tags', where: 'benefit_id = ?', whereArgs: [id]);
      }
      for (final name in b.tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toSet()) {
        await tx.insert('tags', {'name': name}, conflictAlgorithm: ConflictAlgorithm.ignore);
        final t = await tx.query('tags', columns: ['id'], where: 'name = ?', whereArgs: [name]);
        await tx.insert('benefit_tags', {'benefit_id': id, 'tag_id': t.first['id']},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      return id;
    });
  }

  Future<void> setPinned(int id, bool pinned) =>
      db.update('benefits', {'pinned': pinned ? 1 : 0}, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteBenefit(int id) async {
    await db.delete('benefit_tags', where: 'benefit_id = ?', whereArgs: [id]);
    await db.delete('benefits', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- النسخ الاحتياطي ----------

  static const _tables = ['wird_plans', 'wird_logs', 'progress', 'benefits', 'tags', 'benefit_tags'];

  Future<Map<String, Object?>> exportAll() async {
    return {for (final t in _tables) t: await db.query(t)};
  }

  Future<void> importAll(Map<String, dynamic> data) async {
    await db.transaction((tx) async {
      for (final t in _tables) {
        await tx.delete(t);
      }
      for (final t in _tables) {
        final rows = (data[t] as List?) ?? const [];
        for (final r in rows) {
          await tx.insert(t, Map<String, Object?>.from(r as Map));
        }
      }
    });
  }
}
