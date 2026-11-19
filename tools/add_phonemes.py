"""يضيف إلى assets/data/quran.db جدول phon: أصوات كل كلمة من المصحف (حرفاً وحركة) كما يخرجها
نموذج متابعة التلاوة، كلمةً مقابل كل كلمة معروضة. المصدر معجم Quran-Lab
(quran_text2phoneme، رخصة NPL-1.2) بصيغة ملف «zipformer_quran.json».

    python3 tools/add_phonemes.py zipformer_quran.json assets/data/quran.db tools/data/quran-phonemes.tsv

يكتب أيضاً ملفاً نصياً (سورة، آية، الأصوات) ليُعاد بناء الجدول منه دون المعجم الأصلي:

    python3 tools/add_phonemes.py tools/data/quran-phonemes.tsv assets/data/quran.db
"""
import json, re, sqlite3, sys

MARKS = re.compile('[ؐ-ًؚ-ٰٟۖ-ۭـࣰ-ࣲ]')


def skeleton(w):
    return re.sub('[^ء-يٱ-ۓ]', '', MARKS.sub('', w))


src, out = sys.argv[1:3]
lex = {}
if src.endswith('.json'):
    for s in json.load(open(src, encoding='utf-8'))['surahs']:
        for a in s['ayahs']:
            lex[(s['n'], a['n'])] = [(w[1], w[2]) for w in a['w']]
else:
    for line in open(src, encoding='utf-8'):
        s, a, t = line.rstrip('\n').split('\t')
        lex[(int(s), int(a))] = [(w, '') for w in t.split(' ')]
assert len(lex) == 6236, len(lex)

db = sqlite3.connect(out)
db.execute('DROP TABLE IF EXISTS phon')
db.execute('CREATE TABLE phon(id INTEGER PRIMARY KEY, words TEXT NOT NULL)')
rows = db.execute('SELECT id, sura, aya, text FROM ayat ORDER BY id').fetchall()
merged = 0
tsv = []
for i, s, a, text in rows:
    disp = [w for w in text.split(' ') if skeleton(w)]
    ph = [w[0] for w in lex[(s, a)]]
    ut = [w[1] for w in lex[(s, a)]]
    # كلمتان في المعجم تُكتبان كلمة واحدة في مصحف المدينة («لَّوۡمَا»، «مَالِيَ»): تُضمّان.
    while len(ph) > len(disp) and ut[0]:
        for k in range(len(disp)):
            if len(skeleton(disp[k])) >= len(skeleton(ut[k])) + len(skeleton(ut[k + 1])) - 1 and \
                    skeleton(disp[k])[:2] == skeleton(ut[k])[:2] and len(skeleton(ut[k])) < len(skeleton(disp[k])):
                ph[k:k + 2] = [ph[k] + ph[k + 1]]
                ut[k:k + 2] = [ut[k] + ut[k + 1]]
                merged += 1
                break
        else:
            raise SystemExit(f'تعذّرت مقابلة {s}:{a}')
    assert len(ph) == len(disp), (s, a, len(ph), len(disp))
    assert all(' ' not in w and w for w in ph)
    db.execute('INSERT INTO phon VALUES(?,?)', (i, ' '.join(ph)))
    tsv.append(f'{s}\t{a}\t{" ".join(ph)}\n')
db.execute("INSERT OR REPLACE INTO meta VALUES('phon','Quran-Lab quran_text2phoneme (NPL-1.2), huggingface.co/Quran-Lab')")
db.commit()
db.execute('VACUUM')
db.close()
if len(sys.argv) > 3:
    open(sys.argv[3], 'w', encoding='utf-8').writelines(tsv)
print('ok', len(rows), 'merged', merged)
