# Deterministik iş akışı motoru (F03)

Durum: **uygulandı**, 1.1.0 üzerinde, F00/F00.5/F01/F02 değişikliklerinin üstüne; sürüm artırılmadı, commit yapılmadı. Bu belge F03'ün kapsamı, tasarımı, karar kayıtları ve doğrulama kaydıdır. Amaç: hangi iş akışının seçildiği, fazların nasıl geçildiği, ajan sözleşmesinin ne zaman şart olduğu ve hata/yeniden deneme davranışı **kodla** belirlensin, `SKILL.md`'yi okuyan modelin hatırlamasına bırakılmasın. Yeni bir orkestrasyon çatısı, ek ajan çağrısı ya da ikinci bir durum dosyası yoktur.

## 1. Mevcut durum: koda bağlı olanlar ve olmayanlar

| Karar | F03 öncesi | F03 sonrası |
|---|---|---|
| Faz sırası, atlama yasağı | kodda (`sdd.sh`) | aynı; tablo `sdd.sh transitions` ile okunur, tek tanım `PHASES` |
| RED (testler **düşmeli**), GREEN (**geçmeli**) | kodda | aynı |
| `proposed` girişi: DoD listesi; high için yarış/sıralama bölümü | kodda | aynı |
| Risk tabanı (`RISK_FLOOR_GLOBS`) | kodda | aynı |
| medium/high için bağımsız doğrulayıcı PASS, diff parmak izine bağlı | kodda | aynı |
| **Süreç ağırlığı (küçük / normal / sıkı)** | yalnızca `SKILL.md` düzyazısı ("küçük low görevleri kendin yapabilirsin") | `--profile`, görev durumunda sabit, kodda doğrulanır |
| Sözleşme işaretini devire eklemek | yalnızca orkestratörün hatırlaması | `workflow.sh require`: Claude hook'u ve `run-role.sh` zorunlu olduğu yerde sorar/reddeder |
| Cevapsız / yarım kalan ajan | düzyazı + `contract.sh pending` (kimse sormuyordu) | high-assurance'ta `green` ve `verified` kapısı |
| Reddedilen geçişin **nedeni** | insan metni (stderr) | metin + `phase.reject` olayında `reason` |
| `verified` sonrası eski kanıt | `gate push` reddeder ama "yeniden doğrula, `advance verified`" diyen mesaj **uygulanamazdı** (`verified→verified` reddediliyordu) | `verified`/`pr` → `verified` yeniden doğrulama, yalnızca kanıt bayatsa |
| Aynı anda iki `advance` | okuma-kontrol-yazma kilitsizdi: ikisi de geçebilir, tarihçe iki kez yazılırdı | yazma kilit altında, faz hâlâ kontrol edilen fazsa geçer; biri kazanır |
| Aynı anda iki `start` | ikisi de "açık görev yok" görebilirdi | kilit altında kontrol |
| Yeniden deneme sınırı | `state.sh retry` (kodda) + "üçüncü döngü yok" (düzyazı) | aynı; BLOCK mesajı artık hakkın harcanıp harcanmadığını söyler |
| Reviewer / security-auditor'ın çalıştırılması (high) | düzyazı | **hâlâ düzyazı** (bölüm 9, risk 1) |

## 2. Profiller

Profil **süreç ağırlığıdır**, risk **kapılardır**. Kullanıcı riski onaylar; profil onunla birlikte önerilir. İkisi de `sdd.sh start` ile yazılır ve görev boyunca değişmez (risk etiketi gibi): profil görev ortasında hafifletilemez.

| Profil | Kural (kodda) | Ne zaman |
|---|---|---|
| `small` | yalnızca `low`; `medium`/`high` ile `start` reddedilir. Sözleşme yükü yok (en fazla projenin `CONTRACTS=1`'i). Hiçbir zorunlu adım atlanmaz: RED/GREEN, risk tabanı, verify komutu aynen | tek dosyalık, düşük riskli iş |
| `standard` (varsayılan) | bugünkü iş akışı, bit bit aynı. `--profile` verilmezse bu | çoğu görev |
| `high-assurance` | her riskte `verified` bağımsız doğrulayıcı PASS ister (low dahil); yazan/karar veren roller (`developer test-writer devsecops engineer verifier reviewer security-auditor`) için sözleşme **zorunlu**; cevapsız ajan `green`/`verified`'ı engeller. `CONTRACTS` ayarı gerekmez | geri alınamaz, güvenlik/para/veri etkisi olan iş |

Değişmezler (testle kanıtlı): `small` risk tabanını düşürmez (`RISK_FLOOR_GLOBS` yüksek yol → `green` reddedilir); `high` risk her profilde yarış/sıralama bölümünü ister; `high-assurance` hiçbir kapıyı kaldırmaz, yalnızca ekler; geçerli sözleşme `advance verified`'ı geçirmez. CI tarafı: `ci-check`, attestation'da `profile: high-assurance` varsa low riskte de PASS ister (attestation'ı yalnızca `sdd.sh` yazar).

**Neden `small` yalnızca bu kadar?** Dürüst değerlendirme: `low` akışı zaten hafif; `small`'ın kodda sağladığı iki şey (a) yanlış etiket koruması: `small` + medium/high imkânsız, (b) sözleşme yükünü kapatması. Plan kapısını ve analyst'i atlama gibi şeyler `SKILL.md`'nin "asla atlama" korumalarına aykırı olurdu; eklenmedi. Prompt düzeyinde `small` yalnızca "tek oturumda kendin yap" demektir (`references/workflow.md`).

## 3. Geçiş politikası

Tek geçerli hareket bir sonraki fazdır; geri dönüş yalnızca `abort` (görevi bitirir). İstisna: **yeniden doğrulama** (`verified|pr → verified`), yalnızca `verifiedFingerprint` mevcut diff'le uyuşmuyorsa ve aynı kapılarla.

```
$ sdd.sh transitions
intake > proposed  proposal.md has a Definition of Done list (high risk: design.md has a race/ordering/timing section)
proposed > red     --test-cmd runs and FAILS
red > green        the tests PASS, the risk floor holds, no agent is still in flight (high-assurance)
green > verified   the risk floor holds; low: the verify command passes; medium/high/high-assurance: an independent PASS for this exact diff
verified > pr      none beyond verified: the push gate already holds the diff to the verified one before a PR exists
pr > done          none (the PR is merged: the user's call)
verified|pr > verified  re-verification, only while the verified diff is stale: the same checks as verified
any > (aborted)    sdd.sh abort; the only way back, and it ends the task
```
`pr` girişine ek koşul **eklenmedi** (denendi): mevcut testler `verified`'dan sonra repoya takip edilmeyen dosya düşüren akışları `pr`'a taşıyordu; itme kapısı (`gate push`) zaten PR açılmadan önce diff'in doğrulanan diff olduğunu denetliyor. Geriye uyumluluk bu ek denetimin önüne alındı.

Reddedilen hareket: durum **değişmez**, stderr'e neden yazılır, `phase.reject` olayına `reason` düşer. Nedenler: `not-next unknown-phase no-artifact no-dod no-design tests-pass tests-fail verify-failed no-verdict verdict-block stale-verdict risk-floor agents-pending out-of-phase concurrent` (kategori: `tests` yalnızca test koşusundan gelen red için, gerisi `gate`). `phase.reject` yalnızca sabit kelimeler taşır: devir metni, test çıktısı, yol listesi yazılmaz.

## 4. Sözleşme politikası (F02 ile bütünleşme)

`workflow.sh contracts --role R` `off | optional | required` döndürür. Girdi: görevin profili, `CONTRACTS` ayarı, rol. Çalıştırma sınırı yalnızca *nasıl uygulandığını* belirler.

| Profil | `CONTRACTS` boş | `CONTRACTS=1` |
|---|---|---|
| (görev yok) | off | optional |
| small | off | optional (asla required) |
| standard | off | optional (F02 davranışı, eski devirler geçer) |
| high-assurance | **required** (kit rolleri), optional (`scout`, `analyst`, kit dışı ajan) | aynı |

| Sınır | Uygulayan | Zorunlu ve işaret yoksa |
|---|---|---|
| Ajan aracı (Claude Code `PreToolUse` `Agent`) | `check-contract.sh` → `workflow.sh require` | `strict`: **ask**; `guided`: uyarı; `off`: sessiz. Hook'un kendi hatası asla bloklamaz |
| Ayrı süreç (`run-role.sh`, tüm host'lar) | `run-role.sh` → `workflow.sh require` | `strict`: çıkış **2**, ajan başlamaz; `guided`: uyarı, çalışır |
| Oturum içi (orkestratör kendisi yapıyor) | — | sınır yok, sözleşme yok |
| Diğer host'ların hook'ları (Codex/OpenCode/Cursor/Gemini) | uygulanmaz | host'ta `Agent` benzeri PreToolUse doğrulanmadı (F02 §5 ile aynı). Karşılığı: `run-role.sh` ve `advance` kapıları (`agents-pending`) her host'ta aynı |

Host sınırları (incelendi): Claude'un `SubagentStop` hook'u bloklayamaz, yalnızca mesaj ekler; bu yüzden cevap tarafı hâlâ "bir kez bildir" davranışındadır ve hook hangi devre ait olduğunu bilmediği için `--legacy-ok` kalır. Zorunluluğun gerçek dişi **spawn öncesi** (ask/exit 2) ve **faz kapısıdır** (cevapsız ajan `green`/`verified`'ı durdurur). `workflow.sh` hiçbir şeyi yazmaz; `sdd.sh` bu dosyada geçen "sözleşme" kelimesini bilmez (test: `grep -i contract sdd.sh` boş): `sdd.sh` yalnızca "ajan havada mı?" sorusunu `workflow.sh gate`'e sorar, kapı yalnızca `high-assurance`'ta çağrılır.

**Geçerli sözleşme doğrulamanın yerini tutmaz**: `verified` hâlâ yalnızca `record-verdict.sh`/`parse-verdict.sh`'ın yazdığı, mevcut diff'e bağlı PASS ile geçer. Test: high-assurance görevde geçerli, `done` bir verifier sözleşmesi kaydedilir; `advance verified` yine reddedilir, verdict kaydı yoktur.

Ek ajan çağrısı yok: politika betik kararıdır. Ek süreç: yalnızca high-assurance'ta (bölüm 8).

## 5. Hata ve kurtarma politikası

Mevcut `state.sh retry` (kimlik başına bir hak) ve `contract.sh close/pending` yeniden kullanıldı; yeni durum dosyası yok.

| Durum | Davranış | Nerede |
|---|---|---|
| Geçersiz geçiş | reddedilir, durum aynı, neden `not-next`/`unknown-phase`; `abort` dışında geri yok | `sdd.sh` |
| Eksik artefakt (proposal, design, `--test-cmd`) | reddedilir: `no-artifact`/`no-dod`/`no-design`; `verified` anında proposal kaybolduysa da `no-artifact` | `sdd.sh` |
| Eksik/geçersiz sözleşme | zorunluysa spawn öncesi ask/exit 2; geçersiz cevap: `state.sh retry <id>` ile **bir** yeniden deneme, ikinci hata kullanıcıya | hook, `run-role.sh`, F02 |
| Yarım kalan ajan | devir `issued` kalır → high-assurance'ta `green`/`verified` `agents-pending` ile durur; `contract.sh close <id> --reason interrupted` + tek yeniden deneme (`RETRY-OF:`) | `workflow.sh gate` |
| Yeniden deneme sınırı | kimlik başına bir; ikinci BLOCK/hata otomatik döngüyü durdurur, kullanıcıya gider | `state.sh`, `references/workflow.md` |
| Bloke doğrulama | `verified` `verdict-block` ile reddedilir; mesaj: hak harcanmadıysa tek yeniden deneme, harcandıysa "dur, kullanıcıya sor" | `sdd.sh` |
| Bayat kanıt | verdict başka diff'e aitse `stale-verdict`; `verified`/`pr` sonrası düzenleme: `status` → `evidence=stale`, `gate push` reddeder, `advance verified` yeniden doğrulamaya izin verir | `sdd.sh` |
| Eşzamanlı durum değişikliği | `start`: kilitli kontrol; `advance`: yazma anında faz karşılaştırılır (`concurrent`) | `sdd.sh` |

Kapsam dışı (F04): kontrol noktası/devam (resume) yeniden tasarımı. Burada yalnızca mevcut `state.sh`/`sdd.sh status` kullanıldı.

## 6. Telemetri (F01 defterine ek, ikinci defter yok)

| Olay / alan | Ne zaman |
|---|---|
| `task.start` + `profile` | profil seçimi (her görev; yeni olay yok, varsayılan akışta olay sayısı değişmez) |
| `workflow.decision` (`source=contract-policy`, `outcome=required|optional`, `profile`) | yalnızca profil `standard` değilse, görev başında bir kez |
| `workflow.decision` (`outcome=missing-marker`, `role`, `note=boundary=agent|process`, `reason=missing-field`) | zorunlu sözleşmesi olan devirde işaret yoksa |
| `phase.enter` | her geçiş (değişmedi) |
| `phase.reject` + `reason` (+ `category`, `phase`, `source`) | her reddedilen geçiş ve kapı |
| `retry`, `failure` (`verdict-block`, `contract`, ...) | `state.sh`, F02 (değişmedi) |

`telemetry.sh summary` çıktısına `workflow` bölümü eklendi: profil, kararlar, `rejections_by_reason`. `validate` bilinmeyen profil ve nedeni reddeder. Hassas veri yok: alanlar sabit sözlük kelimeleri ve kimliktir.

## 7. Testler (`tests/workflow.test.sh`)

135 durum, hepsi geçti: geçiş tablosu ve **her fazdan** her geçersiz hedef (durum değişmez), her geçerli geçiş, neden kodları, `start` doğrulaması; risk × profil etkileşimi (small + medium/high reddi, risk tabanı, high-assurance low, high'ın tasarım şartı); bağımsız doğrulama kapıları (no-verdict / BLOCK / bayat / yeniden doğrulama, attestation ve `ci-check`); rol × profil × `CONTRACTS` matrisi, hook (ask/guided/off, scout, kit dışı ajan, geçerli/geçersiz devir), `run-role.sh --dry-run` (exit 2 / uyarı / eski davranış); geçerli sözleşmenin doğrulamayı geçirmemesi; yarım kalan ajan (`agents-pending`, `close`, tek yeniden deneme, standard'da engellemez); eşzamanlılık (4 eş zamanlı `start` → 1, 6 eş zamanlı `advance` → 1 olay, `_verdict` kaybolmaz); telemetri; eski durum dosyası (profilsiz) ve `workflow.sh`'siz kısmi kurulum.

Çalıştırılan: `tests/run.sh`, `sdd`, `shared`, `sdkit-dir`, `risk-floor`, `hardening`, `budget`, `memory`, `telemetry`, `contract`, `workflow` paketleri ve `bin/build-adapters.sh --check`: hepsi geçti: run.sh 109, budget 45, contract 197, hardening 53, memory 38, risk-floor 76, sdd 52, sdkit-dir 64, shared 29, telemetry 118, workflow 135; adapter tutarlılığı güncel.

## 8. Benchmark

`bench/run.sh workflow` (yeni; F01 fikstürleri, simüle, ücretli LLM çağrısı yok) her senaryoyu iki kez koşar: `standard` ve `high-assurance` + sözleşmeli devirler. Betik başlatmaları `BASH_ENV` sayacıyla (`bench/call-counter.sh`) betik adına göre sayılır (alt kabuklar ve `jq`/`git` sayılmaz).

```
scenario                   variant         result   events launches  wf.sh ctr.sh tele.sh sdd.sh
high-independent-verify    standard        done         24       76      0      0     46      9
high-independent-verify    high-assurance  done         35      102      3     12     57      9
low-single-file            standard        done         13       41      0      0     23      7
low-single-file            high-assurance  refused      14       44      3      4     24      6
medium-multi-file          standard        done         15       50      0      0     28      8
medium-multi-file          high-assurance  done         20       64      3      6     33      8
multi-agent-handoff        standard        done         25       86      0      0     53      8
multi-agent-handoff        high-assurance  done         40      120      3     16     68      8
```
Okuma:
- **Mevcut senaryolarla uyum / varsayılan yol:** `standard` koşuların olay sayıları F02 öncesi/sonrası taban çizgisiyle aynıdır (24/13/15/25, F02 `overhead` tablosu) ve `workflow.sh` hiç çağrılmaz (0). Varsayılan yoldaki F03 eklentileri betik başlatması eklemez: kilit (`mkdir`), yazmada faz karşılaştırması (aynı `jq` çağrısı içinde), `reason` alanı (aynı olay). 4 senaryonun hepsi `done`'a ulaşır.
- **Ek iş yükü, yalnızca high-assurance:** görev başına **3** `workflow.sh` başlatması (bir `announce`, `green` ve `verified` kapıları), +1 `workflow.decision` olayı. Geri kalan fark (olay +5…+15, `contract.sh` 4…16 çağrı) F02'nin sözleşme maliyetidir, F03'ün değil; high-assurance bunu *zorunlu* kıldığı için bu senaryolarda görünür.
- `low-single-file` high-assurance'ta **reddedilir**: senaryoda doğrulayıcı adımı yok, `verified` `no-verdict` ile durur. Bu hata değil, tasarlanan davranıştır (bağımsız doğrulama low'da bile zorunlu).
- Taban çizgisi sınırı: F03 öncesi kodu ayrıca koşturacak bir kopya tutulmadı; karşılaştırma F02'nin kayıtlı olay sayılarına ve "varsayılan yolda `workflow.sh` çağrısı 0" ölçümüne dayanır. Süre (wall) ölçümü gürültülü olduğundan raporlanmadı. Token/maliyet iddiası yok; `--real` koşusu yapılmadı (onay gerekir).


## 9. Kalan riskler

1. **Reviewer/security-auditor çalıştırıldı mı?** high riskte hâlâ düzyazı: bu rollerin sonuçları durum dosyasında kayıtlı değil, `verified` kapısı onları aramıyor. Kayıt (ör. verifier hook'una benzer bir `record-review`) ve high-assurance'ta zorunluluğu F04 adayıdır.
2. **Profil seçimi insan/orkestratör kararıdır.** Kod, seçilen profilin altına inmeyi engeller ama "bu iş high-assurance olmalıydı" sonucunu çıkarmaz. Projeler `RISK_FLOOR_GLOBS` ile riski yola bağlayabilir; profili yola bağlayan bir taban eklenmedi (karmaşıklık). Bir ekip için sabit varsayılan profil ayarı (`SDD_PROFILE`) yok: `small` varsayılan olsaydı medium görevler start'ta düşerdi.
3. **Diğer host'larda spawn öncesi uygulama yok** (Codex/OpenCode/Cursor/Gemini hook'ları doğrulanmadı); `run-role.sh` ve faz kapıları dışında zorunluluk yalnızca düzyazıdır.
4. **`SubagentStop` bloklayamaz**: zorunlu sözleşme tarafında cevap eksikliği orkestratöre bildirilir, durdurulmaz; durdurma `agents-pending` kapısındadır ve yalnızca devir kayıtlıysa vardır.
5. **`pr` girişi**: ek koşul yok (bölüm 3); `done` girişi kullanıcıya bırakıldı.
6. Benchmark simülasyondur: token ve maliyet iddiası yok; gerçek koşu (`--real`) çalıştırılmadı, onay gerekir.

## 10. F04 için öneriler

- Reviewer/security-auditor sonuçlarını `sdd.sh` durumuna kaydeden ve high riskte `verified`'dan önce arayan bir kayıt (bölüm 9, risk 1).
- Kontrol noktası/devam: `state.sh` (`work/<slug>/state.json`) ile `sdd.sh` (`.sdd/state.json`) iki dosya; devam tek `resume` komutunda (`sdd.sh status` + `contract.sh pending` + `state.sh show`) birleştirilebilir. Bu belge ikisini birleştirmedi.
- `workflow.sh policy --json` çıktısını SessionStart bağlamına (`session-context.sh`) eklemek: model her oturumda kuralı okumak yerine koddan alır (bir süreç ve ~200 bayt).
- Profili yola/etikete bağlayan isteğe bağlı taban (`PROFILE_FLOOR_GLOBS`), yalnızca gerçek bir ihtiyaç doğarsa.
