# Yürütme adaptörleri (F12) ve isteğe bağlı LiteLLM (F13)

## Sözleşme
Yerleşik host'lar (`claude codex opencode cursor gemini`) `run-role.sh` ile **eskisi gibi** çalışır; `core/adapters.json` yeteneklerini bildirir. Harici adaptör `<project-dir>/adapters.d/<ad>.sh` (veya kit'in `adapters.d/`) çalıştırılabilir dosyasıdır; `run-role.sh --host ext:<ad>` ile çağrılır, yani risk tabanı, spawn kaydı, `parse-verdict --record`, kullanım defteri ve yönlendirme yolu **değişmez**. Adaptör kendi verdict'ini asla kaydetmez.

| Fiil | Çağrı | Beklenen çıktı |
|---|---|---|
| capabilities | `<f> capabilities` | tam 8 anahtarlı JSON (`noninteractive tool_use model_selection usage_reporting structured_output cancellation timeout cost_reporting`), değerler `help-verified\|declared\|estimated\|kit\|none` |
| execute | `<f> execute --role R --cwd D --tier T --ro 0\|1 [--model M] --prompt-file P` | `{"result": metin, "usage": {input_tokens, output_tokens, cache_*?}}`; `usage` yoksa **ölçülmedi** (sıfır değil) |
| status / cancel | `<f> status\|cancel [id]` | desteklenmiyorsa çıkış 3; `adapter.sh` bunu "unsupported" diye bildirir |
| usage | `adapter.sh usage <host>` | `none` / `declared`; sıfır uydurmaz |
| evidence | `run-role.sh` → `parse-verdict.sh --record` | adaptörden bağımsız |

`scripts/adapter.sh capabilities|usage|cancel|status|validate`. Yerleşik host'larda iptal yoktur (yalnız `timeout` komutu varsa süre sınırı); eşitlik taklit edilmez.

## LiteLLM / OpenAI uyumlu uç nokta (F13, varsayılan kapalı)
`adapters.d/litellm.sh`: `POST <LITELLM_BASE_URL>/chat/completions`. **Yalnız metin**: araç yok, dosya erişimi yok; bu yüzden `verifier/reviewer/security-auditor` ve yazan roller reddedilir (bağımsız karar yapıştırılmış içeriğe dayanamaz). `LITELLM_EGRESS=allow` olmadan hiçbir şey gönderilmez (istem repo içeriği taşıyabilir); sunucu `LITELLM_ALLOW_HOSTS` listesinde olmalı (varsayılan yalnız localhost). Anahtar ortam değişkeninden okunur (`LITELLM_API_KEY_ENV`), curl'e **stdin** ile verilir, hata iletilerinden maskelenir. Sağlayıcı hataları çıkış 5. Kullanım yanıttaki `usage`'dan; yoksa ölçülmedi. Model başına atıf `--model` ile kullanım defterine yazılır.
Claude abonelik trafiği LiteLLM'den **geçmez**. **FusionCLI için adaptör yok**: komut yüzeyi buradan doğrulanamadı; gerçek `--help` ile yazılmalı. Testler sahte `curl` kullanır (`tests/litellm.test.sh`); canlı uç noktaya karşı denenmedi.
