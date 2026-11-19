"""يختار آيات عشوائية ثابتة لكل قارئ (قارئ ورمز الآية في كل سطر)."""
import random, sqlite3, sys

db, shard, shards, per = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
c = sqlite3.connect(db)
rows = c.execute('select a.sura, a.aya, p.words from ayat a join phon p on p.id = a.id order by a.id').fetchall()
reciters = [l.strip() for l in open('tools/phon_eval/reciters.txt') if l.strip() and not l.startswith('#')]
ok = [(s, a) for s, a, t in rows if 3 <= len(t.split()) <= 35]
for k, r in enumerate(reciters):
    if k % shards != shard:
        continue
    rnd = random.Random(r)
    for s, a in rnd.sample(ok, per):
        print(r, f'{s:03d}{a:03d}')
