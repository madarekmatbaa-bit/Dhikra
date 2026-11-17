"""يختار آيات عشوائية ثابتة لكل قارئ، ويكتب نص المصحف المشكول للتقييم."""
import random, sqlite3, sys

db, shard, shards, per, out_tsv = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
c = sqlite3.connect(db)
rows = c.execute('select a.id, a.sura, a.aya, v.text from ayat a join voweled v on v.id = a.id order by a.id').fetchall()
with open(out_tsv, 'w', encoding='utf-8') as f:
    for i, s, a, t in rows:
        f.write(f'{i}\t{t}\n')
reciters = [l.strip() for l in open('tools/asr_eval/reciters.txt') if l.strip() and not l.startswith('#')]
ok = [(s, a) for i, s, a, t in rows if 3 <= len(t.split()) <= 35]
for k, r in enumerate(reciters):
    if k % shards != shard:
        continue
    rnd = random.Random(r)
    for s, a in rnd.sample(ok, per):
        print(r, f'{s:03d}{a:03d}')
