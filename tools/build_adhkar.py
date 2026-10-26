"""يبني assets/data/adhkar.json من azkar-db (osamayy/azkar-db، مأخوذ عن حصن المسلم).
أذكار الصباح والمساء كما هي مع حذف التطويل فقط. أذكار ما بعد الصلاة مقسّمة إلى
أذكار مستقلة بأعدادها كما ينص عليها حصن المسلم، والنص منقول حرفياً من المصدر."""
import json, re, sys
src, out = sys.argv[1:3]
rows = json.load(open(src))['rows']
def clean(t):
    t = t.replace('ـ', '')            # التطويل
    t = re.sub(r'[ \t]+', ' ', t).strip()
    return t
def ref(r):
    return {'أبن السني': 'ابن السني', 'ابن ماجة': 'ابن ماجه'}.get(r.strip(), r.strip())
def section(cat):
    items = []
    for c, zekr, desc, count, reference, _ in rows:
        if c != cat: continue
        items.append({'text': clean(zekr), 'count': int(count or 1), 'virtue': clean(desc or ''), 'ref': ref(reference or '')})
    return items
after = [clean(r[1]) for r in rows if r[0] == 'الأذكار بعد السلام من الصلاة']
assert len(after) == 8, len(after)
def inner(t): return t.replace('((', '').replace('))', '').strip(' .')
a0 = inner(after[0])
istighfar, salam = a0[:a0.index('(')].strip(), a0[a0.index(')') + 1:].strip()
a3 = inner(after[3])
tasbih = [x.strip() for x in a3[:a3.index('(')].split('،')]
tahlil = a3[a3.index(')') + 1:].strip()
assert len(tasbih) == 3, tasbih
mu = after[4]
ak = after[5]
ak = after[5][:after[5].index('﴾') + 1]
mu = mu[:mu.rindex('﴾') + 1]
yuhyi = after[6].split('))')[0].replace('((', '')
ilm = after[7].split('))')[0].replace('((', '')
prayer = [
    {'text': istighfar, 'count': 3, 'virtue': '', 'ref': 'مسلم'},
    {'text': salam, 'count': 1, 'virtue': '', 'ref': 'مسلم'},
    {'text': inner(after[1]), 'count': 1, 'virtue': '', 'ref': 'البخاري ومسلم'},
    {'text': inner(after[2]), 'count': 1, 'virtue': '', 'ref': 'مسلم'},
    {'text': tasbih[0], 'count': 33, 'virtue': '', 'ref': 'مسلم'},
    {'text': tasbih[1], 'count': 33, 'virtue': '', 'ref': 'مسلم'},
    {'text': tasbih[2], 'count': 33, 'virtue': '', 'ref': 'مسلم'},
    {'text': tahlil, 'count': 1, 'virtue': 'من قال ذلك دبر كل صلاة غفرت خطاياه وإن كانت مثل زبد البحر.', 'ref': 'مسلم'},
    {'text': mu, 'count': 1, 'virtue': 'مرة بعد كل صلاة، وثلاث مرات بعد الفجر والمغرب.', 'ref': 'أبو داود والنسائي والترمذي'},
    {'text': ak, 'count': 1, 'virtue': 'من قرأها دبر كل صلاة لم يمنعه من دخول الجنة إلا أن يموت.', 'ref': 'النسائي في عمل اليوم والليلة'},
    {'text': yuhyi, 'count': 10, 'virtue': 'عشر مرات بعد صلاة المغرب والفجر.', 'ref': 'الترمذي وأحمد', 'only': ['fajr', 'maghrib']},
    {'text': ilm, 'count': 1, 'virtue': 'بعد السلام من صلاة الفجر.', 'ref': 'ابن ماجه', 'only': ['fajr']},
]
sl = [r for r in rows if r[0] == 'أذكار النوم']
assert len(sl) == 13, len(sl)
def sitem(r, count=1):
    return {'text': inner(clean(r[1])), 'count': count, 'virtue': clean(r[2] or ''), 'ref': ref(r[4] or '')}
t7 = inner(clean(sl[7][1]))
parts = [x.strip() for x in t7.replace(')', '(').split('(') if x.strip()]
# ['سُبْحَانَ اللَّهِ', 'ثلاثاً وثلاثين', 'وَالْحَمْدُ لِلَّهِ', 'ثلاثاً وثلاثين', 'وَاللَّهُ أَكْبَرُ', 'أربعاً وثلاثينَ']
assert len(parts) == 6, parts
sleep = []
for i, r in enumerate(sl):
    if i == 0:
        it = sitem(r, 3)
        it['text'] = it['text'].split(' (يفعلُ')[0].rstrip(' .)')
        it['virtue'] = 'يفعل ذلك ثلاث مرات.'
        sleep.append(it)
    elif i == 7:
        for t, c in ((parts[0], 33), (parts[2], 33), (parts[4], 34)):
            sleep.append({'text': t, 'count': c, 'virtue': '', 'ref': 'البخاري ومسلم'})
    else:
        sleep.append(sitem(r))
data = {
    'source': 'حصن المسلم للشيخ سعيد بن وهف القحطاني، عبر مجموعة البيانات المفتوحة osamayy/azkar-db',
    'morning': section('أذكار الصباح'),
    'evening': section('أذكار المساء'),
    'prayer': prayer,
    'sleep': sleep,
}
json.dump(data, open(out, 'w'), ensure_ascii=False, indent=1)
print({k: len(v) for k, v in data.items() if isinstance(v, list)})
