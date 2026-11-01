# Dokümantasyon haritası

Nereden başlayacağını role göre seç.

| Ben... | Oku | Sonra |
|---|---|---|
| Hazır bir repoda çalışacak **geliştiriciyim** | [cheatsheet.md](cheatsheet.md) | [guide.md](guide.md) §4 (akış), §7 (hook'lar neden engelledi?) |
| Yeni bir repoyu **kuracağım** | [../README.md](../README.md) "Quick start" | [guide.md](guide.md) §10 (ayarlar), §11 (kurulum), sonra `doctor.sh` |
| Bir **hata çözdüm**, tekrarını önlemek istiyorum | [guide.md](guide.md) §5 (`incident-to-rule`) | §8 (`verify.d` protokolü) |
| Bir hook veya guard'ın **neden çalıştığını/çalışmadığını** anlamaya çalışıyorum | [guide.md](guide.md) §7 | §12 (izin modeli), §13 (sınırlar) |
| Projemi **yeni kit sürümüne** yükseltmek istiyorum | [upgrading.md](upgrading.md) | `bin/upgrade.sh` |
| PR'ı **GitHub/GitLab**'a açmak istiyorum | [hosts.md](hosts.md) | |
| **Codex, OpenCode, Cursor veya Gemini** (ya da Claude ile karışık) kullanacağım | [guide.md](guide.md) §16 | §13 (host sınırları), [../skills/spec-driven-dev/references/hosts.md](../skills/spec-driven-dev/references/hosts.md) |
| Bir **stack**'in ne sağladığını öğrenmek / yeni stack eklemek istiyorum | [../stacks/README.md](../stacks/README.md) | [../CONTRIBUTING.md](../CONTRIBUTING.md), [guide.md](guide.md) §14 |
| **Paralel** çalışmak / token harcamasını ve proje belleğini ayarlamak istiyorum | [guide.md](guide.md) §17, §18, §19 | [../core/rules/token-economy.md](../core/rules/token-economy.md) |
| Bir **rol** eklemek/değiştirmek istiyorum | [../core/roles/README.md](../core/roles/README.md) | [guide.md](guide.md) §6, §14 |
| Kitin **ne kadar token/zaman harcadığını** ölçmek, benchmark koşturmak istiyorum | [design-telemetry.md](design-telemetry.md) | [guide.md](guide.md) §18 |
| Ajan **devir/sonuç sözleşmelerini** (`CONTRACTS=1`) anlamak, açmak | [design-contracts.md](design-contracts.md) | [../skills/spec-driven-dev/references/contract.md](../skills/spec-driven-dev/references/contract.md) |
| İş akışı **profillerini** (small/standard/high-assurance), faz geçişlerini, hata/yeniden deneme politikasını anlamak | [design-workflow.md](design-workflow.md) | [../skills/spec-driven-dev/references/workflow.md](../skills/spec-driven-dev/references/workflow.md) |
| **Yüksek riskte** reviewer/security-auditor zorlamasını, kanıt geçerliliğini ve host yetenek matrisini anlamak | [design-evidence.md](design-evidence.md) | [design-workflow.md](design-workflow.md) |
| Hangi **ajanın/modelin** çalışacağını, bütçeyi, yeniden denemeyi ve yükseltmeyi (F06) anlamak | [design-routing.md](design-routing.md) | [design-evidence.md](design-evidence.md) |
| Aynı görevi **ajanlı geliştirme ile SDKit'in** çözdüğü doğruluk ve maliyet karşılaştırmasını (benchmark altyapısı, F05-A) anlamak | [design-benchmark.md](design-benchmark.md) | [design-telemetry.md](design-telemetry.md) |
| **Kit'in kendisini** değiştireceğim | [../CONTRIBUTING.md](../CONTRIBUTING.md) | [guide.md](guide.md) §14, §15 |

## Dosyalar

| Dosya | İçerik |
|---|---|
| [cheatsheet.md](cheatsheet.md) | Tek sayfa: komutlar, risk tablosu, "X olduysa Y yap", sık sorunlar |
| [design-sdkit-dir.md](design-sdkit-dir.md) | Tasarım kaydı: tek `.sdkit/` dizini, kişisel `sdkit.env`, neyin git'e girdiği, doğrulamalar ve sapmalar (1.0.0) |
| [audit-architecture.md](audit-architecture.md) | Mimari ve yetenek denetimi (F00): bileşen haritası, yetenek envanteri, yaşam döngüleri, bulgular, öncelikli liste, önerilen ADR'ler |
| [design-routing.md](design-routing.md) | Akıllı orkestrasyon (F06): karar motoru, model kayıt defteri, yürütme sözleşmesi, yeniden deneme/yükseltme, bütçe (sert/danışma), yönlendirme matrisi, güven sınırları |
| [design-benchmark.md](design-benchmark.md) | Görev benchmark'ı (F05-A): görev kaydı, yalıtım ve güvenlik sınırı, stratejiler, metrikler (host başına), simülasyon, rapor, F05-B önkoşulları |
| [design-telemetry.md](design-telemetry.md) | Temel ölçüm ve telemetri (F01): olay şeması, hangi metrik güvenilir, benchmark çerçevesi, simüle sonuçlar, sınırlar, F02 önerileri |
| [design-contracts.md](design-contracts.md) | Ajan sözleşmeleri (F02): devir/sonuç biçimi, doğrulama kategorileri, host durumu, benchmark ek yükü, geçiş, sınırlar |
| [design-report.md](design-report.md) | Value Report: görev/oturum raporu, ölçülen ve tahmin ayrımı, tasarruf metodolojisi, tek seferlik üretim, sınırlar |
| [design-evidence.md](design-evidence.md) | Kanıt bütünlüğü (F04): yüksek risk zorlaması, güven sınırı, geçerlilik durumları, atomiklik, host yetenek matrisi, kabul edilen sınırlar |
| [guide.md](guide.md) | Tam rehber: her skill, agent, hook, motor, ayar, kurulum akışı, sınır |
| [upgrading.md](upgrading.md) | Projeleri yeni kit sürümüne yükseltme, sürüme göre elle yapılacaklar |
| [hosts.md](hosts.md) | PR host'ları (Bitbucket hazır; GitHub/GitLab notları) |
| [../stacks/README.md](../stacks/README.md) | Stack sözleşmesi: `detect.sh`, `steps.sh`, `tools.sh`, `permissions.txt` |
| [../tests/run.sh](../tests/run.sh) | Kit bakımcıları için betik/hook/init smoke testi |

## Sözlük

| Terim | Anlamı |
|---|---|
| **DoD** | Definition of Done: `proposal.md`'deki, test veya diff ile PASS/FAIL denebilen kabul koşulları |
| **Risk etiketi** | `low` / `medium` / `high`. Proje rubriğine göre önerilir, kullanıcı onaylar; doğrulama derinliğini belirler |
| **Verifier** | Gerçekleştirmeyi görmemiş, DoD'yi ve diff'i bağımsız değerlendiren agent |
| **Diff tabanı** | Değişikliğin kıyaslandığı ref (`resolve-base.sh`): release branch'i veya `origin/BASE_BRANCH` |
| **Frozen test** | `high` riskte yazılıp `<project-dir>/.frozen`'a eklenen, uygulayıcının değiştiremediği regresyon testi |
| **`verify.d`** | Projenin kendi kontrolleri: `<project-dir>/verify.d/` altında `FAIL:`/`WARN:` basan çalıştırılabilir betikler |
| **Rol** | `core/roles/` altında araçtan bağımsız tanımlı ajan sorumluluğu; her host için subagent dosyasına üretilir |
| **Katman (tier)** | Rolün maliyet sınıfı: `light` / `standard` / `strong`; `core/tiers.env` modele eşler |
| **Plan kapısı** | `propose`'dan önce planın sana detaylıca sorularak onaylandığı adım |
| **Dalga (wave)** | Birbirinden bağımsız, yazma yolları çakışmayan ve paralel çalışabilen görev grubu |
| **Host** | Kit'in çalıştığı ajan aracı: Claude Code, Codex, OpenCode, Cursor veya Gemini CLI. (PR host'u ayrıdır: Bitbucket vb.) |
| **Stack** | Dil/framework parçası: `go`, `spring-boot`, `nextjs`, `react-native`; repo başına bir tane |
| **`verifier-deep`** | `verifier`'ın strong katmanlı üretilmiş ikizi; `high` riskte kullanılır |
| **`state.json`** | `work/<slug>/state.json`: görev durumu, devam etme ve tek otomatik yeniden deneme |
| **Pitfall** | `known-pitfalls.md`'deki, verifier'ın her diff'te aradığı geçmiş hata sınıfı |
| **Plugin / copy modu** | Kit'in plugin olarak mı yoksa repoya kopyalanarak mı kullanıldığı |
