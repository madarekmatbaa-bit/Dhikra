// واجهة صغيرة فوق whisper.cpp يستدعيها التطبيق عبر dart:ffi.
// تأخذ صوتاً أحادياً بتردد 16 كيلوهرتز (أعداد عشرية بين -1 و1) وتعيد النص.
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <cmath>

#include "whisper.h"

#define DQ_API extern "C" __attribute__((visibility("default"))) __attribute__((used))

static void dq_quiet_log(enum ggml_log_level, const char *, void *) {}

DQ_API void *dq_init(const char *model_path) {
    whisper_log_set(dq_quiet_log, nullptr);
    whisper_context_params cp = whisper_context_default_params();
    cp.use_gpu = false;
    cp.flash_attn = false;
    return whisper_init_from_file_with_params(model_path, cp);
}

DQ_API void dq_free(void *ctx) {
    if (ctx) whisper_free(static_cast<whisper_context *>(ctx));
}

DQ_API void dq_free_str(char *s) { free(s); }

// يعيد النص (يحرره المستدعي بـ dq_free_str)، أو nullptr عند الفشل.
// prompt: ما قرأه القارئ قبل هذا المقطع من نص المصحف، ليتّبع النموذج إملاءه.
// audio_ctx: 0 للنافذة الكاملة (30 ثانية)، أو عدد أقل لتسريع المقاطع القصيرة.
DQ_API char *dq_transcribe(void *ctx, const float *pcm, int n_samples, const char *prompt, int audio_ctx,
                           int threads) {
    if (!ctx || !pcm || n_samples <= 0) return nullptr;
    auto *wctx = static_cast<whisper_context *>(ctx);
    whisper_full_params p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    p.n_threads = threads > 0 ? threads : 4;
    p.language = "ar";
    p.detect_language = false;
    p.translate = false;
    p.no_context = true;
    p.no_timestamps = true;
    p.single_segment = false;
    p.print_progress = false;
    p.print_realtime = false;
    p.print_special = false;
    p.print_timestamps = false;
    p.suppress_blank = true;
    p.suppress_nst = true;
    p.temperature = 0.0f;
    // بلا إعادة بحرارة أعلى: وقت ثابت يناسب المتابعة الحية.
    p.temperature_inc = 0.0f;
    p.greedy.best_of = 1;
    p.audio_ctx = audio_ctx;
    // حدّ للرموز بقدر طول المقطع، فلا يدور النموذج في تكرار إن اضطرب.
    p.max_tokens = 32 + (n_samples / 16000) * 24;
    if (prompt && prompt[0]) p.initial_prompt = prompt;

    if (whisper_full(wctx, p, pcm, n_samples) != 0) return nullptr;
    std::string out;
    const int n = whisper_full_n_segments(wctx);
    for (int i = 0; i < n; i++) {
        const char *t = whisper_full_get_segment_text(wctx, i);
        if (t) {
            if (!out.empty()) out += ' ';
            out += t;
        }
    }
    char *r = static_cast<char *>(malloc(out.size() + 1));
    memcpy(r, out.c_str(), out.size() + 1);
    return r;
}

// احتمال النص [text] (لوغاريتم، مجموعاً على رموزه) لآخر صوت مرّ على dq_transcribe.
// به نوازن بين ما سمعه النموذج وما في المصحف: إن كان نص المصحف قريب الاحتمال
// فالنموذج غير متأكد، ولا نعدّ الكلمة خطأً.
// يعيد أيضاً عدد الرموز في [n_tokens_out]. يعيد 1 عند الفشل.
DQ_API float dq_score(void *ctx, const char *text, int threads, int *n_tokens_out) {
    if (n_tokens_out) *n_tokens_out = 0;
    if (!ctx || !text) return 1.0f;
    auto *wctx = static_cast<whisper_context *>(ctx);
    const int n_max = 448;
    std::vector<whisper_token> toks(n_max);
    const int n = whisper_tokenize(wctx, text, toks.data(), n_max - 8);
    if (n <= 0) return 1.0f;
    std::vector<whisper_token> prefix = {
        whisper_token_sot(wctx),
        whisper_token_lang(wctx, whisper_lang_id("ar")),
        whisper_token_transcribe(wctx),
        whisper_token_not(wctx),
    };
    const int th = threads > 0 ? threads : 4;
    if (whisper_decode(wctx, prefix.data(), (int)prefix.size(), 0, th) != 0) return 1.0f;
    const int n_vocab = whisper_n_vocab(wctx);
    double total = 0;
    int past = (int)prefix.size();
    // الرمز التالي بعد النص: نهاية النص، فلا يُكافأ نص مبتور.
    toks[n] = whisper_token_eot(wctx);
    for (int i = 0; i <= n; i++) {
        const float *logits = whisper_get_logits(wctx);
        float mx = -1e30f;
        for (int v = 0; v < n_vocab; v++) mx = logits[v] > mx ? logits[v] : mx;
        double sum = 0;
        for (int v = 0; v < n_vocab; v++) sum += std::exp((double)(logits[v] - mx));
        total += (double)(logits[toks[i]] - mx) - std::log(sum);
        if (i == n) break;
        if (whisper_decode(wctx, &toks[i], 1, past, th) != 0) return 1.0f;
        past++;
    }
    if (n_tokens_out) *n_tokens_out = n;
    return (float)total;
}
