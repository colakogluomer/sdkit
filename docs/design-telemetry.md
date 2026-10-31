# Temel ölçüm ve telemetri (F01)

Durum: **uygulandı**, 1.1.0 üzerinde, F00/F00.5 değişikliklerinin üstüne. Bu belge F01'in spec'i, tasarımı, görev listesi ve doğrulama kaydıdır (kitin kendi tasarım kayıtları gibi `docs/` altında). Amaç, mimariyi değiştirmeden önce **bugünkü** SDKit'in bir iş akışını ne kadar verimli yürüttüğünü ölçebilmek. Bu sürüm hiçbir tasarruf iddiası taşımaz: tasarruf ancak aynı senaryonun önce/sonra ölçümüyle söylenebilir (`bench/run.sh compare`).

## 1. Spec

Kapsam: görev başına yapılandırılmış yerel olay günlüğü, onu okuyan rapor, sınır noktalarına takılmış olay yazımı, tekrarlanabilir bir benchmark çerçevesi.
Kapsam dışı (bilerek): LiteLLM/proxy, dış servis veya veritabanı, pano, ajan davranışı ya da model yönlendirmesi değişikliği, faz makinesi değişikliği.

Kabul ölçütleri (DoD) ve kanıtı (`tests/telemetry.test.sh`, hepsi geçti; bölüm 6):

| # | Ölçüt | Kanıt bölümü |
|---|---|---|
| D1 | Olay şeması tek yerde tanımlı; geçersiz olay yazılmaz, bozuk satır `validate` ile bulunur | "schema and validation" |
| D2 | Her olay görev, koşu (`run`) ve gerekiyorsa `span` ile ilişkilenir; yeni `task.start` yeni koşu açar | "correlation ids" |
| D3 | Eşzamanlı yazım satır kaybetmez ve bozmaz | "concurrent recording" |
| D4 | Ölçülemeyen değer yazılmaz ve `unavailable` olarak işaretlenir, 0 yazılmaz; her ölçüm `actual/estimated/unavailable` | "missing or incomplete usage data" |
| D5 | Telemetri hatası iş akışını bozmaz (jq yok, yazılamayan dizin, bozuk/eksik betik, geçersiz alan) | "failure isolation" |
| D6 | Varsayılan kapalı; kapalıyken mevcut davranış ve dosyalar aynı; token defteri (`usage.jsonl`) ikinci bir defter olmaz | "backward compatibility", "off by default" |
| D7 | Prompt, kimlik bilgisi, dosya içeriği kaydedilmez | şema (bölüm 2), test "no prompt-like field" |
| D8 | Dört temsilî iş akışı benchmark'ı; deterministik koşu tekrarlanabilir; gerçek LLM koşusu yalnızca açık talimatla | "benchmarks" |
| D9 | Yerel komut: özet, durum, ajan/faz süreleri, token, (güvenilir fiyat varsa) maliyet, yeniden deneme/hata, doğrulama; okunur çıktı ve `--json` | "the phase machine ..." ve bench |
| D10 | Mevcut test paketi geçer | bölüm 6 |

## 2. Mevcut yeteneklerin yeniden kullanımı (F00'a göre)

| Mevcut | F01'de |
|---|---|
| `usage.sh` / `usage.jsonl` (token defteri; Claude hook'u ve `run-role.sh` yazar) | **Token defteri olarak kalır.** `agent.end` olayı aynı sayıları kaynak etiketiyle taşır; rapor `usage.sh` satırlarını "çapraz kontrol" olarak ayrıca gösterir, toplamlara karıştırmaz (çift sayım olmasın) |
| `sdkit_active_slug` (ADR-0002), `sdkit_lock`, `env.sh` ayrıştırıcısı | Görev çözümü, kilit (yalnızca ilk `run.id`), ayar okuma. `sdkit_lock` yazılamayan dizinde sonsuz beklerdi; bu feature'ın hata yalıtımını sınarken bulundu ve düzeltildi (`[ -w dir ] || return 0`) |
| `sdd.sh` faz geçmişi (`history`, `done`'da silinir) | Olaylar kalıcı: `phase.enter` her geçişi yazar; `archive` `work/<slug>` silinmeden önce kopyalar (F00 D6) |
| `state.sh retry/spawn` | `retry` olayı; tükenen yeniden deneme `failure/verdict-block` |
| `record-verdict.sh`, `parse-verdict.sh` | Doğrulama olayları: `sdd.sh _verdict` (PASS/BLOCK), hook (malformed) |
| `run-role.sh` (ayrı süreç yürütme noktası) | `agent.start/agent.end`, süre, token (host yazdıysa), `host-error`/`host-missing`/`budget` hataları |
| `hooks/usage-log.sh` (Claude SubagentStop/Stop) | Aynı transkript okumasından `agent.end`: token, **araç çağrısı sayısı**, süre (tahmin) |

Yeni ikinci bir log sistemi yoktur: tek yeni dosya `events.jsonl` ve tek yeni betik `scripts/telemetry.sh` (+ `bench/` geliştirici aracı).

## 3. Tasarım

### 3.1 Olay modeli

`<project-dir>/work/<slug>/events.jsonl`, kişisel ve git dışı (`work/` zaten ignore). Satır başına bir JSON; `TELEMETRY=1` (`sdkit.local.env`) ile açılır. Şema `scripts/telemetry.sh` içindeki tek `errs` tanımıdır; `emit` ve `validate` aynı kuralı kullanır.

| Alan | Anlam |
|---|---|
| `v` | şema sürümü, şimdilik 1 |
| `ts` | UTC, saniye çözünürlüğü |
| `type` | `task.start task.end phase.enter phase.reject agent.start agent.end retry test.result verify.result failure bench.mark` (+ `contract.check`, F02) |
| `task` | görev kimliği (slug) |
| `run` | **koşu kimliği**: `task.start` yenisini açar (`work/<slug>/run.id`); `SDKIT_RUN_ID` ile dışarıdan verilebilir (benchmark) |
| `span` / `parent` | bir ajan koşusunu (start+end) ve üst koşuyu bağlar; aynı `span`'ın son `agent.end`'i geçerlidir (büyüyen oturum anlık görüntüleri) |
| `mode` | `live` veya `simulated` (fixture) |
| `phase`, `from`, `to` | iş akışı fazı |
| `role`, `host`, `model`, `tier` | ajan; sağlayıcı alanı **yoktur**: host sağlayıcıyı belirlemez (OpenCode/Cursor çok sağlayıcılı), kit model adı uydurmaz |
| `in`, `out`, `cache_read`, `cache_write`, `dur_ms`, `tool_calls`, `attempt` | negatif olmayan tamsayılar; bilinmiyorsa **alan yazılmaz** |
| `q` | ölçüm kalitesi: `{tokens, duration, tool_calls: actual\|estimated\|unavailable}`; sayı yoksa `unavailable` zorlanır |
| `outcome`, `category` | sonuç (`pass/fail/PASS/BLOCK/malformed/completed/aborted/ok/error`); hata kategorisi `budget gate tests verdict-block verdict-malformed host-error host-missing timeout contract other` (`contract`: F02, ayrıntı alanı `reason`) |
| `source`, `risk`, `note` | üretici; risk etiketi; en çok 160 karakter serbest not (satırlar tek `write` ile eklenebilsin diye alanlar kısaltılır) |

Gizlilik: istem, devir metni, cevap, dosya yolu ya da içerik için alan yoktur; çağıranlar bunları geçirmez. `note` yalnızca kısa durum metnidir (ör. `exit 7`).

### 3.2 Yazım ve hata yalıtımı

- `telemetry.sh emit` her hatada `exit 0` ile çıkar (jq yok, yazılamayan dizin, geçersiz alan: olay düşer). `--strict` yalnızca testler içindir.
- Çağıranlar ayrıca `>/dev/null 2>&1 || true` ile sarar; `sdd.sh`, `state.sh` ve `run-role.sh` içinde `tele` yardımcısı `TELEMETRY≠1` iken süreç bile açmaz.
- Satır tek `O_APPEND` yazımıdır (kısa satır, parçalanmaz); eşzamanlı ajanlar için kilit gerekmez. Kilit yalnızca `run.id`'nin ilk oluşturulmasında.
- Kapalıyken yeni dosya yazılmaz; hook'lar ve betikler eskisi gibi çalışır.

### 3.3 Takılan sınırlar

| Sınır | Olaylar |
|---|---|
| `sdd.sh start/advance/abort` | `task.start`, `phase.enter`, `task.end`, `phase.reject` (kategori `tests` red/green'de, `gate` diğerlerinde; faz atlama dahil), `test.result` (+süre), `verify.result` (low: verify komutu) |
| `sdd.sh gate` reddi | `phase.reject` (kaynak `gate-edit`/`gate-push`) |
| `sdd.sh _verdict` | `verify.result` (PASS/BLOCK), BLOCK'ta `failure/verdict-block` |
| `state.sh retry` | `retry`; ikinci denemede `failure/verdict-block` |
| `run-role.sh` | `agent.start`, `agent.end` (süre ölçülür; token yalnızca host yazdıysa), `failure` (`host-error`, `host-missing`, `budget`) |
| `hooks/usage-log.sh` | `agent.end` (Claude: token, araç çağrısı sayısı, tahmini süre) |
| `hooks/record-verdict.sh` | bozuk verdict: `verify.result/malformed` + `failure/verdict-malformed` |

### 3.4 Hangi metrik güvenilir?

| Metrik | Durum | Not |
|---|---|---|
| Faz sırası ve süreleri | **actual** (saniye) | olay zaman damgalarından; macOS `date` milisaniye vermez |
| Test sonucu ve süresi (red/green) | **actual** | `sdd.sh advance` kendisi çalıştırır |
| Doğrulama sonucu (PASS/BLOCK/malformed) | **actual** | tek karar noktası `parse-verdict`/`_verdict` |
| Yeniden deneme, kapı reddi, hata sayısı | **actual** | kategoriyle |
| Ajan sayısı | **actual** `run-role` yolunda; Claude'da yalnızca biten `agent.end` sayılır | Claude'da `agent.start` yok (PreToolUse hook'u yalnızca bütçe açıkken çalışıyor) |
| Ajan süresi | `run-role`: **actual**; Claude hook'u: **estimated** (transkriptin ilk-son zaman damgası) | |
| Token (giriş/çıkış/önbellek) | Claude (`run-role` ve hook): **actual**; Gemini: giriş/çıkış **actual**, önbellek yok; Codex, OpenCode, Cursor: **unavailable** | rapor "ölçülen X / Y koşu" yazar ve eksik varsa toplamın alt sınır olduğunu söyler |
| Araç çağrısı sayısı | Claude hook'u: **actual**; `run-role` yolu: **unavailable** | |
| Model | yalnızca yapılandırılmış/transkriptte görülen | uydurulmaz |
| Maliyet | **estimated**, yalnızca kullanıcı fiyat tablosu verirse (`<project-dir>/pricing.json` veya `TELEMETRY_PRICES`: model → milyon token başına USD) | tablo yoksa `unavailable`; kit fiyat içermez (F00 §7) |
| Yeniden deneme (host düzeyi, ağ) | **unavailable** | host CLI içinde, görünmez |
| Provider | yok | bkz. şema |

## 4. Komutlar

```bash
# aç (kişisel): .sdkit/sdkit.local.env  →  TELEMETRY=1
scripts/telemetry.sh summary [slug] [--run ID] [--json]   # bir koşunun özeti
scripts/telemetry.sh list                                  # olayı olan görevler (arşivlenenler dahil)
scripts/telemetry.sh validate [slug]                       # şema denetimi
scripts/telemetry.sh archive [slug]                        # kapanıştan önce: work/_archive/ altına kopyala (work/<slug> silinir)
scripts/telemetry.sh emit <type> [...]                     # elle/yeni sınırlar için; asla hata vermez

bench/run.sh list
bench/run.sh run <senaryo|all> [--out DIR] [--json] [--keep]               # SİMÜLE (varsayılan): ücretsiz, deterministik
bench/run.sh run <senaryo|all> --real --host claude [--verifier-host codex] --yes   # GERÇEK: gerçek token harcar, yalnızca elle
bench/run.sh compare A.json B.json
```

Fiyat tablosu örneği (`pricing.json`; değerleri kendi sözleşmenizden doldurun, kit değer vermez):

```json
{ "<model-kimliği>": { "in": 0.0, "out": 0.0, "cache_read": 0.0, "cache_write": 0.0 } }
```

## 5. Benchmark çerçevesi

`bench/scenarios/<ad>/` dört senaryo içerir; her biri gerçek `sdd.sh` faz makinesini, gerçek `run-role.sh`'ı, `parse-verdict.sh --record`'u ve `state.sh retry`'ı çalıştırır. **Simüle** modda yalnızca host CLI'ı fixture'dır (`bench/stub-host/claude|codex`: adım dizinindeki dosyaları kopyalar, hazır cevabı ve hazır token sayısını verir).

| Senaryo | Risk | Ne sınar |
|---|---|---|
| `low-single-file` | low | tek dosya, kapı = verify komutu, doğrulayıcı yok |
| `medium-multi-file` | medium | üç dosya, bağımsız verifier PASS |
| `high-independent-verify` | high | test-writer → developer → `verifier-deep`; önce BLOCK, tek yeniden deneme, düzeltme, sonra PASS; tasarımda yarış bölümü |
| `multi-agent-handoff` | medium | scout, engineer, test-writer, iki paralel developer, reviewer, verifier; devirler `out/` dosyalarıyla; reviewer+verifier başka host'ta (token vermeyen) |

Sonuç dosyası `{scenario, mode, host, deterministic, timing, summary}`. `deterministic` iki simüle koşuda **bit bit aynıdır** (testle doğrulanır); `timing` değildir. Gerçek koşu aynı sürücüyü, aynı kapıları ve aynı raporu kullanır; farkı yalnızca rollerin canlı CLI olması ve token/süre değerlerinin gerçek olmasıdır. Gerçek koşu `tests/` ve CI tarafından **hiç** başlatılmaz; `--real` ve `--yes` (veya yazılan `yes`) ister.

## 6. Görevler ve doğrulama kaydı

| Görev | Durum |
|---|---|
| T1 `scripts/telemetry.sh` (emit/summary/list/validate/archive/run-id/now-ms) | tamam |
| T2 sınır takibi: `sdd.sh`, `state.sh`, `run-role.sh`, `usage-log.sh`, `record-verdict.sh` | tamam |
| T3 ayar: `TELEMETRY` (`templates/sdkit.local.env`, kişisel; `split_personal_env` şablondan alır) | tamam |
| T4 `bench/` (sürücü, 2 stub host, 4 senaryo, `compare`) | tamam |
| T5 `tests/telemetry.test.sh` (118 durum) | tamam |
| T6 belgeler: bu dosya, `guide.md` (§2, §9, §10, §15, §18), `cheatsheet.md`, `README.md`, `CONTRIBUTING.md`, `upgrading.md` | tamam |
| T7 `sdkit_lock` yazılamayan dizinde beklememe düzeltmesi | tamam |

Çalıştırılan denetimler: `tests/run.sh` 109, `sdd` 52, `shared` 29, `memory` 38, `budget` 45, `sdkit-dir` 64, `risk-floor` 76, `hardening` 53, **`telemetry` 118**; hepsi geçti, hiçbiri kırılmadı. `bin/build-adapters.sh --check` güncel (rol dosyalarına dokunulmadı).

### Simüle benchmark sonuçları (fixture; gerçek ölçüm DEĞİL)

`bench/run.sh run all` (mode `simulated`). Token sayıları fixture dosyalarından gelir; bu tablo **kitin kendi sayaç ve raporlama doğruluğunu** gösterir, SDKit'in model maliyetini değil.

| Senaryo | Ajan | in | out | cache_read | cache_write | Ölçülen / toplam koşu | Yeniden deneme | Hata | Olay |
|---|---|---|---|---|---|---|---|---|---|
| low-single-file | 1 | 1200 | 300 | 4000 | 500 | 1/1 | 0 | 0 | 13 |
| medium-multi-file | 2 | 8300 | 1820 | 37000 | 2600 | 2/2 | 0 | 0 | 15 |
| high-independent-verify | 5 | 21100 | 4920 | 106000 | 4000 | 5/5 | 1 | 1 (`verdict-block`) | 24 |
| multi-agent-handoff | 7 | 11000 | 2540 | 46000 | 4900 | **4/7** | 0 | 0 | 25 |

Son satır, "eksik veri" yolunun sınanmış halidir: üç koşu (scout ve codex'teki reviewer/verifier) token vermediği için toplam **alt sınır** olarak işaretlenir.

**Gerçek LLM ölçümü: yapılmadı.** Gerçek koşu token harcar ve kullanıcının açık talimatını bekler; çerçeve hazır (`--real`), ama bu belgedeki hiçbir sayı gerçek bir model koşusundan gelmez.

## 7. Bilinen sınırlar

- Zaman damgaları saniye çözünürlüğünde; kısa fazlar 0 sn görünür.
- Claude'da yalnızca biten ajanlar sayılır (`agent.start` yok); `Agent` aracı bütçe kapalıyken bir hook'tan geçmez. Başlayıp bitmeyen ajan görünmez.
- Claude hook'unun süresi tahmindir (transkript aralığı); araç çağrısı sayısı transkriptten sayılır, `run-role` yolunda yoktur.
- Codex, OpenCode, Cursor'da token yoktur (host çıktısı vermiyor veya ayrıştırılmıyor); Gemini'de önbellek yoktur. Bu host'ların `run-role.sh` çıkış biçimleri canlı doğrulanmadı (F00 §8.8).
- `run-role` kendi içindeki host yeniden denemelerini ve zaman aşımını görmez; `timeout` kategorisi şemada var ama üreten yok (F00 R5 `RUN_ROLE_TIMEOUT` yapılınca dolar).
- `usage.jsonl` sıfır yazar (host vermediğinde); rapordaki "çapraz kontrol" satırı bu yüzden gerçek tüketimi alt sınır gösterebilir. Olay günlüğü bunu `unavailable` olarak ayırır.
- Claude Stop anlık görüntüsü ile SubagentStop aynı `span`'ı paylaşmaz; orkestratör oturumu ayrı bir "ajan" satırı (`orchestrator`) olarak görünür.
- Parse edilen biçimler: bozuk verdict, host dışı (`parse-verdict.sh --record`) yolunda `malformed` olayını yalnızca benchmark sürücüsü ve Claude hook'u yazar; başka host'ların orkestratörü `telemetry.sh emit verify.result --outcome malformed` ile yazabilir.
- `pricing.json` kullanıcıdan gelir: maliyet hiçbir zaman "actual" değildir, en iyi ihtimalle "estimated".
- Gerçek koşu (`--real`) canlı host CLI bayraklarına bağlıdır; bayrak yazımları canlı doğrulanmadı (`run-role.sh --dry-run` ile kontrol edin).

## 8. F02 (Yapılandırılmış Ajan Sözleşmeleri) için öneriler

> F02 uygulandı: [design-contracts.md](design-contracts.md). Aşağıdaki maddelerden 1 (sözleşme sürümü olayda ayrı alan: `cv`), 2 (ihlal kategorisi: `contract`), 3'ün bayt kısmı (`bytes`; sözleşmeli/sözleşmesiz simüle karşılaştırma `bench/run.sh overhead`) ve 6 (tek yeniden deneme: `state.sh retry`) yapıldı; 4 (gerçek taban koşu) ve 3'ün token iddiası **hâlâ yapılmadı**; 5 yapılmadı (ayrı karar).

1. **Devir ve cevap biçimini olaya bağla.** F02'de her rol sözleşmesinin (girdi alanları, çıktı şeması) bir `contract` adı/sürümü olsun; `agent.end` bunu `source` yerine ayrı alan olarak taşısın. Böylece "hangi sözleşme sürümü kaç token, kaç BLOCK" sorusu cevaplanır.
2. **Sözleşme ihlalini hata kategorisi yap** (`contract`): şema dışı cevap bugün yalnızca verifier için `verdict-malformed` ile ölçülüyor; scout/engineer/developer cevapları ölçülmüyor.
3. **Devir boyutunu ölç:** `handoff_bytes` ve `answer_bytes` (içerik değil, boyut) alanları, yapılandırılmış devrin düzyazıya göre token etkisini önce/sonra ölçmenin ilk adımı. Bu iddia, F01 senaryolarının sözleşmeli ve sözleşmesiz iki koşusuyla (`bench/run.sh compare`) kanıtlanmadan yapılmamalı.
4. **Önce baseline'ı kaydet:** F02 başlamadan `bench/run.sh run all --real --host <h> --yes` ile gerçek temel koşuyu bir kez alın (kullanıcı kararı, maliyetli) ve JSON'ları saklayın; simüle sayılar karşılaştırma tabanı olamaz.
5. Claude'da `agent.start` için `PreToolUse: Agent` hook'u bütçe kapalıyken de çalışmalı (yalnızca olay yazan, hiç engellemeyen biçimde); F02 paralel ajan sayısını ölçmek isterse gerekir.
6. Sözleşmeli roller `run-role.sh --out` çıktısını `parse-*.sh` ile doğrulayıp ihlalde tek yeniden deneme yapacaksa, mevcut `state.sh retry` ve `retry` olayı yeniden kullanılabilir.
