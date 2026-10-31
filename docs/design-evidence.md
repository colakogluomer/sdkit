# Kanıt bütünlüğü ve yüksek risk zorlaması (F04)

F03'ün bilinen sınırları: yüksek riskte `reviewer` ve `security-auditor` yalnızca istemdeydi; kanıtın bayatlığı yalnızca doğrulayıcı için izleniyordu; `parse-verdict.sh --record` herkesin elle çağırabileceği bir yoldu. F04 bunları **kodla** kapatır, ek LLM çağrısı olmadan.

## 1. Ne zorlanır

| Risk / profil | `verified` | `pr` | `done` |
|---|---|---|---|
| low, standard / small | verify komutu (değişmedi) | – | – |
| medium | bağımsız verifier PASS, bu diff için (değişmedi) | – | – |
| low + high-assurance | verifier PASS (değişmedi) | – | – |
| **high** (her profil) | verifier **+ reviewer + security-auditor**, her biri *kayıtlı bir ajan çalışmasından* PASS, bu görev, bu diff | kanıt hâlâ bu diff için geçerli | kanıt, doğrulanan parmak iziyle (`verifiedFingerprint`) hâlâ geçerli ve sonradan gelen BLOCK yok |

Politikanın tek yeri `scripts/workflow.sh evidence-roles`; kapıyı `scripts/sdd.sh` uygular (`SDD_MODE`'dan bağımsız, doğrulayıcı kapısı gibi). Risk tabanı (`RISK_FLOOR_GLOBS`) etiketi yükseltir, yükselen etiket bu tabloya girer; hafif profil seçmek kapıyı düşürmez.

## 2. Kanıt kaydı

`.sdkit/.sdd/state.json` içinde (yeni dosya yok):

- `evidence.<rol>` = `{result, fingerprint, task, trust, source, run, at, seq}` — rol başına **son** kayıt geçerlidir; daha yeni BLOCK eski PASS'i her zaman ezer.
- `spawns[]` = başlatılmış ama henüz kaydı alınmamış ajan çalışmaları `{role, source, run, fp, at}` (en çok 16).
- `evidenceLog[]` = her deneme (kabul/ret ve nedeni; en çok 40). Denetim içindir.
- `evseq` = kabul edilen her kanıtta artan sayaç (eşzamanlılık koruması).
- `verdict` = eski alan; verifier kanıtıyla birlikte yazılır (geri uyum).

Geçerlilik durumu (`sdd.sh evidence [--json]`): `valid | missing | block | wrong-task | untrusted | stale | conflict`. Bayat bir PASS hiçbir kapıyı sessizce geçemez; yeniden doğrulama görevi sıfırlamaz: roller yeniden çalıştırılır, yeni kayıt eskisinin yerine geçer.

## 3. Güven: kimlik nasıl kurulur

Ajanın yazdığı metin **güvenilmez girdidir**; rol adı çıktıdaki bir satır değildir. Güvenilir kayıt (`trust=spawned`) yalnızca şöyle oluşur:

1. Çalışma **başlarken** yürütme sınırı kaydı açar: `sdd.sh _spawn <rol>` (Claude Code: `guard-budget.sh`, `PreToolUse` Agent; diğer host'lar: `run-role.sh` kendi süreci için, benzersiz `--run` kimliğiyle). Kayıt o anki diff parmak iziyle bağlanır.
2. Çalışma **biterken** kaydı o sınır yapar: Claude Code `record-verdict.sh` (`SubagentStop`, host'un `agent_id`'si), diğerlerinde `run-role.sh` sürecin sonunda `parse-verdict.sh --role <rol> --record --source run-role --run <id>`.
3. `sdd.sh _evidence` kaydı yalnızca açık bir kaydı **tüketerek** güvenilir sayar: aynı rol, aynı kaynak, aynı diff (aksi: `stale-at-record`, çalışma sırasında kod değişmişse), bir kayıt yalnızca bir kez.

Sonuçlar: elle kayıt (`manual`) saklanır ama yüksek riskte kapıyı açmaz; kayıtsız bir host olayı `unregistered` olur; kayıtlı olmayan bir `run-role` iddiası **reddedilir** (`unknown-run`); aynı kimlik iki rolde kullanılamaz (`role-conflict`); aynı kimlikle ikinci gönderim reddedilir (`duplicate`); başka görev adına gönderim reddedilir (`task-mismatch`); görev bittikten sonra gelen kanıt reddedilir (durum dosyası yok, çıkış 4). Elle kaydedilen bir PASS, aynı diff için güvenilir PASS'in yerine geçmez; elle kaydedilen BLOCK her zaman geçer (güvenli yön).

Claude Code'da `guard-pr.sh` model kabuğundan `sdd.sh _evidence|_spawn|_verdict`, `record-verdict.sh`, `guard-budget.sh` ve `.sdd/` erişimini reddeder.

`run-role.sh` reviewer/security-auditor için kayıt ve biçim denetimini yalnızca risk `high` iken yapar (düşük riskte cevapları serbest biçimde kalır; verifier her riskte kayıt alır). `bench/run.sh` simülasyonu artık doğrulayıcı verdict'ini `run-role.sh`'tan alır (ikinci elle kayıt yok) ve high-independent-verify senaryosu üç rolü de çalıştırır: **yüksek riskte simüle ajan sayısı 2 artar** (reviewer + security-auditor; bunlar SKILL.md'de zaten vardı, simülasyon modellemiyordu).

Kesilen çalışma: `run-role.sh` host sürecinin hata kodunu döndürür, kaydı bırakır (`_spawn-close`), kanıt yazmaz. Biçimi bozuk ya da `sdd.sh`'ın reddettiği cevap çıkış 6 verir, kanıt yazmaz.

## 4. Roller ve biçim

`reviewer` ve `security-auditor` çıktılarına iki satır eklendi (`SUMMARY` sayıları ve `VERDICT: PASS|BLOCK`). `parse-verdict.sh --role` bunları doğrular: bulgu satırı sayıları SUMMARY ile eşleşmeli, tam bir `VERDICT`, reviewer'da BLOCKER → BLOCK, auditor'da CRITICAL/HIGH → BLOCK, bulgu yoksa `NO FINDINGS`. LLM çağrısı yoktur.

## 5. Atomiklik ve eşzamanlılık

Tüm yazımlar `sdkit_lock` altındaki tek `put` ile yapılır (oku-değiştir-yaz). Faz geçişi `testCmd`/`verifiedFingerprint` yazımını faz hareketiyle **aynı** yazıma katar: reddedilen ya da yarışı kaybeden bir `advance` durumu değiştirmez. Attestation, hareket başarılı olduktan sonra yazılır. `verified|pr|done` hareketi, hükmünü verdiği kanıttan sonra yeni kanıt geldiyse reddedilir (`concurrent`, `evseq`).

## 6. Host yetenek matrisi (`workflow.sh capabilities`)

| Yol | Başlatmada sözleşme | Verdict ayrıştırma | Güvenilir kimlik | Kanıt kaydı | Bayat tespiti | Tamamlama kapısı | Hata bildirimi |
|---|---|---|---|---|---|---|---|
| Claude Code (hook'lar) | sorar (`PreToolUse` Agent, yalnızca `CONTRACTS=1`/high-assurance) | otomatik (`SubagentStop`) | host `agent_id` + kayıt | otomatik | zorlanır | zorlanır (`sdd.sh advance`) | orkestratöre `systemMessage` |
| `run-role.sh` (her host) | zorlanır (çıkış 2, süreç başlamaz) | otomatik (süreç bitince) | süreç sahipli kimlik + kayıt | otomatik | zorlanır | zorlanır | çıkış 3/4/5/6 + stderr |
| Host'un kendi alt ajanları (Codex, OpenCode, Cursor, Gemini) | **yok** | elle (`parse-verdict.sh --record`) | **yok**: `manual`, yüksek riskte reddedilir | elle | advance'te tespit | zorlanır | advance'te ret |
| Git hook'ları / CI | yok | yok | attestation incelemesi | attestation'dan | `ci-check` | `ci-check` | CI günlüğü |

Matrisin iddiaları `tests/evidence.test.sh` ile gönderilen dosyalara karşı sınanır (ör. Claude dışındaki hiçbir adaptör `SubagentStop`/`guard-budget` bağlamaz). Host'un kendi alt ajanlarında yürütme kimliği kurulamaz; yüksek riskte kapı orada **kapalı kalır**: o host'ta üç rol `run-role.sh` ile çalıştırılmalıdır.

## 7. CI

`ci-check`, risk `high` olan attestation'da üç rolün `PASS`, `trust=spawned` ve CI'ın yeniden hesapladığı parmak iziyle eşleşen kaydını arar (attestation `evidence` alanını taşır). F04 öncesi yüksek riskli attestation'lar bu alanı taşımaz: yeni diff için görev yeniden doğrulanmalıdır.

## 8. Sınırlar (kabul edilen)

- **Aynı kullanıcıyla kabuk erişimi olan bir süreç her yerel dosyayı, `state.json` dahil, taklit edebilir.** F04 kazara ve istem düzeyindeki öz-onayı (ajanın "PASS" yazması, `--record` çağırması, başka görevin kanıtını yeniden kullanması, bayat PASS) engeller; kararlı bir saldırganı yerelde engelleyemez. `guard-pr.sh` bir düzenli ifadedir (örn. değişkenle dolaylı çağrı onu atlatır). Arka plan güvencesi: CI `ci-check` + `<project-dir>/attestations/` için CODEOWNERS incelemesi; elle yazılmış bir attestation'ı CI da ayırt edemez.
- Claude Code `SubagentStop` yükündeki `agent_id` alanı bu depodaki hook'ların varsayımına dayanır; **canlı oturumda koşturulmadı**. Alan yoksa kayıt `manual` olur ve yüksek riskte kapı kapalı kalır (güvenli yön).
- `run-role.sh` bayrakları canlı CLI'lara karşı doğrulanmadı (F02'den beri).
- Bir ajanın cevabının *doğru* olduğu doğrulanmaz; yalnızca biçimi, görevi, rolü, yürütme kaydını ve diff'i. İçerik kalitesi rolün işidir.
- Paralel aynı rol çalışmaları aynı diff'te kayıt paylaşır; aralarında düzenleme olursa güvenli yönde reddedilir.

- Kayıt (spawn) ajana değil role bağlıdır: `PreToolUse` anında `agent_id` yoktur. Bu yüzden bir rol için **eski diff'e ait** açık kayıt varken gelen kayıt reddedilir (`stale-at-record`, roller yeniden çalıştırılır); aynı diff'te hiç ajan başlamamış bir "hayalet" kaydı başka bir durak tüketebilir (kabul edilen sınır; `run-role.sh` yolunda kayıt `--run` kimliğiyle birebir eşleşir).
- Bağımsız inceleme (F04 değerlendirmesi) `guard-pr.sh` düzenli ifadesinin değişkenle dolaylı çağrıyla (`S=…/sdd.sh; $S _evidence …`) atlatılabildiğini yeniden üretti: yerel kabuk erişimi olan süreç güvenilir kanıt üretebilir. CI/CODEOWNERS dışında yerel çözüm yoktur.

## 9. Maliyet

Düşük/orta riskte yeni zorunlu LLM çağrısı **yok**. Yüksek riskte `reviewer` ve `security-auditor` zaten SKILL.md §5'in parçasıydı; F04 onları atlanamaz yapar, çağrı eklemez; aynı diff için geçerli kanıt yeniden kullanılır, bayat olmayan rol yeniden çalıştırılmaz. Ek yük: `SKILL.md` +201 bayt, `reviewer` +94, `security-auditor` +176 bayt (yalnızca o roller çalışınca); bir bağımsız rol başlatmada bir `git` parmak izi + bir `jq` yazımı (küçük fikstürde ~0,3 sn); diğer ajan başlatmalarında hook'a ~70 ms. Gerçek token ölçümü yapılmadı.

## 10. F04.1: çalışma zamanı güveni ve sertleştirme

**Güven sınırı (iki kategori).** (A) Ajan çıktısı ve iş akışı komutlarıyla (kazara ya da istem düzeyinde) aşılabilenler: kod kapatır. (B) Aynı kullanıcı olarak keyfi kabuk/dosya yazımı gerektirenler: yerelde kapatılamaz; düzenli ifadeyle "kapatılmış" gösterilmez.

Yeniden üretilen ve sonuçları (`tests/evidence.test.sh`, "F04.1" bloğu):

| Deneme | Sonuç | Kategori |
|---|---|---|
| Kayıtsız `run-role` iddiası, uydurma `rr-…` kimliği | reddedilir (`unknown-run`) | A, kapalı |
| `agent_id` var ama spawn kaydı yok / `agent_id` yok | `untrusted`, high'da `advance verified` reddeder | A, kapalı |
| Aynı kimlik iki rolde; kimliğin yeniden kullanımı | `role-conflict` / `duplicate` | A, kapalı |
| Başka göreve ait kanıt; bayat parmak izi; görev bittikten sonra kanıt | `wrong-task` / `stale` / çıkış 4 | A, kapalı |
| Paralel kayıt ve paralel `advance verified` | `state.json` geçerli kalır, kayıt bir kez tüketilir | A, kapalı |
| Spawn kaydı açık kalan, cevapsız biten (kesilen) ajan | **düzeltildi**: `record-verdict.sh` boş cevapta `_spawn-close --role` ile kaydı kapatır; öncesinde kayıt sonraki gerçek çalışmayı `stale-at-record` ile boşa harcatırdı | A, düzeltildi |
| `Write`/`Edit` ile `.sdd/` ve `attestations/` | `guard-protected` reddeder | A, kapalı |
| `sdd.sh "_evidence"` (tırnak), `S=…; $S _evidence` | `guard-pr.sh` geçirir | **B**, kabul |
| `state.json`'u elle yazmak, sahte attestation | yerelde engellenemez; **sahte attestation `ci-check`'i geçer** (aynı diff için) | **B**, kabul |

**CI gerçeği.** `ci-check` parmak izini, risk tabanını ve bayrakları CI'da yeniden hesaplar, ama rol kanıtını (`trust=spawned`) attestation dosyasından **okur**; LLM çalışmasını CI yeniden üretemez. Yani CI yerel olarak üretilmiş attestation'a *kısmen* güvenir: yalnızca dosyanın adı verdiği diff'i (herhangi bir sonraki düzenleme onu geçersiz kılar) doğrular. En küçük pratik önlem kod değil süreçtir: `<project-dir>/attestations/` için CODEOWNERS + zorunlu inceleme + korumalı dal; imzalama altyapısı bu tehdit modeli için gerekçelendirilmedi (imzalayan anahtar da aynı kullanıcının makinesinde olurdu). Daha güçlüsü gerekirse yüksek riskli PR'da reviewer/auditor'u CI'da `run-role.sh` ile yeniden çalıştırmak (ücretli, isteğe bağlı) tek gerçek bağımsız doğrulamadır.

**Canlı Claude Code doğrulaması: UNVERIFIED.** Gerçek `Agent` çağrısı ücretli model çağrısı gerektirir; yetki yoktu. Yalnızca `claude` 2.1.316 ikilisinin şemasında `SubagentStop` girdisi için `agent_id`, `agent_type`, `agent_transcript_path`, `last_assistant_message` alanlarının tanımlı olduğu görüldü (statik kanıt). PreToolUse `Agent|Task` eşleşmesi `hooks.json`'da var. Diğer host CLI'ları (codex, opencode, cursor-agent, gemini) bu makinede kurulu değil: bayrakları doğrulanmadı.
