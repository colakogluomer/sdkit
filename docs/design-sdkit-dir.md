# Tasarım: `.sdkit/` tek proje dizini

Durum: **uygulandı, 1.1.0** (1.0.0 + ortak/kişisel ayar ayrımı, §9). Aşağıdaki kararlar kodda; sapmalar §9'da. Kullanıcıya dönük anlatım: `guide.md` §3 ve §15, geçiş: `upgrading.md` (1.0.0).

## 1. İlke

1. **`.sdkit/` kitin tek proje dizinidir ve repoya girer; içeriği herkeste aynıdır.** Projeyle ilgili ortak her şey orada durur: kurallar, pitfall'lar, ADR'ler, doğrulama politikaları, proje belleği.
2. **Yalnızca kişiye özel olanlar girmez** (`.sdkit/.gitignore` ile): `sdkit.local.env` (bütçeler, limitler, memory davranışı ve host/model seçimi kişiden kişiye değişir), `work/` (görev durumu, defter, geçici bellek) ve çalışma zamanı dosyaları.
3. **Host dizinlerinde (`.claude/`, `.codex/`, `.cursor/`, `.gemini/`, `.opencode/`) yalnızca en temel `.md` giriş dosyaları repoya girer** (`CLAUDE.md`, `AGENTS.md`).
   Kitin oraya ürettiği geri kalan her şey (kurallar kopyası, hook, rol, ayar, bağlantı) repoya girmez: `sdkit init` onu herkeste aynı üretir, üretmiyorsa da aynıdır, commit'lemenin değeri yoktur.
4. **Güncellemelerin hedefi hep `.sdkit/`'tir.** Ajan bir pitfall, karar ya da bellek girdisi eklerken `.sdkit/` altındaki dosyaya yazar; host dizinindeki hiçbir dosyaya değil.
5. Hedef: desteklenen her aracı temel seviyede desteklemek. Aynı projede kimi geliştirici Claude, kimi Codex kullanabilir; ortak içerik araçtan bağımsız `.sdkit/`'te durur, her araç ona kendi yoluyla bağlanır.

## 2. Sorun (neden değişiyor)

- Bugün kit dosyaları host'un kendi dizinine yazılır ve projenin kendi içeriğiyle karışır; kaldırmak için `.scaffold-manifest` ile ayıklanır.
- Dizin adı kuruluma göre değişir (`.claude`, `.codex`, `.agentkit`), bu yüzden 12 script bir çözücü döngüsü taşır ve belgeler `<project-dir>` der.
- Bağlayıcı içerik host dizinine bağlı: Codex kullanan biri `.claude/project.md`'yi bilemez.
- `project.env` hem proje gerçeklerini hem kişisel ayarları taşır; var olan dosyaya yeni anahtar eklenemediği için eski kurulumlar yeni ayarlardan habersiz kalır.

## 3. Düzen

```
<repo>/
├── AGENTS.md                tüm araçlar için giriş: kısa harita + kit bloğu          (repoda)
├── CLAUDE.md  (.claude/CLAUDE.md)  Claude için giriş: aynı kit bloğu               (repoda)
├── .sdkit/                                                                            (repoda, ayrıca aşağıdaki hariçler)
│   ├── .gitignore           aşağıdaki kişisel dosyaları gizler; kökteki *.env kuralını sdkit.env için ayrıca ele alır
│   ├── project.md           risk ölçeği, release akışı, PR/test düzeni
│   ├── rules/               projeye özgü kurallar (kitin varsayılanları kitten gelir, buraya kopyalanmaz)
│   ├── known-pitfalls.md    adr/    verify.d/    roles.d/
│   ├── memory/              kalıcı proje belleği: INDEX.md + girdiler (fact, howto, decision)
│   │
│   ├── sdkit.env            EKİBİN ortak ayarları (git'te): STACK, release akışı, korunan yollar/branch'ler, prod cluster, secret kalıpları ...
│   ├── sdkit.local.env      KİŞİSEL (ignore, sdkit.env'den sonra okunur): bütçeler, limitler, MAX_PARALLEL, memory davranışı, host/model seçimi
│   ├── work/                KİŞİSEL (ignore): görev durumu, plan, notlar (geçici bellek), token defteri, scout önbelleği
│   └── scripts/ hooks/ roles/ tiers.env  .frozen  .verify-cache/  .sdd/      ÜRETİLMİŞ (ignore): kurulumdan yeniden üretilir
└── .claude/ .codex/ .cursor/ .gemini/ .opencode/ .githooks/    kitin yazdığı her şey ÜRETİLMİŞ (yerel ignore); projenin kendi dosyaları ne ise o
```

### Neyin repoya girdiği

| Dosya | Repoda | Neden |
|---|---|---|
| `AGENTS.md`, `CLAUDE.md` | evet | Her araç aynı haritayı ve kuralı görür; kurulumu olmayan biri bile `.sdkit/`'e yönlenir |
| `.sdkit/project.md`, `rules/`, `known-pitfalls.md`, `adr/`, `verify.d/`, `roles.d/`, `memory/` | evet | Ekip için ortak; zamanla güncellenir, değişiklik PR'da görünür |
| `.sdkit/sdkit.local.env`, `work/` | hayır | Kişiye özel |
| `.sdkit/sdkit.env` | evet | Ekibin makine-okunur politikası |
| `.sdkit/scripts/ hooks/ roles/ tiers.env`, `.frozen`, `.verify-cache/`, `.sdd/` | hayır | Üretilmiş ya da çalışma zamanı |
| host dizinlerinde kitin ürettiği ayar, hook, rol, kural kopyası | hayır | `init` herkeste aynısını üretir |
| host dizinlerinde projenin kendi skill, command, agent dosyaları | kit karışmaz | Projeye aittir |

Host tarafındaki ignore `.git/info/exclude` ile yapılır (yerel, `init` yazar); projenin `.gitignore`'una dokunulmaz.

## 4. Bellek ve güncellemeler

Güncellenebilir her şey `.sdkit/` altında tek yerde yaşar; ajanın yazacağı hedef hep orası:

| İçerik | Dosya | Yazan |
|---|---|---|
| Kalıcı proje belleği | `.sdkit/memory/` | `memory.sh add/promote` (kapanışta kullanıcı onayıyla) |
| Geçici (görev) bellek | `.sdkit/work/<slug>/notes.md` | ajan görev sırasında; kişisel, kapanışta aday çıkarılır |
| Hata sınıfları | `.sdkit/known-pitfalls.md` | `incident-to-rule` |
| Kararlar | `.sdkit/adr/` | engineer / kullanıcı |
| Doğrulama politikaları | `.sdkit/verify.d/` | kullanıcı |

### Host yönlendirmesi
Ajan belleğe iki yoldan gider; ikisi de git'te olan ya da ajanın kendi oturumunda çalışan şeylerdir:

- **Giriş dosyaları (repoda):** `AGENTS.md` ve `.claude/CLAUDE.md` içindeki kit bloğu "önce `.sdkit/memory/INDEX.md`'yi oku, kuralları `.sdkit/rules/`'ten oku, yazarken `memory.sh` / `incident-to-rule` / `adr/` ile `.sdkit/`'e yaz" der.
- **Oturum hook'u (Claude):** `session-context.sh` `INDEX.md`'yi bağlama koyar.
- Claude Code `.claude/memory.md` gibi bir yolu okumaz (belgelerle doğrulandı, §9), bu yüzden o yönde yönlendirme dosyası üretilmez.
- Aracın kendi kişisel belleği (Claude'un kullanıcı düzeyi otomatik belleği) kitin kapsamı dışındadır; blok kalıcı proje bilgisinin `.sdkit/`'e yazılmasını ister.

## 5. `sdkit.env` ve eksik anahtarlar

- `project.env` yerine `.sdkit/sdkit.env` (ekip, commit'li) ve `.sdkit/sdkit.local.env` (kişisel, ignore, sonra okunur).
- `init` ve `upgrade`, şablonda olup dosyada olmayan anahtarları mevcut değerlere dokunmadan sona ekler (yorumlu blok). `doctor` eksik anahtarı bildirir.
- Proje gerçekleri (risk ölçeği, release akışı, `PROTECTED_PATHS`, `SECRET_GLOBS`) hem `.sdkit/project.md`'de (insan okur, repoda) durur; `sdkit.env` bunları algılamadan ve `project.md`'den doldurur, çelişirse `doctor` uyarır.

## 6. Çözücü ve geriye uyum

Tek yardımcı (`bin/lib.sh`, `hooks/lib.sh`); 12 script'teki döngü ona iner. Sıra: `.sdkit/`, sonra eski `.agentkit`, `.claude`, `.codex` içindeki `project.env`.
Eski düzen çalışmaya devam eder; `doctor` uyarı verir. `sdkit upgrade --migrate` (varsayılan `--dry-run`, önce arşiv yedeği): kit dosyalarını `.sdkit/`'e `git mv` ile taşır, `project.env`'i `sdkit.env` yapar,
host bağlantılarını yeniden yazar, eski kit kopyalarını host dizinlerinden kaldırır. Projenin kendi skill, command ve agent dosyalarına dokunmaz.

## 7. CI kapısı

Önceki konuşmada "tamamen kaldır" kararı verilmişti, ama o karar `.sdkit/`'in repoya girmeyeceği varsayımına dayanıyordu. `.sdkit/` repoya girdiğine göre `attestations/` orada durabilir ve sunucu tarafı kapı çalışabilir.
**Karar gerekiyor** (§9, soru 1). Varsayılan öneri: kapı **kalsın, isteğe bağlı** (`init --ci`), `attestations/` `.sdkit/` altında repoda.

## 8. Etki

| Alan | İş |
|---|---|
| Çözücü | `bin/lib.sh`, `hooks/lib.sh` ve 10 script'teki döngü tek yardımcı olur |
| Şablonlar | `templates/sdkit.env`, `templates/sdkit.gitignore`, giriş dosyası blokları (`AGENTS.kit.md`, `CLAUDE.kit.md`); `claude.gitignore` kalkar |
| `init` / `upgrade` / `doctor` / `sync` | yeni düzen, yerel ignore, eksik anahtar ekleme, `--migrate`, host yönlendirmeleri |
| Hook ve skill'ler | `<project-dir>` yerine `.sdkit`; `project.env` → `sdkit.env` (105 dosyada geçiyor, `project.md` 69'unda) |
| Yazan script'ler | `memory.sh`, `incident-to-rule` ve ADR şablonu hedefi `.sdkit/`'e sabitler |
| Test | `run.sh`, `shared.test.sh`, `memory.test.sh`, `budget.test.sh` yeni ve eski düzende; `migrate` ve karma host için yeni testler |
| Doküman | README, `docs/guide.md` (§3, §10, §15, §19), cheatsheet, `upgrading.md`; sayılar tek değişiklikte eşitlenir |

## 9. Kararlar ve uygulamadaki sapmalar

Kararlar (kullanıcı onayıyla):
- **CI kapısı ve attestation kalır**, isteğe bağlı (`init --ci`); `attestations/` ve CI için gereken iki script (`sdd.sh`, `resolve-base.sh`) `.sdkit/` içinde git'tedir. CI `sdkit.env`'i görmediği için varsayılanlarla çalışır.
- **Bellek:** `.sdkit/memory/INDEX.md` ve girdiler (tek dosya değil). Yeni kurulumlarda **varsayılan açık**; `USAGE_LOG` da açık. Limitler (`TOKEN_BUDGET_TASK`, `MAX_SPAWNS`, `SUBAGENT_RESULT_MAX_LINES`) boş; kit sayı dayatmaz.
- **Kitin varsayılan kuralları** (`core/rules`, stack kuralları) projede eksikse `.sdkit/rules/`'e kopyalanır (var olan dosyalar korunur); bunlar git'tedir ve proje düzenler.
- **Eski düzen** 1.x boyunca okunur (`.claude`/`.codex`/`.agentkit` + `project.env`); sonraki majör sürümde kalkması planlı.
- **Sürüm:** bu iş 1.0.0 olarak çıkar.

Doğrulama sonuçları (Claude Code belgelerine göre) ve sapmalar:
- `CLAUDE.md` içinden `@yol` içe aktarma çalışır, `settings.local.json` plugin, marketplace, izin ve hook'ları okur, `.claude/rules/*.md` otomatik yüklenir ve bağlar izlenir; **ama `.claude/memory.md` türü bir yol Claude Code tarafından okunmaz.**
- Bu yüzden **`.claude/memory.md` yönlendirme dosyası üretilmedi.** Belleğe giden gerçek yollar: oturum hook'u `INDEX.md`'yi bağlama koyar, kit bloğu (`CLAUDE.md` / `AGENTS.md`) "önce `.sdkit/memory/INDEX.md`'yi oku, yazarken `memory.sh` ile `.sdkit/`'e yaz" der.
- **`@AGENTS.md` içe aktarması kullanılmadı;** `CLAUDE.md` ve `AGENTS.md` aynı kit bloğunu taşır (yinelenen kısa metin, tek şablon kaynağından `__KIT_DIR__` ile üretilir).
- **Kurallar `.claude/rules/`'e bağlanmadı:** `.sdkit/rules/` Claude'da otomatik yüklenmez, blokta yol olarak listelenir ve ihtiyaç olunca okunur. Bu, her oturumda tüm kuralları bağlama yüklemeyen token ekonomisiyle uyumludur.
- Claude'un kit girdileri `settings.local.json`'a gider; **kullanıcının kendi `settings.json`'ına dokunulmaz.** Eski düzende (ve `--migrate`'ten önce) `settings.json` kullanılır.
- Host'un paylaşılan, proje dosyasına birleştirilen ayarları (`.codex/config.toml`, `.cursor/hooks.json`, `.gemini/settings.json`) diğer araçlarda yerel değişken olmadığı için yerinde birleştirilir; dosya zaten izleniyorsa kit değişikliği `git status`'ta görünür ve commit'lemek geliştiricinin kararıdır.

**1.1.0 değişikliği.** 1.0.0'da `sdkit.env` tamamen kişiseldi; gerçek bir repoda bunun ekibin politikasını (`BASE_BRANCH_MODE=release`, `PROTECTED_BRANCHES`, `PROD_KUBE_CLUSTERS`, `PROTECTED_PATHS`, `SECRET_GLOBS`, `SERVICES_DIR` ...) tek makinede bıraktığı görüldü; arkadaşları `sdkit init` çalıştırınca bu korumalar varsayılana düşerdi. Karar: `sdkit.env` ortak ve commit'li, kişisel anahtarlar (`templates/sdkit.local.env`) `sdkit.local.env`'de. `init`/`upgrade`/`migrate`, 1.0.0 tek dosyasını `split_personal_env` ile böler.

## 10. Riskler

- **Büyük yüzey** (çözücü 11 script + hook + git hook + OpenCode eklentisi; 105 dosyada ad değişikliği). Önlem: eski düzen testlerle korunur, yeni düzen için `tests/sdkit-dir.test.sh`.
- **Eski sürüm.** 0.5.x kurulu bir makine yeni düzende `sdkit.env` bulamaz; `upgrading.md` yazar.
- **`--migrate`** yanlış dosyayı taşımasın diye yalnızca kitin bilinen adlarını ve manifest'teki dosyaları taşır, önce arşiv yedeği alır, varsayılan kuru koşudur.
- **Karma ekip:** bir geliştiricide kit yoksa yalnızca commit'li `AGENTS.md` / `CLAUDE.md` bloğunu ve `.sdkit/` belgelerini görür; hook ve roller yoktur, kural belgede durur.
