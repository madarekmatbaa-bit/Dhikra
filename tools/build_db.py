import json, sqlite3, re, sys, os
src_api, src_books, out = sys.argv[1:4]
d = json.load(open(src_api)); a = json.load(open(src_books))
titles = {c['id']: c['arabic'].replace('كتاب ', '', 1).strip() for c in a['chapters']}
fix = {'بدء الوحى': 'بدء الوحي', 'فضل الصلاة فى مسجد مكة والمدينة': 'فضل الصلاة في مسجد مكة والمدينة',
       'العمل فى الصلاة': 'العمل في الصلاة', 'فى الاستقراض': 'في الاستقراض', 'فى اللقطة': 'في اللقطة',
       'فضائل أصحاب النبى صلى الله عليه وسلم': 'فضائل أصحاب النبي ﷺ', 'المغازى': 'المغازي', 'التمنى': 'التمني'}
titles = {k: fix.get(v, v) for k, v in titles.items()}
ranges = {int(k): (v['hadithnumber_first'], v['hadithnumber_last']) for k, v in d['metadata']['section_details'].items() if k != '0'}
def book_of(n):
    for b, (f, l) in ranges.items():
        if f <= n <= l: return b
    refs = [x['reference']['book'] for x in groups[n] if x['reference']['book']]
    if refs: return refs[0]
    return book_of(n - 1)
TASH = re.compile('[ً-ْٰـ‏‎]')
def plain(t):
    t = TASH.sub('', t)
    t = re.sub('[أإآٱ]', 'ا', t).replace('ى', 'ي').replace('ة', 'ه').replace('ؤ', 'و').replace('ئ', 'ي')
    return re.sub(r'\s+', ' ', t)
def clean(t):
    t = t.replace('‏', '').replace('‎', '')
    t = re.sub(r'[ \t]+', ' ', t)
    t = re.sub(r' ([،,:.؛])', r'\1', t)
    return t.strip()
groups = {}
for x in d['hadiths']:
    n = int(x['hadithnumber']); groups.setdefault(n, []).append(x)
if os.path.exists(out): os.remove(out)
db = sqlite3.connect(out)
db.executescript('''
CREATE TABLE books(id INTEGER PRIMARY KEY, title TEXT NOT NULL, first INTEGER NOT NULL, last INTEGER NOT NULL);
CREATE TABLE hadiths(number INTEGER PRIMARY KEY, book_id INTEGER NOT NULL, text TEXT NOT NULL, text_plain TEXT NOT NULL, merged_into INTEGER);
CREATE INDEX hadith_book ON hadiths(book_id);
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
''')
for b, (f, l) in sorted(ranges.items()):
    db.execute('INSERT INTO books VALUES(?,?,?,?)', (b, titles[b], f, l))
last_nonempty = None
for n in range(1, 7564):
    parts = [clean(x['text']) for x in sorted(groups[n], key=lambda x: x['hadithnumber']) if x['text'].strip()]
    text = '\n\n'.join(parts)
    merged = None
    if not text: merged = last_nonempty
    else: last_nonempty = n
    db.execute('INSERT INTO hadiths VALUES(?,?,?,?,?)', (n, book_of(n), text, plain(text), merged))
db.execute("INSERT INTO meta VALUES('source','fawazahmed0/hadith-api ara-bukhari (sunnah.com text, Fath al-Bari numbering)')")
db.execute("INSERT INTO meta VALUES('version','1')")
db.commit(); db.execute('VACUUM'); db.close()
print('ok', os.path.getsize(out))
