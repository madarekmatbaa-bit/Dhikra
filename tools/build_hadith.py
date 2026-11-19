"""يبني assets/data/hadith.db: الكتب الستة في قاعدة واحدة.

صحيح البخاري من fawazahmed0/hadith-api (ara-bukhari) بترقيم فتح الباري كما كان في bukhari.db،
حتى لا يتغير موضع ورد أحد. والكتب الخمسة الأخرى من AhmedBaset/hadith-json (the_9_books)،
بترتيبها في الكتاب (المقدمة أولاً) وأسماء كتبها العربية.

python3 tools/build_hadith.py ara-bukhari.json ab-bukhari.json DIR_OF_ab-*.json out.db
"""
import json, sqlite3, re, sys, os, zlib

api_bukhari, ab_bukhari, ab_dir, out = sys.argv[1:5]

TASH = re.compile('[ً-ْٰـ‏‎]')
def plain(t):
    t = TASH.sub('', t)
    t = re.sub('[أإآٱ]', 'ا', t).replace('ى', 'ي').replace('ة', 'ه').replace('ؤ', 'و').replace('ئ', 'ي')
    return re.sub(r'\s+', ' ', t).strip()
def clean(t):
    t = t.replace('‏', '').replace('‎', '')
    t = re.sub(r'[ \t]+', ' ', t)
    t = re.sub(r' *\n *', '\n', t)
    t = re.sub(r' ([،,:.؛])', r'\1', t)
    return t.strip()
def z(t):
    # النص بحركاته مضغوطاً (zlib) ليصغر حجم القاعدة على الهاتف؛ البحث في text_plain.
    return zlib.compress(t.encode('utf-8'), 9)
def title(t):
    t = t.strip()
    t = re.sub('^كتاب ', '', t)
    return t

COLLECTIONS = [
    ('bukhari', 'صحيح البخاري', 'الإمام محمد بن إسماعيل البخاري'),
    ('muslim', 'صحيح مسلم', 'الإمام مسلم بن الحجاج النيسابوري'),
    ('abudawud', 'سنن أبي داود', 'الإمام أبو داود السجستاني'),
    ('tirmidhi', 'جامع الترمذي', 'الإمام أبو عيسى الترمذي'),
    ('nasai', 'سنن النسائي', 'الإمام أحمد بن شعيب النسائي'),
    ('ibnmajah', 'سنن ابن ماجه', 'الإمام محمد بن يزيد ابن ماجه'),
]

if os.path.exists(out): os.remove(out)
db = sqlite3.connect(out)
db.executescript('''
CREATE TABLE collections(id TEXT PRIMARY KEY, ord INTEGER NOT NULL, title TEXT NOT NULL, author TEXT NOT NULL, total INTEGER NOT NULL);
CREATE TABLE books(collection TEXT NOT NULL, id INTEGER NOT NULL, title TEXT NOT NULL, first INTEGER NOT NULL, last INTEGER NOT NULL, PRIMARY KEY(collection, id));
CREATE TABLE hadiths(collection TEXT NOT NULL, number INTEGER NOT NULL, book_id INTEGER NOT NULL, text BLOB NOT NULL,
  text_plain TEXT NOT NULL, merged_into INTEGER, PRIMARY KEY(collection, number));
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
''')

# ---------- البخاري: كما في tools/build_db.py ----------
d = json.load(open(api_bukhari)); a = json.load(open(ab_bukhari))
titles = {c['id']: title(c['arabic']) for c in a['chapters']}
fix = {'بدء الوحى': 'بدء الوحي', 'فضل الصلاة فى مسجد مكة والمدينة': 'فضل الصلاة في مسجد مكة والمدينة',
       'العمل فى الصلاة': 'العمل في الصلاة', 'فى الاستقراض': 'في الاستقراض', 'فى اللقطة': 'في اللقطة',
       'فضائل أصحاب النبى صلى الله عليه وسلم': 'فضائل أصحاب النبي ﷺ', 'المغازى': 'المغازي', 'التمنى': 'التمني'}
titles = {k: fix.get(v, v) for k, v in titles.items()}
ranges = {int(k): (v['hadithnumber_first'], v['hadithnumber_last']) for k, v in d['metadata']['section_details'].items() if k != '0'}
groups = {}
for x in d['hadiths']:
    groups.setdefault(int(x['hadithnumber']), []).append(x)
def book_of(n):
    for b, (f, l) in ranges.items():
        if f <= n <= l: return b
    refs = [x['reference']['book'] for x in groups[n] if x['reference']['book']]
    return refs[0] if refs else book_of(n - 1)
for b, (f, l) in sorted(ranges.items()):
    db.execute('INSERT INTO books VALUES(?,?,?,?,?)', ('bukhari', b, titles[b], f, l))
last = None
for n in range(1, 7564):
    parts = [clean(x['text']) for x in sorted(groups[n], key=lambda x: x['hadithnumber']) if x['text'].strip()]
    text = '\n\n'.join(parts)
    merged = None
    if not text: merged = last
    else: last = n
    db.execute('INSERT INTO hadiths VALUES(?,?,?,?,?,?)', ('bukhari', n, book_of(n), z(text), plain(text), merged))

# ---------- الخمسة الأخرى ----------
counts = {'bukhari': 7563}
for cid, _, _ in COLLECTIONS[1:]:
    a = json.load(open(os.path.join(ab_dir, f'ab-{cid}.json')))
    chapters = sorted(a['chapters'], key=lambda c: c['id'])  # المقدمة (0) أولاً
    by_ch = {}
    for h in a['hadiths']:
        by_ch.setdefault(h['chapterId'], []).append(h)
    n = 0
    for bi, c in enumerate(chapters, start=1):
        hs = sorted(by_ch.get(c['id'], []), key=lambda h: h['idInBook'])
        if not hs: continue
        first = n + 1
        for h in hs:
            t = clean(h['arabic'])
            if not t: continue
            n += 1
            db.execute('INSERT INTO hadiths VALUES(?,?,?,?,?,?)', (cid, n, bi, z(t), plain(t), None))
        db.execute('INSERT INTO books VALUES(?,?,?,?,?)', (cid, bi, title(c['arabic']), first, n))
    counts[cid] = n

for i, (cid, t, au) in enumerate(COLLECTIONS):
    db.execute('INSERT INTO collections VALUES(?,?,?,?,?)', (cid, i, t, au, counts[cid]))
db.execute("INSERT INTO meta VALUES('source','bukhari: fawazahmed0/hadith-api ara-bukhari; others: AhmedBaset/hadith-json the_9_books')")
db.execute("INSERT INTO meta VALUES('version','2')")
db.commit(); db.execute('VACUUM'); db.close()
print('ok', counts, os.path.getsize(out))
