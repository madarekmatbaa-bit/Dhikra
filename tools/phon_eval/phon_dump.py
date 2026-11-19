"""يشغّل نموذج متابعة التلاوة (Zipformer2-CTC، ONNX) على تسجيلات ويكتب لكل تسجيل ملف ‎.top‎:
لكل إطار (40ms) أرجح ثلاثة رموز (3 بايت) واحتمالاتها (3 أعداد float32). هذا ما يقرؤه
test/phoneme_eval_test.dart، فيُعاد تقييم المتابعة دون إعادة تشغيل النموذج.

    python3 tools/phon_eval/phon_dump.py model.onnx out_dir a.wav b.wav ...
"""
import os, sys, wave
import numpy as np
import onnxruntime as ort
import kaldi_native_fbank as knf

T, HOP = 61, 48


def load(model, threads=4):
    so = ort.SessionOptions()
    so.intra_op_num_threads = threads
    return ort.InferenceSession(model, so, providers=['CPUExecutionProvider'])


def feats(pcm):
    o = knf.FbankOptions()
    o.frame_opts.dither = 0
    o.frame_opts.snip_edges = False
    o.frame_opts.samp_freq = 16000
    o.mel_opts.num_bins = 80
    o.mel_opts.high_freq = -400
    f = knf.OnlineFbank(o)
    f.accept_waveform(16000, pcm.tolist())
    f.input_finished()
    return np.stack([f.get_frame(i) for i in range(f.num_frames_ready)])


def run(s, x):
    st = {}
    for i in s.get_inputs():
        if i.name != 'x':
            shape = [d if isinstance(d, int) else 1 for d in i.shape]
            st[i.name] = np.zeros(shape, np.int64 if 'int64' in i.type else np.float32)
    outs = [o.name for o in s.get_outputs()]
    x = np.concatenate([x, np.full((T, 80), np.log(1e-10), np.float32)])
    lp, i = [], 0
    while i + T <= len(x):
        r = s.run(outs, {'x': x[None, i:i + T].astype(np.float32), **st})
        lp.append(r[0][0])
        for n, v in zip(outs[1:], r[1:]):
            st[n[4:]] = v
        i += HOP
    return np.concatenate(lp)


def top3(lp):
    ids = np.argsort(-lp, axis=1)[:, :3]
    p = np.exp(np.take_along_axis(lp, ids, axis=1)).astype('<f4')
    return ids.astype(np.uint8), p


def write_top(path, lp):
    ids, p = top3(lp)
    with open(path, 'wb') as f:
        for i in range(len(ids)):
            f.write(ids[i].tobytes())
            f.write(p[i].tobytes())


def transcribe(s, pcm):
    """الصوت (float32، 16 كيلوهرتز) مع ثلث ثانية صمت قبله وثانية بعده."""
    a = np.concatenate([np.zeros(4800, np.float32), pcm.astype(np.float32), np.zeros(16000, np.float32)])
    return run(s, feats(a))


def read_wav(p):
    w = wave.open(p)
    assert w.getframerate() == 16000 and w.getnchannels() == 1 and w.getsampwidth() == 2, p
    return np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768


if __name__ == '__main__':
    model, out = sys.argv[1:3]
    os.makedirs(out, exist_ok=True)
    s = load(model)
    for p in sys.argv[3:]:
        write_top(os.path.join(out, os.path.basename(p)[:-4] + '.top'), transcribe(s, read_wav(p)))
    print('done', len(sys.argv) - 3)
