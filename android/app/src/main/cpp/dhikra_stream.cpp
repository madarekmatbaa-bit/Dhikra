// متابعة التلاوة المباشرة: نموذج Zipformer2-CTC (ONNX) يخرج أصوات التلاوة (حرفاً وحركة) كل
// نصف ثانية تقريباً أثناء القراءة. يستدعيه التطبيق عبر dart:ffi.
//
// الدخل صوت أحادي 16 كيلوهرتز (أعداد عشرية بين -1 و1) يُعطى قطعةً قطعة. تُحسب منه خصائص
// fbank على طريقة Kaldi (80 قناة، نافذة povey، 25ms كل 10ms)، ويأخذ النموذج 61 إطاراً في
// كل مرة ويتقدم 48، فيخرج 12 إطاراً (40ms لكل إطار) من لوغاريتم احتمال كل رمز.
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "onnxruntime_c_api.h"

#define ZQ_API extern "C" __attribute__((visibility("default"))) __attribute__((used))

namespace {

const int kRate = 16000, kWin = 400, kShift = 160, kFft = 512, kBins = 80;
const int kChunk = 61, kHop = 48;
const int kMaxOut = 16; // أكثر ما يخرجه النموذج من إطارات في المرة (12 فعلاً)

// تحويل فورييه لطول 512 (قوة اثنين)، في مكانه.
void fft(std::vector<float> &re, std::vector<float> &im) {
    const int n = (int)re.size();
    for (int i = 1, j = 0; i < n; i++) {
        int bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) {
            std::swap(re[i], re[j]);
            std::swap(im[i], im[j]);
        }
    }
    for (int len = 2; len <= n; len <<= 1) {
        const double ang = -2 * M_PI / len;
        const float wr = (float)std::cos(ang), wi = (float)std::sin(ang);
        for (int i = 0; i < n; i += len) {
            float cr = 1, ci = 0;
            for (int k = 0; k < len / 2; k++) {
                const int a = i + k, b = i + k + len / 2;
                const float xr = re[b] * cr - im[b] * ci, xi = re[b] * ci + im[b] * cr;
                re[b] = re[a] - xr;
                im[b] = im[a] - xi;
                re[a] += xr;
                im[a] += xi;
                const float nr = cr * wr - ci * wi;
                ci = cr * wi + ci * wr;
                cr = nr;
            }
        }
    }
}

struct Fbank {
    std::vector<float> window;
    // لكل قناة: أول خانة تردد وأوزانها.
    std::vector<int> first;
    std::vector<std::vector<float>> weights;
    std::vector<float> re, im;

    Fbank() : window(kWin), first(kBins), weights(kBins), re(kFft), im(kFft) {
        for (int i = 0; i < kWin; i++) {
            window[i] = (float)std::pow(0.5 - 0.5 * std::cos(2 * M_PI * i / (kWin - 1)), 0.85);
        }
        auto mel = [](double f) { return 1127.0 * std::log(1.0 + f / 700.0); };
        const double lo = mel(20.0), hi = mel(kRate / 2.0 - 400.0);
        const double delta = (hi - lo) / (kBins + 1), binw = (double)kRate / kFft;
        for (int b = 0; b < kBins; b++) {
            const double left = lo + b * delta, center = left + delta, right = center + delta;
            first[b] = -1;
            for (int i = 0; i < kFft / 2; i++) {
                const double m = mel(binw * i);
                if (m > left && m < right) {
                    if (first[b] < 0) first[b] = i;
                    weights[b].push_back((float)(m <= center ? (m - left) / (center - left) : (right - m) / (right - center)));
                }
            }
        }
    }

    // إطار واحد من 400 عينة → 80 قيمة.
    void compute(const float *frame, float *out) {
        double mean = 0;
        for (int i = 0; i < kWin; i++) mean += frame[i];
        mean /= kWin;
        std::fill(re.begin(), re.end(), 0.f);
        std::fill(im.begin(), im.end(), 0.f);
        for (int i = 0; i < kWin; i++) re[i] = frame[i] - (float)mean;
        for (int i = kWin - 1; i > 0; i--) re[i] -= 0.97f * re[i - 1];
        re[0] -= 0.97f * re[0];
        for (int i = 0; i < kWin; i++) re[i] *= window[i];
        fft(re, im);
        for (int b = 0; b < kBins; b++) {
            double e = 0;
            const int f0 = first[b];
            for (size_t k = 0; k < weights[b].size(); k++) {
                const int i = f0 + (int)k;
                e += weights[b][k] * (re[i] * re[i] + im[i] * im[i]);
            }
            out[b] = (float)std::log(e < 1.1920929e-07 ? 1.1920929e-07 : e);
        }
    }
};

std::string g_error; // آخر خطأ، ليُعرض سببه

struct Stream {
    const OrtApi *api = nullptr;
    OrtEnv *env = nullptr;
    OrtSession *session = nullptr;
    OrtAllocator *alloc = nullptr;
    OrtMemoryInfo *mem = nullptr;

    std::vector<std::string> inNames, outNames;
    std::vector<const char *> inPtrs, outPtrs;
    std::vector<std::vector<int64_t>> inShapes;
    std::vector<ONNXTensorElementDataType> inTypes;
    // مكان كل حالة داخلة في قائمة المخارج (new_<اسمها>).
    std::vector<int> stateFrom;
    std::vector<OrtValue *> states; // بترتيب المداخل، والأول (x) فارغ
    int vocab = 0;

    Fbank fbank;
    std::vector<float> pcm;   // عينات لم تُحسب خصائصها بعد
    int64_t consumed = 0;     // عدد العينات التي حُذفت من أول pcm
    int64_t nextFrame = 0;    // رقم إطار الخصائص التالي
    std::vector<float> feats; // إطارات الخصائص المنتظرة (80 لكل إطار)
    std::string error;

    bool ok(OrtStatus *st) {
        if (!st) return true;
        error = api->GetErrorMessage(st);
        g_error = error;
        api->ReleaseStatus(st);
        return false;
    }

    void freeStates() {
        for (auto *&v : states) {
            if (v) api->ReleaseValue(v);
            v = nullptr;
        }
    }

    bool reset() {
        freeStates();
        states.assign(inNames.size(), nullptr);
        for (size_t i = 1; i < inNames.size(); i++) {
            if (!ok(api->CreateTensorAsOrtValue(alloc, inShapes[i].data(), inShapes[i].size(), inTypes[i], &states[i]))) return false;
            size_t n = 1;
            for (auto d : inShapes[i]) n *= (size_t)d;
            void *data = nullptr;
            if (!ok(api->GetTensorMutableData(states[i], &data))) return false;
            memset(data, 0, n * (inTypes[i] == ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64 ? 8 : 4));
        }
        pcm.clear();
        feats.clear();
        consumed = 0;
        nextFrame = 0;
        return true;
    }

    ~Stream() {
        if (!api) return;
        freeStates();
        if (mem) api->ReleaseMemoryInfo(mem);
        if (session) api->ReleaseSession(session);
        if (env) api->ReleaseEnv(env);
    }
};

float sampleAt(const Stream &s, int64_t idx, int64_t total) {
    // أول الصوت يُعكس كما في Kaldi (snip_edges=false).
    if (idx < 0) idx = -idx - 1;
    if (idx >= total) idx = 2 * total - 1 - idx;
    idx -= s.consumed;
    return idx >= 0 && idx < (int64_t)s.pcm.size() ? s.pcm[(size_t)idx] : 0.f;
}

} // namespace

ZQ_API void *zq_init(const char *model_path, int threads) {
    auto *s = new Stream();
    s->api = OrtGetApiBase()->GetApi(ORT_API_VERSION);
    if (!s->api) {
        delete s;
        return nullptr;
    }
    const OrtApi *a = s->api;
    OrtSessionOptions *so = nullptr;
    bool good = s->ok(a->CreateEnv(ORT_LOGGING_LEVEL_ERROR, "dhikra", &s->env)) && s->ok(a->CreateSessionOptions(&so));
    if (good) {
        (void)s->ok(a->SetIntraOpNumThreads(so, threads > 0 ? threads : 2));
        (void)s->ok(a->SetInterOpNumThreads(so, 1));
        (void)s->ok(a->SetSessionGraphOptimizationLevel(so, ORT_ENABLE_ALL));
        good = s->ok(a->CreateSession(s->env, model_path, so, &s->session));
    }
    if (so) a->ReleaseSessionOptions(so);
    good = good && s->ok(a->GetAllocatorWithDefaultOptions(&s->alloc)) &&
           s->ok(a->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &s->mem));
    size_t nIn = 0, nOut = 0;
    good = good && s->ok(a->SessionGetInputCount(s->session, &nIn)) && s->ok(a->SessionGetOutputCount(s->session, &nOut));
    for (size_t i = 0; good && i < nIn; i++) {
        char *name = nullptr;
        good = s->ok(a->SessionGetInputName(s->session, i, s->alloc, &name));
        if (!good) break;
        s->inNames.emplace_back(name);
        (void)s->ok(a->AllocatorFree(s->alloc, name));
        OrtTypeInfo *ti = nullptr;
        good = s->ok(a->SessionGetInputTypeInfo(s->session, i, &ti));
        if (!good) break;
        const OrtTensorTypeAndShapeInfo *info = nullptr;
        (void)s->ok(a->CastTypeInfoToTensorInfo(ti, &info));
        size_t nd = 0;
        (void)s->ok(a->GetDimensionsCount(info, &nd));
        std::vector<int64_t> dims(nd);
        (void)s->ok(a->GetDimensions(info, dims.data(), nd));
        for (auto &d : dims) {
            if (d <= 0) d = 1; // حجم الدفعة
        }
        ONNXTensorElementDataType t;
        (void)s->ok(a->GetTensorElementType(info, &t));
        s->inShapes.push_back(dims);
        s->inTypes.push_back(t);
        a->ReleaseTypeInfo(ti);
    }
    for (size_t i = 0; good && i < nOut; i++) {
        char *name = nullptr;
        good = s->ok(a->SessionGetOutputName(s->session, i, s->alloc, &name));
        if (!good) break;
        s->outNames.emplace_back(name);
        (void)s->ok(a->AllocatorFree(s->alloc, name));
    }
    if (good) {
        good = !s->inNames.empty() && s->inNames[0] == "x" && !s->outNames.empty() && s->outNames[0] == "log_probs";
    }
    if (good) {
        s->stateFrom.assign(s->inNames.size(), -1);
        for (size_t i = 1; i < s->inNames.size(); i++) {
            const std::string want = "new_" + s->inNames[i];
            for (size_t o = 0; o < s->outNames.size(); o++) {
                if (s->outNames[o] == want) s->stateFrom[i] = (int)o;
            }
            if (s->stateFrom[i] < 0) good = false;
        }
        for (auto &n : s->inNames) s->inPtrs.push_back(n.c_str());
        for (auto &n : s->outNames) s->outPtrs.push_back(n.c_str());
    }
    if (!good || !s->reset()) {
        if (g_error.empty()) g_error = "unexpected model inputs";
        delete s;
        return nullptr;
    }
    return s;
}

ZQ_API const char *zq_error() { return g_error.c_str(); }

ZQ_API void zq_free(void *ctx) { delete static_cast<Stream *>(ctx); }

// يبدأ تلاوة جديدة: تُصفَّر حالة النموذج وما بقي من صوت.
ZQ_API int zq_reset(void *ctx) { return ctx && static_cast<Stream *>(ctx)->reset() ? 0 : -1; }

// يضيف [n] عينة، ويكتب في [out] ما اكتمل من إطارات (vocab قيمة لكل إطار، لوغاريتم الاحتمال).
// يعيد عدد الإطارات المكتوبة (لا يتجاوز cap_frames)، أو -1 عند الفشل.
ZQ_API int zq_accept(void *ctx, const float *pcm, int n, float *out, int cap_frames) {
    if (!ctx || n < 0) return -1;
    auto *s = static_cast<Stream *>(ctx);
    const OrtApi *a = s->api;
    if (n > 0) s->pcm.insert(s->pcm.end(), pcm, pcm + n);
    const int64_t total = s->consumed + (int64_t)s->pcm.size();
    // الإطار t يبدأ عند العينة 160t - 120 ويحتاج 400 عينة.
    float frame[kWin];
    while (true) {
        const int64_t start = s->nextFrame * kShift - (kWin - kShift) / 2;
        if (start + kWin > total) break;
        for (int i = 0; i < kWin; i++) frame[i] = sampleAt(*s, start + i, total);
        s->feats.resize(s->feats.size() + kBins);
        s->fbank.compute(frame, s->feats.data() + s->feats.size() - kBins);
        s->nextFrame++;
    }
    // نحذف ما لن يُحتاج من العينات (يبقى ما قبل بداية الإطار التالي).
    const int64_t keepFrom = s->nextFrame * kShift - (kWin - kShift) / 2;
    if (keepFrom > s->consumed) {
        const int64_t drop = keepFrom - s->consumed < (int64_t)s->pcm.size() ? keepFrom - s->consumed : (int64_t)s->pcm.size();
        s->pcm.erase(s->pcm.begin(), s->pcm.begin() + drop);
        s->consumed += drop;
    }

    int written = 0;
    while ((int)(s->feats.size() / kBins) >= kChunk && written + kMaxOut <= cap_frames) {
        const int64_t xShape[3] = {1, kChunk, kBins};
        OrtValue *x = nullptr;
        if (!s->ok(a->CreateTensorWithDataAsOrtValue(s->mem, s->feats.data(), (size_t)kChunk * kBins * sizeof(float), xShape, 3,
                                                     ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &x))) {
            return -1;
        }
        std::vector<const OrtValue *> ins(s->inNames.size());
        ins[0] = x;
        for (size_t i = 1; i < ins.size(); i++) ins[i] = s->states[i];
        std::vector<OrtValue *> outs(s->outNames.size(), nullptr);
        const bool good = s->ok(a->Run(s->session, nullptr, s->inPtrs.data(), ins.data(), ins.size(), s->outPtrs.data(), outs.size(), outs.data()));
        a->ReleaseValue(x);
        if (!good) {
            for (auto *v : outs) {
                if (v) a->ReleaseValue(v);
            }
            return -1;
        }
        // شكل المخرج [1، إطارات، رموز] يُقرأ من النتيجة نفسها.
        OrtTensorTypeAndShapeInfo *info = nullptr;
        int64_t dims[3] = {0, 0, 0};
        size_t nd = 0;
        if (s->ok(a->GetTensorTypeAndShape(outs[0], &info))) {
            (void)s->ok(a->GetDimensionsCount(info, &nd));
            if (nd == 3) (void)s->ok(a->GetDimensions(info, dims, 3));
            a->ReleaseTensorTypeAndShapeInfo(info);
        }
        float *lp = nullptr;
        (void)s->ok(a->GetTensorMutableData(outs[0], (void **)&lp));
        const int frames = (int)dims[1];
        if (nd != 3 || !lp || (s->vocab && dims[2] != s->vocab) || written + frames > cap_frames) {
            for (auto *v : outs) {
                if (v) a->ReleaseValue(v);
            }
            g_error = "unexpected model output";
            return -1;
        }
        s->vocab = (int)dims[2];
        memcpy(out + (size_t)written * s->vocab, lp, (size_t)frames * s->vocab * sizeof(float));
        written += frames;
        a->ReleaseValue(outs[0]);
        outs[0] = nullptr;
        for (size_t i = 1; i < s->inNames.size(); i++) {
            a->ReleaseValue(s->states[i]);
            s->states[i] = outs[s->stateFrom[i]];
            outs[s->stateFrom[i]] = nullptr;
        }
        for (auto *v : outs) {
            if (v) a->ReleaseValue(v);
        }
        s->feats.erase(s->feats.begin(), s->feats.begin() + (size_t)kHop * kBins);
    }
    return written;
}
