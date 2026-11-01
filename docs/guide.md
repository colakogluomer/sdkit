# spec-driven-kit rehberi

Bu rehber kit'in içindeki her parçayı (skill, agent, hook, script, yapılandırma) ve birbirleriyle nasıl çalıştıklarını
anlatır. Hızlı kurulum için `README.md`, PR host'ları için `hosts.md` var.

İçindekiler: 1. Nedir · 2. Genel bakış · 3. Plugin ve proje tarafı ·
4. Akış: spec-driven-dev · 5. Skill'ler · 6. Roller ·
7. Hook'lar ve guard'lar · 8. Doğrulama motoru ·
9. Yardımcı script'ler · 10. Yapılandırma referansı ·
11. Kurulum akışları · 12. İzin modeli · 13. Sınırlar ·
14. Genişletme · 15. Dosya haritası ·
16. Host'lar: Claude Code, Codex, OpenCode, Cursor, Gemini · 17. Paralel çalışma · 18. Token ekonomisi

---

## 1. Nedir

Claude Code ile bir göreve "tek seferde, kontrolsüz" girişmek yerine **tanımlı bir süreçten** geçirir:

```
görev ──► analist (eksik var mı?) ──► risk etiketi (sen onaylarsın) ──► keşif
      ──► PLAN KAPISI (sen detaylıca onaylarsın) ──► öneri + test-doğrulamalı "Definition of Done"
      ──► test önce (RED) ──► rollerle gerçekleştirme (GREEN, gerekirse paralel)
      ──► bağımsız doğrulama ──► PR (ajan açar) ──► kapanış
```

Kit bir **ajan geliştirme kütüphanesidir**: roller ve akış araçtan bağımsız yazılır, Claude Code, Codex, OpenCode, Cursor ve Gemini CLI için adaptörler üretilir (bölüm 16).

Dört şeyi garanti etmeye çalışır:

1. **Aynı model hem yazıp hem "tamam" diyemez.** Orta ve yüksek riskte doğrulamayı, gerçekleştirmeyi görmemiş ayrı bir agent yapar.
2. **Kurallar hatırlatma değil, mekanizma.** Tehlikeli veya yanlış bir adım (prod'a `kubectl`, secret dosyası okumak, `develop`'u feature'a
   merge etmek, kırık kodla "bitti" demek) hook'larla engellenir veya onay ister.
3. **Test öncelikli düşünce.** Her Definition of Done maddesi nasıl doğrulanacağını söyler; yazılabilen test koddan önce yazılır (`rules/test-first.md`).
4. **Proje bilgisi kit'in içinde değil.** Risk ölçütleri, kurallar, test yerleşimi, projeye özel kontroller repodaki proje klasörü
   klasöründe durur. Kit hiçbir projeye özel şey içermez, bu yüzden her repoda çalışır.

İki ek ilke: **token israf edilmez, kısılmaz da** (bölüm 18) ve **uygulama planı sen onaylamadan öneriye (`propose`) geçilmez** (bölüm 4, adım 2).

---

## 2. Genel bakış

| Parça | Adet | Ne işe yarar |
|---|---|---|
| **Skill** | 4 | Görevi yürüten talimat setleri: `spec-driven-dev` (ana akış, `references/` ile kademeli yüklenir), `incident-to-rule`, `scaffold-init`, `scaffold-doctor` |
| **Rol** | 10 | `core/roles/` altında araçtan bağımsız tanımlar: `orchestrator`, `analyst`, `scout`, `engineer`, `developer`, `test-writer`, `devsecops`, `reviewer`, `security-auditor`, `verifier`. Dokuzu subagent olarak üretilir; `verifier`'ın `deep: strong` ile strong katmanlı ikizi `verifier-deep` de üretilir, yani host başına **10 rol dosyası** |
| **Hook** | 18 + 1 | Claude Code'da araç adımları ve oturum sınırlarında otomatik çalışan 18 kontrol (`guard-readonly`, `usage-log`, `guard-budget`, `result-size`, `check-contract`, `value-report` dahil) ve diğer host'ların aynı hook'ları çağırdığı `adapt.sh` kabuğu. Hook olmayan yerde git hook'ları aynı kuralların çoğunu uygular |
| **Doğrulama motoru** | 1 çekirdek + stack başına adımlar | `scripts/verify-core.sh` (diff tabanı, değişen dosyalar, `verify.d`, yeşil-sonuç önbelleği) + `stacks/<stack>/scripts/steps.sh` (stack'in kendi kontrolleri) |
| **Stack** | 7 | `go`, `spring-boot` ve `jvm` (Maven/Gradle), `python`, `nextjs`, `react-native` (son ikisi `stacks/_node/` yardımcısını paylaşır) ve algılama başarısızsa `generic`. Sözleşme: `stacks/README.md` |
| **Script** | 31 | `sdd.sh`, `resolve-base.sh`, `open-pr.sh`, `guard.sh`, `plan-waves.sh`, `worktree.sh`, `state.sh`, `parse-verdict.sh`, `check-plan-parity.sh`, `dod-check.sh`, `digest.sh`, `test-select.sh`, `adapter.sh`, `dispatch.sh`, `knowledge.sh`, `recover.sh`, `redact.sh`, `audit.sh`, `pr-check.sh`, `check-writes.sh`, `usage.sh`, `telemetry.sh`, `contract.sh`, `workflow.sh`, `route.sh`, `memory.sh`, `lookup-cache.sh`, `run-role.sh` + `verify-core.sh` ve `verify-lib.sh` (motor; doğrudan çalıştırılmaz) |
| **Kurallar** | 4+ | `core/rules/`: `general`, `git`, `test-first`, `token-economy` (+ stack kuralları) |
| **Şablonlar** | | Yeni repoda doldurulacak proje tarafı dosyaları (`templates/`, `stacks/go/`, `core/rules/`) |
| **Host** | 5 | `claude`, `codex`, `opencode`, `cursor`, `gemini`; rol/guard biçimi `bin/emit/<host>.sh` + `core/hosts.env` (bölüm 16) |
| **Araçlar** | 6 | `bin/init.sh`, `bin/doctor.sh`, `bin/sync.sh`, `bin/upgrade.sh` (`--migrate` için `bin/migrate.sh`), `bin/build-adapters.sh` + tek komut olan `bin/sdkit` |

Kullanıcı tarafında gördüğün isimler plugin kuruluyken ad alanlıdır: `spec-driven-kit:spec-driven-dev`,
`spec-driven-kit:verifier`. Slash komutu ad alanı olmadan da çalışır: `/spec-driven-dev`. Codex'te skill `$spec-driven-dev` ile çağrılır; diğer host'larda bölüm 16'daki tabloya bak.

---

## 3. Plugin ve proje tarafı

Kit iki parçadan oluşur ve bunların ayrımı her şeyi belirler.

| | Nerede durur | Kim yazar | Örnekler |
|---|---|---|---|
| **Plugin tarafı** (genel) | Bu repo, Claude Code plugin'i olarak kurulur | Kit bakımcıları | skill'ler, agent'lar, hook'lar, doğrulama motoru, script'ler |
| **Proje tarafı** (özel) | Her repoda `.sdkit/` (1.0 öncesi kurulumlarda `.claude`, `.codex` veya `.agentkit`; aşağıya bak) | O projenin ekibi | `sdkit.env` (ekibin ortak ayarları), `project.md`, `rules/`, `known-pitfalls.md`, `adr/`, `verify.d/`, `memory/` (hepsi git'te) ve kişisel `sdkit.local.env` |

Plugin tarafı, proje tarafını **çalışma anında okur**. Hiçbir şey sabit yazılı değildir: branch adı, risk ölçütleri, korunan yollar,
prod cluster adı hep proje dosyalarından gelir.

### Çalışma modları

| Mod | Ne zaman | Nasıl |
|---|---|---|
| **plugin** (varsayılan) | Normal kullanım (yalnız Claude) | Repoda yalnızca proje tarafı var. Hook, agent, skill ve script'ler kurulu plugin'den gelir |
| **copy** | Plugin kurulamayan ortam | `init.sh --mode copy` hook/agent/skill'leri `.claude/`, kit script'lerini `<project-dir>/scripts/` altına kopyalar; `sdkit.env` onlara işaret eder; `sync.sh` günceller |

Hook ve script'ler `VERIFY_CMD` / `DIFF_BASE_CMD` doluysa o yolu (repoya göre), boşsa plugin'in kendi script'ini kullanır.

### Proje klasörü: `.sdkit/`
1.0'dan itibaren her host için tek proje klasörü vardır: **`.sdkit/`**. Repoya **girer ve herkeste aynıdır**; yalnızca kişisel veya üretilmiş dosyalar girmez (`.sdkit/.gitignore`). Skill'ler, rol metinleri ve belgeler bu klasörden `<project-dir>` diye söz eder. 1.0 öncesi kurulumlarda klasör `.claude`, `.codex` veya `.agentkit` ve ayar dosyası `project.env`'dir; hepsi çalışmaya devam eder, `sdkit upgrade --migrate` `.sdkit/`'e taşır.

| `.sdkit/` altında | Git | Not |
|---|---|---|
| `sdkit.env`, `project.md`, `rules/`, `known-pitfalls.md`, `adr/`, `verify.d/`, `roles.d/`, `memory/`, `attestations/` | **evet** | Ekip için ortak; zamanla güncellenir (güncellemelerin hedefi hep burasıdır). `sdkit.env` ekibin makine-okunur politikasıdır: release akışı, korunan yollar ve branch'ler, prod cluster, secret kalıpları, stack ve doğrulama ayarları, memory konumu |
| `sdkit.local.env` | hayır | Kişisel, `sdkit.env`'den sonra okunur ve onu ezer: token bütçesi ve limitler, `USAGE_LOG`, `MAX_PARALLEL`, memory davranışı (`MEMORY_AUTOLOAD`, `MEMORY_PROMOTE` ...), host ve model seçimi |
| `work/`, `.frozen`, `.verify-cache/`, `.sdd/` | hayır | Çalışma zamanı |
| `hooks/`, `roles/`, `tiers.env`, `scripts/*` (CI için `sdd.sh`, `resolve-base.sh` ve `env.sh` hariç), `.scaffold-*` | hayır | `sdkit init` herkeste aynısını üretir |

Host klasörlerinde (`.claude/`, `.codex/`, `.cursor/`, `.gemini/`, `.opencode/`) repoya yalnızca temel giriş dosyaları girer: `AGENTS.md` ve `.claude/CLAUDE.md` (kit bloğu). Kitin oraya ürettiği her şey (Claude'da `settings.local.json`, roller, hook'lar, `.agents/`, `.githooks/`) bu klonun `.git/info/exclude` dosyasına yazılır; projenin `.gitignore`'una dokunulmaz. Projenin kendi skill, komut ve agent dosyalarına kit karışmaz. Kit'in `CLAUDE.md` ve `AGENTS.md` blokları ajana yeni bilginin host klasörüne değil `.sdkit/`'e yazılacağını söyler.

### Kim neyi düzenler (sahiplik)

**Kural: geliştirici kit repo'sunda hiçbir satırı değiştirmez.** Kit'i klonlar, `init.sh` ile kendi reposuna kurar; düzenlediği tek yer kendi reposudur.
Kit ayarlanacak her şeyi proje tarafında bir dosyaya bırakır:

| Dosya | Sahibi | Kit güncellenince |
|---|---|---|
| `project.md`, `rules/`, `known-pitfalls.md`, `verify.d/`, `adr/`, `roles.d/`, `memory/`, projenin kendi skill/agent/komutları ve host'un kendi hafıza dosyaları | **Proje** | Kit bir daha dokunmaz |
| `sdkit.env` | **Ekip** | Commit'li ortak politika. Kit yalnızca şablonda yeni olan ayarları sonuna ekler; var olan satır ve değerlere dokunmaz |
| `sdkit.local.env` | **Kişi** | Git'e girmez; aynı kural: yalnızca yeni ayarlar eklenir |
| `AGENTS.md`, `CLAUDE.md`, `.codex/config.toml` | **Ortak**: kit yalnızca `spec-driven-kit:begin … :end` işaretli bloğu yazar, işaretlerin dışı projenindir | `sync.sh` yalnızca bloğu yeniler |
| `.claude/settings.json` (varsa), `.cursor/hooks.json`, `.gemini/settings.json` | **Ortak**: kit yalnızca kendi anahtar ve girdilerini ekler (plugin, marketplace, izinler, `adapt.sh` / kit hook'ları); senin env, izin, hook ve diğer anahtarların olduğu gibi kalır | `sync.sh` yalnızca kit girdilerini yeniler |
| `.sdkit/scripts/`, `.sdkit/hooks/`, `.sdkit/roles/`, `.githooks/`, host rol dosyaları (`.codex/agents/` …), `.agents/skills/`, Claude'da `.claude/settings.local.json` | **Kit** (yönetilen kopya; düzenleme, git'e girmez) | `sync.sh` günceller; yerelde değiştirdiysen `CONFLICT` verir |

Kit'in davranışını özelleştirmek için kit dosyasını düzenlemek yerine: bir rolün işine proje bilgisi eklemek → `<proje-klasörü>/roles.d/<rol>.md`
(her rol varsa onu da okur, kuralları gevşetemez); OpenCode'un eski `bash` izin anahtarı → `sdkit.env`'de `OPENCODE_SHELL_KEY=bash`; model/katman →
`sdkit.env`'deki `RUN_ROLE_MODEL_*`; riskler, test düzeni, release akışı → `project.md`. İşaretli bloğun içine not yazma; kendi metnini işaretlerin dışına yaz. `.scaffold-shared` hangi dosyada kit'in hangi payı olduğunu kaydeder; `sync.sh --check` ve `doctor.sh` kit payının
güncelliğini denetler. Mevcut bir repoda ilk `upgrade`: işaretsiz `AGENTS.md`/`CLAUDE.md` varsa blok sonuna eklenir; eski kit sürümlerinin yazdığı
metin dosyada kalmışsa bir kez elle silinir.

### Proje tarafının üç ana dosyası

- **`sdkit.env`**: makine okur (hook'lar ve script'ler `source` eder). Branch, stack, tracker, korunan yollar, opsiyonel modüller. Bkz. bölüm 10.
- **`project.md`**: insan ve model okur. Tracker aracı, PR aracı, commit scope'ları, test yerleşimi, korunan kod kuralı, **risk rubriği**,
  (varsa) release akışı. Rubrik olmadan akış başlamaz.
- **`known-pitfalls.md`**: projenin yaşadığı hata sınıfları. Verifier her diff'i bu listeye karşı tarar.

---

## 4. Akış: spec-driven-dev

Ana skill. `/spec-driven-dev <ticket veya açıklama>` ile başlar. Aşağıdaki adımları sırayla yürütür; OpenSpec skill'lerini
(`openspec-explore`, `openspec-propose`, `openspec-sync-specs`, `openspec-archive-change`) çağırarak. Ana oturum **orchestrator** rolündedir.
Skill kısa tutulur; ayrıntılar `references/` altında ve yalnızca ilgili adımda okunur (`plan-gate.md`, `parallel.md`, `handoff.md`, `hosts.md`, `model-routing.md`).

### Adım 0: Girdi, analist ve risk etiketi
- Ticket numarası verildiyse ve `TRACKER` doluysa ticket çekilir; yoksa açıklama doğrudan görev olur.
- **`analyst` rolü** görevi inceler: hedef, test edilebilir kabul ölçütleri, kapsam ve kapsam dışı, hata/uç durumlar, veri etkisi, performans/güvenlik
  gereksinimi, bağımlılıklar, test edilebilirlik. Koddan cevaplanabilecek şeyi kendisi bulur, kullanıcıya yalnızca koddan çıkmayanı sorar.
  Çıktı: `READINESS: READY|NEEDS-INFO`, görev özeti, `GAPS` (eksik, neden önemli, soru, önerilen varsayılan), `ASSUMPTIONS`, önerilen risk etiketi.
- Analist `low` riskte de çalışır (ucuz ve tutarlı; derinlik riske göre değil, katmana göre ayarlanır). Roller başka rolü çağırmaz: cevaplayamadığı arama sorularını çıktısının sonuna `NEEDS-LOOKUP: <soru>` satırları olarak yazar, orchestrator `scout`'u **bir kez** çalıştırıp cevabı yol olarak geri verir.
- `NEEDS-INFO` ise boşluklar turda en fazla 4 soru olarak sana sorulur (önerilen varsayılan ilk seçenek). DoD'yi etkileyen boşluk açıkken ilerlenmez.
- Risk etiketini (`low` / `medium` / `high`) **sen onaylar veya değiştirirsin**; sonradan sen söylemeden değişmez. Risk ticket önceliğinden bağımsızdır.
- Görev durumu `state.sh <slug> init <risk> <branch>` ile `<project-dir>/work/<slug>/state.json`'a yazılır (aşağıda "Devam etme").

### Adım 1: Keşif
`openspec-explore` ile problem koda dayandırılır. "Nerede tanımlı / kim çağırıyor" soruları ucuz `scout` rolüne gider. `low` riskte de atlanmaz.

### Adım 2: Plan kapısı (öneriden önce)
`propose`'dan **önce** yapılacakların son doğrulaması, sana detaylıca sorarak. Plan `<project-dir>/work/<slug>/plan.md`'de tutulur (kişisel, git'e girmez).
`medium`/`high` riskte `engineer` rolü taslak tasarımı, test stratejisini ve görev bölünmesini hazırlar; `low` riskte orchestrator kendisi çıkarır.

Plan bölümleri: kapsam ve kapsam dışı · varsayımlar ve açık sorular · **DoD (her madde "Verified by" ile)** · tasarım (reddedilen alternatifler, `high`'da yarış senaryosu) ·
yürütme planı (görevler, dalgalar, roller) · maliyet şekli (boyut, kaç ajan çalışması; uydurma token sayısı yok) · riskler ve yayın · karar günlüğü.

Sorma biçimi: turlar halinde, turda en fazla 4 soru; her soru ilgili metni alıntılar, `Onayla` ve somut alternatifler sunar, serbest cevap her zaman mümkündür.

| Risk | Turlar |
|---|---|
| `low` | Tek tur (kapsam + DoD + yürütme), sonra son onay |
| `medium` | Kapsam/varsayımlar · DoD ve test stratejisi madde madde · yürütme ve maliyet · son onay |
| `high` | Yukarıdakilere ek olarak tasarım ve yarış senaryosu turu ile riskler/yayın turu · son onay |

**Güncelleme:** her cevap plana işlenir ve karar günlüğüne yazılır. Değişiklik **yayılır**: DoD değişirse test stratejisi ve görevler yeniden kontrol edilir,
tasarım değişirse DoD ve görevler. Yalnızca değişen ve sonuç doğuran bölümler yeniden gösterilir. Sonraki herhangi bir adımda "planı güncelle" diyebilirsin;
yalnızca etkilenen turlar tekrarlanır ve `proposal.md`/`tasks.md` OpenSpec skill'leriyle güncellenir.
Son onayda üç seçenek vardır: `Onayla ve propose et` / `Bir bölümü düzenle` / `Burada dur`. Yalnızca ilki `propose`'a geçirir.

### Adım 3: Öneri ve test-doğrulamalı Definition of Done
`openspec-propose` plan girdisiyle `proposal.md` / `design.md` / `specs/` / `tasks.md` üretir. `proposal.md`'ye **Definition of Done** eklenir: her kabul ölçütü somut
bir koşul ve bir **Verified by** girdisi. Satır biçimi sabittir: `D<n>: <metin> | Verified by: <unit test|integration test|manual check|none: gerekçe>`.
Plan, `proposal.md` ve `tasks.md` arasındaki eşitlik LLM gözüyle değil `scripts/check-plan-parity.sh plan.md proposal.md tasks.md` ile denetlenir (fark varsa düzeltilir veya sana bildirilir). `tasks.md` görevleri `role:` / `writes:` / `after:` taşır
(bölüm 17). `high` riskte `design.md`'de yarış/sıralama/zamanlama senaryosu zorunludur. Öneri plana madde madde uymalıdır; sapma sana bildirilir.

### Adım 4: Branch ve rollerle test-önce uygulama
Branch, `project.md`'deki "branch source" kuralına göre açılır (varsayılan: diff tabanı; release akışlı projede aktif release branch'i).
Release dondurulmuşsa branch açılmaz, kullanıcıya sorulur.

Önce **test edilebilirlik** kontrol edilir: kod gerçek altyapı olmadan test edilemiyorsa (örneğin somut bir istemci tipi) skill durur, hangi tip/çağrının
engellediğini söyler ve 2-3 seçenek sunar. Sessizce soyutlama eklemez, kapsamı sessizce düşürmez.

Dağıtım: testler `test-writer`, kod `developer`, pipeline/altyapı dosyaları `devsecops` rolüne, her biri bir devir özetiyle (`handoff.md`) gider. Küçük `low` görevleri
tek oturumda yapılabilir. Bağımsız görevler paralel çalıştırılabilir (bölüm 17).

| Risk | Süreç |
|---|---|
| **low** | DoD'dan test yaz → RED → gerçekleştir → GREEN → verify → PR. Ayrı doğrulayıcı yok |
| **medium** | low ile aynı + **zorunlu bağımsız doğrulama** (Adım 5) |
| **high** | Üç ayrı rol: **[A]** `test-writer` (gerçek altyapıda regresyon testi; RED görür; test dosyasını `<project-dir>/.frozen` listesine ekler), **[B]** `developer` (donmuş testi alır ama değiştiremez; yalnızca GREEN'e getirir), **[C]** `verifier`. Ek olarak `reviewer` + `security-auditor` (paralel, salt okunur) |

`high` riskte roller taze başlatılır, `fork` ile değil; böylece B, A'nın "çözüm nasıl olmalı" çerçevesini miras almaz.

### Adım 5: Bağımsız doğrulama kapısı
`verifier` (`high` riskte strong katmanlı ikizi `verifier-deep`) sıfırdan başlatılır ve yalnızca şunu alır: `proposal.md` yolu (+ `high` için `design.md`), diff tabanı, risk etiketi. Önce verify komutunu çalıştırır (kırmızıysa pahalı
okumaya girmez), sonra her DoD maddesini ve **Verified-by kanıtını** (var olmayan veya değişiklik olmadan da geçen test kanıt sayılmaz), `known-pitfalls.md`'yi tarar ve
`DOD / FINDINGS / VERIFY / VERDICT` bloğu döner (bölüm 6). Orchestrator çıktıyı `parse-verdict.sh - --proposal proposal.md`'den geçirir: 0 PASS, 1 BLOCK, 2 biçim bozuk veya tutarsız (verifier'dan biçim bir kez istenir; bu bir deneme sayılmaz). Verify kendi içinde önbellek kullanır; verifier'ın temiz bir koşu görmesi gerekirse `--no-cache` (bölüm 8).
`high` riskte ayrıca `reviewer` + `security-auditor` çalışır; `EXTRA_REVIEW_SKILLS` doluysa host'un kendi inceleme skill'leri de eklenir. Verifier farklı bir model ailesinden olsun istenirse `VERIFIER_HOST` + `run-role.sh` (bölüm 9, 16).

- Herhangi bir DoD maddesi `FAIL` veya herhangi bir `CONFIRMED` bulgu → `VERDICT: BLOCK` → PR'a geçilmez.
- `PLAUSIBLE` bulgular kaydedilir ama engellemez.

### Adım 6: Hata yönlendirme ve döngü sınırı
- **Uygulama hatası** (DoD maddesi sağlam, kod karşılamıyor) → `developer`'a **tam bir** yeniden deneme, yalnızca başarısız maddelerle. Deneme `state.sh <slug> retry <görev>` ile alınır: çıkış 0 devam, 1 hak kullanılmış (dur ve kullanıcıya sor). Sınırı hafıza değil script uygular.
- **Spec boşluğu** (DoD maddesi tutarsız/yerine getirilemez) → plan kapısına dön (etkilenen turlar) ve kullanıcıyı hemen bilgilendir.
- Aynı görevde **ikinci bir BLOCK** → otomatik deneme durur; ne olduğunu özetleyip kararı kullanıcıya bırakır. Üçüncü otomatik döngü yoktur.

### Adım 7: PR
Conventional commit, branch push, ve **PR'ı skill'in kendisi açar** (kullanıcıya iş bırakmaz). PR açıklaması: ne değişti, neden, nasıl test
edilir, doğrulama sonucu. Hedef branch `project.md`'de yazar. Merge sonrası adımlar kullanıcıya iletilir, skill çalıştırmaz.

### Adım 8: Kapanış
Merge sonrası `openspec-sync-specs` ve `openspec-archive-change`; `<project-dir>/work/<slug>/` silinir, görev worktree'leri temizlenir.

### Devam etme (resume)
Durum bir dosyada tutulur: `scripts/state.sh <slug> show` → `<project-dir>/work/<slug>/state.json` (adım, risk, branch, görev durumları, yeniden denemeler, verdict; kişisel, git'e girmez).
`/clear`, sıkıştırma veya çökme sonrası dosya varsa skill baştan başlamaz, kayıtlı `step`'ten sürer. Kapanışta `work/<slug>/` ile birlikte silinir.

### Değişmez kurallar
Aynı rol/oturum hem uygulayıp hem "doğrulandı" diyemez; DoD ve Verified-by atlanamaz; plan onaylanmadan öneri yazılmaz; risk etiketi sessizce atanamaz;
doğrulama otomatik olarak bir kereden fazla döngüye girmez; çakışan `writes:` paralel çalışmaz; küçük görünse de risk etiketi süreci belirler; proje bilgisi skill'e gömülmez.

---

### Zorlama: faz makinesi

Akışın sırası skill metnine değil mekanizmaya bağlıdır. `scripts/sdd.sh` fazı tutar (`intake → proposed → red → green → verified → pr → done`),
her geçişin kapısını **kendisi** denetler, hook'lar da durumu okuyup uygunsuz adımı engeller.

F03 ([design-workflow.md](design-workflow.md)): `sdd.sh start --profile small|standard|high-assurance` süreç ağırlığını seçer (varsayılan `standard` = aşağıdaki akış, değişmedi; profil riski ve kapıları düşürmez); `sdd.sh transitions` geçerli geçişleri ve girişlerini, `sdd.sh policy` görevin gerçek kurallarını yazar; reddedilen geçiş durumu değiştirmez ve telemetride `reason` taşır.

| Geçiş / adım | Kapı |
|---|---|
| `start` | Kullanıcının onayladığı risk etiketi ve proposal yolu verilmeden görev açılmaz |
| `advance proposed` | `proposal.md`'de maddeli bir "Definition of Done" yoksa (high: `design.md`'de yarış/sıralama/zamanlama bölümü yoksa) reddeder |
| `advance red` | `--test-cmd` çalıştırılır ve **başarısız** olmalıdır; geçen test kanıt sayılmaz |
| `advance green` | Aynı komut bu kez **geçmeli** |
| `advance green` / `verified` | `RISK_FLOOR_GLOBS` doluysa görevin riski, diff'in dokunduğu dosyaların tabanından düşük olamaz (strict reddeder, guided uyarır) |
| `advance verified` | low: verify komutu geçmeli. medium/high: **mevcut diff** için verifier'dan `PASS` kaydı gerekir |
| `git push`, `gh pr create`, `glab mr create`, `open-pr.sh` | `verified` fazı ve değişmemiş diff olmadan hook reddeder |

Karar tek yerde, `sdd.sh gate`'te verilir; Claude hook'ları, Cursor/Gemini/OpenCode adaptörleri ve git `pre-commit`/`pre-push` aynısını sorar, yani kural her host'ta aynıdır. Hook'lar: `guard-phase` (görev yokken ve `intake`'te yalnızca doküman/spec/`.claude/`; `proposed`'da yalnızca test dosyaları),
`guard-pr` (push/PR kapısı, durum dosyasına elle dokunmayı reddeder), `record-verdict` (verifier bitince `VERDICT` satırını o anki diff
parmak iziyle kaydeder; uygulayan oturumun beyanı sayılmaz, sonradan yapılan her düzenleme kararı eskitir).

`SDD_MODE` (`sdkit.env`): `strict` reddeder (**varsayılan**, boşsa da strict), `guided` hook'ta sorar / git hook'ta uyarır, `off` kapatır. Test dosyası kalıpları `SDD_TEST_GLOBS`,
her zaman serbest yollar `SDD_FREE_GLOBS` ile değişir. Doğrulama: `tests/sdd.test.sh`.

**Sunucu tarafı kapı (CI).** Faz durumu git-ignored olduğu için CI onu göremez. `advance verified` bu yüzden `<proje-klasörü>/attestations/<görev>.json`
yazar (görev, risk, verdict, değişen dosyaların parmak izi, kit sürümü); bunu değişiklikle **commit'lersin**. CI'da `sdd.sh ci-check` çalışır:
kod değişikliği içeren her diff için o diff'e ait bir kanıt ister, medium/high için verifier `PASS` şart koşar; yalnızca doküman/spec/proje dosyası
değişiyorsa kanıt aramaz. Doğrulamadan sonra bir dosya değişirse parmak izi tutmaz, yeniden doğrulayıp kanıtı yenilersin. Parmak izi PR'ın
hedef dalından ayrıldığı noktaya göre hesaplanır, hedef dal ilerlese de değişmez. Şablonlar: `templates/ci/` (`init.sh --ci bitbucket|github`).
Sınır: kanıt dosyası repoya yazma yetkisi olan biri tarafından üretilebilir; yani kuralı atlamayı zorlaştırır, kötü niyeti engellemez. Güvenmek için
`attestations/` yolunu CODEOWNERS / zorunlu code review ile koru.

**Makine kurulumu ve kayma.** Repoda kit script'leri yoksa (ör. Claude plugin modu) git hook'ları makineye kayıtlı kiti kullanır: `<kit>/bin/install.sh`
(`--status`, `--uninstall`). Repodaki yönetilen kopyaların kit ile uyumu `sync.sh --check` ile (dosya değiştirmez, kayma varsa çıkış 1) CI'da
denetlenebilir; `doctor.sh` aynı kontrolü, sürüm farkını, makine kaydını ve CI kapısının varlığını raporlar.

`parse-verdict.sh` verdict için **tek doğrulayıcıdır**; Claude'da `record-verdict` hook'u verifier bitince onu `--record` ile çağırır (biçimi bozuk veya kendiyle çelişen blok kaydedilmez, orkestratöre bildirilir; elle `--record` orada `guard-pr` ile reddedilir). SubagentStop olmayan host'larda orkestratör `parse-verdict.sh --record` çalıştırır (`guard-pr` adaptörlerde `SDKIT_HOST` ile buna izin verir). Tek seferlik atlama: `SDD_SKIP=1` (git hook).

Sınır: hook'lar kararlı bir saldırgana karşı değil, yanlış yola sapmaya karşıdır (örneğin `Bash` ile dosya yazmayı
tam kapatmaz). Claude dışı araçlar ve doğrudan `git push` git hook'larıyla kapsanır; git hook'u `--no-verify` ile atlanabilir, bu yüzden atlanamayan katman CI'dır (aşağıda).

## 5. Skill'ler

| Skill | Ne zaman | Ne yapar |
|---|---|---|
| `spec-driven-dev` | Her yeni görevde | Yukarıdaki akış (analist, plan kapısı, rollerle uygulama, doğrulama) |
| `incident-to-rule` | Bir hata çözüldükten sonra | Olayı kalıcı bir korumaya çevirir (aşağıda) |
| `scaffold-init` | Yeni repo kurarken, **bir kez** | Hangi host'lar (Claude/Codex/OpenCode/Cursor/Gemini) diye sorar, `init.sh --host ...` çalıştırır, `openspec init`'i başlatır, `project.md`'yi doldurmada yardım eder, sonunda doctor çalıştırır |
| `scaffold-doctor` | Kurulum sonrası veya bir şey çalışmıyormuşsa | `doctor.sh` çalıştırır, her `FAIL` için neyi nerede değiştireceğini söyler |

### incident-to-rule
Düzeltilen bir hatanın aynı sınıfından tekrar oluşmasını engellemek için, **en güçlü uygun koruma** seçilir (ilk uyan kazanır):

1. **Lint kuralı**: bir linter yakalayabiliyorsa `LINT_CONFIG`'e ekle
2. **Verify politikası**: grep/diff örüntüsüyle yakalanabiliyorsa `<project-dir>/verify.d/` altına çalıştırılabilir dosya ekle
3. **Regresyon testi**: bir test hatada kırılabiliyorsa
4. **Hook**: bir araç çağrısı olmadan önce engellenmeli/onaylanmalıysa projeye hook ekle
5. **Pitfall kaydı**: yukarıdakiler mümkün değilse `known-pitfalls.md`'ye (belirti, kök neden, olay, "diff'te nasıl görülür")

Önce hatayı **genel mekanizma** olarak tarif etmek zorundadır (belirti, kök neden, diff'teki izi). Mekanik koruma, düzyazıdan tercih edilir.
Koruma, orijinal hatayı yeniden üreten bir diff'te önce **kırılıp**, düzeltmede **geçerek** doğrulanır. Tasarım kararı gerekiyorsa ADR eklenir.

---

## 6. Roller

Roller `core/roles/*.md` altında **araçtan bağımsız** tanımlanır (alanlar: `kind`, `access`, `tier`, `independent`). `bin/build-adapters.sh` bunlardan her host'un rol dosyalarını üretir (Claude `agents/`; `adapters/{codex,opencode,cursor,gemini}/`; host başına 10 dosya: 9 subagent rolü + `verifier-deep`); üretilen dosyaları elle düzenleme, kaynağı düzenle ve betiği çalıştır (`--check` güncel mi diye bakar).
Subagent rolleri ana oturumdan **ayrı bağlamda** çalışır; konuşma geçmişini görmez, yalnızca devir özetini (`handoff.md`) ve repodaki dosyaları.

| Rol | Erişim | Katman | Bağımsız | Görevi |
|---|---|---|---|---|
| `orchestrator` | oturum | strong | | Akışı yürütür, işi böler, planı ve özeti sahiplenir (ana oturum, subagent değil) |
| `analyst` | salt okunur | standard | | Görev isteminin eksiksizliğine karar verir; boşluk, varsayım, soru listeler |
| `scout` | salt okunur | **light** | | Ucuz kod arama: nerede tanımlı, kim çağırıyor; en fazla 15 satır cevap |
| `engineer` | yalnızca tasarım dosyaları | strong | | Tasarım, seçenekler ve ödünleşimler, ADR, yarış senaryosu, test stratejisi, görev bölünmesi (`writes:`/`after:`) |
| `developer` | kod | standard | | Anlaşılan tasarım ve testlere göre gerçekleştirir; "doğrulandı" demez, testi zayıflatmaz |
| `test-writer` | yalnızca test | standard | | Test yazar, üretim koduna dokunmaz |
| `devsecops` | altyapı/pipeline | standard | | CI/CD, container, IaC, bağımlılık ve secret hijyeni, en az yetki; prod'a dokunmaz, yalnızca dry-run/plan |
| `reviewer` | salt okunur | standard | evet | Diff'i kural ve pitfall'lara göre inceler |
| `security-auditor` | salt okunur | standard | evet | Saldırı odaklı inceleme (yetkilendirme, enjeksiyon, sızıntı, pipeline yetkileri) |
| `verifier` | salt okunur | standard | evet | Bağımsız DoD kapısı (`medium`) |
| `verifier-deep` | salt okunur | strong | evet | `verifier` ile aynı gövde (kaynakta `deep: strong`), `high` riskte kullanılır; ayrı dosya olarak üretilir |

**Katman = maliyet sınıfı.** Roller model adı değil katman (`light`/`standard`/`strong`) bildirir; karşılığı `core/tiers.env`'de (Claude: haiku/sonnet/opus takma adları;
Codex: `model_reasoning_effort`; OpenCode/Cursor/Gemini: `*_MODEL_<KATMAN>`; modeller boşsa oturumdan miras). Böylece model değişince tek yer güncellenir.

**Görev başına boyut.** Rolün sabit katmanı varsayılandır; `tasks.md`'de görevin isteğe bağlı `size: small|medium|large` alanı varsa katman ona göre seçilir
(small → light, medium → standard, large → strong). `size:` yoksa rolün kendi katmanı geçerlidir (eski davranış). Alt sınır: bağımsız roller
(`verifier`, `reviewer`, `security-auditor`) kendi katmanlarının altına inmez, yalnızca yukarı çıkabilir; `high` risk doğrulaması her zaman strong'dur (`verifier-deep`).
Boyut ölçütleri (dokunulan dosya sayısı, mekanik mi yeni mantık mı, risk, açık tasarım kararı, yarış/sıralama) `skills/spec-driven-dev/references/model-routing.md`'dedir;
orkestratör boyutları planda (bölüm 5) gösterir, kullanıcı plan onayında değiştirebilir. Seçilen katman devir özetindeki `TIER:` alanıyla gider.
Claude Code'da orkestratör her `Agent` çağrısında `model` parametresini `CLAUDE_MODEL_<KATMAN>`'dan verir; diğer host'larda rol dosyasındaki model sabit olduğundan,
görev başına farklı model gerektiren rol `run-role.sh --tier` ile ayrı süreç olarak çalışır.

**Bağımsızlık kuralı:** gerçekleştiren rol (`developer`, `devsecops`) asla doğrulayan rol olmaz; bağımsız roller (`verifier`, `reviewer`, `security-auditor`)
gerçekleştiricinin gerekçesini değil yalnızca artifact'ları alır.

**Roller başka rolü çağırmaz.** Bir arama cevaplanamıyorsa rol çıktısını `NEEDS-LOOKUP: <soru>` satırlarıyla bitirir (şu an `analyst` ve `engineer`); orchestrator `scout`'u bir kez çalıştırır ve cevabı yol olarak geri verir.

**Salt okunur roller zorlanır** (yalnız talimatla değil), host'a göre:

| Host | Mekanizma |
|---|---|
| Claude Code | `hooks/guard-readonly.sh` (PreToolUse `Bash\|Edit\|Write\|NotebookEdit`): hook girdisindeki `agent_type`'tan rolü bulur, agent dosyasında `Edit`/`Write` aracı yoksa dosya yazan araçları ve değiştirici shell komutlarını (`>` yönlendirmesi, `rm`, `sed -i`, `git commit/checkout/...`, bağımlılık kurulumu) reddeder. `agent_type` yoksa (ana oturum, eski sürüm) sessizce kapalıdır |
| OpenCode | Üretilen rol dosyasında `permission:` izin listesi (`edit: deny`, shell için `"*": deny` + `READONLY_SHELL_ALLOW` allow-list'i) |
| Cursor | Rol dosyasında `readonly: true` |
| Gemini | Rol dosyasında `tools:` listesi (yazma araçları yok) |
| Codex | Rol TOML'unda `sandbox_mode = "read-only"` (not: bazı build önbelleklerini de engelleyebilir) |

**`analyst` çıktısı:**
```
READINESS: READY|NEEDS-INFO
BRIEF  (başlık, test edilebilir kriterler, bileşenler, önerilen risk)
GAPS   - <eksik> | <neden önemli> | <soru> | <önerilen varsayılan>
ASSUMPTIONS - <varsayım> | <yanlışsa ne bozulur>
```

**`verifier` çıktısı** (format kesindir):
```
DOD
- <madde> | PASS|FAIL | <kanıt>
FINDINGS
- CONFIRMED|PLAUSIBLE | <dosya:satır> | <sorun> | <başarısızlık senaryosu>
VERIFY
- command: <çalıştırılan> | result: green|red | <özet>
VERDICT: PASS|BLOCK
```
Kanıtsız madde `FAIL`'dir; bildirilen test yoksa veya maddeyi sınamıyorsa `FAIL`. `CONFIRMED` yalnızca tam satır gösterilebiliyorsa. `<project-dir>/.frozen`'daki bir dosya diff'te
değişmişse bu `CONFIRMED` iş akışı ihlalidir.

**`reviewer`:** `BLOCKER|MAJOR|MINOR | dosya:satır | kural | sorun | öneri`; linter'ın yakaladığı stil nitlerini raporlamaz.
**`security-auditor`:** yetkilendirme, kimlik doğrulama, enjeksiyon, gizli bilgi, girdi sınırları, hata sızıntısı, pipeline yetkileri; bulgu yoksa `NO FINDINGS` ve neleri kontrol ettiği.
**`test-writer`:** DoD maddelerini önce, sonra hata yolları/doğrulama/mutlu yol/kenar durumlar; `TestSubject_Condition_ExpectedResult`; `errors.Is`.

---

## 7. Hook'lar ve guard'lar

Hook'lar Claude'un araç çağrıları sırasında otomatik çalışır ve model onları atlayamaz. Üç tür sonuç verebilirler:

| Karar | Anlamı |
|---|---|
| **deny** | Çağrı yapılmaz, model nedenini görür |
| **ask** | Çağrı kullanıcı onayına sunulur |
| **block** (Stop) | Oturum "bitti" diyemez, model düzeltmeye devam eder |

Hook'lar aslen **Claude Code'a özgüdür**. Gemini ve Cursor aynı hook script'lerini `hooks/adapt.sh` kabuğuyla, OpenCode bir JS eklentisiyle çağırır (aşağıda); yine de Stop-verify ve SessionStart gibi olaylar o host'larda yoktur. Her yerde yedek olarak git hook'ları (commit/push anı) vardır (bölüm 16). Hook kararları `settings.json`'daki `allow` kurallarından **üstündür**: `git checkout` izinli olsa bile `guard-git` yanlış dal kaynağını reddeder.

| Hook | Olay / eşleşme | Karar | Ne yapar | Ayar | Ne zaman kapalı |
|---|---|---|---|---|---|
| `session-context.sh` | SessionStart | bilgi | Oturum başında branch, ticket (branch adındaki `ABC-123`), eşleşen OpenSpec change'i, aktif release ve durumu (açık/dondurulmuş) söyler | `BASE_BRANCH_MODE` | Hiç kapanmaz; release bilgisi yalnızca release modunda |
| `check-tools.sh` | SessionStart | bilgi | Eksik araçları kurulum komutuyla bildirir: `jq`, `git`, (`openspec/` varsa) `openspec` ve stack'in `tools.sh` listesi | `STACK` | Eksik araç yoksa sessiz |
| `guard-secrets.sh` | PreToolUse: Read, Edit, Write | **deny** | `SECRET_GLOBS` ile eşleşen dosyayı okumayı/yazmayı reddeder | `SECRET_GLOBS` | `SECRET_GLOBS` boşsa |
| `guard-protected.sh` | PreToolUse: Edit, Write | **ask** | `PROTECTED_PATHS` altındaki bir dosyayı değiştirmeden önce onay ister | `PROTECTED_PATHS` | Boşsa |
| `frozen-tests.sh` | PreToolUse: Edit, Write | **deny** | `<project-dir>/.frozen` listesindeki test dosyalarının değiştirilmesini engeller | `<project-dir>/.frozen` | Dosya yoksa |
| `guard-prod.sh` | PreToolUse: Bash | **ask** | Prod cluster'a karşı **değiştirici** `kubectl` komutlarında onay ister | `PROD_KUBE_CLUSTERS` | Boşsa |
| `guard-git.sh` | PreToolUse: Bash | **deny** / **ask** | Release akışı kurallarını zorlar (aşağıda) | `BASE_BRANCH_MODE=release` | Release modu yoksa |
| `guard-readonly.sh` | PreToolUse: Bash, Edit, Write, NotebookEdit | **deny** | Salt okunur bir rolün (reviewer, verifier ...) dosya değiştirmesini engeller (bölüm 6) | `agent_type` (hook girdisi) | `agent_type` yoksa |
| `post-edit-fmt.sh` | PostToolUse: Edit, Write | yok | Yazılan dosyayı stack'in `fmt.sh`'ı ile biçimlendirir (Go: `gofmt`) | `STACK` | Formatlayıcı kurulu değilse no-op |
| `stop-verify.sh` | Stop | **block** | Commit'siz değişiklikler stack'in hızlı kontrolünde (`--fast`) kırıksa "bitti" demeyi engeller | `VERIFY_CMD` | Verify betiği bulunamazsa |
| `value-report.sh` | SessionEnd, SessionStart | yok | Value Report oturum düzeyi (`scripts/report.sh`): `SessionEnd`'te oturumu bitmiş işaretler ve özetini saklar; `SessionStart`'ta bitiş sinyali almadan kesilmiş eski oturumları `interrupted` olarak kurtarır. Stdout'a yazmaz, engellemez. `VALUE_REPORT` ≠ `on` ise sessiz. Ayrıntı [design-report.md](design-report.md) |
| `usage-log.sh` | Stop, SubagentStop | yok | Transkriptten token kullanımını `usage.sh` defterine, `TELEMETRY=1` ile ayrıca `agent.end` olayı olarak (token, araç çağrısı sayısı, tahmini süre) yazar (bölüm 18) | `USAGE_LOG=1` veya `TELEMETRY=1` | ikisi de 1 değilse |
| `guard-budget.sh` | PreToolUse: Agent | **ask** (strict) / uyarı (guided) | Her subagent açılışını sayar (`state.sh spawn`) ve görev token bütçesini denetler (`usage.sh budget`); sınır aşılınca sorar (bölüm 18) | `MAX_SPAWNS`, `TOKEN_BUDGET_TASK` | İkisi de boşsa, `SDD_MODE=off`, aktif görev yoksa |
| `result-size.sh` | SubagentStop | yok | Rolün son cevabı `SUBAGENT_RESULT_MAX_LINES` satırdan uzunsa uyarır (engellemez) | `SUBAGENT_RESULT_MAX_LINES` | Boşsa |
| `check-contract.sh` | PreToolUse: Agent; SubagentStop | **ask** (strict, yalnızca geçersiz devirde) / uyarı | `CONTRACT:` satırı taşıyan devri doğrulayıp kaydeder; alt ajanın son cevabındaki `HANDOFF-RESULT` satırını denetler. Verdict'e ve faza dokunmaz | `CONTRACTS=1` | Boşsa ya da devirde `CONTRACT:` yoksa |

### Ayrıntılar

**guard-secrets**: Dosya adına (basename) veya tam yola glob uygular. Varsayılan: `.env*`, `*credentials*`, `*.pem`.
Yalnızca **dosya araçlarını** kapsar; `cat .env` gibi bir Bash komutunu görmez. O yüzden `settings.json`'daki `deny` listesi de aynı dosyaları `Read` için yasaklar (bkz. bölüm 12).

**guard-protected**: Yolu proje köküne göre kıyaslar; `PROTECTED_PATHS`'teki bir önekle başlıyorsa onay ister. Mesaj `project.md`'ye yönlendirir
(örneğin "yalnızca şu koşulda değiştirilebilir").

**frozen-tests**: `spec-driven-dev` yüksek riskte **[A]** rolü test dosyasını (repoya göre yol, satır başına bir tane) `<project-dir>/.frozen`'a ekler.
Uygulayıcı bu testi "düzeltmek" yerine kodu düzeltmek zorunda kalır. Görev bitince/bırakılınca dosya silinir. Dosya kişiseldir, git'e girmez.

**guard-prod**: "Değiştirici" komutlar: `apply, delete, rollout, scale, patch, edit, replace, create, run, set, annotate, label, exec, cp, drain,
cordon, taint`. `get/describe/logs` serbesttir. Hedef context, komuttaki `--context` veya aktif context'tir; context'in **gösterdiği cluster**
adı `PROD_KUBE_CLUSTERS` önekleriyle eşleşirse sorar. Cluster adına baktığı için aynı prod'u gösteren tüm context takma adları kapsanır.

**guard-git** (yalnızca `BASE_BRANCH_MODE=release`):
1. Feature branch'teyken `git merge|pull|rebase` ile **ana branch'i** (`develop`) içeri almayı **reddeder**. Sebep: henüz test'ten geçmemiş işler release paketine sızar.
2. Ana branch'ten (veya ana branch'teyken başlangıç noktası vermeden) `git checkout -b` / `git switch -c` ile yeni dal açmayı **reddeder**; aktif release branch'ini önerir.
3. `PROTECTED_BRANCHES`'teki bir env branch'ine doğrudan `git push` için **onay** ister.
Düzenli ifade tabanlıdır; alışılmadık sözdizimi (alias, betik içinden çağrı) kaçabilir.

**guard-readonly**: Komutu `&&`, `||`, `;`, `|` ile bölüp her parçayı denetler; `/dev/null` dışı çıktı yönlendirmesini, `rm/mv/cp/mkdir/touch/tee`, yerinde `sed -i`, repoyu değiştiren `git` komutlarını ve `npm install` gibi kurulumları reddeder. Okuma komutları (`git diff/log/show`, `ls`, `cat`, `grep`, verify, test) serbesttir. Düzenli ifade tabanlıdır: sıkı bir sınır değil, hata önleyicidir.

**usage-log**: Hiçbir zaman engellemez; transkript yoksa veya biçim beklenmedikse sessizce çıkar. Ayrıntı bölüm 18.
(0.5.0'a kadar `hooks.json` ve `settings.copy.json` içinde `SubagentStop` anahtarı iki kez tanımlıydı; JSON'da son tanım kazandığı için alt agent kullanımı hiç yazılmıyordu. Artık tek dizide `record-verdict`, `usage-log`, `result-size` var; `tests/budget.test.sh` anahtarın tekrarlanmadığını denetler.)

**guard-budget**: Yalnızca `MAX_SPAWNS` veya `TOKEN_BUDGET_TASK` doluysa çalışır. En son güncellenen `work/<slug>/state.json` aktif görev sayılır; yoksa sessizdir. Sınır aşıldıysa `strict` modda kullanıcıya sorar, `guided` modda yalnızca uyarı mesajı verir, `off` modda hiçbir şey yapmaz. Eşik altı uyarıda (`TOKEN_BUDGET_WARN_PCT`) izin kararı vermez, yalnızca mesaj yazar; bu yüzden normal izin akışını değiştirmez. Reddedilen bir açılış da sayılır. Kendi hatasında asla engellemez.

**result-size**: Cevabı `last_assistant_message` alanından, yoksa alt agent transkriptinden alır. Yalnızca uyarır; çıktının dosyaya yazılması rol metinleri ve devir özeti (`OUT:`) ile istenir.

**check-contract**: Ajan sözleşmeleri (F02, [design-contracts.md](design-contracts.md)). PreToolUse'ta `tool_input.prompt` içinde `CONTRACT:` satırı arar (yoksa eski devirdir, sessiz çıkar); varsa `contract.sh issue` ile doğrular ve `work/<görev>/contracts/` altına kaydeder. Geçersizse `strict`'te sorar, `guided`'da uyarır, `off`'ta susar. SubagentStop'ta son mesajı (yoksa transkriptin son metnini) `check-result --record --legacy-ok` ile denetler; geçersizse orkestratöre bir kez `systemMessage` verir. **Hiçbir zaman engellemez, verdict'i kaydetmez, fazı değiştirmez**: bağımsız doğrulama yine `record-verdict` + `parse-verdict` + `sdd.sh` yolundadır. Canlı Claude Code'da koşturulmadı; Cursor/Gemini/OpenCode/Codex için hook yoktur (`run-role.sh` ya da elle `contract.sh`).

**`adapt.sh <gemini|cursor> <hook>`**: Host'un araç çağrısı JSON'unu (Gemini `read_file/write_file/replace/run_shell_command`, Cursor `beforeShellExecution/beforeReadFile/afterFileEdit/preToolUse`) hook'ların okuduğu Claude biçimine çevirir, hook'u değiştirmeden çalıştırır, `permissionDecision`'ı host'un protokolüne geri çevirir: Gemini deny = çıkış 2 + stderr; Cursor `{"permission":"deny"}`. `ask` desteklemeyen host'ta `ask`, "açık onay gerekir" gerekçeli `deny`'a düşer (Cursor shell'de `ask` desteklenir). OpenCode için `.opencode/plugins/spec-driven-kit-guard.js` aynı hook script'lerini çağırır.

**stop-verify**: Doğrulama motorunu `--fast --since-head` ile çalıştırır, yani yalnızca **commit'siz** değişiklikleri vet+build eder. Başarısızsa son 30
satırı modele geri verir ve düzeltmesini ister. `stop_hook_active` kontrolü sayesinde kendi engellemesinden doğan ikinci Stop'ta tekrar engellemez
(sonsuz döngü yok). Zaman aşımı 180 sn.

---

## 8. Doğrulama motoru ve `verify.d`

Motor iki parçadır: ortak **çekirdek** `scripts/verify-core.sh` ve her stack'in kendi adımları `stacks/<stack>/scripts/steps.sh`. Giriş noktası `stacks/<stack>/scripts/verify.sh` ince bir sarmaldır (çekirdeği bulur, `steps.sh`'ı yükler, `verify_main` çağırır). Hook'lar, skill'ler ve `make verify` hep bunu çağırır.

```
verify.sh [--fast] [--since-head] [--no-cache]
  --fast         yalnızca ucuz kontroller (stack'e göre: vet+build, typecheck, derleme; test ve lint yok)
  --since-head   yalnızca commit'siz değişiklikler (Stop hook'u bunu kullanır), tüm branch değil
  --no-cache     yeşil-sonuç önbelleğini yok say
```

### Çekirdek ne yapar (sırayla)
1. **Diff tabanını** bulur (`resolve-base.sh`; release akışında aktif release branch'i, yoksa `origin/BASE_BRANCH`).
2. Değişen dosyaları toplar: commit'li, staged, staged olmayan ve **takip edilmeyen** dosyalar; stack'in `STACK_SOURCE_RE`'sine uyanları `CHANGED_SRC` yapar. Değişiklik yoksa "nothing changed" ile 0 çıkar.
3. **Önbellek:** anahtar = tam ağaç durumu (HEAD + diff + takip edilmeyen dosya içeriği + bayraklar + `sdkit.env` + `verify.d` politikaları). Aynı anahtar daha önce **yeşil** bittiyse çıktısı tekrarlanır ("cached"). Başarısızlık asla önbelleğe alınmaz. `<project-dir>/.verify-cache/` altında son 20 girdi tutulur.
4. `stack_run`: stack'in kontrolleri (aşağıda).
5. **Proje politikalarını** (`<project-dir>/verify.d/*.sh`) çalıştırır.
6. Özet satırı: `verify: N failure(s), M warning(s)`. Çıkış kodu 0 yalnızca hata yoksa.

### Stack'ler
| Stack | Algılama | Kontroller (özet) |
|---|---|---|
| `go` | `go.mod` | değişen **go.mod modüllerinde** `gofmt`, `go vet`, `go build`; `--fast` değilse `go test ./...` ve `golangci-lint --new-from-rev` (yalnız yeni kod). `SHARED_MODULE` değişirse `DEPENDENT_MODULES_GLOB` modülleri de eklenir; `INTEGRATION_MODULE_GLOB` modülleri vet/build edilir, çalıştırılmaz |
| `spring-boot` | Maven/Gradle dosyasında Spring Boot | modül başına derleme, `--fast` değilse test ve (yapılandırılmışsa) spotless/checkstyle; wrapper (`./mvnw`, `./gradlew`) önce denenir, `JAVA_BUILD_TOOL` ile zorlanır |
| `jvm` | Spring olmayan Maven/Gradle dosyası (Java/Kotlin) | `spring-boot` ile aynı motor: modül başına derleme, `--fast` değilse test ve (yapılandırılmışsa) spotless/checkstyle; formatlama `google-java-format` / `ktlint` |
| `python` | `pyproject.toml`, `setup.py`, `setup.cfg` veya `requirements.txt` | paket başına sözdizimi (`py_compile`); `--fast` değilse `ruff`, yapılandırılmışsa `mypy`, `pytest` (yoksa `unittest`). `uv.lock`/`poetry.lock` varsa araçlar `uv run`/`poetry run` ile, `PY_RUNNER` ile zorlanır. Eksik araç uyarıdır, hata değil |
| `generic` | hiçbiri (yedek) | `sdkit.env`'deki `VERIFY_FAST_CMD` ve `VERIFY_TEST_CMD` repo kökünde çalışır; ikisi de boşsa yalnızca `verify.d` politikaları çalışır ve uyarı verilir |
| `nextjs` | `package.json`'da `next` | paket başına typecheck, `--fast` değilse lint ve test; `VERIFY_BUILD` doluysa `next build`; paket yöneticisi lockfile'dan veya `NODE_PM`'den |
| `react-native` | `package.json`'da `react-native` | typecheck/lint/test; `nextjs` ile `stacks/_node/scripts/node-lib.sh` yardımcısını paylaşır |

Her stack şunları sağlar: `detect.sh`, `scripts/{verify,steps,fmt,tools}.sh`, `permissions.txt`, `rules/`, `verify.d.example/`. Sözleşmenin tamamı `stacks/README.md`'de. Tek repoda **tek `STACK`** vardır; birden çok stack'li monorepo kapsam dışıdır.
Stack kuralı: yalnızca değişeni doğrula, `--fast` gerçekten ucuz olsun, eksik araç `warn` olsun (atlanır), az çıktı ver.

### verify.d protokolü
Projeye özel kontroller, `<project-dir>/verify.d/` içinde **çalıştırılabilir** (`chmod +x`) dosyalardır. Motor hepsini alfabetik sırayla çalıştırır.

- Bir satır `FAIL: <mesaj>` ise hata, `WARN: <mesaj>` ise uyarı sayılır.
- Hiç `FAIL:` satırı yazmayıp sıfır dışı kodla çıkan politika da hata sayılır.
- `_` ile başlayan dosyalar yardımcıdır, çalıştırılmaz.
- Motor şu değişkenleri verir: `VERIFY_ROOT`, `VERIFY_MERGE_BASE`, `VERIFY_CHANGED` (satır satır dosya listesi), `VERIFY_CHANGED_SRC` (Go'da ayrıca `VERIFY_CHANGED_GO`), ve
  `VERIFY_LIB` (yardımcı fonksiyon dosyası; içinde `added_lines <pathspec...>`: taban sonrası eklenen satırlar, takip edilmeyen dosyalar dahil).

Örnek (`stacks/<stack>/verify.d.example/`'dan, `init` bunları `.example` uzantısıyla kurar; kullanmak için uzantıyı sil):

```bash
#!/usr/bin/env bash
. "${VERIFY_LIB:?run this through the verify engine}"
added="$(added_lines '*.go' ':!*_test.go')"
echo "$added" | grep -nE 'log\.Printf|fmt\.Println' && echo "FAIL: debug printing added"
exit 0
```

`init` stack'e göre üç örnek getirir (Go: yasaklı örüntüler `10-`, `.up.sql`/`.down.sql` çifti `20-`, OpenAPI güncellemesi `30-`; diğer stack'lerde yasaklı örüntüler, migration/env/yerel değişiklik ve bağımlılık/OpenAPI örnekleri). Hepsi projenin dizin düzenine göre uyarlanmalıdır.

---

## 9. Yardımcı script'ler

### `scripts/resolve-base.sh`
Bir branch'in neye göre diff'leneceğini ve **hangi dalın üzerinden açılacağını** yazdırır.

| Durum | Çıktı |
|---|---|
| `BASE_BRANCH_MODE=release` | HEAD'in türediği **en yeni** `origin/<RELEASE_BRANCH_PREFIX>*` branch'i (çatallanma noktasından sonra en az commit'i olan; eşitlikte yeni olan) |
| release branch'i yok / mod kapalı | `origin/BASE_BRANCH` |
| `VERIFY_BASE` ortam değişkeni verilmiş | o değer (her şeyi ezer) |

`--frozen` bayrağı, o release için `freeze/<ad>` etiketi varsa `frozen`, yoksa `open` yazdırır.

### `scripts/open-pr.sh`
Mevcut branch için PR açar: `open-pr.sh "<başlık>" <açıklama-dosyası> [hedef-branch]`. Hedef verilmezse `BASE_BRANCH`.
Branch önce push edilmiş olmalı. `PR_HOST` yalnızca `bitbucket`'ı bilir; diğer değerler ağa çıkmadan kod 2 ile çıkar ([hosts.md](hosts.md)).
Kimlik: e-posta `BITBUCKET_EMAIL`, yoksa `git config user.email`; parola `origin` URL'sinden, yoksa `BITBUCKET_TOKEN`, yoksa `PR_TOKEN_REPO`
(başka bir yerel reponun URL'sinden). Parola hiçbir zaman yazdırılmaz.

### `scripts/guard.sh`
Araçtan bağımsız guard'lar; git hook'larından (`adapters/git/pre-commit`, `pre-push`) çağrılır. `pre-commit`: stage'li dosyalarda `SECRET_GLOBS` eşleşmesi, `<project-dir>/.frozen`
listesindeki testler (**reddeder**), `PROTECTED_PATHS` altı (reddeder; onayla sonra `ALLOW_PROTECTED=1`). `pre-push`: `PROTECTED_BRANCHES`'e push (reddeder; `ALLOW_PROTECTED_PUSH=1`)
ve `verify.sh --fast --since-head` kırmızıysa push'u reddeder (`GUARD_SKIP_VERIFY=1` bilerek atlatır). Claude hook'larındaki "ask" burada "reddet + onay bayrağı"dır; çünkü git hook'u soru soramaz.

### `scripts/plan-waves.sh <tasks.md>`
Görevleri bağımlılık (`after:`) ve yazma kümesine (`writes:`) göre **dalgalara** ayırır. Aynı dalgadaki görevler birbirinden bağımsızdır ve yazma yolları çakışmaz
(bir yol diğerine eşit veya onun üst dizini ise çakışır). Bilinmeyen id veya döngüde 1 ile çıkar. Görev biçimi bölüm 17'de.

### `scripts/worktree.sh add|path|merge|clean|list <görev-id>`
Paralel görevler için git worktree: `add` HEAD'den `../<repo>-wt/<id>` ve `wt/<branch>/<id>` dalını açar; `path` yolunu yazar (devir özetindeki `WORKTREE:` için); `merge <id> [tasks.md]` önce görevin değişikliklerini `writes:` kümesine karşı denetler (`check-writes.sh`; dışına çıkan görev birleştirilmez), sonra dalı `--no-ff` birleştirir (çakışmada iptal edip çıkar:
yazma kümeleri yanlıştı, plan düzeltilir); `clean` birleşmiş worktree'leri siler.

### `scripts/check-writes.sh <tasks.md> <görev-id> <base-ref> [head-ref]`
Görev `writes:` kümesinin dışında dosya değiştirdiyse 1 ile çıkar ve dosyaları listeler. `head-ref` verilirse commit'li değişiklikler, verilmezse çalışma ağacı + takip edilmeyen dosyalar denetlenir. `writes:`'sız görev salt okunurdur. 2: kullanım hatası veya bilinmeyen görev.

### `scripts/env.sh`
Çalıştırılmaz, kaynaklanır; her script ve hook kullanır. `sdkit_env_load <kök>` proje klasörünü bulur ve `sdkit.env` + `sdkit.local.env`'i **ayrıştırır** (kabuk olarak çalıştırmaz: `KEY=değer`, tırnaklı değer, `export`, `: "${K:=v}"`, `$AD`/`${AD}`; geri kalanı `dosya:satır` olarak bildirilip yok sayılır; `PATH`, `IFS`, `BASH_*` gibi anahtarlar reddedilir; geçiş notu `upgrading.md`). Ayrıca `sdkit_active_slug` (açık SDD görevi, yoksa en yeni `work/*/state.json`), `sdkit_lock`/`sdkit_unlock` (`mkdir` tabanlı kilit; paralel ajanlar durum ve defteri aynı anda yazar) ve varsayılan stack.

### `scripts/state.sh <slug> init|show|get|set|task|retry|path`
`<project-dir>/work/<slug>/state.json` görev durumu (devam etme için). `task <id> todo|doing|done|blocked`; `retry <id>` ilk seferde 0 çıkıp sayar, hak kullanılmışsa 1 çıkar (tek otomatik deneme kuralı). `jq` gerekir.

### `scripts/parse-verdict.sh <dosya|-> [--proposal proposal.md]`
Verifier çıktısını doğrular: `DOD / FINDINGS / VERIFY / VERDICT` sırası, her DoD satırı `PASS|FAIL`, her bulgu `CONFIRMED|PLAUSIBLE`, `VERDICT` kurala uyuyor mu (herhangi bir `FAIL` veya `CONFIRMED` ise `BLOCK`). `--proposal` ile verifier'ın, öneri dosyasındaki DoD kadar maddeyi yargıladığı da denetlenir. Çıkış: 0 PASS, 1 BLOCK, 2 bozuk/tutarsız. F08: önce yalnızca biçimi etkileyen kurallarla normalleştirilir (CRLF, `**` vurgu, `*`/`1.` madde işareti, küçük harfli `pass/fail/confirmed/plausible`, `**VERDICT:** **PASS**`); hiçbir şey çıkarsanmaz, eksik belirteç eksik kalır. Hata iletisi türünü söyler: `MALFORMED[format]` (şekil; bir kez yeniden sorulur) veya `MALFORMED[semantic]` (içerik kendiyle çelişiyor ya da kanıtsız: FAIL'li PASS, `PASS | manual`, `PASS | post-deploy`, `PASS | n/a`, boş kanıt, atlanan DoD maddesi; yargı asla düzeltilmez). `manual`/`post-deploy` bir PASS kanıtı değildir.

### `scripts/dod-check.sh <proposal.md>`
F08 erken DoD denetimi; pahalı bir rol çalışmadan önce, `D<n>: ... | Verified by: <yöntem>` satırlarını sınıflar: `automated`, `static`, `manual`, `post-deploy`, `none: <neden>`. Yöntemsiz madde, nedensiz `none`, yinelenen id, bilinmeyen yöntem → çıkış 1 (her sorun yazdırılır). `run-role.sh` açık bir öneri varken verifier'ı başlatmadan önce bunu çağırır (maliyet yok, `exit 2`). Çıkış: 0 ok, 1 sorun, 2 kullanım.

### `scripts/digest.sh output|envelope|stats`
F09 sınırlı görünümler. `output`: uzun komut çıktısı (varsayılan >60 satır) için ilk 10 satır + her hata satırı (FAIL/ERROR/panic/CONFIRMED…) + son 15 satır + tam metnin yolu. `envelope --role R --ref F`: bir rolün uzun cevabı için `ENVELOPE/1` (karar, DoD sayıları, FAIL/CONFIRMED/BLOCKER satırları aynen, kanıt yolu); kısa cevap (<1500 bayt) olduğu gibi basılır. Zarf bir **görünümdür, karar değil**: karar tam cevap üzerinde `parse-verdict.sh`'tir. `run-role.sh --envelope` / `RESULT_ENVELOPE=1` (varsayılan kapalı). Boyutlar `work/<slug>/context.jsonl`'a yazılır; `stats` özetler.

### `scripts/test-select.sh list|run`
F10 değişen dosya → odaklı test eşlemesi (`<project-dir>/test-map.conf` veya `tests/test-map.conf`: `ERE => komut ;; komut | ALL | NONE`, zorunlu `@all =>`, isteğe bağlı `@always =>`). Haritada olmayan yol veya paylaşılan modül tüm takımı seçer (tahmin yok). `run`: `pipefail` ile çalıştırır, komut başına süre, özet satırı; yalnız yeşil sonuç tam ağaç kimliğiyle önbelleğe alınır. T0–T3 politikası: Implementation Roadmap §3.

### `bench/costbase.sh capture|compare`
F11 model çağırmayan sabit-veri taban çizgisi (`bench/baselines/*.costbase.json`): biçim-yalnız verdict yeniden denemeleri (normalleştirme kapalı/açık), anlamsal hataların asla kabul edilmemesi, bağlam baytları, küçük yamada seçilen test sayısı. **Görev başına maliyet ÖLÇÜLMEDİ** (canlı koşu gerekir). `compare` farklı fikstür/harita varsa reddeder.

### `scripts/report.sh` (Value Report)
Görev ve oturum değer raporu: roller/modeller, token kategorileri, API-eşdeğeri maliyet, **gözlenen** optimizasyonlar ve tasarruf (kanıt hiyerarşisi, taban kaynağı, kapsam, güven, ölçülen/tahmin ayrımı; yetersiz kanıtta "N/A — insufficient baseline data"). Yeni defter yok: `usage.sh`, `telemetry.sh`, yönlendirme/bağlam/test-seçim kayıtlarını okur; LLM çağrısı yok. `sdkit report task|session|latest|history [--detailed|--json|--markdown]`, `regenerate`. Tam tasarım, formüller ve sınırlar: [design-report.md](design-report.md).

### Faz F12–F20 script'leri (kısa)
- `adapter.sh capabilities|usage|cancel|status|validate <host|ext:ad>`: yürütme adaptörü sözleşmesi, desteklenmeyen yetenek dürüstçe "unsupported" (çıkış 3). Ayrıntı: [design-adapters.md](design-adapters.md). `adapters.d/litellm.sh`: isteğe bağlı, metin-yalnız, varsayılan kapalı.
- `route.sh` + `ROUTE_COST_ENFORCE=hard`: sert maliyet politikası, rezervasyon, bilinmeyen = geçmez ([design-routing.md](design-routing.md) F14).
- `dispatch.sh claim|done|release|status`: isteğe bağlı (`PARALLEL=on`) idempotent paralel dağıtım; bağımlılık, yazma çakışması, `MAX_PARALLEL`.
- `knowledge.sh put|get|list|clear`: dosya içerik hash'ine bağlı görev notları; bağımsız roller reddedilir.
- `telemetry.sh trace`: görev → faz → rol → yürütme → istek izi, içerik yok ([design-telemetry.md](design-telemetry.md) F17).
- `recover.sh scan|apply`: yarım kalan kayıt işlerini güvenle ve idempotent kapatır; yeniden çalıştırmaz, BLOCK'a dokunmaz.
- `redact.sh`, `audit.sh log|show|verify|policy`: gizli bilgi filtresi, hash zincirli denetim izi, statik zorlama denetimi ([design-security.md](design-security.md)).
- `dod-check.sh accept|accepted|acceptances`: manual/post-deploy/none DoD maddesini yalnız bir kişi (`--by`, `--reason` zorunlu) kabul edebilir; madde metnine bağlıdır, metin değişirse geçersiz olur. `parse-verdict.sh` `accepted: <kim>` kanıtını yalnız kayıt varsa sayar; kanıt-belirteci ayrıştırması sezgisel süzgeçtir, kanıt değildir.
- `route.sh reservations`, `SDKIT_CHILD_RUN`: bayat rezervasyon süresi ve `run-role.sh` çocuk oturumu işareti (Stop hook'u aynı token'ı ikinci kez yazmaz; canlı doğrulanmadı).
- `pr-check.sh [--milestone]` + `bench/history.sh`: ucuz PR denetimi (T0+T1), kilometre taşında T3 ve fikstür regresyon geçmişi; `templates/ci/pr-check.yml` örnektir, kurulmaz.

### `scripts/check-plan-parity.sh <plan.md> <proposal.md> [tasks.md] [--loose]`
Plan ↔ öneri ↔ görevler eşitliğini deterministik denetler. DoD satırı `D<n>: <metin> | Verified by: <tür>`; varsayılan olarak id, metin ve Verified-by eşleşmeli (`--loose`: yalnız id ve Verified-by). `tasks.md` verilirse plandaki "Execution plan" görevleri `role/writes/after` açısından karşılaştırılır. Çıkış: 0 eşit, 1 fark (yazdırılır), 2 kullanım/DoD bulunamadı.

### `scripts/usage.sh log|report|budget [slug]`
Token defteri (bölüm 18). `budget [slug]` görevin kullandığı token'ı (`in + out + cache-write`; cache okumaları ucuz olduğu için sayılmaz) `TOKEN_BUDGET_TASK` ile kıyaslar: eşik (`TOKEN_BUDGET_WARN_PCT`, 70) altında çıkış 0, eşikte 3, %100'de 4; bütçe yoksa veya defter boşsa sessiz çıkış 0. `log --role R [--tier --host --model --in --out --cache-read --cache-write --slug --id]`; `USAGE_LOG=1` değilse sessiz no-op (`--force` ile aşılır). `report` rol ve katman başına toplamları, genel toplamı ve önbellek isabet oranını (`cache_read / (in + cache_read + cache_write)`) yazar.

### `scripts/telemetry.sh emit|summary|list|validate|archive|run-id`
Yapılandırılmış olay günlüğü (`work/<slug>/events.jsonl`) ve özeti; `TELEMETRY=1` ile açılır, kapalıyken sessiz no-op'tur. `emit` hiçbir koşulda hata vermez. `summary` bir koşunun durumunu, faz ve ajan sürelerini, token'ı (ölçülen/toplam koşu, kalite etiketiyle), fiyat tablosu varsa tahmini maliyeti, yeniden deneme/hata sayısını ve doğrulama sonuçlarını verir (`--json` makine okunur). Şema, metrik tablosu ve sınırlar: [design-telemetry.md](design-telemetry.md). Benchmark: `bench/run.sh`.

### `scripts/contract.sh issue|check-result|close|pending|status|id`
Ajan sözleşmeleri (F02, [design-contracts.md](design-contracts.md)): devir (`CONTRACT: 1`, `ID: <görev>/<etiket>`, mevcut `ROLE/READ/SCOPE/OUT` satırları) ve ajanın son satırı `HANDOFF-RESULT/1 | id | role | status | artifacts | blockers | next` deterministik doğrulanır; model çağrısı yok. Kategoriler: `no-result malformed unsupported-version missing-field bad-value inconsistent id-mismatch role-mismatch task-mismatch unknown-id duplicate stale unsafe-path missing-artifact out-of-scope`. Çıkış: 0 geçerli ve `done`, 1 geçerli ama `partial|blocked|failed`, 2 geçersiz; **0 doğrulandı demek değildir** (verdict ve faz `parse-verdict.sh` / `sdd.sh`'ta kalır). `--record` kabulü `work/<görev>/contracts/<etiket>.json`'a yazar (ilk geçerli cevap kazanır, sonrası `duplicate`). `RETRY-OF:` eski kimliği `superseded` yapar. `TELEMETRY=1` ile `contract.check` olayı yazar.

### `scripts/workflow.sh policy|contracts|require|gate|announce|profiles`
İş akışı profilleri ve ajan sözleşmesi politikası (F03, [design-workflow.md](design-workflow.md)). Yalnızca **okur**: görevin `.sdd/state.json`'ından profil ve riski, ayarlardan `CONTRACTS`'ı alır; fazı `sdd.sh`, sözleşmeyi `contract.sh` yönetmeye devam eder. `policy [--json]` görev için geçerli kuralları yazar (profil, doğrulayıcı, sözleşme düzeyi); `contracts --role R` `off|optional|required` yazar; `require` zorunlu sözleşmesi olan bir devirde işaret yoksa 1 ile çıkar (hook ve `run-role.sh` çağırır); `gate green|verified` high-assurance'ta cevapsız/yarım kalmış ajan varsa 1 ile çıkar (`sdd.sh` çağırır). Profiller: `small` (yalnızca low risk, sözleşme yükü yok), `standard` (varsayılan, bugünkü akış), `high-assurance` (her riskte bağımsız doğrulayıcı PASS + yazan/karar veren roller için zorunlu sözleşme). Profil riski ve kapıları asla düşürmez; `sdd.sh start --profile` ile seçilir, görev boyunca sabittir.

### `scripts/memory.sh status|init|add|index|search|stale|autoload|candidates|promote`
Proje belleği (bölüm 19). `MEMORY=1` değilse hepsi sessiz no-op'tur.

### `scripts/lookup-cache.sh get|put|clear <slug> [soru]`
Scout cevaplarını görev boyunca saklar (`work/<slug>/lookups/`). Cevap yalnızca aynı HEAD ve aynı commit'siz diff için geçerlidir; kod değişince düşer. Soru küçük harfe çevrilip boşlukları sadeleştirilir, böylece yeniden ifade edilen aynı soru isabet eder. `get` isabette cevabı yazar ve 0, ıskada 1 döner.

### `scripts/run-role.sh <rol> --handoff F [--cwd D] [--host H] [--tier T] [--model M] [--out F] [--ignore-budget] [--dry-run]`
`MAX_SPAWNS` / `TOKEN_BUDGET_TASK` doluysa (ve `SDD_MODE` `off` değilse) çalıştırmadan önce açılışı sayar ve bütçeyi denetler; sınırda `strict` modda çıkış 3 ile durur (kullanıcı onayından sonra `--ignore-budget`), `guided` modda uyarıp devam eder. Bir rolü **ayrı başsız süreç** olarak çalıştırır: taze bağlam (yalnızca devir özeti), `--cwd` ile bir dizine (görev worktree'si) sabit, salt okunur rollerde host'un salt okunur kipinde. Rol metni `core/roles/<rol>.md`'den veya `<project-dir>/roles/`'tan gelir; `verifier-deep` strong katman modeliyle koşar. Host sırası: `--host`, bağımsız roller için `VERIFIER_HOST`, sonra `RUN_ROLE_HOST`; model: `--model`, sonra `RUN_ROLE_MODEL_<KATMAN>`; `--tier light|standard|strong` (`small|medium|large` da olur) verilirse katman rolün katmanının yerine geçer (bağımsız rollerde alt sınır: rolün kendi katmanı) ve model ayrıca `core/tiers.env`'deki `<HOST>_MODEL_<KATMAN>`'dan çözülür; Codex'te model yerine `model_reasoning_effort` (`CODEX_EFFORT_<KATMAN>`) değişir. `--tier` yoksa eski davranış aynen sürer. `VERIFIER_HOST` ile verifier başka bir sağlayıcıda koşabilir (gerçek bağımsızlık). CLI yoksa 127. Token kullanımını host'un yazdığı yerde `usage.sh`'a kaydeder. **Bayrak yazımları CLI başına canlı doğrulanmadı:** `--dry-run` ile komutu yazdır ve `<cli> --help` ile karşılaştır.

### `scripts/route.sh decide|explain|outcome|classify|registry|capabilities|validate|log`
Orkestrasyon kararları (F06, [design-routing.md](design-routing.md)): hangi adaptör ve model, hangi bütçeyle, çalıştır / yeniden kullan / yeniden dene / yükselt / dur. Saf kabuk+jq, model çağrısı yok; her karar bir neden kodu taşır.
`ROUTING=on` iken `run-role.sh` bu kararı **tüketir** (karar `execute|retry|escalate` değilse hiçbir şey başlatmaz: çıkış 3 bütçe, 2 politika reddi, **7 geçerli kanıt yeniden kullanıldı (başarı benzeri, yeniden deneme yok)**, **8 çalıştırılmadı ve geçerli sonuç yok (asla başarı değil)**; `--rerun <neden>` bilinçli tekrar için).
`ROUTING=off` (varsayılan) iken `run-role.sh` eskisi gibi çalışır. `route.sh explain --role R` beş satırda kararı gösterir ve hiçbir şey kaydetmez. `route.sh capabilities --probe` kurulu CLI'ların `--help` çıktısıyla yetenek bayraklarını denetler (model çağrısı yok). Kapı rolleri (verifier, reviewer, security-auditor) risk tabanını, zorunluluğu ve kanıt kurallarını asla aşmaz; duran bir BLOCK aynı diff'te başka sağlayıcıyla yeniden yargılanmaz.

### `scripts/verify-core.sh`
Doğrudan çalıştırılmaz; stack'in `verify.sh`'ı yükler (bölüm 8). `verify-lib.sh` `verify.d` yardımcısıdır (tüm stack'lerde ortak).

### `bin/build-adapters.sh [--check]`
`core/roles/*.md`'den `agents/*.md` (Claude) ve `adapters/{codex,opencode,cursor,gemini}/` üretir; host başına biçim `bin/emit/<host>.sh`'tadır, host araç/izin adları `core/hosts.env`'de, katman eşlemesi `core/tiers.env`'de. `--check` üretilmiş dosyaların güncel olup olmadığına bakar (yayın öncesi).

---

## 10. Yapılandırma referansı

### `<project-dir>/sdkit.env` ve `sdkit.local.env`

`sdkit.env` ekibin ortak politikasıdır ve commit'lenir. `sdkit.local.env` kişiseldir, git'e girmez, `sdkit.env`'den sonra okunur ve ortak değeri ezer (örneğin kendi makinenizde `MAX_PARALLEL=2`). Aşağıda **(kişisel)** işaretli anahtarlar `sdkit.local.env`'e yazılır; gerisi `sdkit.env`'e. 1.0 öncesi kurulumlarda ikisi de tek `project.env`'dedir.

| Değişken | Varsayılan | Anlamı |
|---|---|---|
| `BASE_BRANCH` | otomatik algılanır | Entegrasyon branch'i (`develop`, `main` ...) |
| `RISK_FLOOR_GLOBS` | boş (kapalı) | İsteğe bağlı risk tabanı: `seviye:glob,seviye:glob` (örn. `high:services/payments/*,medium:migrations/*.sql`). Diff'in gerçekten dokunduğu dosyalardan en katı eşleşme, görevin risk etiketinin alt sınırıdır; `advance green`/`verified` ve CI (`ci-check`, taban branch'in `sdkit.env`'ini de okur) denetler. Bozuk değer kapalı kalmaz, reddedilir. Ayrıntı: `upgrading.md` |
| `CONTRACTS` | boş (kapalı) | `1` ise Claude Code hook'u (`check-contract`) `CONTRACT:` taşıyan devirleri ve alt ajan cevaplarındaki `HANDOFF-RESULT` satırını denetler ([design-contracts.md](design-contracts.md)). `run-role.sh` `CONTRACT:` satırlı devri bu ayardan bağımsız denetler. Ekip ayarı (`sdkit.env`) |
| `STACK` | `go` (tek yerde: `scripts/env.sh`; `doctor` boşsa uyarır) | Stack: `go`, `spring-boot`, `jvm`, `python`, `nextjs`, `react-native`, `generic` (repo başına tek) |
| `VERIFY_FAST_CMD`, `VERIFY_TEST_CMD` | boş | Yalnızca `generic`: hızlı kontrol ve test komutu (repo kökünde çalışır) |
| `PY_RUNNER` | boş | Yalnızca `python`: araç öneki (`uv run`, `poetry run`); boşsa lockfile'dan |
| `VERIFY_CMD` | boş | Boş: plugin'in motoru. Dolu: repoya göre yol (copy modu) |
| `DIFF_BASE_CMD` | boş | Boş: plugin'in `resolve-base.sh`'ı. Dolu: repoya göre yol |
| `LINT_CONFIG` | `<project-dir>/golangci.yml` | golangci-lint yapılandırması (repoya göre) |
| `TRACKER` | `none` | `jira` veya `none` (`none` ise görev serbest metin) |
| `PR_HOST` | `bitbucket` | PR host'u |
| `PROTECTED_PATHS` | boş | Virgülle ayrılmış, kök-göreli yol önekleri. `guard-protected` onay ister |
| `SECRET_GLOBS` | `.env*,*credentials*,*.pem` | `guard-secrets` ile engellenen dosya desenleri |
| `PROD_KUBE_CLUSTERS` | boş | Prod cluster adı önekleri. **Dolu değilse kubectl guard'ı kapalı** |
| `BASE_BRANCH_MODE` | boş | `release` ise release-branch akışı açılır (`guard-git`, release-bilinçli taban) |
| `RELEASE_BRANCH_PREFIX` | `release/` | Release branch öneki |
| `FREEZE_TAG_PREFIX` | `freeze/` | Dondurma etiketi öneki |
| `PROTECTED_BRANCHES` | boş | Doğrudan push'a onay isteyen env branch'leri |
| `SERVICES_DIR` | `services` | Örnek OpenAPI politikasının baktığı dizin |
| `SHARED_MODULE` | boş | Değişince bağımlılarının da derleneceği paylaşılan Go modülü |
| `DEPENDENT_MODULES_GLOB` | boş | Bağımlı modüllerin glob'u (`services/*`) |
| `INTEGRATION_MODULE_GLOB` | `tests/*` | Gerçek altyapıya giden modüller: vet/build edilir, test edilmez (Spring Boot'ta da geçerli; boş = hepsi test edilir) |
| `NODE_PM` | boş | Node stack'leri: `npm\|pnpm\|yarn\|bun`; boşsa lockfile'dan |
| `VERIFY_BUILD` | boş | Node stack'leri: tam doğrulamada `next build` vb. çalıştırılsın mı |
| `JAVA_BUILD_TOOL` | boş | Spring Boot: `maven\|gradle` (algılama yanlışsa) |
| `VALUE_REPORT` **(kişisel)** | `on` | `on` ise görev bittiğinde (`sdd.sh advance done`, `abort`) kompakt Value Report stderr'e yazılır ve `work/_reports/`'a saklanır; oturum bitişinde özet saklanır. Okuma-yalnız, LLM çağrısı yok. Boş = otomatik kapalı (komutlar yine çalışır). [design-report.md](design-report.md) |
| `REPORT_BASELINE_MODEL` | boş | Value Report yönlendirme karşı-olgusunun taban modeli (`pricing.json`'daki kimlik). Boşsa yönlendirme tasarrufu `N/A`; kit model uydurmaz |
| `USAGE_LOG` **(kişisel)** | `1` | `1` ise token defteri açılır (bölüm 18); boş = kapalı |
| `TELEMETRY` **(kişisel)** | boş | `1` ise `work/<slug>/events.jsonl` olay günlüğü açılır (bölüm 18, [design-telemetry.md](design-telemetry.md)); boş = kapalı |
| `EXTRA_REVIEW_SKILLS` | boş | `high` riskte reviewer + security-auditor'a ek host skill'leri, boşlukla ayrılmış (ör. `code-review security-review`) |
| `ROUTING` | `off` | `on` ise `run-role.sh` adaptör/model/bütçe/yeniden deneme kararını `route.sh`'tan alır; ayrıntılı `ROUTE_*` ayarları ([design-routing.md](design-routing.md) §9): `ROUTE_POLICY`, `ROUTE_FIXED_MODEL`, `ROUTE_DOWNGRADE_LOW`, `ROUTE_FLOOR_*`, `ROUTE_FALLBACK_HOSTS`, `ROUTE_MAX_RETRIES/ESCALATIONS/ATTEMPTS`, `ROUTE_ESCALATE_TO`, `ROUTE_BACKOFF_S`, `ROUTE_PREFER_<ROL>`. Ekip ayarı (`sdkit.env`) |
| `ROUTE_ROLE_TOKENS`, `ROUTE_TIMEOUT_S`, `ROUTE_BUDGET_COST` **(kişisel)** | boş | Rol başına token, çalıştırma başına saniye, tahmini USD sınırı (parasal sınır her zaman danışma). `TOKEN_BUDGET_TASK`/`MAX_SPAWNS` da `route.sh` tarafından denetlenir |
| `RUN_ROLE_HOST` **(kişisel)** | boş | `run-role.sh` için varsayılan host (`claude\|codex\|opencode\|cursor\|gemini`) |
| `VERIFIER_HOST` **(kişisel)** | boş | Bağımsız roller (verifier, reviewer, security-auditor) için host; başka sağlayıcı = gerçek bağımsızlık |
| `RUN_ROLE_MODEL_LIGHT/STANDARD/STRONG` **(kişisel)** | boş | `run-role.sh` için katman başına host-özel model kimliği |
| `MAX_PARALLEL` **(kişisel)** | `3` | Aynı anda çalışacak en fazla subagent/süreç; `plan-waves.sh` daha büyük dalgayı böler (pozitif tamsayı; geçersizse 3) |
| `TOKEN_BUDGET_TASK` **(kişisel)** | boş | Bir görevin en çok kullanacağı token (`in + out + cache-write`); `USAGE_LOG=1` gerekir. Boş = bütçe yok |
| `TOKEN_BUDGET_WARN_PCT` **(kişisel)** | `70` | Bütçenin bu yüzdesinden itibaren uyarı |
| `MAX_SPAWNS` **(kişisel)** | boş | Görev başına en çok subagent açılışı; aşılınca `strict` sorar, `guided` uyarır. Boş = sınır yok |
| `SUBAGENT_RESULT_MAX_LINES` **(kişisel)** | boş | Bir rolün cevabı bundan uzunsa `result-size` uyarır |
| `MEMORY` | `1` | `1` ise proje belleği açılır (bölüm 19); boş = kapalı (`sdkit init --no-memory`) |
| `MEMORY_DIR` | `memory` | Girdilerin dizini: `<project-dir>`'e göre veya mutlak yol |
| `MEMORY_VCS` | `commit` | `commit` = ekip paylaşır, `ignore` = kişisel (`init --memory-vcs` `.gitignore` satırını yazar; sonradan değiştirilebilir) |
| `MEMORY_AUTOLOAD` **(kişisel)** | `1` | `1` ise oturum hook'u `INDEX.md`'yi bağlama koyar |
| `MEMORY_INDEX_MAX` **(kişisel)** | `100` | En çok girdi ve en çok enjekte edilen `INDEX.md` satırı |
| `MEMORY_STALE_DAYS` **(kişisel)** | `90` | `memory.sh stale` bu kadar gündür güncellenmeyen girdileri işaretler |
| `MEMORY_PROMOTE` **(kişisel)** | `ask` | Kapanışta `MEMORY:` adaylarını kullanıcıya sor (`ask`), hepsini al (`auto`) veya hiçbirini (`off`) |

Yalnızca ortam değişkeni olanlar: `VERIFY_BASE` (diff tabanını ez), `VERIFY_POLICY_DIR` (varsayılan `<project-dir>/verify.d`),
`BITBUCKET_EMAIL`, `BITBUCKET_TOKEN`, `PR_TOKEN_REPO`. Ortam değişkeni, `sdkit.env`'deki varsayılanı ezer (`PR_HOST` için `: "${PR_HOST:=bitbucket}"` biçimi bunu sağlar).

### `<project-dir>/project.md` bölümleri
Tracker · Branches and PRs (commit scope'ları dahil) · Release flow (opsiyonel) · Verification · Test layout · Protected code · **Risk rubric** · Known pitfalls.
`scaffold-doctor`, `TODO` kaldıysa veya rubrik yoksa hata verir.

### Diğer proje dosyaları
`rules/` (proje kuralları; `init` genel ve Go kurallarını kopyalar, proje düzenler) · `golangci.yml` · `adr/` · `CLAUDE.md` (harita) ·
`.gitignore` (kişisel dosyalar: `settings.local.json`, `.frozen`, `.cc-writes/`, `scheduled_tasks.lock`, `memory/`, `work/`, `.verify-cache/`). Claude dışı host'lar ayrıca repo köküne `AGENTS.md`, `.agents/skills/`, `.githooks/` ve kendi dizinlerini yazar (bölüm 16).

---

## 11. Kurulum akışları

### Yeni repo (bir kez, repoyu hazırlayan kişi)
```bash
git clone <bu-repo> ~/spec-driven-kit
~/spec-driven-kit/bin/init.sh /yol/repo      # stack ve base branch'i kendi bulur
# <project-dir>/project.md ve sdkit.env'i doldur, işine yarayan verify.d/*.example dosyalarının uzantısını sil
~/spec-driven-kit/bin/doctor.sh /yol/repo    # 0 hata olana kadar
git add <project-dir> .claude && git commit      # <project-dir>: init'in yazdığı klasör
```
`init.sh` seçenekleri: `--host` (virgüllü liste: `claude,codex,opencode,cursor,gemini`; varsayılan `claude`), `--dir .sdkit` (varsayılan; mevcut eski klasör korunur), `--no-memory`, `--memory-vcs commit|ignore`, `--mode plugin|copy` (yalnızca Claude), `--stack go|spring-boot|jvm|python|nextjs|react-native|generic` (verilmezse sırayla `go`, `spring-boot`, `jvm`, `react-native`, `nextjs`, `python` algılanır; ilk eşleşen kazanır, hiçbiri yoksa `generic`), `--marketplace-url <url>`, `--force`. **Proje tarafı dosyalarını (project.*, rules, settings.json ...) var olsa bile hiçbir zaman ezmez**,
bir kez yazılır, sonrasında sizindir. `--force` yalnızca copy modunda kit'ten kopyalanan (yönetilen) dosyaları ezer.

### Geliştirici (repo hazırsa)
```bash
git clone <repo> && cd <repo>
claude      # güveni ve plugin'i kabul et
/spec-driven-dev <ticket veya açıklama>
```
İstem çıkmazsa: `/plugin marketplace add <bu-repo-url>` ve `/plugin install spec-driven-kit@spec-driven-kit`.

### `doctor.sh` neleri kontrol eder
`jq`, git deposu · `sdkit.env` yüklenebiliyor mu, `BASE_BRANCH` var mı, `VERIFY_CMD` çalıştırılabilir mi · `project.md` doldurulmuş mu, risk rubriği var mı ·
`known-pitfalls.md`, `CLAUDE.md`, `<project-dir>/.gitignore` · aktif `verify.d` politikası var mı (yoksa uyarı) · `settings.json` geçerli ve `deny` listesi var mı ·
plugin modunda plugin etkin ve marketplace adresi tanımlı mı, copy modunda hook'lar bağlı mı · Claude dışı host'lar: `AGENTS.md`, `.agents/skills`, kit script'leri (`verify-core`, `state`, `parse-verdict`, `run-role` ... ) çalıştırılabilir mi, `hooks/adapt.sh`, `core.hooksPath`, kurulu host için rol dosyaları (`.codex/agents`, `.opencode/agents` + guard eklentisi, `.cursor/agents` + geçerli `hooks.json`, `.gemini/agents` + geçerli `settings.json`) · her host'un CLI'ı kurulu mu (yalnız uyarı: yalnızca `run-role.sh` ister) · stack'in `tools.sh` listesi (`required` eksikse hata, `optional` eksikse uyarı) ve `openspec`.

### `upgrade.sh` (güncelleme)
Kit'i kullanan bir projeyi yeni sürüme taşır: host'ları (`.codex/`, `.opencode/agents`, `.cursor/agents`, `.gemini/agents` varlığından; eski 0.3 Codex düzeni için `AGENTS.md`/`.agents/skills`), mod ve stack'i algılar, yeni dosyaları ekler (var olanlara dokunmaz), `.gitignore`'a eksik satırları ekler, copy veya Claude dışı kurulumlarda `sync.sh` çalıştırır, `doctor.sh` ile bitirir. Plugin tarafı ayrıca `/plugin` ile yenilenir. Ayrıntı ve sürüme göre elle yapılacaklar: [upgrading.md](upgrading.md). **Copy modundaki Claude projeleri:** `.claude/settings.json` proje sahipliğinde olduğu için yeni hook'lar (PreToolUse `Bash|Edit|Write|NotebookEdit` için `guard-readonly`, Stop ve SubagentStop için `usage-log`) elle birleştirilmelidir; kaynak `templates/settings.copy.json`.

### `sync.sh` (yalnızca copy modu)
Kit'te değişiklik olunca projedeki kopyaları günceller. Yerel olarak düzenlenmiş bir dosya, kit'te de değiştiyse üzerine yazmaz: farkı gösterir (`--force` ile kit sürümü alınır).

---

## 12. İzin modeli

İki katman birlikte çalışır:

1. **`settings.json` kuralları** (projede commit'li): `permissions.deny` her zaman kazanır: `rm -rf`, `git push --force/-f`, `git reset --hard`,
   `.env*` / `*.pem` / `*credentials*` okuma. `permissions.allow` rutin komutlara izin verir (Edit/Write, `make`, okuma amaçlı `git`,
   `git add/commit/push/checkout/switch`, `kubectl get/describe/logs`, `openspec`, `jq`, `ls`, `cat`) ve seçilen stack'in `permissions.txt` desenlerini (ör. Go: `go`; Node: paket yöneticisi; Spring: `mvn`/`gradle`/wrapper) ekler; `init` bunları `settings.json`'a yazar, ki ilk gün izin yağmuru olmasın.
2. **Hook'lar** (plugin'den): `allow` kuralının üstüne **deny/ask** verebilir. Yani izinli bir komut bile yanlış dal kaynağı gibi bir
   gerekçeyle reddedilebilir.

Kişisel izinler `settings.local.json`'a gider (git'e girmez).

Güven: Claude Code, bir projeyi **güven onayından** önce yalnızca kullanıcı ayarlarını uygular; o ana kadar projenin `permissions.allow`'ı ve
projenin tanımladığı plugin devreye girmez. Bu normal davranıştır, kit'in sorunu değil.

---

## 13. Sınırlar ve bilinen eksikler

- **Codex, OpenCode, Cursor ve Gemini adaptörleri canlı kurulumlarda doğrulanmadı.** Dosya düzenleri her aracın belgelenmiş biçimine göre üretilir; yalnızca Claude Code yolu uçtan uca denendi. Doğrulanmamış noktalar:
  - Codex: kullandığın sürümde multi-agent özelliğinin açık olduğu ve anahtar adları; salt okunur sandbox build önbelleklerini engelleyebilir.
  - OpenCode: shell izin anahtarı `shell` mi `bash` mi (eski sürümlerde `bash`; `core/hosts.env` içinde `OPENCODE_SHELL_KEY`), eklenti hook'larının subagent içinde tetiklenip tetiklenmediği.
  - Cursor: IDE'de hook ve subagent var, CLI'da belgelenmemiş; `--output-format json` token kullanımı vermez (defter bu host'ta boş kalır).
  - Gemini: subagent'lar deneysel bayrak arkasında olabilir; yazma/düzenleme araç adları (`write_file`, `replace`) ve `context.fileName` dizi biçimi doğrulanmadı.
  - `run-role.sh` bayrak yazımları CLI başına: `--dry-run` ile yazdır, `<cli> --help` ile karşılaştır.
  - Görev boyutuna göre model seçimi (`--tier`, `size:`): Codex, OpenCode, Cursor ve Gemini yolları yalnızca `--dry-run` ile sınandı, gerçek model çağrısı yapılmadı. Codex'in `-c model_reasoning_effort=...` bayrağı ve OpenCode'un `anthropic/claude-*-5-5` model kimlikleri canlı kurulumda doğrulanmadı. Cursor ve Gemini için `core/tiers.env` modelleri bilerek boş bırakıldı (kit model adı uydurmaz): doldurulana kadar `--tier` oturumun modelini değiştirmez.
- **Claude dışı host'larda garantiler daha zayıftır.** Stop-verify ve SessionStart yoktur; secret/frozen/protected/push guard'ları Gemini/Cursor/OpenCode'da araç çağrısında (kabuk/eklenti) çalışsa da bu yolların kendisi denenmemiştir, Codex'te yalnızca commit/push anında (git hook, CI) çalışır. `ask` desteklemeyen host'ta onay istemi `deny`'a düşer. Bağımsız doğrulama subagent desteğine veya `run-role.sh`'a bağlıdır; yoksa ayrı bir oturumda yapılmalıdır.
- **Proje tarafı klasörü `.sdkit/`'tir** (eski kurulumlarda `.claude` / `.codex` / `.agentkit`); script'ler/hook'lar onu adıyla arayarak bulur, başka bir ad desteklenmez. Claude Code'un kendi dosyaları (`CLAUDE.md`, `settings.local.json`, copy modunda `agents/ skills/ hooks/`) `.claude/` altında kalır.
- **Token kullanımı:** kit isteğe bağlı defter tutar (`USAGE_LOG=1`, bölüm 18) ama ölçüm host'a bağlıdır; Claude'da hook'tan, `run-role.sh`'ta CLI'ın yazdığı yerden alınır, bazı host'larda eksiktir.
- **Repo başına bir `STACK`** (`go`, `spring-boot`, `jvm`, `python`, `nextjs`, `react-native`, `generic`). Birden çok stack'li monorepo kapsam dışıdır. Tanınmayan dilde `init` `generic`'e düşer; derleme/test komutlarını `sdkit.env`'e sen yazarsın. Yeni stack için bölüm 14.
- **Doğrulama önbelleği** yalnızca yeşil sonucu ve tam ağaç durumunu tanır. Ağaç dışı bir şey (ortam, ağ, dış servis, `verify.d` dışında okunan dosya) değiştiyse eski yeşil geçerli görünebilir: şüphede `--no-cache`.
- **Bitbucket tek PR host'u.** GitHub/GitLab için yalnızca [kurulum notu](hosts.md) var.
- **Guard'lar düzenli ifade ve basit eşleşmeyle çalışır.** `guard-secrets` Bash'teki `cat .env`'i görmez (bunun için `deny` listesi var); `guard-git` alışılmadık git
  sözdizimini veya betik içinden çağrıları kaçırabilir; `guard-prod` yalnızca `kubectl`'e bakar; `guard-readonly` bilinmeyen bir yazma komutunu kaçırabilir. Bunlar güvenlik **sınırı** değil, hata önleyici emniyettir.
- **`stop-verify` yalnızca commit'siz değişikliklerin hızlı kontrolünü** (`--fast`: Go'da vet/build) çalıştırır; testleri ve lint'i çalıştırmaz (hızlı kalsın diye). Tam doğrulama için `verify.sh` (bayraksız).
- **OpenSpec'e bağımlıdır.** `spec-driven-dev` OpenSpec skill'lerini çağırır; CLI kurulu olmalıdır. OpenSpec dosyaları kit'e dahil değildir.
- **Plugin kurulum istemi** ilk açılışta, güven onayından sonra beklenir; bazı ortamlarda çıkmayabilir, iki `/plugin` komutu yedektir.
- **Başsız (`claude -p`) modda** güvenilmeyen projede proje ayarları yok sayılır.

---

## 14. Genişletme

**Projeye özel kontrol eklemek:** `<project-dir>/verify.d/NN-ad.sh` yaz (`FAIL:`/`WARN:` protokolü), `chmod +x`.

**Projeye özel hook eklemek (Claude):** Repoda `.claude/hooks/` altına script, `settings.json`'a bağlantı. Plugin hook'larını tamamlar, onların yerini almaz.
Script `jq` ile stdin'deki araç çağrısını okur, `permissionDecision` (`deny`/`ask`) JSON'u yazar (bkz. `hooks/lib.sh`: `jget`, `decide`).

**Yeni rol eklemek:** `core/roles/<ad>.md` yaz (`kind`, `access`, `tier`, `independent`), `bin/build-adapters.sh` çalıştır, `core/roles/README.md` tablosunu ve bu rehberin bölüm 6'sını güncelle. Rol, projeye özel hiçbir şey içermemeli.

**Yeni host eklemek:** `bin/emit/<host>.sh` (rol biçimini üretir: `emit_<host>_begin/role`), `core/hosts.env`'e host'un araç/izin adları, `core/tiers.env`'e model katmanı anahtarları, `init.sh`'a `--host` dalı (host dosyaları ve guard bağlaması; gerekirse `hooks/adapt.sh`'a çeviri), `doctor.sh`'a kontroller (rol dosyaları, CLI), `scripts/run-role.sh`'a headless çağrı, `skills/spec-driven-dev/references/hosts.md`'ye bir sütun ekle; sonra `bin/build-adapters.sh` çalıştır ve çıktıyı commit'le.

**Yeni risk ölçütü / kural:** `project.md` rubriği ve `rules/` düzenlenir; kit'e dokunmaya gerek yok.

**Yeni stack eklemek** (sözleşme: `stacks/README.md`): `stacks/<ad>/` altında
1. `detect.sh` (`$1` bu stack'te bir proje ise 0), `init.sh` içindeki `STACKS` sırasına eklenir
2. `scripts/steps.sh` (`STACK_SOURCE_RE` ve `stack_run`; çekirdek `scripts/verify-core.sh` bayrakları, önbelleği ve `verify.d`'yi halleder) ve ince `scripts/verify.sh`
3. `scripts/fmt.sh` (hep 0 çıkar), `scripts/tools.sh` (`required|komut|ipucu`), `permissions.txt`
4. `rules/`, `verify.d.example/` ve varsa linter yapılandırması

**Kit'i güncellemek:** Bu repoda değişiklik yap, `.claude-plugin/plugin.json` ve `marketplace.json` sürümünü artır, push et. Plugin kullanan repolar
güncellemeyi `/plugin` ile alır; copy modundakiler `sync.sh` çalıştırır.

---

## 15. Dosya haritası

```
spec-driven-kit/
├── .claude-plugin/        plugin.json, marketplace.json
├── core/
│   ├── roles/             ARAÇTAN BAĞIMSIZ rol tanımları (kaynak), README.md
│   ├── tiers.env          katman -> model eşlemesi (Claude, Codex, OpenCode, Cursor, Gemini)
│   ├── hosts.env          host araç/izin adları (salt okunur shell allow-list'i, Gemini araçları, OpenCode anahtarı)
│   └── rules/             general, git, test-first, token-economy     (dilden bağımsız)
├── skills/                spec-driven-dev (+ references/), incident-to-rule, scaffold-init, scaffold-doctor
├── agents/                ÜRETİLMİŞ Claude agent'ları (verifier-deep dahil; core/roles'tan; elle düzenleme)
├── adapters/
│   ├── codex/ opencode/   ÜRETİLMİŞ rol dosyaları (+ config.toml.snippet; OpenCode guard eklentisi plugins/)
│   ├── cursor/ gemini/    ÜRETİLMİŞ rol dosyaları + hooks.json / settings.json
│   └── git/               pre-commit, pre-push (guard.sh'ı çağırır)
├── hooks/                 hooks.json (olay bağlantıları) + lib.sh + 17 hook + adapt.sh (Gemini/Cursor kabuğu)
├── scripts/               env (ayar okuyucu, kilit, aktif görev), sdd, resolve-base, open-pr, guard, plan-waves, worktree, state, parse-verdict, check-plan-parity,
│                          check-writes, usage, telemetry, contract, workflow, route, memory, lookup-cache, run-role, verify-core, verify-lib   (stack'ten bağımsız)
├── bench/                 run.sh (benchmark sürücüsü), scenarios/ (4 F01 + 5 sözleşme senaryosu), stub-host/ (simüle modun sahte host CLI'ları); bkz. design-telemetry.md, design-contracts.md
├── stacks/
│   ├── README.md          stack sözleşmesi
│   ├── _node/scripts/     node-lib.sh (nextjs ve react-native ortak)
│   ├── go/                detect.sh, permissions.txt, golangci.yml, rules/, verify.d.example/,
│   │   └── scripts/       verify.sh (sarmal), steps.sh, fmt.sh, tools.sh
│   └── spring-boot/ jvm/ python/ nextjs/ react-native/ generic/    aynı yapı
├── tests/                 run.sh (script duman testleri), sdd.test.sh, shared.test.sh, memory.test.sh, hardening.test.sh, telemetry.test.sh, usage.test.sh, budget.test.sh, route.test.sh
├── templates/             sdkit.env, project.md, known-pitfalls.md, CLAUDE.md, AGENTS.md, adr/, settings.*.json, claude.gitignore
├── bin/                   init.sh, doctor.sh, sync.sh, upgrade.sh, build-adapters.sh, lib.sh, emit/<host>.sh
└── docs/                  guide.md (bu dosya), cheatsheet.md, hosts.md, README.md
```

Bir repoda `init.sh` sonrası proje tarafı:

```
<repo>/.sdkit/             tek proje klasörü; git'te, kişisel ve üretilmiş dosyalar hariç (kendi .gitignore'u)
├── project.md  known-pitfalls.md  adr/  verify.d/  roles.d/  golangci.yml (yalnız Go)      (git'te)
├── rules/                 genel + test-first + token-economy + stack kuralları (kopya, proje düzenler)  (git'te)
├── memory/                proje belleği: INDEX.md + girdiler (MEMORY=1; MEMORY_VCS=ignore ile kişisel)  (git'te)
├── attestations/          doğrulama kayıtları, CI kapısı için (git'te)
├── sdkit.env              ekibin ortak ayarları: release akışı, korunan yollar, stack ... (git'te)
├── sdkit.local.env        KİŞİSEL ayarlar: bütçeler, limitler, memory davranışı, host/model (git'e girmez)
├── work/<slug>/           plan.md, state.json, notes.md, usage.jsonl, out/, lookups/ (git'e girmez)
├── scripts/ roles/ hooks/ tiers.env   kit kopyaları, kurulumdan üretilir (git'e girmez; CI için sdd.sh, resolve-base.sh ve env.sh hariç)
└── .verify-cache/ .frozen .sdd/ .scaffold-*   çalışma zamanı (git'e girmez)
<repo>/.claude/            (Claude host'u) CLAUDE.md (kit bloğu, git'te), settings.local.json (git'e girmez); copy modunda agents/ skills/ hooks/
<repo>/AGENTS.md  .agents/skills/  .githooks/                                         (Claude dışı host'lar)
<repo>/.codex/{config.toml,agents/}  .opencode/{agents/,plugins/spec-driven-kit-guard.js}
<repo>/.cursor/{agents/,hooks.json}  .gemini/{agents/,settings.json}               (ilgili host)
```

---

## 16. Host'lar: Claude Code, Codex, OpenCode, Cursor, Gemini

Kit üç katmandır; hangisinin taşınabilir olduğu bellidir.

| Katman | İçerik | Taşınabilirlik |
|---|---|---|
| **A. Markdown** | Roller, akış (`SKILL.md`), kurallar, `AGENTS.md` | Her araç okur. `SKILL.md` biçimi ortak |
| **B. CLI script'ler** | `verify.sh`, `resolve-base.sh`, `guard.sh`, `plan-waves.sh`, `worktree.sh`, `state.sh`, `parse-verdict.sh`, `run-role.sh` ... | Her araç shell'den çağırır |
| **C. Araca özel bağlama** | Claude hook'ları ve agent dosyaları; Codex/OpenCode/Cursor/Gemini rol dosyaları ve guard bağlaması; git hook'ları | Host'a göre (`bin/emit/<host>.sh`) |

| | Claude Code | Codex | OpenCode | Cursor | Gemini CLI |
|---|---|---|---|---|---|
| Talimat | `.claude/CLAUDE.md` + skill'ler | `AGENTS.md` + `.agents/skills/` | `AGENTS.md` + `.agents/skills/` | `AGENTS.md` + `.agents/skills/` | `AGENTS.md` (`.gemini/settings.json` `context.fileName`) + `.agents/skills/` |
| Roller | `agents/*.md` (plugin) / `.claude/agents/` | `.codex/agents/*.toml` + `config.toml` | `.opencode/agents/*.md` | `.cursor/agents/*.md` | `.gemini/agents/*.md` |
| Salt okunur zorlama | `guard-readonly` hook | sandbox `read-only` | `permission:` izin listesi | `readonly: true` | `tools:` listesi |
| Guard'lar | hook'lar (model atlayamaz) | git hook'ları | JS eklentisi + git hook'ları | `hooks.json` → `adapt.sh cursor` + git hook'ları | `settings.json` hook'ları → `adapt.sh gemini` + git hook'ları |
| Kit script'leri | plugin kökü veya `<project-dir>/scripts/` | `<project-dir>/scripts/` | aynı | aynı | aynı |
| Kurulum | `init.sh --host claude` | `--host codex` | `--host opencode` | `--host cursor` | `--host gemini` |
| Skill çağırma | `/spec-driven-dev` | `$spec-driven-dev` veya `/skills` | host'a göre | host'a göre | host'a göre |

`--host` virgüllü liste alır (`claude,codex,...`). Claude dışındaki her host'ta `init` skill'leri `.agents/skills/`'e, kit script'lerini, rol metinlerini ve hook'ları `<project-dir>/{scripts,roles,hooks}`'a, git hook'larını `.githooks/`'e kopyalar. Doğrulanmamış noktalar bölüm 13'te.

Host notları:
- Codex: `.codex/config.toml` proje tarafıdır; var olan dosyanın üzerine yazılmaz, `adapters/codex/config.toml.snippet` elle birleştirilir. Rol TOML'ları `model_reasoning_effort`, `sandbox_mode` ve `developer_instructions` içerir; `model` yalnızca `core/tiers.env`'de `CODEX_MODEL_*` doluysa yazılır.
- OpenCode: shell izin anahtarı `core/hosts.env`'deki `OPENCODE_SHELL_KEY`'dir (eski sürümlerde `bash`).
- Cursor/Gemini: var olan `.cursor/hooks.json` veya `.gemini/settings.json` varsa elle birleştir. Guard kararı `ask` desteklemeyen yerde `deny`'a düşer.
- Proje klasörü her host için `.sdkit/`'tir. Çalışma anında `.sdkit`, `.agentkit`, `.claude`, `.codex` sırasıyla `sdkit.env` (eski kurulumlarda `project.env`) aranır; 1.0 öncesi projeler olduğu gibi çalışır.
- Her klonda bir kez: `git config core.hooksPath .githooks` (`doctor.sh` uyarır).

**Ayrı süreç ve bağımsız sağlayıcı:** `scripts/run-role.sh <rol> --handoff F --host H` bir rolü ayrı başsız CLI süreci olarak çalıştırır (`claude -p`, `codex exec`, `opencode run`, `cursor-agent -p`, `gemini -p`). `VERIFIER_HOST` ile verifier farklı bir sağlayıcıya verilirse bağımsızlık gerçek olur (aynı model ailesi kendi hatasını kaçırmaz).

Subagent desteği olmayan host'ta aynı plan sırayla yürütülür; bağımsız doğrulama için taze bir oturum veya `run-role.sh` kullanılır.

---

## 17. Paralel çalışma

Varsayılan **sıralıdır**; paralel koşular token'ı çarpar. Yalnızca risk `medium`/`high`, en az iki görevin yazma kümesi ayrık ve host subagent çalıştırabiliyorsa paralel çalışılır.

Görev biçimi (`tasks.md` ve plan bölüm 5):
```
- [ ] T3 importer'a retry ekle | role: developer | size: medium | writes: services/importer/ | after: T1
```
`size:` isteğe bağlıdır (model katmanı, bölüm 6); `plan-waves.sh` onu çıktıda `T3(developer,medium)` diye gösterir, gruplamayı etkilemez.
`scripts/plan-waves.sh tasks.md` örnek çıktısı:
```
wave 1: T1(developer)  ||  T3(devsecops)  ||  T5(developer)
wave 2: T2(developer)
wave 3: T4(test-writer)      # T2 ile yazma yolu çakışıyor, sonraya kaldı
```

Güvenli paralel çiftler: `test-writer ‖ developer` (test ve arayüz plana sabitlenmişse; developer testi değiştiremez) · ayrık `writes:` olan iki `developer` · `developer ‖ devsecops` ·
`reviewer ‖ security-auditor` (ikisi de salt okunur). **Asla:** `verifier` ile gerçekleştirici, aynı dosyada iki yazan, birleşmemiş sonuca bağlı iş.

İzolasyon **kit'e aittir**, host'un yerel worktree özelliğine bağlı değildir (böylece her host'ta aynı çalışır): her yazan görev kendi worktree'sinde çalışır (`worktree.sh add T3`), yolu `worktree.sh path T3` ile alınıp devir özetine `WORKTREE:` olarak yazılır ve rol yalnızca o yol altında okur/yazar; host rolü bir dizine sabitleyemiyorsa `run-role.sh --cwd` kullanılır. Orchestrator dalga dalga birleştirir: `worktree.sh merge T3 tasks.md` önce `check-writes.sh` ile görevin `writes:` kümesinin dışına çıkıp çıkmadığına bakar (çıktıysa birleştirmez), sonra birleştirir; her birleştirmeden sonra `verify --fast` çalıştırır ve ancak sonra sonraki dalgaya geçer.
`high` riskte reviewer ve security-auditor paralel çalışır (`EXTRA_REVIEW_SKILLS` doluysa host skill'leri de). Birleştirme çakışması yazma kümelerinin yanlış olduğu demektir: dur, kullanıcıya söyle, planı düzelt. Aynı anda en fazla `MAX_PARALLEL` (varsayılan 3) subagent: `plan-waves.sh` daha büyük bir dalgayı böler, sığmayan görevler sonraki dalgaya kalır.

---

## 18. Token ekonomisi

Hedef: judgement gereken yerde harcamak; arama, yeniden yazma ve yeniden okumada harcamamak. Kurallar `core/rules/token-economy.md`'dedir (projeye kopyalanır); özeti:

| Kaldıraç | Nasıl |
|---|---|
| Doğru boyutlu rol | Arama `scout` (light), planlama kontrolü `analyst`, tasarım ve `high` doğrulama (`verifier-deep`) strong, geri kalanı standard. Roller katman bildirir, model adı değil |
| Ucuz olan önce | `verify.sh` LLM incelemesinden önce; kırmızıysa pahalı okuma yok |
| Tekrar etme | Yeşil doğrulama önbelleği: Stop hook'u, verifier ve PR adımı aynı ağaç için işi tekrarlamaz (`--no-cache` ile atlanır) |
| Script, LLM değil | Plan eşitliği (`check-plan-parity.sh`), verdict doğrulaması (`parse-verdict.sh`), yazma kümesi (`check-writes.sh`), deneme sınırı (`state.sh retry`) deterministik script'tir |
| Artifact devri | Alt role konuşma değil, yol içeren kısa devir özeti (`handoff.md`). Bağımsız roller zaten gerçekleştiricinin gerekçesini almaz, bu bağlamı da küçük tutar |
| Çıktıyı kırp | Komutun özet satırı + başarısız satırlar (`tail -40`); roller yapılandırılmış blok + en fazla 15 satır döner |
| Dar oku | Sembolü grep'le, gereken satırları aç; dosyanın çoğunu değiştirmiyorsan tamamını okuma |
| İsteğe bağlı yükleme | `SKILL.md` kısa; `references/` yalnızca ilgili adımda okunur |
| Derinlik riske göre | `low`: engineer çalışması, bağımsız doğrulayıcı ve paralel dalga yok; analist `low`'da da çalışır (ucuz, tutarlı). `NEEDS-LOOKUP` ile rol zincirleri yerine tek `scout` koşusu |
| Paralel yalnızca kazandırıyorsa | Ayrık yazma kümeleri veya salt okunur incelemeler, en fazla `MAX_PARALLEL` (3) eşzamanlı |
| Bir deneme, sonra sor | İkinci otomatik tekrar token yakar ve nadiren işe yarar |
| Gerektiğinde aç | Bir veya iki dosyalık iş yerinde yapılır; roller rol açmaz. Karar tablosu: `references/delegation.md` |
| Sonuç kısa ve dosyada | Rol en çok 15 satır + yapılandırılmış blok döner; uzun hali `work/<slug>/out/` altında. Aynı scout sorusu `lookup-cache.sh` ile tekrar ödenmez |
| Bütçe | `MAX_SPAWNS`, `TOKEN_BUDGET_TASK`: aşılınca sorulur, doğrulama bütçeye sığdırmak için kısılmaz |
| Önbellek dostu devir | Sabit satırlar başta, her açılışta değişenler sonda; dalga içinde aynı model; açılışlar birlikte |
| Kontrol noktası | Adım sınırında `state.sh set step` + `notes.md`; `/clear` veya sıkıştırma sonrası kayıpsız devam |
| Yeniden türetme | Plan karar günlüğündeki ve oturumda kesinleşmiş şeyler yeniden sorulmaz/yapılmaz |

### Ölçüm: token defteri
`USAGE_LOG=1` (`sdkit.env`) ile her ajan koşusu `<project-dir>/work/<slug>/usage.jsonl`'a bir JSON satırı yazar: rol, katman, host, model, giriş/çıkış ve önbellek token'ları. Claude'da `hooks/usage-log.sh` (SubagentStop ve Stop) transkriptten toplar; `run-role.sh` host CLI'ın kullanım bilgisini yazdığı yerde kaydeder (Claude evet; Cursor json çıktısında kullanım yok; diğerlerinde en iyi çaba). Kapalıyken hepsi sessiz no-op'tur.
`scripts/usage.sh report [slug]` rol ve katman başına koşu sayısı ve token toplamlarını, ayrıca önbellek isabet oranını verir.

### Ölçüm: olay günlüğü ve benchmark
`TELEMETRY=1` (`sdkit.local.env`) ile faz geçişleri, kapı reddi, test sonucu, ajan koşuları (süre, token, araç çağrısı), yeniden deneme, hata ve doğrulama sonucu `work/<slug>/events.jsonl`'a yapılandırılmış olay olarak yazılır; yeni bir defter değildir, token sayıları `usage.sh` ile aynı kaynaktandır. Her ölçüm `actual`, `estimated` veya `unavailable` etiketi taşır; host vermediği sayı yazılmaz. İstem ve dosya içeriği kaydedilmez. `scripts/telemetry.sh summary [slug] [--json]` raporu verir; kapanıştan önce `telemetry.sh archive <slug>` çalıştırın (`work/<slug>` silinir). Fiyat tablosu (`pricing.json`) verilmedikçe maliyet gösterilmez. `bench/run.sh` dört temsilî iş akışını simüle (ücretsiz, deterministik) ya da `--real` ile gerçek host'larda koşturur. Ayrıntı: [design-telemetry.md](design-telemetry.md).

Sözleşmeler (F02) aynı günlüğe `contract.check` olayı yazar (geçerli/geçersiz, kategori, sürüm, rol, kimlik, baytlar; metin yok). Ek yük simüle fikstürlerle ölçüldü (`bench/run.sh overhead`): devir başına 202 sabit bayt, cevap başına ~119 bayt, ajan başına 2 betik çağrısı, ek ajan çağrısı yok; **token tasarrufu veya maliyeti ölçülmedi**. Ayrıntı: [design-contracts.md](design-contracts.md) §7.

### Bütçe ve subagent yönetimi
Hepsi varsayılan olarak kapalıdır; kit sayı dayatmaz, her ekip kendi sınırını `sdkit.env`'e yazar.

| Ayar | Ne yapar |
|---|---|
| `TOKEN_BUDGET_TASK` **(kişisel)** | `usage.sh budget` defterdeki `in + out + cache-write` toplamını sınırla kıyaslar. `TOKEN_BUDGET_WARN_PCT`'te (70) uyarır, %100'de durur. `USAGE_LOG=1` gerekir |
| `MAX_SPAWNS` **(kişisel)** | `state.sh <slug> spawn` her açılışı sayar; sınır aşılınca bir sonraki açılış kullanıcıya sorulur. Token ölçümü gerekmez |
| `SDD_MODE` | `strict` sınırı aşan açılıştan önce sorar, `guided` yalnızca uyarır, `off` ikisini de yok sayar |
| `SUBAGENT_RESULT_MAX_LINES` **(kişisel)** | Uzun cevapta `result-size` hook'u uyarır (engellemez) |

Claude Code'da sayımı `guard-budget` hook'u her `Agent` çağrısında yapar. Diğer host'larda açılış noktası `run-role.sh`'tır: sınırdayken çıkış 3 ile durur, kullanıcı onaylayınca `--ignore-budget` ile yeniden çalıştırılır. Host token bilgisi vermiyorsa defter boş kalır ve token bütçesi sessiz kalır; kit tahmin yürütmez. Aynı sebeple Codex'te token bütçesi yalnızca `run-role.sh` CLI çıktısından kayıt geldiğinde işler; `MAX_SPAWNS` her host'ta işler.

Orchestrator için karar ve sonuç kuralları (`references/delegation.md`): bir iki dosyalık iş yerinde yapılır, roller rol açmaz, scout soruları toplu sorulur ve önce `lookup-cache.sh get` ile bakılır. Salt okunur roller dosya yazamaz; uzun cevabı orchestrator `run-role.sh --out` ile veya kendisi `work/<slug>/out/<rol>-<n>.md` altına yazar. Yazan roller (`engineer`, `developer`, `test-writer`, `devsecops`) uzun halini devir özetindeki `OUT:` yoluna koyar.

Önbellek: model önbelleği aynı önek ve aynı model için çalışır, ömrü kısadır. Devir özetinde sabit satırlar (ROLE, RISK, PROJECT-DIR, standart READ) başta, değişenler (TASK, DIFF-BASE, TESTS) sonda durur; bir dalgada aynı katmanın görevleri aynı modeli kullanır; dalganın açılışları birlikte yapılır; görev ortasında `project.md` ve kurallar değiştirilmez.

Ölçme yöntemi: sabit bir görevle **temel koşu** yap, `usage.sh report` çıktısını sakla, sonra **tek bir değişkeni** değiştir (bir rolün katmanı, `verifier-deep` yerine `verifier`, önbellek açık/kapalı, paralel/sıralı) ve aynı görevi tekrarla; raporları karşılaştır. Tahminle değil defterle karar ver.

Sınır: kurallar tasarım düzeyindedir; defter yalnızca host'un token bilgisini verdiği yerde dolar (bölüm 13).

---

## 19. Proje belleği

Hedef: ajanın her görevde yeniden keşfettiği, kodda görünmeyen bilgiyi tek yerde tutmak; ama her oturumda hepsini bağlama yüklememek. 1.0'dan itibaren yeni kurulumlarda **varsayılan açıktır** (`sdkit.env`'de `MEMORY=1`; `sdkit init --no-memory` ile kapanır). Eski bir repoda `sdkit upgrade` eksik ayarları varsayılanlarıyla ekler, yani belleği de açar; istemiyorsanız `MEMORY=` yapın.

| Katman | Yer | Ömür |
|---|---|---|
| Çalışma | Konuşma bağlamı | Bir oturum |
| Görev | `work/<slug>/` (`state.json`, `plan.md`, `notes.md`, `out/`, `lookups/`) | Kapanışa kadar; `/clear` ve sıkıştırmadan sağ çıkar, kapanışta silinir; kişisel, git'e girmez |
| Proje | `.sdkit/memory/` (`MEMORY_DIR`) | Kalıcı ve git'te; `memory.sh stale` eskiyenleri işaretler |
| Kişisel | Host'un kendi belleği (Claude'un kullanıcı düzeyi otomatik belleği, `.claude/memory/`) | Host belirler; kit dokunmaz. `.claude/memory.md` gibi bir yol Claude Code tarafından zaten okunmaz, bu yüzden kit yönlendirme dosyası üretmez: ajan `CLAUDE.md`/`AGENTS.md` bloğu ve oturum hook'u üzerinden `.sdkit/memory/INDEX.md`'ye gider |

**Proje belleği.** `memory/INDEX.md` her girdi için tek satır tutar; yalnızca bu dosya oturum başında bağlama girer (Claude'da `session-context` hook'u, diğer host'larda `AGENTS.md` bloğundaki "önce INDEX'i oku" yönlendirmesi). Girdi gövdesi, satırı ilgili görünce okunur. `INDEX.md` ayrıca `known-pitfalls.md` ve `adr/`'ye bağlanır; ikisi olduğu gibi kalır (verifier ve `incident-to-rule` bunlara bağlıdır). Girdi türleri: `fact` (koddan çıkmayan gerçek), `howto` (keşfedilmiş komut dizisi), `decision` (küçük karar; büyükleri ADR'ye).

Girdi dosyası `<slug>.md`'dir ve başlığında `type`, `title`, `updated`, `verify-by`, `refs` alanları bulunur. Girdi, `updated` tarihinde yapılmış bir iddiadır: koda aykırıysa koda güvenilir ve kullanıcıya girdinin düzeltilmesi gerektiği söylenir.

**Yazma.** Görev sırasında ajan öğrendiklerini `work/<slug>/notes.md`'ye `MEMORY: fact|howto|decision | <slug> | <başlık> | <bir iki cümle>` satırları olarak ekler. Kapanışta (`MEMORY_PROMOTE=ask`) orchestrator `memory.sh candidates <slug>` listesini gösterir, kullanıcı seçer, `memory.sh promote <slug> <n...|all>` ekler. Kullanıcı onayı olmadan kalıcı belleğe yazılmaz (`auto` bunu bilinçli olarak kaldırır). Gizli bilgi gibi görünen metin reddedilir; `MEMORY_INDEX_MAX` dolunca yeni girdi eklenmez, önce `memory.sh stale` ile temizlenir.

**Komutlar.** `memory.sh status|init|add|index|search|stale|autoload|candidates|promote` (bölüm 9'daki script ayrıntıları). `doctor` belleğin durumunu ve eskiyen girdileri raporlar. Ayrıntı ve orchestrator adımları: `skills/spec-driven-dev/references/memory.md`.

**Git.** Bellek `.sdkit/` içinde olduğu için varsayılan olarak git'te ve ekipçe paylaşılır (`MEMORY_VCS=commit`). Kişisel istenirse `MEMORY_VCS=ignore` (`init --memory-vcs ignore` `.sdkit/.gitignore`'a satırı yazar) ya da `MEMORY_DIR`'i `.sdkit/` dışına verin. Sonradan değiştirmek serbesttir.

Sınır: Bellek bir güvenlik sınırı değildir; secret taraması basit bir kalıp denetimidir.
