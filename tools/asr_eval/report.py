"""يلخّص نتائج asr_eval_test.dart: الأخطاء الكاذبة والالتقاط عند كل حدّ للتحقق."""
import csv, sys, collections

rows, cases, words, ayat = [], collections.Counter(), 0, 0
reached = collections.Counter()
for path in sys.argv[1:]:
    for r in csv.reader(open(path, encoding='utf-8')):
        if not r or r[0] == 'reciter':
            continue
        if r[0] == '#total':
            ayat += int(r[1]); words += int(r[2])
        elif r[0] == '#phrase':
            continue
        elif r[0] == '#case':
            cases[r[1]] += 1; reached[r[1]] += int(r[3])
        else:
            rows.append(dict(reciter=r[0], aya=r[1], cond=r[2], truth=r[3] == '1', kind=r[4],
                             delta=float(r[5]), heard=r[6], want=r[7]))

print(f'## تقييم التسميع: {ayat} آية، {words} كلمة، {len({r["reciter"] for r in rows})} قارئاً')
print(f'وصلت المتابعة إلى آخر الآية: {reached["ok"]} من {cases["ok"]}')
print()
print('| الحد | أخطاء كاذبة | لكل 1000 كلمة | التقاط المبدلة | التقاط الساقطة |')
print('|---|---|---|---|---|')
for m in [0, 2, 4, 6, 8, 10, 12, 15, 20, 30]:
    kept = [r for r in rows if r['delta'] >= m]
    fp = sum(1 for r in kept if not r['truth'])
    sub = sum(1 for r in kept if r['truth'] and r['cond'] == 'sub')
    skip = sum(1 for r in kept if r['truth'] and r['cond'] == 'skip')
    print(f'| {m} | {fp} | {1000 * fp / max(words, 1):.2f} | {sub}/{cases["sub"]} ({100 * sub / max(cases["sub"], 1):.0f}%)'
          f' | {skip}/{cases["skip"]} ({100 * skip / max(cases["skip"], 1):.0f}%) |')
print()
print('### الأخطاء الكاذبة في التلاوة الصحيحة (Δ ≥ 0)')
for r in sorted((r for r in rows if not r['truth']), key=lambda r: -r['delta'])[:80]:
    print(f'- {r["reciter"]} {r["aya"]} [{r["cond"]}] {r["kind"]} Δ={r["delta"]:.1f}: سُمع «{r["heard"]}» والمنتظر «{r["want"]}»')
print()
print('### أخطاء حقيقية لم تُلتقط بحدّ 6')
for r in [r for r in rows if r['truth'] and r['delta'] < 6][:40]:
    print(f'- {r["reciter"]} {r["aya"]} [{r["cond"]}] {r["kind"]} Δ={r["delta"]:.1f}: سُمع «{r["heard"]}» والمنتظر «{r["want"]}»')

print()
print('### الأخطاء الكاذبة في التلاوة الصحيحة لكل قارئ (بحدّ 6)')
per = collections.Counter(r['reciter'] for r in rows if r['cond'] == 'ok' and r['delta'] >= 6)
kinds = collections.Counter(r['kind'] for r in rows if r['cond'] == 'ok' and r['delta'] >= 6)
for k, v in per.most_common():
    print(f'- {k}: {v}')
print('الأنواع:', dict(kinds))
