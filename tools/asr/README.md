# نموذج التسميع

`asr-model.yml` يحوّل نموذجَي Tarteel (Whisper معدّل على تلاوة القرآن) إلى صيغة ggml
التي يقرؤها whisper.cpp، ويصغّرهما، ويجرّبهما على تلاوات من everyayah، ثم ينشرهما
في الإصدار `asr-2` ليُنزّلهما التطبيق عند أول استعمال.

- tarteel-ai/whisper-base-ar-quran
- tarteel-ai/whisper-tiny-ar-quran

لتشغيله من جديد عدّل `version.txt` هنا.
