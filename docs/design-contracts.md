# Yapılandırılmış ajan sözleşmeleri ve güvenilir devirler (F02)

Durum: **uygulandı**, 1.1.0 üzerinde, F00/F00.5/F01 değişikliklerinin üstüne; sürüm artırılmadı. Bu belge F02'nin spec'i, tasarımı, görev listesi ve doğrulama kaydıdır. Amaç: bir ajana verilen iş (devir) ve ajanın döndürdüğü cevap, **makinenin doğrulayabileceği** kadar yapılandırılsın; ama ajanlar için ek bağlam, ek ajan çağrısı ya da çift durum yaratılmasın. İlke: *makinenin garanti istediği yerde yapılandırılmış, ajanın bağlam istediği yerde kısa.*

Bu sürüm hiçbir token veya maliyet tasarrufu iddiası taşımaz: simüle benchmark yalnızca **baytları, olayları ve betik çağrılarını** ölçer (bölüm 7); token etkisi gerçek koşuyla (`--real`, kullanıcı onayı) ölçülmeden söylenemez ve ölçülmedi.

## 1. Spec

Kapsam: sürümlü bir devir sözleşmesi (çağrı + sonuç), onu doğrulayan tek betik (`scripts/contract.sh`), desteklenen sınırlara takılması (Claude Code hook'u, `run-role.sh`), F01 telemetrisine `contract.check` olayı, sözleşmeli benchmark fikstürleri, testler.
Kapsam dışı (bilerek): ajan davranışı, model yönlendirme, risk politikası ve faz makinesi değişikliği; ek ajan/LLM ile doğrulama; JSON şema kütüphanesi ya da dış servis; Cursor/Gemini/OpenCode/Codex için canlı doğrulanmamış hook iddiası.

Kabul ölçütleri (DoD) ve kanıtı (`tests/contract.test.sh`, 197 durum, hepsi geçti; bölüm 8):

| # | Ölçüt | Kanıt bölümü (test) |
|---|---|---|
| D1 | Sözleşme sürümlü ve belgeli (`CONTRACT: 1`, `HANDOFF-RESULT/1`); desteklenmeyen sürüm reddedilir | "malformed output", "handoff validation" |
| D2 | Desteklenen sınırlar (Claude hook'u, `run-role.sh`, elle `contract.sh`) sözleşmeyi deterministik doğrular | "the Claude Code hook", "run-role.sh" |
| D3 | Bozuk/tutarsız sözleşme geçerli sayılamaz: bozuk JSON/düzyazı, eksik alan, bilinmeyen/çift alan, rol, görev, kimlik, güvensiz yol, eksik artefakt, kapsam dışı | "malformed output", "identity", "artifacts of a result" |
| D4 | Ajanın bildirdiği başarı bağımsız doğrulamayı atlatamaz: geçerli sözleşme faz geçişi vermez, verdict kaydetmez | "the verifier stays independent" |
| D5 | Mevcut kapılar sağlam: `sdd.sh`, `parse-verdict.sh`, `record-verdict.sh` sözleşmeyi bilmez | aynı bölüm (`grep` testleri) + mevcut paketler değişmedi |
| D6 | Telemetri sözleşme sonuçlarını kaydeder (geçerli/geçersiz, sürüm, rol, kimlik, durum, kategori, boyut); ikinci defter yok; kayıp veri 0 sayılmaz | "telemetry" |
| D7 | Benchmark fikstürleri tekrarlanabilir; F01 taban çizgisi bit bit aynı | "contract benchmarks" + bölüm 7 |
| D8 | Geriye uyumluluk: `CONTRACT:` satırı olmayan devir/cevap eskisi gibi; varsayılan kapalı | "backward compatibility" |
| D9 | Host sınırlamaları belgeli (bölüm 5) | bu belge, `references/hosts.md` |

## 2. Mevcut yeteneklerin yeniden kullanımı (F00/F01'e göre)

| Mevcut sınır | F02'de |
|---|---|
| `references/handoff.md` (ROLE, TASK, READ, SCOPE, OUT, DONE WHEN, ...) | **Çağrı sözleşmesi zaten budur.** Yeni bir şema/dosya yok: yalnızca `CONTRACT: 1`, `ID:`, sabit `REPLY-END:` (ve gerekirse `RETRY-OF:`) satırları eklenir; mevcut satırlar doğrulanır |
| `parse-verdict.sh` + `record-verdict.sh` (verifier bloğu) | **Dokunulmadı.** Verdict'in tek otoritesi. Sözleşme yalnızca zarfı (kimlik/rol/durum) doğrular, DOD/VERDICT'e bakmaz |
| `sdd.sh` (faz, kapı, verdict bağlama) | **Dokunulmadı.** `contract` kelimesi bu dosyada geçmez (test) |
| `state.sh retry` (tek yeniden deneme) | Geçersiz/yarım kalan sözleşme için de aynı tek hak; ikinci yeniden deneme kullanıcıya gider |
| `check-writes.sh` (kapsam: dosya veya dizin önekleri) | Aynı önek kuralı artefakt kapsamı için (`in_scope`); gerçek yazma denetimi hâlâ `check-writes.sh`/git hook'larında |
| `telemetry.sh` (`events.jsonl`, `q` kalite etiketi, hata kategorileri) | Yeni olay türü `contract.check` + `failure/contract`; aynı dosya, aynı `errs` şeması |
| `run-role.sh` (ayrı süreç yürütme noktası) | Sözleşmeli devirde çağrı öncesi `issue`, sonrası `check-result`; host hatasında `close` |
| `hooks/guard-budget.sh` (PreToolUse Agent) | Aynı eşleyici grubuna `check-contract.sh` eklendi; ayrı bir mekanizma değil |
| `bench/` | Yeni senaryolar aynı sürücüde; `--contracts` ve `overhead` komutları |

Yeni durum dosyası yok; yalnızca `work/<slug>/contracts/<etiket>.json` (kimlik başına bir küçük kayıt: rol, kapsam, durum). Bu, başka hiçbir yerde tutulmayan "bu devir verildi mi, cevaplandı mı" bilgisidir; git durumu, SDD fazı, token verisi ya da doğrulama kanıtı **kopyalanmaz**.

## 3. Tasarım

### 3.1 Biçim seçimi: üç aday

| Aday | Güvence | Uyumluluk | Maliyet | Karar |
|---|---|---|---|---|
| JSON sonuç **dosyası** (`out/<id>.result.json`) | yüksek | **zayıf**: salt okunur roller dosya yazamaz (reviewer, verifier, scout); ek araç çağrısı | ek yazma + okuma | Reddedildi: en güvenilir kanal olan cevap metnini bırakıyor |
| Cevap içinde JSON yükü | yüksek | iyi | kaçış karakterleri, çok satır; LLM'in JSON sözdizimi hatası riski; düzyazı okunurluğu bozulur | Reddedildi |
| **Tek satırlık işaretçi** (`HANDOFF-RESULT/1 \| key: value ...`) | yeterli (sabit alanlar, katı ayrıştırma) | **en iyi**: her host'ta ve `last_assistant_message`'ta bulunan son metin | ~120 bayt | **Seçildi**: insan okur, `awk`/bash ayrıştırır, jq gerekmez |

Mevcut `parse-verdict.sh` de aynı yaklaşımın (metin bloğu + katı ayrıştırıcı) kanıtlanmış hâlidir.

### 3.2 Çağrı sözleşmesi

```
ROLE: developer     RISK: medium     PROJECT-DIR: .sdkit
CONTRACT: 1
TASK: ...                         # amaç
READ: plan.md,src/a.sh            # girdiler: var olan, depo-göreli yollar (virgüllü, düzyazı yok)
SCOPE: writes: src/,docs/x.md     # izinli yazma kapsamı; salt okunur roller için `none`
OUT: work/t1/out/dev-a.md         # beklenen çıktı (work/<görev>/out/ altında)
ID: t1/dev-a                      # <görev>/<etiket>: koşu kimliği
REPLY-END: one line "HANDOFF-RESULT/1 | id: <ID> | role: <ROLE> | status: ... | artifacts: ... | blockers: ... | next: ..."
RETRY-OF: t1/dev-a                # yalnızca yeniden denemede
```
`CONTRACT:` sabit satırdır (önbellek öneki), `ID:` her açılışta değişir (en sonlara yakın). Görev kimliği = `ID`'nin ilk parçası (aktif görevle karşılaştırılır), koşu kimliği telemetride otomatik (`run`). Kısıtlar `DONE WHEN` / `NOT YOUR JOB` satırlarında düzyazı kalır: makine onları doğrulamaz, ajan okur.

### 3.3 Sonuç sözleşmesi

`HANDOFF-RESULT/1 | id: t1/dev-a | role: developer | status: done | artifacts: src/a.sh | blockers: none | next: -`

| Alan | Kural |
|---|---|
| sürüm | `/1`; sayı değilse `malformed`, başka sayıysa `unsupported-version` |
| `id`, `role`, `status`, `artifacts`, `blockers` | zorunlu, boş olamaz (`none` yazılır); `next` isteğe bağlı |
| `status` | `done` `partial` `blocked` `failed` (**"verified" diye bir durum yoktur**) |
| tutarlılık | `done` ⇔ `blockers: none`; `partial/blocked/failed` blocker ister |
| `artifacts` | `none` ya da virgüllü yollar: güvenli, var olan, `writes:` (veya `OUT`) içinde; salt okunur rol `none` demek zorunda |
| uzunluk/karakter | `blockers`/`next` ≤ 200; değer içinde `\|` olmaz; bilinmeyen veya çift alan reddedilir |
| tek satır | cevapta tek (farklı) işaretçi; birden fazla farklı satır belirsizdir |

### 3.4 Doğrulama kategorileri

`no-result` `malformed` `unsupported-version` `missing-field` `bad-value` `inconsistent` `id-mismatch` `role-mismatch` `task-mismatch` `unknown-id` `duplicate` `stale` `unsafe-path` `missing-artifact` `out-of-scope`. Çıktı tek satır: `CONTRACT=valid|invalid stage=handoff|result id=.. role=.. [status=..] [reason=..: ayrıntı]`.
Çıkış kodu (`parse-verdict.sh` ile aynı üçlü): **0** geçerli ve `done`, **1** geçerli ama `partial/blocked/failed`, **2** geçersiz. Çıkış 0 asla "doğrulandı" demek değildir.

### 3.5 Kayıt ve yaşam döngüsü

`issue` kimliği `work/<slug>/contracts/<etiket>.json` olarak kaydeder (dışlayıcı oluşturma: aynı kimlik iki kez verilemez). Durumlar: `issued → accepted` | `invalid` (yeniden gönderilebilir) | `superseded` (`RETRY-OF` ile yenisi verildi) | `interrupted` (`close`). Aynı kimliğe ikinci geçerli cevap `duplicate`; yerine geçilmiş/ölü kimliğe geç gelen cevap `stale`; hiç verilmemiş kimlik `unknown-id`. Kabul, kilit altında "kontrol et ve yaz" olduğundan sekiz eşzamanlı özdeş cevaptan tam biri kabul edilir (test).

### 3.6 Doğrulama bağımsızlığı (D4/D5)

Dört kavram ayrı kalır ve ayrı yerde tutulur:

| Kavram | Nerede | Sözleşme ile ilişkisi |
|---|---|---|
| Sözleşme geçerliliği | `contract.sh` (bu özellik) | yalnızca zarf: biçim, kimlik, rol, yol |
| Yürütme sonucu | sonuç satırındaki `status` | ajanın beyanı; kanıt değil |
| Test kanıtı | `sdd.sh advance red/green --test-cmd` (kendisi çalıştırır) | dokunulmadı |
| Bağımsız doğrulama | `parse-verdict.sh` / `record-verdict.sh` / `sdd.sh advance verified` | dokunulmadı; sözleşme olmadan da verdict kaydedilir, sözleşme geçerli olsa da verdict gerekir |
| İş akışı tamamlanması | `sdd.sh` fazları | `contract.sh` faz makinesini, `_verdict`'i, `parse-verdict`'i çağırmaz (test) |

`next:` yalnızca öneri metnidir; hiçbir betik onu çalıştırmaz.

## 4. Sınırlar ve entegrasyon

| Sınır | Ne yapar | Engeller mi? |
|---|---|---|
| `hooks/check-contract.sh`, PreToolUse `Agent\|Task` (Claude Code) | `tool_input.prompt` içinde `CONTRACT:` varsa `contract.sh issue` (doğrula + kaydet). Geçersizse `strict`'te **ask**, `guided`'da uyarı, `off`'ta sessiz | yalnızca `ask`; hook hatası asla engellemez |
| `hooks/check-contract.sh`, SubagentStop (Claude Code) | Son mesajı (yoksa transkriptin son metnini) `check-result --record --legacy-ok` ile doğrular; geçersizse orkestratöre `systemMessage` | hayır; verdict yolundan bağımsız |
| `scripts/run-role.sh` (her host) | `CONTRACT:` varsa çağrıdan önce `issue` (geçersiz: çıkış 2, **ajan başlatılmaz**, bütçe sayılmaz), sonra `check-result`; cevap yine yazdırılır/saklanır. Çıkış 4: sözleşme bozuk, 5: geçerli ama `partial/blocked/failed`; host hatasında `close` | evet (çıkış kodu) |
| Elle `contract.sh issue / check-result / pending / close / status` | Hook'u olmayan host'ların orkestratörü için | — |

Kapalıyken (`CONTRACTS` boş, `CONTRACT:` satırı yok) hiçbiri bir şey yapmaz; `run-role.sh` istemi bayt bayt aynıdır (ek cümle yalnızca sözleşmeli devirde, test).

### Claude Code hakkında araştırma bulguları (hiçbiri uydurulmadı)

- `Agent` aracının girdisi gerçek transkriptlerde `{description, prompt, subagent_type}` olarak görüldü; PreToolUse hook'u devri (`prompt`) bu yüzden görebilir.
- Repoda ve elimdeki transkriptlerde PreToolUse(`Agent`) ile SubagentStop'u **bağlayan ortak bir kimlik görülmedi** (SubagentStop'ta `agent_id`, `agent_type`, `last_assistant_message`, `agent_transcript_path` var; PreToolUse'ta `tool_use_id`). Bu yüzden eşleşme host üstverisine değil, **devirdeki `ID:` ve cevaptaki `id:`** ile kurulur. Cevapta işaretçi yoksa hook yalnızca o rol için bekleyen (`issued`) devir varsa bunu bulgu sayar; yoksa eski (sözleşmesiz) çağrıdır ve sessiz kalır. Aynı roldeki eşzamanlı sözleşmeli ve sözleşmesiz ajanlar bu durumda yanlış uyarı üretebilir (yalnızca uyarı).
- Alt ajan transkriptinin ilk kullanıcı mesajından `ID:` okunabilir mi? **Doğrulanamadı** (elimde alt ajan transkripti yok); kullanılmadı.
- SubagentStop hook'unun alan adları repodaki mevcut hook'larla (`record-verdict.sh`, `usage-log.sh`) aynı varsayımlara dayanır; **canlı Claude Code oturumunda bu F02 hook'u koşturulmadı**, testler hook'u örnek JSON ile besler.

## 5. Host uyumluluk durumu

| Host | Çağrı doğrulaması | Cevap doğrulaması | Durum |
|---|---|---|---|
| Claude Code, `Agent` aracı | PreToolUse hook (`check-contract.sh`) | SubagentStop hook | Örnek hook JSON'uyla test edildi; **canlı doğrulanmadı** |
| Claude Code, `run-role.sh --host claude` | `run-role.sh` | `run-role.sh` (`result` JSON'undan) | Stub host ile test edildi; canlı CLI yok |
| Codex, OpenCode, Cursor, Gemini — `run-role.sh` | `run-role.sh` | `run-role.sh` | Stub host (codex biçimi dahil) ile test edildi; canlı CLI bayrakları F00 §8.8 gibi **doğrulanmadı** |
| Codex, OpenCode, Cursor, Gemini — host'un kendi alt ajanı | yok | yok | Kitte alt ajan sonucu hook'u yok (`adapt.sh` yalnızca araç çağrısı çevirir; OpenCode eklentisi sözleşme hook'unu taşımaz). **Güvenli yedek:** orkestratör `contract.sh issue/check-result` komutlarını elle çağırır (`references/contract.md`) ya da rolü `run-role.sh` ile ayrı süreç olarak açar |
| Başka | — | — | Rolü ana oturumda oynamak: yine elle |

## 6. Telemetri entegrasyonu (F01'in yeniden kullanımı)

Yeni olay türü `contract.check` (aynı `events.jsonl`, aynı `errs` şeması, ikinci defter yok), yeni alanlar `contract` (etiket), `stage` (`handoff\|result`), `status` (`done/partial/blocked/failed`), `reason` (15 kategori), `bytes`, `cv` (sözleşme sürümü); `role`, `source`, `task` ve koşu kimliği (`run`) mevcut alanlar. Geçersiz sonuçta ayrıca `failure` + yeni kategori `contract`. `summary`/`render` yeni `contracts` bölümü verir (kontrol, geçerli/geçersiz, kategori dağılımı, ajan durumu, devir/cevap baytı, sürüm); hiç sözleşme olayı yoksa çıktı değişmez.

- Metin, istem, blocker açıklaması **kaydedilmez** (test): yalnızca kimlik etiketi, rol, kategori, durum ve bayt sayısı.
- `bytes` yerelde ölçülen gerçek değerdir (kabuk sondaki satır sonunu atar, 1-2 bayt farkı olur). Token/süre alanları bu olayda yoktur; kayıp token hiçbir yerde 0 sayılmaz (F01 kuralı aynen).
- Kapalıyken (`TELEMETRY` ≠ 1) sözleşme çalışır, olay dosyası oluşmaz (test).
- Doğrulama gecikmesi olayda **yok** (macOS `date` milisaniye vermez); `bench/run.sh overhead` ölçer.

## 7. Benchmark: F01 taban çizgisine karşı (simüle; token/maliyet iddiası yok)

Taban çizgisi bütünlüğü: F02 değişikliklerinden önce alınan `bench/run.sh run all` çıktısının `deterministic` kısmı, değişikliklerden sonrakiyle **bit bit aynıdır** (4/4 senaryo, özet sağlaması eşit).

**Beş sözleşme fikstürü** (`bench/run.sh run contracts`, GROUP=contract; `run all` yine yalnızca F01'in dört senaryosu):

| Fikstür | Ne sınar | Sonuç (iki koşuda aynı) |
|---|---|---|
| `contract-valid-single` | geçerli tek devir | 1 devir, 1 cevap, 0 geçersiz; tamamlandı |
| `contract-invalid-handoff` | dev-a'nın devri eksik (`SCOPE` yok): **ajan başlamadan** reddedilir (`missing-field`), düzeltilip yeniden verilir; dev-b'nin cevabında işaretçi yok (`malformed`), tek yeniden deneme (yeni kimlik + `RETRY-OF`) ile düzelir; bağımsız verifier PASS | 2 geçersiz (`malformed`, `missing-field`), 1 yeniden deneme, `failure/contract` 2; tamamlandı |
| `contract-multi-chain` | 7 ajan, hepsi sözleşmeli; sonraki devirler önceki çıktıları `READ` olarak adlandırır (artefakt zinciri doğrulanır); reviewer+verifier başka host | 7 devir, 7 cevap, 0 geçersiz; tamamlandı |
| `contract-interrupted` | ajan süreci çöker (çıkış 7); kimlik `interrupted` kapanır, tek yeniden deneme başarılı | `host-error` 1, `no-result` 1, 1 yeniden deneme; token 1/2 koşuda ölçülmüş (çöken koşu 0 sayılmaz); tamamlandı |
| `contract-verifier-evidence` | verifier devri yalnızca artefakt/diff tabanı içerir (**uygulayıcının çıktısı yok**); sözleşmesi geçerli, verdict `parse-verdict.sh` ile ayrı karara bağlanır | PASS yalnızca verdict'ten; tamamlandı |

**Ek yük, F01 senaryoları sözleşmeli/sözleşmesiz** (`bench/run.sh overhead`, deterministik sütunlar):

| Senaryo | Ajan | Devir bayt (düz → sözleşmeli) | Cevap bayt (düz → sözleşmeli) | Olay (düz → sözleşmeli) | `contract.sh` çağrısı |
|---|---|---|---|---|---|
| low-single-file | 1 | 293 → 456 | 29 → 154 | 13 → 15 | 2 |
| medium-multi-file | 2 | 879 → 985 | 209 → 482 | 15 → 19 | 4 |
| high-independent-verify | 5 | 2934 → 3085 | 649 → 1334 | 24 → 34 | 10 |
| multi-agent-handoff | 7 | 4225 → 4515 | 282 → 1164 | 25 → 39 | 14 |

Okuma notları: (a) sözleşmeli devirde mevcut düzyazı satırlarının bir kısmı yapılandırılmış satırlara dönüştüğü için "düz → sözleşmeli" fark yalnızca eklenen metin değildir; eklenen **sabit** metin devir başına 202 bayt (`CONTRACT`, `ID`, `REPLY-END`), cevap başına tipik 119 bayttır. (b) Cevap baytındaki büyük oran, fikstür cevaplarının zaten çok kısa olmasındandır (`low`: 29 bayt). (c) Ajan başına 2 `contract.sh` çağrısı (çağrı öncesi `issue`, sonrası `check-result`), `TELEMETRY=1` iken çağrı başına 1 `telemetry.sh emit` (geçersizse +1); ek ajan çağrısı **sıfırdır**. (d) Token sütunları simülede fikstür değeridir; token/maliyet farkı bu tablodan **okunamaz**.

**Doğrulama gecikmesi** (bu makinede ölçüldü, değişir; sonuç dosyalarının deterministik kısmında değil): 100 çağrının ortalaması `contract.sh issue --check-only` ≈ 189 ms, `contract.sh check-result` ≈ 180 ms, kıyas için `parse-verdict.sh` ≈ 153 ms. Süre ağırlıkla süreç başlatma maliyetidir (CPU ≈ %5); bir LLM çağrısının saniyeleriyle kıyaslandığında önemsizdir ama sıfır değildir.

**Gerçek LLM ölçümü: yapılmadı.** Tüm sayılar fikstürden veya yerel betik ölçümünden gelir.

## 8. Geriye uyumluluk ve geçiş

- Varsayılan kapalı: `CONTRACTS` boş (`templates/sdkit.env`, ekip ayarı; `init`/`upgrade` yeni ayarı mevcut dosyalara ekler, var olanı ezmez).
- `CONTRACT:` satırı olmayan devir **eski devirdir**: `run-role.sh` istemi bayt bayt aynı, hook sessiz, kayıt yok, olay yok (testler). Eski cevap (işaretçisiz) da sessizdir.
- Eski biçimler için tüketici incelemesi: devri okuyan tek kod `run-role.sh` (dosyayı olduğu gibi isteme koyar) ve bench sürücüsü; cevabı okuyan tek kod `parse-verdict.sh`/`record-verdict.sh` (verifier bloğu). İkisi de değişmedi. Verifier cevabı artık sonunda ek bir `HANDOFF-RESULT` satırı taşıyabilir; `parse-verdict.sh` bu satırı `DOD/FINDINGS/VERIFY/VERDICT` bölümleri arasında aramadığı için etkilenmez (test: aynı metin her iki ayrıştırıcıdan geçer).
- Yapılandırılmış ama bozuk olan sessizce kabul edilmez: `CONTRACT:` satırı **varsa** devir tam doğrulanır; işaretçi bulunmayan/bozuk/çift/bilinmeyen alanlı cevap `invalid` olur.
- Geçiş adımı gerekmez. Açmak için: `sdkit.env`'de `CONTRACTS=1`, devirlere `references/contract.md`'deki üç satırı ekle (skill `CONTRACTS=1` iken bunu bilir). Copy modu: `templates/settings.copy.json` hook'u içerir; `migrate.sh` hook adı desenine `check-contract`'ı ekledi.
- Not (F01 sürücüsünde bulunan gizli hata): `bench/run.sh`'taki `make_handoff` tek `local` satırında `$label`'ı atamadan önce kullanıyordu; `fix` adımının devri çağıranın etiketinin dosyasına yazılıyordu. Düzeltildi; F01 `deterministic` çıktısı etkilenmedi (doğrulandı).

## 9. Görevler ve doğrulama kaydı

| Görev | Durum |
|---|---|
| T1 `scripts/contract.sh` (issue, check-result, close, pending, status, id) | tamam |
| T2 sınır takibi: `hooks/check-contract.sh` (+ `hooks.json`, `settings.copy.json`, `migrate.sh`), `run-role.sh` | tamam |
| T3 telemetri: `contract.check`, `failure/contract`, `contracts` özeti | tamam |
| T4 ayar: `CONTRACTS` (`templates/sdkit.env`) | tamam |
| T5 bench: 5 fikstür, `--contracts`, `overhead`, stub host (`fail/`, otomatik işaretçi) | tamam |
| T6 `tests/contract.test.sh` (197 durum) | tamam |
| T7 belgeler: bu dosya, `references/contract.md`, `handoff.md`, `hosts.md`, `SKILL.md`, `guide.md`, `cheatsheet.md`, `README.md`, `CONTRIBUTING.md`, `upgrading.md`, `design-telemetry.md` | tamam |

Çalıştırılan denetimler: `tests/run.sh` 109, `sdd` 52, `shared` 29, `memory` 38, `budget` 45, `sdkit-dir` 64, `risk-floor` 76, `hardening` 53, `telemetry` 118 (hepsi F02 öncesiyle aynı sayıda, hiçbiri kırılmadı), **`contract` 197**; hepsi geçti. `bin/build-adapters.sh --check` güncel (rol dosyalarına dokunulmadı). `bash -n` ve `jq .` temiz; `shellcheck` bu makinede kurulu değil, çalıştırılmadı.

## 10. Bilinen sınırlar ve kalan riskler

- **Cevap biçimine uyum ajana bağlıdır.** Sözleşme uyumsuzluğu *tespit eder*, ajanın uymasını *sağlamaz*; gerçek modellerin işaretçiyi ne sıklıkla doğru yazdığı **ölçülmedi** (gerçek koşu yapılmadı). Ölçüm için: `bench/run.sh run <senaryo> --contracts --real --host <h> --yes` bu sürümde **tanımlı değildir** (`--contracts` yalnızca simüle); gerçek koşuya sözleşme eklemek F03 öncesi karar bekler.
- Claude Code hook'u canlı koşturulmadı (bölüm 4/5). Eşleşme `ID` metnine dayanır; alt ajan transkriptinden kimlik okuma doğrulanmadı.
- Hook'ta sözleşmesiz ve sözleşmeli aynı rol aynı anda çalışırsa, işaretçisiz cevap için yanlış uyarı çıkabilir (yalnızca uyarı).
- `READ:` alanı virgüllü yol listesi olmak zorunda; açıklamalı düzyazı `unsafe-path`/`missing-artifact` verir. Henüz var olmayan dosya `READ` değil `SCOPE: writes:` içindedir.
- Kapsam denetimi yalnızca *bildirilen* artefaktları `writes:` ile karşılaştırır; ajanın gerçekte neyi değiştirdiğini `check-writes.sh` ve git hook'ları denetler (ajanın beyanına güvenilmez).
- `bytes` hesabı kabuk `$(...)` ile sondaki satır sonlarını atar (1-2 bayt).
- Doğrulama gecikmesi ölçümü makineye bağlı; süreç başlatma baskın.
- Orkestratörün sözleşme satırlarını devire gerçekten eklemesi skill talimatına bağlıdır (makine zorlamaz); eklemezse devir eski devir sayılır ve kapsam dışı kalır.
- Alt ajan transkriptinden `agent.start` yok (F01 §7 aynen); bu özellik onu çözmez.

## 11. Önerilen sonraki özellik

**F03: sözleşmeli gerçek koşu ölçümü ve uyum oranı.** Kullanıcı onayıyla (a) F01'in gerçek taban koşusu (henüz alınmadı), (b) aynı senaryolar `--contracts` ile; ölçülen: işaretçi uyum oranı, `invalid` kategorileri, yeniden deneme maliyeti, gerçek token farkı. Karar şu ölçüme bağlı: uyum oranı düşükse `REPLY-END` metni kısaltılır/örneklenir ya da sözleşme yalnızca bağımsız roller ve paralel yazıcılar için zorunlu tutulur. Ayrıca: Claude hook'unun canlı doğrulaması ve (varsa) alt ajan transkriptinden `ID` okuma.
