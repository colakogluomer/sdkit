# Mimari ve yetenek denetimi (F00)

Durum: **tamamlandı, 1.1.0 üzerinde** (`7919e82`). F00.5'te B1, B2, B3, B4, D1, D2, D4 ve R1 düzeltildi (bkz. "F00.5 sonrası durum" bölümü); bu belgenin gövdesi denetim anındaki durumu anlatır. Kapsam: yalnızca okuma ve ölçüm; üretim davranışına dokunulmadı. Kaynak kod esas alındı, belgelerle çeliştiği yerde kod yazıldı.
Her bulgunun yanında **kanıt** türü var: `okundu` (kaynak satırı), `çalıştırıldı` (aşağıdaki deney) veya `doğrulanmadı` (canlı host gerekir).

Sınıflar: **Implemented** (kodda var, testli), **Partial** (var ama bir koşulda boşluk), **Missing**, **Needs Verification** (canlı kurulum olmadan söylenemez).
Her öneri ayrıca **Gerçek açık** (davranış yanlış veya garanti boş) veya **İsteğe bağlı** (yok ama kimse zarar görmüyor) diye etiketli.

## 1. Mimari ve bileşen haritası

Kit bir uygulama değil; bash betikleri, düz dosyalar ve üretilmiş host adaptörlerinden oluşur. Çalışma zamanında tek kalıcı süreç yoktur: her hook ve betik kısa ömürlü bir süreçtir, durum dosyalardadır.

```
 kullanıcı ──► host (Claude/Codex/OpenCode/Cursor/Gemini)
                 │  skill: skills/spec-driven-dev (131 satır) ─ okur ─► references/*.md (256 satır, adım başına)
                 │  rol:   core/roles/*.md ──build-adapters──► agents/, adapters/<host>/agents/
                 ▼
   ┌──────────── karar katmanı (aynı kural, 4 giriş yolu) ─────────────┐
   │ hooks/*.sh (Claude) · hooks/adapt.sh (Cursor, Gemini)             │
   │ adapters/opencode/plugins · adapters/git/{pre-commit,pre-push}    │──► scripts/sdd.sh gate  (tek karar noktası)
   │ CI: templates/ci ──► scripts/sdd.sh ci-check                      │
   └───────────────────────────────────────────────────────────────────┘
   durum:  .sdkit/.sdd/state.json (faz makinesi)   .sdkit/work/<slug>/ (state.json, usage.jsonl, notes.md, lookups/, out/)
           .sdkit/attestations/<görev>.json (commit'li kanıt)   .sdkit/memory/ (commit'li)   .sdkit/.verify-cache/
   kurulum: bin/{sdkit,init,doctor,sync,upgrade,migrate,install,shared,lib}.sh, templates/, stacks/<stack>/
```

| Bileşen | Dosyalar | Rol |
|---|---|---|
| Giriş / CLI | `bin/sdkit` (dağıtıcı), `bin/init.sh` 316 satır, `doctor.sh`, `sync.sh`, `upgrade.sh`, `migrate.sh`, `install.sh`, `shared.sh` (paylaşılan dosyaların işaretli bloğu), `lib.sh` | Repoyu kurar, kaymayı raporlar; proje tarafı dosyalarını ezmez |
| Faz makinesi | `scripts/sdd.sh` (234) | `start/advance/gate/ci-check`, parmak izi, kanıt |
| Görev kaydı | `scripts/state.sh` | Orkestratörün devam kaydı, tek yeniden deneme, spawn sayacı |
| Rol çalıştırma | `scripts/run-role.sh`, `core/roles/`, `core/tiers.env`, `core/hosts.env`, `bin/build-adapters.sh` + `bin/emit/*` | Başsız, ayrı süreçte rol; host/tier/model seçimi |
| Doğrulama | `scripts/verify-core.sh` + `stacks/*/scripts/steps.sh`, `verify.d`, `parse-verdict.sh`, `check-plan-parity.sh`, `check-writes.sh` | Yeşil sonuç önbelleği, politika betikleri, verdict biçimi |
| Paralellik | `plan-waves.sh` (awk), `worktree.sh` | Dalgalar, yazma kümesi çakışması, izole worktree |
| Guard'lar | `hooks/guard-*.sh`, `frozen-tests.sh`, `scripts/guard.sh` | Regex emniyetleri |
| Token ekonomisi | `usage.sh`, `hooks/usage-log.sh`, `guard-budget.sh`, `result-size.sh`, `lookup-cache.sh`, `core/rules/token-economy.md` | Defter, bütçe, çıktı boyu, scout önbelleği |
| Bellek | `scripts/memory.sh`, `hooks/session-context.sh` | Dizin tabanlı proje belleği |
| Paketleme | `.claude-plugin/`, `Formula/sdkit.rb`, `packaging/` | Plugin + Homebrew |

Bağımlılıklar: `bash` (3.2 uyumlu yazılmış), `git`, `jq`, `node`+`openspec` (spec motoru), stack araç zinciri, `shasum` veya `sha1sum`, `column` (`usage.sh report`). Yeni çalışma zamanı bağımlılığı yok; öneriler de eklemiyor.
Dış entegrasyonlar: OpenSpec skill'leri (`opsx:*`), Bitbucket (`open-pr.sh`, CI şablonu), GitHub Actions şablonu, beş host CLI'ı (`run-role.sh`), Homebrew tap.

Boyut: 242 izlenen dosya, 16 hook, 16 betik, 10 rol, 4 skill, 7 stack; belgelerdeki sayılar kodla uyumlu (sayıldı).

## 2. Yetenek envanteri

| # | Yetenek | Sınıf | Gerçek uygulama | Sınırlama |
|---|---|---|---|---|
| 1 | Mimari, giriş noktaları | Implemented | `bin/sdkit` dispatcher; roller `core/roles/` tek kaynak, `build-adapters.sh --check` senkron (10 rol dosyası) | Proje dizini çözücüsü 12 dosyada kopya (§6 D1) |
| 2 | CLI: init/doctor/sync/upgrade/migrate | Implemented | `bin/*.sh`; `tests/shared.test.sh` (29), `sdkit-dir.test.sh` (64) | `doctor` yalnızca durağan kontrol; canlı host yok |
| 3 | Faz makinesi `intake→…→done` | Implemented (`start`'tan sonra) / **Partial** (öncesi) | `sdd.sh advance` her kapıyı kendisi sınar; kırmızı testin gerçekten **başarısız** olması, DoD varlığı, high'da yarış bölümü, diff parmak izi | Analist, risk onayı ve plan kapısı yalnızca skill metninde; `start --risk low` komutunu ajan kendisi verebilir (§6 R3) |
| 4 | Rol, devir, orkestrasyon | Implemented | `references/handoff.md`, `delegation.md`, `parallel.md`; "roller rol çağırmaz" kuralı; bağımsız roller `read-only` | Orkestrasyon düzyazı: kural dışına çıkışı makine yakalamaz (OpenCode/Codex'te rol-çağırma yasağı doğrulanmadı) |
| 5 | Model seçimi/yönlendirme | **Partial** | Tier tek kaynak `core/tiers.env`; `run-role.sh` host/tier/model'i betikle çözer (`--dry-run` testli) | Claude yolunda `Agent` aracına `model` parametresini orkestratör modelin hatırlamasına bağlı (`model-routing.md`); `tierenv` mantığı yalnızca `run-role.sh`'ta, başka çağıran yok |
| 6 | Token ekonomisi, defter, bütçe | **Partial** | `usage.sh` (log/report/budget), `guard-budget` (spawn öncesi), `run-role.sh` (spawn noktası); `tests/budget.test.sh` 45 durum | Yalnızca Claude + Gemini token yazar; birim token (tier fiyatı yok); yalnızca spawn öncesi denetim; yarış (§6 D4); kapanışta defter silinir (§6 D6) |
| 7 | Bağlam yükleme | Implemented | SKILL.md kısa; `references/` yalnızca adımda okunur; bellek dizini `MEMORY_INDEX_MAX=100` ile kırpılır; `session-context.sh` tek mesaj | Bellek dizini her oturumda enjekte edilir (sınırlı ve ayarlanabilir) |
| 8 | Bellek, önbellek, kalıcı durum | Implemented, **bir hata** | `memory.sh` (38 test), `verify-core.sh` yeşil önbelleği (ağaç anahtarı: HEAD+diff+izlenmeyen dosya+ayar+politika), `lookup-cache.sh` | `lookup-cache` anahtarı izlenmeyen dosyaları görmez → eski cevap (§6 B3, çalıştırıldı) |
| 9 | Doğrulama, test, kalite kapıları | Implemented, **bir zayıflık** | Verifier formatı `parse-verdict.sh` ile sıkı doğrulanır; attestation + `ci-check`; frozen test; stack `verify.sh`; `verify.d` | Claude'daki `record-verdict` hook'u bu doğrulamayı **yapmaz** (§6 B2, çalıştırıldı) |
| 10 | Güvenlik, izin, izolasyon, Git | **Partial, bilerek** | Regex guard'lar (`guard-secrets/-prod/-git/-pr/-protected/-readonly`), git hook'lar, CI kapısı, worktree izolasyonu, `check-writes.sh` | Belgelenmiş sınırlar (guide §13) ayrı; yeni: env dosyası kod çalıştırır (§6 R1), `run-role --host claude` salt-okunur rolde Bash'e izin verir (§6 R4) |
| 11 | Hata işleme, yeniden deneme, süreklilik | **Partial** | `state.sh` ile devam; tek otomatik yeniden deneme betikle (`retry`); hook'lar kendi hatasında sessiz (`exit 0`); `.sdd/state.json` oturumlar arası kalır | `run-role.sh`'ta zaman aşımı ve geçici hata yeniden denemesi yok; durum dosyası yazımları kilitsiz (§6 D4) |
| 12 | Gözlemlenebilirlik, tanılama | **Partial** | `usage.sh report` (rol/tier/cache oranı), `doctor.sh`, `sync --check`, `sdd.sh status`, `last-test.log`/`last-verify.log` | Faz geçişi/ret olay günlüğü yok; `history` ve defter görev kapanınca silinir; hook kararları iz bırakmaz |

Test paketi: 6 dosya, 773 satır, **hepsi geçti** (aşağıda §10). Boşluk: canlı host adaptörleri (Codex, OpenCode, Cursor, Gemini) test edilmedi, belgelerde zaten "doğrulanmadı" diye geçiyor.

## 3. İş akışı ve ajan yürütme yaşam döngüsü

```
Adım 0 intake      analist→NEEDS-INFO turları→kullanıcı risk etiketini onaylar        [düzyazı]
                   sdd.sh start --risk R --proposal P  ──► faz intake                  [makine]
Adım 1 explore     openspec-explore (scout + lookup-cache)                             [düzyazı]
Adım 2 plan kapısı engineer taslak→plan.md→kullanıcı "Approve and propose"             [düzyazı]
Adım 3 propose     openspec-propose + DoD;  advance proposed (DoD maddesi, high:yarış)  [makine]
Adım 4 uygula      advance red (test BAŞARISIZ) → uygula → advance green              [makine]
                   high: test-writer→.frozen→developer (ayrı rol çalıştırmaları)
Adım 5 doğrula     verifier(-deep) → SubagentStop hook/parse-verdict --record
                   advance verified → attestation yaz                                  [makine]
Adım 6 BLOCK       state.sh retry <id> (1 kez) → 2. BLOCK'ta dur, kullanıcıya sor      [betik+düzyazı]
Adım 7 PR          gate push (hook+git hook+CI) → advance pr                           [makine]
Adım 8 closeout   advance done (.sdd silinir) → sync-specs, archive, work/<slug> silinir [makine+düzyazı]
```

Her `Edit/Write`, `push`, `gh pr create` çağrısı `sdd.sh gate`'e gider; Claude'da hook, Cursor/Gemini'de `adapt.sh`, OpenCode'da eklenti, diğerlerinde `pre-commit`/`pre-push`, sunucuda `ci-check`. **Tek karar noktası tasarımı sağlam** ve kopya mantık yok.

Ajan yürütmesi: Claude'da `Agent` aracı + `guard-budget` (PreToolUse) + `record-verdict`/`usage-log`/`result-size` (SubagentStop). Diğer host'larda `run-role.sh`: rol metni + devir → başsız CLI → cevap + token satırı → `usage.sh log`.
Bağımsızlık makine tarafından yalnızca iki yerde zorlanır: verdict'in diff parmak iziyle bağlanması ve (Claude'da) salt-okunur araç listesi/`guard-readonly`.

## 4. Durum, artefakt ve bellek yaşam döngüsü

| Veri | Yer | Git | Yazan | Ömür / silinme |
|---|---|---|---|---|
| Faz durumu | `.sdkit/.sdd/state.json` (tek dosya = tek açık görev) | hayır | yalnızca `sdd.sh` (hook `_verdict`) | `done`/`abort`'ta `rm -rf`; `history` kaybolur |
| Orkestratör kaydı | `.sdkit/work/<slug>/state.json` | hayır | `state.sh` | closeout'ta elle silinir |
| Defter | `work/<slug>/usage.jsonl` | hayır | `usage.sh log` | closeout ile **silinir** |
| Notlar, plan, çıktılar, scout cevapları | `work/<slug>/{notes.md,plan.md,out/,lookups/}` | hayır | ajanlar | closeout; `lookups/` kod durumu değişince düşer |
| Kanıt | `.sdkit/attestations/<görev>.json` | **evet** | yalnızca `advance verified` | kalıcı; CODEOWNERS ile korunması önerilir |
| Bellek | `.sdkit/memory/*.md` + `INDEX.md` | evet (`MEMORY_VCS=ignore` ile hayır) | `memory.sh` | `stale` raporlar, silmez |
| Doğrulama önbelleği | `.sdkit/.verify-cache/` | hayır | `verify-core.sh` | son 20 giriş |
| Donmuş testler | `.sdkit/.frozen` | hayır | test-writer | `done`/`abort` |

İki "görev durumu" var (`.sdd/state.json`, `work/<slug>/state.json`); `risk` ve `verdict` ikisinde de geçiyor, kimin yetkili olduğu yalnızca belgede yazılı (`SKILL.md`: "`state.sh` stays the resume record; `<sdd>` is the gate"). Sorun bütçe tarafında: hangi `<slug>`'ın bütçesi sayılacak sorusunu `guard-budget.sh` ve `run-role.sh` `ls -t work/*/state.json | head -1` ("en son güncellenen") ile cevaplıyor; `sdd.sh`'ın bildiği `.task` kullanılmıyor.

## 5. Uyumluluk kısıtları

Aşağıdakiler önerileri sınırlar; hiçbir öneri bunları bozmamalı.

1. **Bash 3.2 (macOS), `set -u`**: boş dizi genişletmesi hata verir (kodda not düşülmüş); `declare -A`, `mapfile`, `${!ref}` dizi hileleri yok. `${!var}` dolaylı genişletme 3.2'de çalışır.
2. **Çoklu host**: bir hook değişikliği 4 yere yansımalı (`hooks.json`, `adapt.sh` tabloları, OpenCode eklentisi, `guard.sh`) ve `sdd.sh gate` arayüzü (çıkış 0/1 + stdout gerekçe) kararlı kalmalı.
3. **Proje tarafı dosyaları ezilmez** (`project.md`, `sdkit.env` yalnızca ekleme, `rules/`, `settings.json`); ayar anahtarı adları ve `KEY=VALUE` + `: "${X:=v}"` biçimi mevcut repolarda var (`templates/sdkit.env` satır 25 kabuk sözdizimi kullanıyor).
4. **Eski düzenler**: `.agentkit/.claude/.codex` + `project.env` çözücüsü `upgrade --migrate` ile kalkana kadar korunmalı.
5. **Sürümleme**: `plugin.json` ve `marketplace.json` birlikte; davranış değişikliği için `docs/upgrading.md` bölümü. Sayılar `README`, `core/roles/README.md`, `guide.md` §2/6/7/10/15, `cheatsheet.md`, `CONTRIBUTING.md`'de eşit tutulur.
6. **Guard varsayılanı kapalı/sessiz**: hook kendi hatasında bloklamaz; öneriler bunu bozmamalı.
7. **Attestation biçimi** CI'daki repolarda kullanımda: `fingerprint` hesabı değişirse tüm açık PR'ların kanıtı eskir (major sürüm).
8. **Adaptörler canlı doğrulanmadı**: Claude dışı host'ları etkileyen değişiklik `--dry-run`/fixture ile sınanır, "doğrulandı" denmez.

## 6. Bulgular: teknik borç ve mimari risk

### Hatalar ve kod ile belge çelişkileri (Gerçek açık)

**B1. `guard-pr` skill'in önerdiği komutu reddediyor** (`çalıştırıldı`).
`skills/spec-driven-dev/SKILL.md` §5 orkestratöre `parse-verdict.sh - --proposal <proposal.md> --record` çalıştırmasını söylüyor. `hooks/guard-pr.sh` aynı komutu (`parse-verdict\.sh[^;&|]*--record` kalıbı) Claude'da `deny` ediyor.
Deney: komutu `guard-pr.sh`'a verince `permissionDecision: deny` döndü. Claude'da verdict zaten `record-verdict` hook'undan geldiği için akış çalışır, ama metin yanlış yönlendirir ve ajan "reddi aşma" davranışına itilir. Çözüm: SKILL.md'de "Claude: `--record` kullanma, yalnızca doğrulama"; diğer host'larda `--record`.

**B2. Claude yolunda verdict biçimi doğrulanmıyor** (`çalıştırıldı`).
`hooks/record-verdict.sh` yalnızca `VERDICT: (PASS|BLOCK)` satırını regex ile alıp `sdd.sh _verdict` yazıyor. `parse-verdict.sh` ise DoD satırlarının PASS/FAIL'i, bulguların CONFIRMED/PLAUSIBLE'ı ve verdict-ile-bulgu tutarlılığını sınıyor (ve `--record` yalnızca tutarlı bloğu kaydediyor).
Deney: `DOD - D1 | FAIL | … VERDICT: PASS` içeren bir SubagentStop girdisi hook'tan geçti ve durum dosyasına `verdict.result = PASS` yazıldı; `parse-verdict.sh` aynı metne `MALFORMED … require BLOCK` (çıkış 2) dedi.
Yani en güçlü bağımsız-doğrulama garantisinin Claude'daki yolu, host-bağımsız yoldan zayıf. Çözüm: hook, `parse-verdict.sh --record` çağırsın (tek karar kodu). Bkz. ADR-0003.

**B3. `lookup-cache` yeni izlenmeyen dosyayı görmüyor** (`çalıştırıldı`).
`state()` = `HEAD` + `git diff HEAD` özeti; izlenmeyen dosyalar `git diff HEAD`'te yok. `verify-core.sh` ise anahtarına izlenmeyen dosya içeriğini katıyor. Deney: `put` sonrası yeni dosya eklenince `get` hâlâ **HIT**.
Etki: "bu sembol nerede" cevabı yeni dosya eklenince eskiyor; scout cevabı yanlış kalıyor. Çözüm: `git ls-files -o --exclude-standard` çıktısını (içerik özetiyle) anahtara kat; `verify-core.sh`'taki parçayla ortak yardımcıya taşı.

**B4. `STACK` varsayılanı tutarsız** (`okundu`).
`sdd.sh` `${STACK:-generic}` kullanıyor; `stop-verify.sh`, `guard.sh`, `check-tools.sh`, `post-edit-fmt.sh`, `doctor.sh`, `verify-core.sh`, `upgrade.sh`, `migrate.sh`, `shared.sh`, `lib.sh` `${STACK:-go}` (10 dosya). `STACK` boşsa Go doğrulaması çalışır. `templates/sdkit.env` normalde `STACK` yazdığı için nadir, ama elle silinmiş/eski repoda yanlış stack sessizce seçilir. Çözüm: tek varsayılan (`generic`), tek yerde.

### Çoğaltma ve kırılgan tasarım (Gerçek açık, düşük risk)

**D1. Proje dizini çözücüsü ve env yükleyicisi 12 dosyada kopya** (`okundu`): `hooks/lib.sh`, `scripts/{sdd,state,usage,guard,memory,lookup-cache,open-pr,plan-waves,resolve-base,run-role,verify-core}.sh` aynı iki satırı taşıyor; `plan-waves.sh` farklı bir varyant (env'i `sed` ile okuyor, yerel dosya önce). Tasarım kaydı bunu biliyor (`design-sdkit-dir.md` §2: "12 script"). `matches_glob_list` de 3 kopya (`hooks/lib.sh`, `guard.sh`, `sdd.sh`), biri boş-dizi korumasını taşıyor, biri taşımıyor.
Bakım riski: bir kural (örn. yeni env dosyası, yeni eski-düzen adı) 12 yerde değişir. Çözüm: tek `scripts/env.sh` (kaynaklanır), betikler `. "$here/env.sh"` yapar. Bkz. ADR-0001.

**D2. İki görev durumu** (§4): `risk`/`verdict` çift. Bütçe ve spawn sayımı "en son güncellenen state.json" varsayımına bağlı; iki görev paralel açıksa yanlış göreve yazılır; hiç `work/<slug>/state.json` yoksa bütçe **sessizce devre dışı** (hook `exit 0`). Çözüm: `.sdd/state.json`'daki `.task`'ı kullan. Bkz. ADR-0002.

**D3. Alan kopyası**: `tierenv` (`run-role.sh`) ve `core/tiers.env` ayrıştırması yalnızca orada; Claude yolunda aynı çözümü yapan bir betik yok, yani deterministik tablo var ama çağrılacak komut yok. Çözüm (isteğe bağlı): `run-role.sh --print-model` veya küçük `tier-model.sh <host> <tier>`; orkestratör `model` parametresini ondan alır.

**D4. Yarış durumları** (`çalıştırıldı`). Paralel dalga özelliği (`MAX_PARALLEL=3`, tek mesajda birden çok `Agent`) varken:
- `state.sh spawn` oku-değiştir-yaz kilitsiz: 20 eşzamanlı çağrı sonrası sayaç **3** (beklenen 20). `MAX_SPAWNS` sınırı geçilebilir.
- `usage.sh log --id` satırı `grep -vF` + `mv` ile yeniden yazıyor: 20 eşzamanlı çağrı sonrası defterde **3** satır (beklenen 20). Paralel SubagentStop'lar defterden satır siler, bütçe düşük okunur.
- `sdd.sh put` aynı desen (tek yazar: hook + orkestratör, düşük risk).
Claude'un PreToolUse/SubagentStop hook'larını gerçekten eşzamanlı çalıştırıp çalıştırmadığı **Needs Verification**; betik düzeyindeki yarış kesin. Çözüm: `mkdir` tabanlı küçük kilit (taşınabilir, bağımlılıksız) veya defterde `--id` yeniden yazmak yerine append-only + rapor sırasında `id` tekilleştirme. Bkz. ADR-0004.

**D5. `${…}` dolaylı alan**: `run-role.sh` `eval "model=\${RUN_ROLE_MODEL_$T:-}"`; `T`, `--tier` ile gelirse doğrulanıyor ama rol dosyasının `tier:` alanından geliyorsa (`<project-dir>/roles/<rol>.md`, repo içeriği) doğrulanmıyor. Düşük risk (rol dosyası güvenilir repo içeriği); `${!var}` ile `eval` kalkar.

**D6. Kapanışta tarih kaybı**: SKILL.md §8 `work/<slug>/` siler → `usage.jsonl` gider. `usage.sh report` (tüm slug'lar) yalnızca açık görevleri toplar; "bu kit gerçekten token tasarruf ediyor mu" sorusu görev bittiğinde ölçülemez. Aynı şekilde `sdd.sh`'ın `history` listesi `done`'da silinir. (İsteğe bağlı §7 O1.)

### Güvenlik ve bağımsızlık (Gerçek açık)

**R1. Ayar dosyaları kod olarak çalışıyor** (`çalıştırıldı`). Tüm betikler ve hook'lar `sdkit.env` ve `sdkit.local.env`'i `.` ile *kaynaklıyor*. Deney: `.sdkit/sdkit.env`'e `touch PWNED` satırı eklenip `session-context.sh` çalıştırılınca dosya oluştu.
`sdkit.env` ekip tarafından commit'lenen dosya; kötü niyetli bir PR veya güvenilmeyen klon, SessionStart hook'u çalıştığı anda komut yürütebilir (Claude'un çalışma alanı güven istemi ilk savunma, ama kit ikinci bir kanal açıyor). Bu, "guard'lar güvenlik sınırı değil" uyarısının dışında kalan, kitin kendi yüzeyi. Çözüm: ayarları `KEY=VALUE` olarak **ayrıştır** (çalıştırma yok); `: "${PR_HOST:=bitbucket}"` biçimi şablondan kalkar. D1 tek yükleyiciye indirildikten sonra tek yerde yapılır. Bkz. ADR-0001. Uyumluluk: §5.3.

**R2. Parmak izi ve kanıt güveni** (belgelenmiş, `okundu`): kanıt dosyası yazma yetkisi olan herkesçe üretilebilir; `ci-check` yalnızca parmak izi eşitliğine ve `verdict` alanına bakar, doğrulayıcı kimliğine bakmaz. Belgede var. Ek not: `low` risk için `verdict` boş; CI `low` kanıtını sadece parmak iziyle kabul eder, yani **risk etiketi düşürmek** (R3) CI'da verifier gereksinimini kaldırır.

**R3. Risk etiketi ajan eliyle düşürülebilir** (`okundu`). `sdd.sh start --risk low` komutuna engel yok (`guard-pr` yalnızca `.sdd/` yoluna dokunmayı ve `_verdict`'i reddediyor). "Kullanıcı onaylar" kuralı düzyazı. `ci-check` etiketi sorgulamadan kabul eder. Bu, tasarımın en zayıf halkası: risk kuralı sert olmadığı için verifier zorunluluğu atlanabilir.
Çözüm (isteğe bağlı, kullanıcı kararı): projenin `sdkit.env`'ine `RISK_FLOOR_GLOBS` benzeri "bu yollara dokunan diff en az medium" eşlemesi; `ci-check` kanıtın riskini eşlemeyle karşılaştırır. Boş = bugünkü davranış. Bkz. ADR-0005.

**R4. `run-role.sh --host claude`'da salt-okunur rol Bash çalıştırabilir** (`okundu`): yalnızca `--disallowedTools "Edit Write NotebookEdit"` veriliyor. Başsız oturumda `agent_type` olmadığı için `guard-readonly` susuyor (kendi başlığında belirtilmiş), yani verifier `rm`/`sed -i` çalıştırabilir. Codex (`--sandbox read-only`) ve Gemini (`plan`) gerçek sandbox kullanıyor; Claude yolu daha zayıf. Çözüm: `--allowedTools` ile okuma+izinli kabuk listesi (`READONLY_SHELL_ALLOW`, `core/hosts.env` zaten var). Canlı CLI gerektirir: **Needs Verification**.

**R5. Dayanıklılık**: `run-role.sh` host CLI'ına zaman aşımı koymuyor; takılan bir doğrulayıcı oturumu bloklar. Geçici hatada (rc≠0) yeniden deneme yok (bilerek: tek yeniden deneme BLOCK içindir). Çözüm (isteğe bağlı): `RUN_ROLE_TIMEOUT` (boş = kapalı), taşınabilir `timeout`/`gtimeout` bulunursa. Not: istem argv ile geçiyor (büyük devirde `ARG_MAX`, `ps` ile görünür); stdin'e geçiş host başına doğrulanmalı.

### Taşınabilirlik (Needs Verification)

**P1.** `shasum` doğrudan çağrılıyor (`sdd.sh`, `verify-core.sh`); `lookup-cache.sh` `sha1sum` yedeği taşıyor. CI şablonu `alpine/git` + `coreutils` kuruyor; `shasum` bu pakette gelmeyebilir (doğrulanmadı) → `ci-check` çalışmayabilir. Gerçek bir Bitbucket çalıştırmasıyla doğrulanmalı; yedek `sha256sum`'a düşmek tek satır.
**P2.** Cursor/Gemini hook'ları `guard-readonly`, `guard-budget`, `usage-log`, `record-verdict`'i bağlamıyor (bilerek: Claude'a özgü alanlar). Bu host'larda bütçe yalnızca `run-role.sh` yolunda, bağımsız doğrulama `parse-verdict --record`'a dayalı; belgelerde yazılı.

## 7. Öncelikli iyileştirme listesi

Etiketler: **G** = gerçek açık, **O** = isteğe bağlı. Çaba: S (<1 saat), M (yarım gün), L (gün+). Hepsi bağımlılıksız bash/jq.

| Öncelik | Kimlik | Tür | İş | Çaba | Neden şimdi |
|---|---|---|---|---|---|
| P0 | B2 | G | `record-verdict.sh` → `parse-verdict.sh --record` (tek doğrulama kodu); test: tutarsız blok kaydedilmez | S | En güçlü garantinin Claude yolundaki boşluğu |
| P0 | B1 | G | SKILL.md §5 / `hosts.md`: Claude'da `--record` yok (hook kaydeder); aksi host'ta var | S | Skill, hook'un yasakladığı komutu söylüyor |
| P0 | D4 | G | `state.sh spawn` ve `usage.sh log` için `mkdir` kilidi veya append-only; paralel yarış testi (20 işlem) | M | Paralel dalga ana özellik; sayaç ve defter yanlış |
| P1 | R1+D1 | G | Tek `scripts/env.sh` + `KEY=VALUE` ayrıştırıcı (çalıştırmadan); `plan-waves.sh` varyantını da onunla değiştir; şablondaki `: "${…:=…}"` satırı sadeleşir | L | Güvenlik yüzeyi + 12 kopya tek yerde; ADR-0001, uyumluluk için `upgrade` notu |
| P1 | D2 | G | Bütçe/spawn slug'ı `.sdd/state.json .task`'tan; yoksa mevcut sezgisel yol | S | Paralel iki görevde yanlış bütçe |
| P1 | B3 | G | `lookup-cache` anahtarına izlenmeyen dosyalar | S | Yanlış scout cevabı |
| P1 | B4 | G | Tek `STACK` varsayılanı (`generic`) | S | Sessiz yanlış stack |
| P2 | R3 | O* | `RISK_FLOOR_GLOBS` (varsayılan boş) + `ci-check` karşılaştırması | M | *Kullanıcı kararı (ADR-0005); risk düşürmeyi sertleştirir |
| P2 | D6 | O | Kapanışta `usage.jsonl`'ı özetleyip `.sdkit/work` dışına/`attestations` yanına tek satır arşivle veya `usage.sh report --archive` | S-M | Maliyet geçmişi yoksa tasarruf iddiası ölçülemez |
| P2 | R4 | G? | `run-role --host claude` için izinli kabuk listesi | S | Canlı CLI ile doğrulanınca |
| P2 | P1 | G? | `ci-check` için `sha256sum` yedeği + gerçek CI çalıştırması | S | Alpine şablonu |
| P3 | D3 | O | `tier-model.sh` / `--print-model` | S | Claude yolunda model seçimini betik yapar (ajan hatırlamak zorunda kalmaz) |
| P3 | R5 | O | `RUN_ROLE_TIMEOUT` | S | Takılan CLI |
| P3 | D5 | O | `eval` → `${!var}` | S | Sertleştirme |
| P3 | — | O | Faz geçişi/ret olay günlüğü (`.sdkit/work/<slug>/events.jsonl`, tek satır/olay) | M | Tanılama: "neden reddedildi" bugün yalnızca anlık gerekçe |

**Bilerek önerilmeyenler** (gerçek açık değil veya fayda < maliyet): çok görevli `.sdd/` (worktree başına zaten ayrı), token yerine para bütçesi (tier fiyatları sürümle değişir, kit model adı uydurmaz), Node/Python'a taşıma (bash 3.2 + bağımlılıksız tasarım avantaj), yeni orkestrasyon çerçevesi, imzalı kanıt (CODEOWNERS yeterli; R2'de belgeli), analist/plan kapısını faz makinesine sokmak (kullanıcı onayı makine tarafından kanıtlanamaz; yalnızca R3'teki etiket tabanı anlamlı).

**Sadeleştirme fırsatı:** D1 + D2 + B4 birlikte yaklaşık 12 çözücü kopyasını, 3 `matches_glob_list`'i, 10 `STACK` varsayılanını ve iki bütçe-slug sezgisini tek yere indirir; davranış değişmez, yeni soyutlama değil, var olan kopyaların birleşmesi.

## 8. Mimari karar kayıtları (öneri)

Biçim `templates/adr/TEMPLATE.md`. ADR-0001..0005 F00.5'te uygulandı. Kit'in kendi karar kayıtları `docs/` altında tasarım belgeleri olarak tutuluyor (`design-sdkit-dir.md` gibi); bunlar kabul edilince ayrı tasarım belgesine taşınır.

### ADR-0001. Ayarlar kabuk olarak değil veri olarak okunur
- Status: accepted, uygulandı (F00.5) · Date: 2026-10-29 · Ticket: F00 (R1, D1)
- **Context.** 12 dosya `sdkit.env`/`sdkit.local.env`'i `.` ile kaynaklıyor; commit'li bir dosya hook anında komut çalıştırabilir (çalıştırıldı, §6 R1). Aynı yükleme kodu 12 kez kopya.
- **Decision.** `scripts/env.sh`: çözücü + `KEY=VALUE` (tırnaklı veya düz) ayrıştırıcı, `export` eder, hiçbir şey çalıştırmaz. Betikler onu kaynaklar. Eski `: "${X:=v}"` ve `$(…)` içeren satırlar `doctor`'da uyarı verir ve `upgrade` bunları `KEY=VALUE`'ya çevirir.
- **Alternatives.** Olduğu gibi bırakıp belgelemek: yüzey kalır. Ayarları JSON'a taşımak: tüm mevcut repolar için kırıcı, `jq` her hook'ta ek süreç.
- **Consequences.** Güvenlik yüzeyi kapanır, 12 kopya tek olur. Ayarlarda kabuk genişletmesi (`$HOME`, birleştirme) artık çalışmaz: major/minor kararı ve `upgrading.md` bölümü gerekir. `VERIFY_CMD` gibi komut ayarları hâlâ **çalıştırılan** değerlerdir (yalnızca env yüklenirken değil, çağrıldığında), bu kasıtlı.

### ADR-0002. Etkin görev kimliği `.sdd/state.json`'dan gelir
- Status: accepted, uygulandı (F00.5) · Date: 2026-10-29 · Ticket: F00 (D2)
- **Context.** Bütçe ve spawn sayımı "en son güncellenen `work/*/state.json`" sezgisine dayanıyor; iki açık görevde yanlış kayıt, hiç yoksa sessiz kapanma.
- **Decision.** `sdd.sh status --slug` (veya `.task`) tek kaynak; `guard-budget.sh` ve `run-role.sh` onu sorar, yoksa bugünkü sezgiye düşer. İki durum dosyası birleştirilmez (biri git-dışı faz kapısı, diğeri orkestratör devam kaydı; ömürleri farklı).
- **Alternatives.** Dosyaları birleştirmek: `state.sh`'ın alanları (`step`, `tasks`, `retries`) fazla farklı, geriye uyumsuz. Sezgiyi korumak: paralel görevde yanlış.
- **Consequences.** Küçük, geri alınabilir değişiklik; `sdd.sh` görev yokken boş döner ve eski davranış korunur.

### ADR-0003. Verdict yalnızca `parse-verdict.sh` ile kaydedilir
- Status: accepted, uygulandı (F00.5) · Date: 2026-10-29 · Ticket: F00 (B2)
- **Context.** Claude hook'u regex ile `VERDICT:` satırını alıyor; tutarsız blok PASS olarak kaydedildi (çalıştırıldı).
- **Decision.** `record-verdict.sh` metni `parse-verdict.sh - --record`'a verir; geçersiz blok kaydedilmez, `systemMessage` ile orkestratöre "biçimi bir kez iste" denir.
- **Alternatives.** Hook'ta ikinci doğrulayıcı yazmak: kopya mantık. Yalnızca orkestratöre güvenmek: bağımsızlık ilkesine aykırı.
- **Consequences.** Tek doğrulama yolu, her host'ta aynı; hook, kendi hatasında hâlâ sessiz (`exit 0`). Verifier çıktısı biçimi bozuksa PASS kaydı olmaz, `advance verified` reddeder (doğru davranış).

### ADR-0004. Paylaşılan durum yazımları kilitle veya append-only
- Status: accepted, uygulandı (F00.5): kilit seçildi · Date: 2026-10-29 · Ticket: F00 (D4)
- **Context.** Eşzamanlı `state.sh spawn` ve `usage.sh log --id` güncelleme kaybediyor (20 çağrı → 3; çalıştırıldı).
- **Decision.** Defter: append-only, `--id` yeniden yazma kalkar, `report`/`budget` `id`'ye göre son satırı alır (`jq group_by`). Sayaç: `mkdir <dosya>.lock` ile kısa kritik bölüm.
- **Alternatives.** `flock`: macOS'ta yok. Tek yazıcı süreç: mimari değişikliği.
- **Consequences.** Dosya biraz büyür (anlık görüntü satırları), rapor sonucu aynı kalır; bütçe doğru okunur.

### ADR-0005. Risk tabanı (isteğe bağlı, varsayılan kapalı)
- Status: accepted, uygulandı (F00.5 kapanışı) · Date: 2026-10-29 · Ticket: F00 (R3)
- **Context.** Risk etiketi ajanın `sdd.sh start --risk` çağrısıyla belirlenir; "kullanıcı onaylar" düzyazı; `ci-check` etiketi sorgulamaz.
- **Decision.** `sdkit.env`'de `RISK_FLOOR_GLOBS` (örn. `high:services/payments/*;medium:migrations/*`); boşsa bugünkü davranış. `sdd.sh start` etiket tabanın altındaysa reddeder (`SDD_MODE` ile), `ci-check` kanıtın riskini yola göre taban ile karşılaştırır.
- **Alternatives.** Yok saymak (R3 açık kalır). Etiketi imzalamak: onay makineyle kanıtlanamaz.
- **Consequences.** Projeye özel bilgi kit'e girmez (ayar projeden gelir; "kit genel kalır" korunur). Yanlış glob sahte BLOCK üretir; `guided` kipi ve `doctor` önizlemesi gerekir.

## 9. Eksik / kısmi / iyi olanların özeti

İyi: tek karar noktası (`sdd.sh gate`) dört giriş yolunda; kırmızı-yeşil testi makinenin sınaması; diff parmak izi ile eskiyen verdict; bağımsız rollerin dar erişimi; roller tek kaynaktan üretiliyor ve `--check` ile senkron; bağımlılıksız bash; başlangıçta kapalı ve kendi hatasında sessiz hook'lar; kısa SKILL.md + adım başına referans; sağlam test paketi (773 satır, 337 durum).
Kısmi: model yönlendirmesi (Claude yolu ajana bağlı), token ekonomisi (host kapsamı, yarış, geçmiş yok), hata/süreklilik (zaman aşımı, kilit), gözlemlenebilirlik (olay günlüğü yok), güvenlik (R1, R3, R4).
Eksik (gerçekten): faz geçişi olay günlüğü, kapanış sonrası maliyet geçmişi, çalıştırma zaman aşımı. Bunların hiçbiri P0 değil.

## 10. Denetimde yapılan kontroller

| Kontrol | Sonuç |
|---|---|
| `tests/run.sh` | 109 geçti, 0 kaldı |
| `tests/sdd.test.sh` / `shared` / `memory` / `budget` / `sdkit-dir` | 52 / 29 / 38 / 45 / 64 geçti, 0 kaldı |
| `bin/build-adapters.sh --check` | adaptörler güncel (10 rol dosyası) |
| Deney B1: `guard-pr.sh` ← `parse-verdict.sh … --record` | `deny` |
| Deney B2: `record-verdict.sh` ← DoD `FAIL` + `VERDICT: PASS` | durum dosyasına `PASS` yazıldı; `parse-verdict.sh` çıkış 2 |
| Deney B3: `lookup-cache` put → yeni izlenmeyen dosya → get | HIT (eski cevap) |
| Deney D4: 20 eşzamanlı `state.sh spawn` / `usage.sh log --id` | sayaç 3 / defter 3 satır |
| Deney R1: `sdkit.env`'e `touch` satırı → `session-context.sh` | komut çalıştı |
| Sayı eşitliği (hook 16, betik 16, rol 10, skill 4) | belgelerle uyumlu |

Deneyler geçici `git init` dizinlerinde yapıldı; kit dosyaları değişmedi. Çalıştırılmayanlar: canlı Codex/OpenCode/Cursor/Gemini, gerçek Bitbucket/GitHub CI, Claude'un hook eşzamanlılığı, `shellcheck` (kurulu değilse).

## 11. Açık sorular

1. **ADR-0005 (risk tabanı)** istenir mi? Bu, davranışı sertleştiren tek öneri ve proje başına yapılandırma ister.
2. **ADR-0001** `sdkit.env` biçimini daraltır: "ayar dosyasında kabuk genişletmesi desteklenmez" kabul edilebilir mi, hangi sürümde (minor/major)?
3. Claude PreToolUse/SubagentStop hook'ları paralel `Agent` çağrılarında eşzamanlı mı çalışıyor? Yanıt D4'ün aciliyetini belirler.
4. Maliyet geçmişi (D6) kimin için: kişisel mi (`work/` yanında kalır), ekip raporu mu (commit'li özet)?

## 12. F00.5 sonrası durum

| Bulgu | Durum | Nasıl | Regresyon testi (`tests/hardening.test.sh`) |
|---|---|---|---|
| B2 | düzeltildi | `record-verdict.sh` metni `parse-verdict.sh --record`'a verir (görevin `proposal.md`'si ile: atlanan DoD maddesi de reddedilir); geçersiz blok kaydedilmez, orkestratöre `systemMessage` gider; transcript yedeği artık son asistan metnini `jq` ile çıkarır; hook yine her durumda `exit 0` | tutarsız PASS, çıplak `VERDICT` satırı, atlanan DoD, sonradan gelen bozuk blok, transcript yedeği |
| B1 | düzeltildi | SKILL.md §5 ve `hosts.md`: Claude'da `--record` yok, diğer host'larda var. Denetimin görmediği ikinci çelişki da giderildi: Cursor/Gemini/OpenCode'da `guard-pr` tek kayıt yolunu (`--record`) da reddediyordu; `adapt.sh` ve OpenCode eklentisi `SDKIT_HOST` verir, `guard-pr` yalnızca `SDKIT_HOST` boşken (Claude) reddeder. `_verdict` ve `.sdd/` her host'ta reddedilir | host başına karar, adapt.sh üzerinden gemini, SKILL metni |
| D4 | düzeltildi | `sdkit_lock` (`mkdir`, bağımlılıksız, Bash 3.2): `state.sh` tüm yazan komutlar, `usage.sh log`, `sdd.sh put`. Ölü sahipli kilit 3 sn sonra, takılı kilit 10 sn sonra kırılır. Kilit yerine append-only seçilmedi: `--id` yeniden yazma semantiği ve eski okuyucular korunur | 30 paralel `spawn` (önce 5), 30 `task`, 30 `log --id` (önce 3), aynı `id`, 20 `_verdict`, bayat kilit |
| R1+D1 | düzeltildi | `scripts/env.sh`: tek çözücü + ayrıştırıcı; 12 kopya kalktı (`plan-waves.sh` varyantı dahil, `bin/*` `lib.sh` üzerinden). Geçiş: `upgrading.md`. `doctor` yok sayılan satırları `dosya:satır` ile FAIL olarak bildirir | `$(...)`, backtick, `;`, boşluklu değer, çıplak komut, `PATH=` çalışmaz; desteklenen sözdizimi aynı anlamda; tüm giriş noktaları; kaynak-kullanım taraması |
| D2 | düzeltildi | `sdkit_active_slug`: açık SDD görevi (`work/<slug>/state.json` varsa), yoksa eski sezgi. `sdd.sh task` eklendi. `guard-budget`, `run-role`, `usage.sh` kullanır | iki görev, defter slug'ı, iki geri dönüş yolu |
| B3 | düzeltildi | `lookup-cache` anahtarı izlenmeyen dosya adı+içeriği; kitin kendi `work/`, `.sdd`, `.verify-cache` yolları hariç | yeni dosya, düzenleme, kendi dosyası, izlenen düzenleme |
| B4 | düzeltildi, **denetimin önerisinden farklı** | Tek varsayılan `go` (`SDKIT_DEFAULT_STACK`, `scripts/env.sh`). `generic` önerilmişti, ama `go` belgelenmiş varsayılan (`guide.md` §10) ve stack öncesi Go-only repoların sessiz varsayımı; `generic`e çevirmek onları bozardı. Sapan tek yer (`sdd.sh`) hizalandı; `doctor` boş `STACK`'te uyarır | kaynak taraması, varsayılan, açık değer, doctor |
| R3 | düzeltildi (isteğe bağlı özellik) | ADR-0005: `RISK_FLOOR_GLOBS=seviye:glob,...`, boşken kapalı. Mevcut `matches_glob_list` ve `changed_files` (parmak izinin dosya kümesi, izlenmeyen dosyalar dahil) kullanılır; `advance green`/`verified` ve `ci-check` denetler. CI tabanı kendisi yeniden hesaplar (attestation'daki `floor` alanına güvenmez), düşük riskli attestation yüksek tabanı karşılamaz, taban branch'in `sdkit.env`'indeki `RISK_FLOOR_GLOBS` ve `SDD_MODE` PR tarafından gevşetilemez, tabana uyan dosya serbest glob'larda bile attestation ister, bozuk değer reddedilir. Ayrıntı ve sınırlar: `upgrading.md` | 76 durum, `tests/risk-floor.test.sh` |

Değişmeyenler: faz makinesi, hook sözleşmesi (`exit 0`, kendi hatasında sessiz), rol ve host mimarisi, `sdd.sh gate` arayüzü, attestation biçimi. Açık kalanlar: §7'deki P2/P3 maddeleri (R3 aşağıdaki satırla kapandı).

ADR-0005'in karar metninden sapmalar: `sdd.sh start` etiketi reddetmez (başlangıçta diff yoktur; tabana göre denetim `green` ve `verified`'da yapılır, `start` yalnızca bozuk yapılandırmayı reddeder); biçim `;` değil `,` ayırır (diğer glob listeleriyle aynı) ve her girdi `seviye:` önekini taşır.
