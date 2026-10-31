"""يبني assets/data/quran.db من بيانات مجمع الملك فهد لطباعة المصحف الشريف (رواية حفص، الإصدار 18)
عبر المستودع thetruetruth/quran-data-kfgqpc (hafs/data/hafsData_v18.json).
النص لا يُعدَّل بأي شكل. يتحقق السكربت من 114 سورة و6236 آية و604 صفحات وعدد آيات كل سورة."""
import json, os, re, sqlite3, sys
src, out = sys.argv[1:3]
d = json.load(open(src))
AYAT = [7,286,200,176,120,165,206,75,129,109,123,111,43,52,99,128,111,110,98,135,112,78,118,64,77,227,93,88,69,60,
        34,30,73,54,45,83,182,88,75,85,54,53,89,59,37,35,38,29,18,45,60,49,62,55,78,96,29,22,24,13,14,11,11,18,12,12,
        30,52,52,44,28,28,20,56,40,31,50,40,46,42,29,19,36,25,22,17,19,26,30,20,15,21,11,8,8,19,5,8,8,11,11,8,3,9,5,4,
        7,3,6,3,5,4,5,6]
assert len(d) == 6236 and [a['id'] for a in d] == list(range(1, 6237))
counts = {}
for a in d: counts[a['sora']] = counts.get(a['sora'], 0) + 1
assert [counts[s] for s in range(1, 115)] == AYAT, 'عدد آيات السور لا يطابق'
assert {a['page'] for a in d} == set(range(1, 605))
assert {a['jozz'] for a in d} == set(range(1, 31))
TASH = re.compile('[ؐ-ًؚ-ٰٟۖ-ۭـ]')
def plain(t):
    t = TASH.sub('', t)
    t = re.sub('[أإآٱ]', 'ا', t).replace('ى', 'ي').replace('ة', 'ه').replace('ؤ', 'و').replace('ئ', 'ي')
    return re.sub(r'\s+', ' ', t).strip()
if os.path.exists(out): os.remove(out)
db = sqlite3.connect(out)
db.executescript('''
CREATE TABLE ayat(id INTEGER PRIMARY KEY, sura INTEGER NOT NULL, aya INTEGER NOT NULL, page INTEGER NOT NULL,
  juz INTEGER NOT NULL, text TEXT NOT NULL, plain TEXT NOT NULL);
CREATE INDEX ayat_page ON ayat(page);
CREATE TABLE suras(id INTEGER PRIMARY KEY, name TEXT NOT NULL, ayat INTEGER NOT NULL, first_page INTEGER NOT NULL);
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
''')
for a in d:
    db.execute('INSERT INTO ayat VALUES(?,?,?,?,?,?,?)',
               (a['id'], a['sora'], a['aya_no'], a['page'], a['jozz'], a['aya_text'], plain(a['aya_text_emlaey'])))
for s in range(1, 115):
    first = next(a for a in d if a['sora'] == s)
    db.execute('INSERT INTO suras VALUES(?,?,?,?)', (s, first['sora_name_ar'], AYAT[s - 1], first['page']))
db.execute("INSERT INTO meta VALUES('source','مجمع الملك فهد لطباعة المصحف الشريف، رواية حفص عن عاصم، الإصدار 18')")
db.commit(); db.execute('VACUUM'); db.close()
print('ok', os.path.getsize(out))
