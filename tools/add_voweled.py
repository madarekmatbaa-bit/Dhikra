"""يضيف إلى assets/data/quran.db جدول voweled: النص الإملائي المشكول من Tanzil (Simple 1.1)
بالكتابة التي يخرجها نموذج التسميع، ليوازن التطبيق بين ما سمعه وما في المصحف بالحركات.
النص المعروض يبقى نص مجمع الملك فهد؛ هذا للمقارنة فقط.

    python3 tools/add_voweled.py tools/data/tanzil-quran-simple.txt assets/data/quran.db
"""
import re, sqlite3, sys

MARKS = '[\u064b-\u0652]'


def normalize(t):
    t = re.sub('[\u06d6-\u06ed]', '', t)  # علامات الوقف والعلامات الصغيرة
    t = t.replace('\u0640', '').replace('\u0670', '')  # التطويل والألف الخنجرية
    t = re.sub(r'\s+', ' ', t).strip()
    out = []
    for w in t.split(' '):
        # شدة الإدغام على أول الكلمة («لِّلْمُتَّقِينَ») لا يكتبها النموذج.
        w = re.sub('^(.)(' + MARKS + '?)\u0651', r'\1\2', w)
        # النون واللام والميم الساكنة بلا علامة في Tanzil (الإخفاء والإدغام) يكتبها النموذج بسكون.
        # (لا لام التعريف قبل حرف مشدد: «الرَّحْمَنِ»، «اللَّهِ»)
        w = re.sub('([نلم])(?=[^\u064b-\u0652](?!\u0651)|$)', '\\1\u0652', w)
        out.append(w)
    return ' '.join(out)


src, out = sys.argv[1:3]
rows = {}
for line in open(src, encoding='utf-8'):
    if line.startswith('#') or '|' not in line:
        continue
    s, a, t = line.rstrip('\n').split('|')
    s, a = int(s), int(a)
    if a == 1 and s not in (1, 9):
        w = t.split(' ')
        assert re.sub(MARKS, '', w[0]) == 'بسم', (s, a)
        t = ' '.join(w[4:])
    t = normalize(t)
    rows[(s, a)] = t
assert len(rows) == 6236, len(rows)
db = sqlite3.connect(out)
db.execute('DROP TABLE IF EXISTS voweled')
db.execute('CREATE TABLE voweled(id INTEGER PRIMARY KEY, text TEXT NOT NULL)')
ids = db.execute('SELECT id, sura, aya FROM ayat ORDER BY id').fetchall()
for i, s, a in ids:
    db.execute('INSERT INTO voweled VALUES(?,?)', (i, rows[(s, a)]))
db.execute("INSERT OR REPLACE INTO meta VALUES('voweled','Tanzil Quran Text (Simple, Version 1.1), tanzil.net')")
db.commit()
db.execute('VACUUM')
db.close()
print('ok', len(ids))
