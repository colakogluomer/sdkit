# Akıllı orkestrasyon ve maliyet bilinçli yönlendirme (F06)

Bu belge `scripts/route.sh` (karar motoru), `core/adapters.json` (yürütme sözleşmesi) ve `scripts/run-role.sh`'ın bu kararı nasıl tükettiğini anlatır.
Kısa özet: **çekirdek politikayı sahiplenir, adaptörler yetenek bildirir, sağlayıcılar çalıştırır.** Hiçbir karar için model çağrılmaz.

## 1. Neyi çözer, neyi çözmez

| Soru | Cevap veren | Model çağrısı |
|---|---|---|
| Sıradaki rol zorunlu mu? | `workflow.sh policy` (risk + profil); `route.sh` yalnızca okur | yok |
| Hangi adaptör ve model? | `route.sh` (kayıt defteri + risk + rol + tercih) | yok |
| Çalıştırılsın mı, yeniden kullanılsın mı? | `route.sh` (`sdd.sh evidence` durumu) | yok |
| Hata sonrası yeniden dene / yükselt / dur? | `route.sh` (hata sınıfı + sınırlar) | yok |
| Bütçe izin veriyor mu? | `route.sh` (kullanım defteri + ayarlar) | yok |

Eklenen **zorunlu** model çağrısı: 0. Karar başına maliyet yalnızca yerel süreçlerdir (ölçüm: §10).

Kapsam dışı (bilerek): LiteLLM, FusionCLI veya herhangi bir vekil/ağ geçidi; harici orkestrasyon servisi; eşzamanlı ajan zamanlayıcısı; F07/F08.

## 2. Mimari

```
                 sdkit.env (ROUTING, ROUTE_*)         core/tiers.env + <project-dir>/models.json  (kayıt defteri)
                              │                                        │
 workflow.sh policy ──► ┌──────────────┐ ◄── sdd.sh evidence      core/adapters.json (yetenekler)
 (risk, profil,         │   route.sh   │ ◄── usage.jsonl (kullanım)
  zorunlu roller)       │   decide     │ ◄── work/<görev>/routing.jsonl (önceki denemeler)
                        └──────┬───────┘
                               │ karar (JSON): action, adapter, model, tier, budget, attempt, reason, policy_version
                               ▼
                        run-role.sh ──► ana makine CLI'ı (claude | codex | opencode | cursor-agent | gemini) ──► sağlayıcı
                               │ süreç bitince
                               ▼
                        route.sh outcome  (hata sınıfı, süre, token: yoksa null)  ──► sonraki karar bunu okur
```

`ROUTING=on` iken `run-role.sh` kararı **tüketir**: ana makine, model, katman, zaman aşımı ve bekleme kararın içinden gelir; `execute|retry|escalate`
dışındaki bir karar hiçbir şey başlatmaz. `route.sh` yoksa veya karar üretmezse `run-role.sh` **çalışmaz** (exit 2): politika sessizce atlanmaz.

## 3. Karar yaşam döngüsü

`route.sh decide --role R` sırayla şunları değerlendirir; ilk kesin cevap kazanır:

1. Ayar ve kayıt defteri doğrulaması (`CONFIG_INVALID`), rol metni (`UNKNOWN_ROLE`).
2. Görev gerçekleri: risk, profil, zorunluluk (`workflow.sh policy --json`). Açık görev yoksa risk **orta varsayılır** ve ucuzlatma yapılmaz.
3. **Kanıt** (yalnızca verifier/reviewer/security-auditor):
   bu diff için bir BLOCK duruyorsa → `stop` (`SECURITY_BLOCK` / `VERIFICATION_FAILED`); `--rerun` ve başka sağlayıcı bunu değiştirmez.
   `sdd.sh evidence` durumu `valid` ise → `reuse` (`EVIDENCE_REUSED`). `stale|untrusted|conflict|missing` ise çalıştır.
4. **Zincir** (aynı rol + aynı handoff + gerekirse aynı diff = aynı istek): uçuştaki çalıştırma varsa `DUPLICATE_IN_FLIGHT`; tamamlanmış aynı istek `DUPLICATE_COMPLETED`
   (`--rerun <neden>` ile aşılır); önceki başarısızlık sınıfına göre `retry` / `escalate` / `stop` (§6).
5. **Katman**: rolün kendi katmanı → `--tier` (bağımsız roller kendi katmanının altına inmez) → risk tabanları (`ROUTE_FLOOR_*`; yüksek riskte verifier derin katman).
6. **Adaptör ve model**: aday adaptörler (`--host` > tercih > sabit politika > `VERIFIER_HOST`/`RUN_ROLE_HOST` + `ROUTE_FALLBACK_HOSTS`); gerekli yetenekler; kayıt defterinden
   rolü destekleyen, **gereken katmana eşit veya üstü** en düşük katmanlı kayıt. Daha alt katman asla ikame edilmez.
7. **Bütçe** (§8). Zorunlu rol bütçe nedeniyle çalışamıyorsa `BUDGET_EXHAUSTED` (exit 3): görev durumu değişmez, sahte PASS yazılmaz.
8. `--reserve` ile karar defterine yazılır, çağrı sayısı artar (kilit altında: iki eşzamanlı istek aynı çalıştırmayı başlatamaz).

Çıktı (kısaltılmış): `decision_id, task, role, role_class, mandatory, risk, profile, action, adapter, model, effort, tier, tier_enforced, timeout_s, budget, attempt, wait_s, reason, policy_version`
(+ `previous`, `notes`, `warnings` gerektiğinde). Her karar tek bir **neden kodu** taşır.

### Neden kodları

| Eylem | Kodlar |
|---|---|
| execute | `ROLE_CAPABILITY_MATCH`, `RISK_FLOOR_APPLIED`, `DOWNGRADE_LOW_RISK`, `PREFERENCE_APPLIED`, `OVERRIDE_APPLIED`, `FIXED_POLICY`, `ADAPTER_FALLBACK`, `RERUN_REQUESTED` |
| retry | `RETRY_TRANSIENT`, `RETRY_RATE_LIMIT`, `RETRY_TIMEOUT`, `RETRY_INTERRUPTED`, `RETRY_INVALID_OUTPUT`, `RETRY_CONTRACT_FAILURE`, `ADAPTER_FALLBACK` |
| escalate | `ESCALATE_INVALID_OUTPUT`, `ESCALATE_CONTRACT_FAILURE` |
| stop (exit 3) | `BUDGET_EXHAUSTED` |
| stop (exit 2, politika/yapılandırma reddi) | `CONFIG_INVALID`, `UNKNOWN_ROLE`, `NO_ADAPTER`, `ADAPTER_UNSUPPORTED`, `NO_COMPATIBLE_MODEL`, `OVERRIDE_INVALID`, `OVERRIDE_BELOW_FLOOR`, `PREFERENCE_INVALID`, `PREFERENCE_BELOW_FLOOR`, `FIXED_INVALID`, `FIXED_BELOW_FLOOR`, `NO_ESCALATION_TARGET` |
| reuse (exit 7) | `EVIDENCE_REUSED` (yukarıda) |
| stop (exit 8, çalıştırılmadı, geçerli sonuç yok) | `SECURITY_BLOCK`, `VERIFICATION_FAILED`, `DUPLICATE_IN_FLIGHT`, `DUPLICATE_COMPLETED`, `RETRIES_EXHAUSTED`, `ESCALATION_LIMIT`, `REPORTED_FAILURE`, `UNCLASSIFIED_FAILURE`, `OPTIONAL_SKIPPED` |

`run-role.sh` / `route.sh decide` çıkış kodları: ana makinenin kodu | 3 bütçe | 2 politika/yapılandırma reddi | **7 geçerli kanıt yeniden kullanıldı** (başarı benzeri: çalıştırılacak/yeniden denenecek bir şey yok; `state.sh retry` çağrılmaz) |
**8 yönlendirme çalıştırmamaya karar verdi ve geçerli sonuç yok** (kopya, duran BLOCK, deneme/yükseltme bitti, isteğe bağlı rol atlandı): asla başarı sayılmaz. Hiçbiri tek başına "doğrulandı" demek değildir; kapıyı `sdd.sh evidence` / faz kapısı belirler.
(F06'da 7 her iki durumu da kapsıyordu; F06.1'de ayrıldı. Çağıran olarak yalnızca `bench/run.sh` var ve yönlendirmeyi hiç açmaz; diğer çağıranlar orkestratör talimatlarıdır: `hosts.md`, `model-routing.md`.)

## 4. Kayıt defteri (model)

Varsayılan kayıtlar `core/tiers.env`'den **türetilir**; kit model adı, fiyat veya bağlam sınırı uydurmaz.

| Alan | Anlam |
|---|---|
| `id` | tekil kimlik (`claude:standard`) |
| `adapter` / `provider` | yürütme adaptörü / bilinen sağlayıcı ipucu (`core/adapters.json`) |
| `model` | `--model` değeri; `null` = ana makinenin varsayılan modeli |
| `effort` | yalnızca codex: akıl yürütme eforu (katman bununla ayrılır) |
| `tier` | `light|standard|strong`; `*` = "ana makine varsayılanı", katman **doğrulanamaz** (`tier_enforced:false`, karar `MODEL_INHERITED` uyarısı taşır) |
| `roles` | `"*"` veya rol listesi |
| `status` | `available|disabled` |
| `cost` | yalnızca kullanıcının `pricing.json` tablosunda varsa; yoksa `null` |
| `usage_accounting` | adaptörün token raporlama yeteneği |
| `context`, `tools` | bilinmiyorsa `null` / `true` |

Projeye özel girdiler `<project-dir>/models.json` (JSON dizisi) içine yazılır; aynı `id` türetilmişi **ezer**, yeni `id` eklenir. Örnek:

```json
[
  {"id": "gem:fast", "adapter": "gemini", "model": "<sizin-model-kimliğiniz>", "tier": "light", "roles": ["scout", "analyst"]},
  {"id": "claude:strong", "adapter": "claude", "model": "opus", "tier": "strong", "status": "disabled"}
]
```

`route.sh registry` kaydı, `route.sh validate` ayarları ve `models.json`'ı denetler.

## 5. Yürütme sözleşmesi (adaptörler)

`ExecutionAdapter` kavramsaldır; yeni bir çerçeve yoktur. Karşılıkları: `capabilities()` = `core/adapters.json`, `execute()` = `run-role.sh`'ın ana makine kolu,
`usage()` = o koldaki token ayrıştırması, `cancel()` = **yok** (hiçbir adaptör iddia etmez).

Değerler (F06.1): `help-verified` = yeteneğin ihtiyaç duyduğu **her bayrak** o makinede kurulu CLI'ın `--help` çıktısında bulundu (sürüm `core/adapters.json` `_checked` içinde); davranış **çalıştırılmadı**;
`declared` = kit bayrağı/çıktıyı ana makinenin belgelenmiş başsız moduna göre kullanır, bu makinede **hiç denetlenmedi** (CLI kurulu değil); `estimated` = rapor edilir ama yalnızca ana makinenin kendi istemci tarafı tahmini, fatura değil;
`kit` = kit sağlar; `none` = desteklenmez. Hiçbir değer "canlı modelle uçtan uca çalışıyor" demek değildir. `route.sh capabilities --probe` kurulu CLI'ların `--help`'ini okuyarak bayrakları yeniden denetler (model çağrısı yok);
eksik bayrak adıyla raporlanır, kurulu olmayan CLI "doğrulanmadı" kalır. `tests/route.test.sh` iddiaları `run-role.sh`'ın komut satırına ve probe'a karşı sınar.

| Yetenek | claude | codex | opencode | cursor | gemini |
|---|---|---|---|---|---|
| noninteractive (`-p` / `--sandbox` / `--dir`) | **help-verified** (2.1.316) | declared | declared | declared | declared |
| tool_use (salt okunur/yazma bayrakları) | **help-verified** | declared | declared | declared | declared |
| model_selection | **help-verified** | declared (`-m`; kademe için eforu da) | declared | declared | declared |
| structured_output (`--output-format json`) | **help-verified** (`json` seçeneği `--help`'te) | none | none | declared | declared |
| usage_reporting (token) | declared (JSON biçimi `--help`'te yok, çalıştırılmadı) | none | none | none | declared |
| cache kullanımı | declared | none | none | none | none |
| cancellation | none | none | none | none | none |
| timeout | kit | kit | kit | kit | kit |
| cost_reporting | **estimated** (`total_cost_usd`, aşağıda) | none | none | none | none |

Doğrulama durumu (2026-10-31): bu makinede yalnızca `claude` kurulu; codex, opencode, cursor-agent ve gemini **kurulu değil**, bu yüzden onların tüm yetenekleri `declared` (doğrulanmadı) kalır.

`timeout` yalnızca makinede `timeout` veya `gtimeout` varsa **sert**; yoksa karar bunu `advisory` olarak işaretler.
Gelecekteki adaptörler (OpenAI uyumlu ağ geçidi, LiteLLM, yerel model, kurumsal sağlayıcı) `adapters.json`'a bir kayıt ve `run-role.sh`'a bir kol eklenerek bağlanır; şimdi eklenmedi.

### 5.1 Maliyet telemetrisi (F06.1)

Claude Code'un `--output-format json` çıktısındaki `total_cost_usd`, belgelere göre ([cost-tracking](https://code.claude.com/docs/en/agent-sdk/cost-tracking.md)) **istemci tarafı tahmindir, fatura değildir**
(abonelik/Max kuralları, fiyat değişimi, bilinmeyen model, üçüncü taraf sağlayıcı farklılıkları yüzünden gerçek faturadan sapabilir) ve `--resume`/`--continue` ile **kümülatiftir**.
`run-role.sh` oturum sürdürmez (her çalıştırma yeni oturum), bu yüzden değer çalıştırma başınadır. **Bu alan bu makinede canlı bir model çağrısıyla doğrulanmadı** (ücretli çağrı yasak); anlamı belgeden, ayrıştırma sahte CLI ile sınanmıştır.

Üç şey **ayrı** tutulur: (1) kit'in `pricing.json` fiyat tablosundan token'larla hesapladığı `estimated_usd`; (2) ana makinenin kendi tahmini `host_reported_estimate_usd` (`usage.jsonl`'da `cost_est_usd` + `cost_src:"host-estimate"`,
`routing.jsonl`'da `host_cost_estimate_usd` + `cost_provenance`); (3) gerçekte faturalanan `actual_usd`, daima `null` (hiçbir kaynak bunu bildirmez). Sayısal olmayan/negatif/eksik değer **yazılmaz** (sıfır yazılmaz).
`ROUTE_BUDGET_COST` aşımında uyarı kaynağı belirtilir (`COST_HOST_ESTIMATE_OVER_BUDGET`: "kendi istemci tarafı tahmini, fatura değil") ve hiçbir zaman durdurmaz.
Not: `claude --max-budget-usd` (yalnızca print kipi, istemci tarafı tahmine göre, geçilebilir) kullanılmadı; kit'in sert bütçe sınırı yerine geçmez.

## 6. Yeniden deneme ve yükseltme

`run-role.sh` her çalıştırmanın sonunda `route.sh outcome` ile sonucu **sınıflandırarak** kaydeder; sonraki istek bu sınıfı okur.

| Sınıf | Nasıl belirlenir | Sonraki karar |
|---|---|---|
| `OK` | exit 0, BLOCK değil | aynı istek tekrar gelirse `DUPLICATE_COMPLETED` (kanıt rolleri için kanıt durumu belirler) |
| `TRANSIENT` | stderr: 502/503/504, bağlantı sıfırlandı, ağ ... | aynı modelle `retry`, en çok `ROUTE_MAX_RETRIES` (2) |
| `RATE_LIMIT` | stderr: 429, rate limit, quota, overloaded | `retry` + `wait_s` geri çekilme (`ROUTE_BACKOFF_S` × deneme) |
| `TIMEOUT` | exit 124 veya stderr timeout/deadline | `retry` (aynı sınır) |
| `INTERRUPTED` | karar var, süreç öldü, sonuç yok | `retry` |
| `INVALID_OUTPUT` | exit 6 (geçerli verdict bloğu yok) | bir `retry`, sonra `escalate` (`ROUTE_MAX_ESCALATIONS`, 1) |
| `CONTRACT_FAILURE` | exit 4 | aynı |
| `HOST_MISSING` | exit 127 | `ROUTE_FALLBACK_HOSTS`'taki sonraki adaptör, yoksa `stop` |
| `REPORTED_FAILURE` | exit 5 (geçerli ama partial/blocked/failed) | `stop`: bu bir **kod düzeltme** kararıdır (`state.sh retry`), altyapı yeniden denemesi değil |
| `VERIFICATION_FAILURE` | verifier/reviewer BLOCK | `stop` |
| `SECURITY_BLOCK` | security-auditor BLOCK | `stop`; sağlayıcı/model değiştirmek BLOCK'u PASS yapmaz |
| `BUDGET_EXHAUSTED` | exit 3 | bütçe yeniden değerlendirilir |
| `UNKNOWN` | açıklanamayan hata | `stop` (`UNCLASSIFIED_FAILURE`): kör yeniden deneme yok |

- Altyapı yeniden denemeleri (`ROUTE_MAX_RETRIES`) kod düzeltme yeniden denemesinden (`state.sh retry`, tek hak) **ayrıdır** ve onu tüketmez.
- Zincir toplamı `ROUTE_MAX_ATTEMPTS` (4) ile sınırlıdır. Aynı handoff'u kör tekrar etmek yoktur: her yeniden denemenin neden kodu ve `previous.failure_class` kaydı vardır.
- Yükseltme bir üst katmana gider, `ROUTE_ESCALATE_TO` (strong) ile sınırlıdır; ana makine varsayılan modeliyle çalışmış bir deneme (katman doğrulanamaz) yükseltilemez (`NO_ESCALATION_TARGET`).
- Yükseltme kanıt gerekliliğini gevşetmez: kanıt kapısı ve risk tabanları aynen geçerlidir. Tam bağlamı tekrarlamak gerekmez: kayıt yalnızca karar kimliği ve hata sınıfını taşır.

## 7. Zamanlama ve bağımsızlık

- **Zorunlu** (`mandatory:true`): yüksek riskte verifier, reviewer, security-auditor; orta/yüksek riskte veya `high-assurance` profilinde verifier. Bütçe yetmezse durur (`BUDGET_EXHAUSTED`), atlanmaz.
- **İsteğe bağlı**: scout, analyst ve yüksek risk altında reviewer/security-auditor. Görev token bütçesi uyarı seviyesine (`TOKEN_BUDGET_WARN_PCT`) ulaşınca `OPTIONAL_SKIPPED` ile **gerekçeli** atlanır (`--rerun` ile zorlanır).
- **Tamamlanmış**: geçerli güvenilir kanıt varsa `reuse`; bayat kanıt asla yeniden kullanılmaz.
- Aynı modeli birden çok role yönlendirmek bağımsızlığı bozmaz: kimlik `run-role.sh`'ın süreç sahipli koşu kimliği ve rol başına kayıt ile (F04) korunur; rol ayrımı aynen zorlanır.

## 8. Bütçe anlamları: sert mi, danışma mı

| Sınır | Ayar | Sınıf | Ne zaman |
|---|---|---|---|
| Ajan çağrısı sayısı | `MAX_SPAWNS` | **sert** | süreç başlamadan önce sayılır |
| Deneme sayısı | `ROUTE_MAX_ATTEMPTS`, `ROUTE_MAX_RETRIES`, `ROUTE_MAX_ESCALATIONS` | **sert** | karar anında |
| Görev token bütçesi | `TOKEN_BUDGET_TASK` | sert **yalnızca** önceki tüm çalıştırmaların kullanımı raporlandıysa ve adaptör kullanım bildiriyorsa; aksi halde **danışma** | yeni çalıştırma bütçedeyken veya üstündeyken başlamaz; çalışan süreç kesilmez |
| Rol token bütçesi | `ROUTE_ROLE_TOKENS` | aynı | aynı |
| Süre | `ROUTE_TIMEOUT_S` | `timeout`/`gtimeout` varsa **sert**, yoksa danışma (kayıt) | süreç sarmalayıcıyla |
| Parasal | `ROUTE_BUDGET_COST` | **her zaman danışma**: kullanıcı `pricing.json` + token kullanımından **tahmin**; hiçbir adaptör gerçek maliyet bildirmez | uyarı üretir, durdurmaz |

Hesap kuralları: kullanım bildirmeyen çalıştırma **sıfır sayılmaz**, "ölçülmedi" sayılır (`usage.jsonl` satırında `tq:"unavailable"`, `routing.jsonl` sonucunda `tokens:null`).
Hepsi ölçülmediyse `used:null`; bir kısmı ölçülmediyse `accounting:"partial"` ve rakam alt sınırdır (`USAGE_PARTIAL`). Tahmini ve gerçek maliyet ayrı alanlardır (`estimated_usd` / `actual_usd:null`).

Bütçe tükenince: `BUDGET_EXHAUSTED` (exit 3), faz/durum değişmez, kanıt yazılmaz. Kurtarma: sınırı `sdkit.local.env`'de yükseltin (kayıp yok) veya kullanıcı onayıyla `--ignore-budget`
(yalnızca `SDD_MODE=strict`'te anlamlı; karar `BUDGET_OVERRIDDEN` uyarısıyla kaydedilir). `SDD_MODE=guided` yalnızca uyarır, `off` bütçeyi hiç değerlendirmez (eski davranışla aynı).

## 9. Ayarlar

Tümü isteğe bağlıdır; yalnızca `ROUTING=on` gerekir. Paylaşılan olanlar `sdkit.env`'de, kişisel sınırlar `sdkit.local.env`'de.

```
ROUTING=on                      # off (varsayılan): run-role.sh eskisi gibi çalışır
ROUTE_POLICY=tiered|fixed       # fixed + ROUTE_FIXED_MODEL=<kayıt id>: tekrarlanabilir deneyler için tek model
ROUTE_DOWNGRADE_LOW=0           # 1: düşük riskli iş rolleri bir kademe ucuza (varsayılan kapalı; F05 ölçümü gelene dek)
ROUTE_FLOOR_LOW/MEDIUM/HIGH     # risk başına en düşük kademe (light, light, standard)
ROUTE_FALLBACK_HOSTS="codex"    # seçilen ana makine çalışamazsa sırayla denenecekler
ROUTE_MAX_RETRIES=2  ROUTE_MAX_ESCALATIONS=1  ROUTE_ESCALATE_TO=strong  ROUTE_MAX_ATTEMPTS=4  ROUTE_BACKOFF_S=10
ROUTE_PREFER_DEVELOPER=claude:standard      # rol başına tercih (kayıt id); gereken kademeyi sağlamak zorunda
ROUTE_ROLE_TOKENS=  ROUTE_TIMEOUT_S=  ROUTE_BUDGET_COST=   # kişisel sınırlar
```

Açık geçersiz kılma: `run-role.sh --model M` yalnızca kayıt defterinde olan, kullanılabilir, gereken katmana eşit/üstü bir model olabilir; aksi halde `OVERRIDE_INVALID` / `OVERRIDE_BELOW_FLOOR`.
Hiçbir geçersiz kılma risk tabanını, kanıt kuralını veya zorunlu rolü aşmaz.

İnceleme (LLM çağırmaz, hiçbir şey kaydetmez):

```
$ route.sh explain --role developer --risk medium
Task: add-retry
Risk: medium (profile standard)
Role: developer (work)
Decision: execute
Adapter: claude
Model: sonnet (tier standard)
Reason: ROLE_CAPABILITY_MATCH
Budget: attempts=hard
Policy: route-v1  Routing: on
```

Diğer komutlar: `route.sh decide --json`, `outcome`, `classify`, `registry`, `capabilities`, `validate`, `log`.

## 10. Varsayılan yönlendirme matrisi (ölçüm iddiası yok)

Bunlar **muhafazakâr varsayılanlardır**, ölçülmüş kalite/maliyet sonucu değildir. Model sütunu `core/tiers.env` ile claude içindir; diğer ana makineler §4'e göre.

| Rol (sınıf) | Düşük risk | Orta risk | Yüksek risk | Tekrarlı hata |
|---|---|---|---|---|
| developer, test-writer, devsecops (iş) | standard (`ROUTE_DOWNGRADE_LOW=1` ile light) | standard | standard (`ROUTE_FLOOR_HIGH` ile üstü) | bir üst kademe, `ROUTE_ESCALATE_TO`'ya kadar |
| engineer, orchestrator (iş) | strong | strong | strong | zaten tavan |
| scout (arama) | light | light | light | — |
| analyst (arama) | standard | standard | standard | — |
| verifier (kapı) | standard | standard | **strong** (derin katman) | bir üst kademe |
| reviewer, security-auditor (kapı) | standard | standard | standard | bir üst kademe |

Kapı rolleri hiçbir koşulda kendi katmanının altına inmez. Düşük riskte ucuzlatma varsayılan olarak kapalıdır: F05-B sonuçları olmadan "tasarruf" iddia edilmez.

**Token etkisi**: zorunlu model çağrısı eklenmez (kararlar saf kabuk+jq). Gerçek model çağrısı **azalabilir** (geçerli kanıt yeniden kullanılır, kopya çalıştırma engellenir, BLOCK'lu diff'e boşuna doğrulama yapılmaz),
ama bu bir ölçüm değildir. Ölçülen belirleyici ek yük: bir `decide` ~0,4 sn duvar saati (macOS, ~50 yerel süreç), `run-role.sh` başına bir satır stderr. Rakamlar `tests/route.test.sh`'da değil, elle ölçüldü.

### Gecikme ölçümü (F06.1; macOS, bash 3.2, `jq` 1.8, 15 tekrar, medyan; yalnızca yerel süreçler)

| Parça | ms |
|---|---|
| boş `bash -c :` / tek `jq` / tek `git` | 26 / 27 / 46 |
| `env.sh` ayar yükleme | 24 |
| kayıt defteri kurma (`route.sh registry`) | 78 |
| `workflow.sh policy --json` (görev gerçekleri) | 57 |
| `sdd.sh evidence --json --with-fingerprint` (yalnızca kapı rolleri; diff hash'i + kanıt durumu) | ~310 |
| `decide`: ayar+kayıt defteri (aşama A) / +rol+görev gerçekleri (B) / +katman+model+bütçe (C) | 155 / 283 / 643 → optimizasyon sonrası ~520 |
| `decide`, kapı rolü, açık yüksek riskli görev | 1112 → **~920** |
| `decide --reserve` (kilit + defter yazımı dahil, aşama dışı) | ~750 (önceki ölçüm) |
| `outcome` / `classify` | ~48 |

Darboğaz: (1) aynı diff'in iki kez hash'lenmesi ve (2) karar değerlendirmesindeki çok sayıda küçük `jq` süreci (~25 ms/süreç). Düzeltilenler: tek `sdd.sh` çağrısı (durum + parmak izi), kayıt defterinin karar başına bir kez kurulması,
adaptör/model alanlarının tek `jq`'da okunması, not/uyarı listelerinin tek `jq`'da dizilenmesi. Davranış değişmedi (213 test aynı). Kalan süre çoğunlukla süreç başlatma (macOS) ve zorunlu `sdd.sh evidence`; daha fazlası ancak kabuk yerine tek bir ikili/dil gerektirir ve kapsam dışıdır.
Karşılaştırma için: bir model çağrısı saniyeler sürer; karar başına maliyet token değil duvar saatidir.

## 11. Benchmark uyumu (F05)

- `ROUTING` varsayılanı `off`; `bench/` stratejileri, görevleri ve baz sonuçları değişmedi, tarihî yapılandırmalar yeni yönlendirmeyi **etkinleştirmez**.
- Yönlendirme sürümlüdür (`policy_version: route-v1`); her karar `routing.jsonl`'da ve (TELEMETRY=1) `workflow.decision` olayında (`source=routing`) saklanır: bir koşu yeniden kurulabilir.
- Sabit model deneyleri: `ROUTE_POLICY=fixed` + `ROUTE_FIXED_MODEL` (tabanları yine düşürmez; kapı rolü için yetersizse `FIXED_BELOW_FLOOR` ile reddedilir).
- Ücretli benchmark otomatik çalıştırılmaz. Ucuzlatma kalibrasyonu F05-B sonuçları gelince yapılacaktır.
- F06.1 denetimi (2026-10-31): bu çalışma kopyasında F05-B sonuç dizini yok (yalnızca F05-A altyapısı ve simüle fikstürler), karşılaştırılabilir ölçüm bulunmadığı için `ROUTE_DOWNGRADE_LOW` **kapalı** kaldı (şablon `0`, testle sabitlendi). `bench/` altında `ROUTING` hiçbir yerde geçmez: tarihî yapılandırmalar yönlendirmeyi etkinleştirmez.

## 12. Geriye uyumluluk ve güven sınırları

Zorlanan (kod reddeder/kaydeder): `run-role.sh` yolunda karar tüketimi; `route.sh` yoksa çalışmama; kapı rolü katman tabanı; BLOCK'un aynı diff'te yeniden yargılanmaması; kopya/uçuştaki istek engeli (kilit altında);
spawn ve deneme sayısı; token sınırı (kullanım raporlanıyorsa); ayar ve kayıt doğrulaması; açık model geçersiz kılma doğrulaması.

Danışma / el ile: adaptör yetenekleri (`declared`, canlı doğrulanmadı); token sınırı kullanım raporlanmıyorsa; parasal sınır; süre sınırı `timeout` komutu yoksa; ana makinenin yerel alt ajanlarını (Codex, OpenCode, Cursor, Gemini) çağıran akışlar —
bunlar `run-role.sh`'ı kullanmaz, yönlendirmeyi yalnızca `route.sh explain` ile elle danışarak izler. Claude Code'da PreToolUse(Agent) hook'u `ROUTING=on` iken `route.sh` önizlemesini sorar
(yeniden kullanım/duran BLOCK/kopya/kat tabanının altındaki `model` için `ask`); model parametresi verilmemişse oturum varsayılanı kullanılır ve denetlenemez.

### Zorlanan mı, danışma mı: yönlendirmeyi atlatabilen yollar (F06.1 denetimi)

Kalite kapıları (`sdd.sh advance`: kanıt kapısı, risk tabanı, faz geçişleri) yönlendirmeden **bağımsızdır**: yönlendirme kapalı, atlatılmış veya yanlış olsa bile ilerleme anında aynen denetlenir (F04 testleri yönlendirmeyi hiç içermez ve geçer).
Yönlendirme yalnızca *hangi model/ne zaman/ne kadar* sorusunu etkiler. Yollar:

| Yol | Model katmanı tabanı | Bütçe (spawn/token) | Kopya/yeniden kullanım | Kanıt kapısı |
|---|---|---|---|---|
| `run-role.sh`, `ROUTING=on` | **zorlanır** (kod reddeder) | **zorlanır** (kullanım raporlandıkça) | **zorlanır** | zorlanır (`sdd.sh`) |
| `run-role.sh`, `ROUTING=off` (varsayılan) | eski kurallar (`--tier` tabanı) | eski kurallar (`MAX_SPAWNS`/`TOKEN_BUDGET_TASK`) | yok | zorlanır |
| Claude Code `Agent` aracı, `ROUTING=on` | **danışma**: hook `model` parametresi varsa sorar; parametre yoksa oturum modeli, denetlenemez | hook sayar ve sorar (`guard-budget`) | hook sorar (kullanıcı geçebilir) | zorlanır |
| Claude Code `Agent` aracı, `ROUTING=off` | yok | hook (`MAX_SPAWNS` doluysa) | yok | zorlanır |
| Codex/OpenCode/Cursor/Gemini yerel alt ajanları | **yok** (yalnızca `route.sh explain` ile elle) | yok | yok | zorlanır (el ile kayıt "manual" sayılır, yüksek riskte kabul edilmez) |
| ana makine CLI'ını doğrudan çalıştırmak | yok | yok | yok | zorlanır |
| `sdkit.env`'de `ROUTING=off` yapmak | tüm yönlendirmeyi kapatır: **sdkit.env korumalı değil**; `PROTECTED_PATHS`'e ekleyin | — | — | zorlanır |

`ROUTING` değeri `on|off` dışındaysa `run-role.sh` reddeder (sessizce kapalı saymaz). `--ignore-budget` yalnızca bütçeyi aşar; BLOCK, tavan, zorunlu rol ve kanıt kurallarını aşmaz.

Kabul edilen sınırlar:
- Zincir anahtarı handoff metninin özetidir: handoff'u değiştirmek yeni bir istektir. Bu, kazara döngüleri önler; kötü niyetli bir orkestratörü değil. Kapı kanıtı ve duran BLOCK diff parmak izine bağlıdır, handoff'a değil.
- Orta ve düşük riskte reviewer/security-auditor cevapları serbest biçimlidir ve kanıt olarak kaydedilmez; onların BLOCK'u `outcome`'a yansımaz (yalnızca yüksek riskte).
- `--ignore-budget` kullanıcı onayı varsayar; kod bunu doğrulayamaz (eski davranışla aynı).
- Süreç canlılığı `kill -0` ile bakılır; başka kullanıcının süreci "ölü" görünür. Pid'siz kayıtlar `ROUTE_INFLIGHT_TTL_S` sonra bırakılır.
- Hiçbir adaptör canlı CLI'a karşı doğrulanmadı (`run-role.sh` başlığındaki UNVERIFIED notu geçerli).
- Ana makine varsayılan modeli çalışırsa (cursor/gemini için boş katman modeli) katman doğrulanamaz; karar bunu `tier_enforced:false` ile söyler.

## 13. Testler

`tests/route.test.sh` (model çağrısı yok; yalnızca sahte CLI): yapılandırma ve kayıt, risk/rol/yetenek yönlendirme, geçersiz kılma ve tercihler, sabit politika, yedek ana makine, zorunlu/isteğe bağlı rol, kanıt yeniden kullanımı ve bayatlığı,
kopya ve eşzamanlı istek, hata sınıfları ile yeniden deneme/yükseltme sınırları, sert/danışma bütçe ayrımı, ölçülmeyen kullanım, maliyet tahmini, bütçe kurtarma, `run-role.sh` bütünleşmesi,
telemetri, Claude Code hook'u, yönlendirme kapalıyken eski davranış, benchmark dosyalarının değişmemesi.
