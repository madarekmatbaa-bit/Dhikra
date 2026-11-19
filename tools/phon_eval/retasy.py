"""تسجيلات RetaSy/quranic_audio_dataset (قرّاء عاديون غير عرب سجّلوا بهواتفهم، ومعها حكم
المراجعين: صحيحة أو خاطئة): يشغّل عليها النموذج ويكتب ملفات ‎.top‎ وجدولاً بوصف كل تسجيل.

    python3 tools/phon_eval/retasy.py train-00000-of-00003.parquet 0 out_dir model.onnx [model2.onnx]
"""
import io, os, sys
import numpy as np
import pyarrow.parquet as pq
import soundfile as sf
from scipy.signal import resample_poly

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import phon_dump as P

path, shard, out = sys.argv[1], sys.argv[2], sys.argv[3]
models = [P.load(m) for m in sys.argv[4:]]
for k in range(len(models)):
    os.makedirs(f'{out}/m{k}', exist_ok=True)
pf = pq.ParquetFile(path)
meta = open(f'{out}/retasy-{shard}.tsv', 'w', encoding='utf-8')
n = 0
for batch in pf.iter_batches(batch_size=16):
    for row in batch.to_pylist():
        n += 1
        name = f'retasy{shard}-{n:05d}'
        a = row['audio']
        try:
            pcm, sr = sf.read(io.BytesIO(a['bytes']), dtype='float32', always_2d=True)
            pcm = pcm.mean(axis=1)
            if sr != 16000:
                pcm = resample_poly(pcm, 16000, sr).astype(np.float32)
        except Exception as e:  # تسجيل تالف
            print('skip', name, e)
            continue
        if len(pcm) < 8000 or len(pcm) > 16000 * 90:
            continue
        for k, m in enumerate(models):
            P.write_top(f'{out}/m{k}/{name}.top', P.transcribe(m, pcm))
        f = lambda x: str(row.get(x, '')).replace('\t', ' ').replace('\n', ' ')
        meta.write('\t'.join([name, f('Surah'), f('Aya'), f('final_label'), f('golden'), f('reciter_country'),
                              f('reciter_gender'), f('reciter_age'), f('duration_ms'), f('reciter_id')]) + '\n')
        if n % 200 == 0:
            print(n, flush=True)
meta.close()
print('done', n)
