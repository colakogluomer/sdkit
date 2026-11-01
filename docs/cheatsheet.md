# Kısa başvuru

Ayrıntı için [guide.md](guide.md).

## Günlük kullanım

```
/spec-driven-dev <ticket veya açıklama>     # yeni görev (tam ad: /spec-driven-kit:spec-driven-dev)
/incident-to-rule                           # bir hata çözüldükten sonra, kalıcı koruma ekle
/scaffold-init                              # yeni repo, bir kez (kuran kişi); host: claude, codex, opencode, cursor, gemini (virgülle birden çok)
                                            # Codex'te çağrı: $spec-driven-dev
/scaffold-doctor                            # kurulum sağlam mı?
```

## Risk etiketi ne yapar

| | low | medium | high |
|---|---|---|---|
| Keşif + öneri + **DoD** | evet | evet | evet |
| `design.md`'de yarış/sıralama senaryosu | | | **zorunlu** |
| Test önce (RED → GREEN) | evet | evet | evet (testi ayrı agent yazar ve dondurur) |
| Bağımsız `verifier` | yok | **zorunlu** | **zorunlu** + `code-review` + `security-review` |
| PR'ı Claude açar | evet | evet | evet |

Etiketi analist önerir, **sen onaylarsın**. Ticket önceliği etiketi belirlemez.

## Akış (kısa)

1. **Analist** görevi inceler; eksik varsa sorar (turda en fazla 4 soru, önerilen varsayılan ilk seçenek)
2. Risk etiketi onayı → keşif
3. **Plan kapısı**: kapsam, DoD (her maddenin "Verified by"ı), tasarım, görevler/roller, riskler sana detaylıca sorulur. Düzenleyebilirsin; değişiklik plana yayılır.
   Son onay: `Onayla ve propose et` / `Bir bölümü düzenle` / `Burada dur`
4. `propose` → test önce → rollerle uygulama → bağımsız doğrulama → PR
5. İstediğin an "planı güncelle" diyebilirsin; yalnızca etkilenen turlar tekrarlanır

## Roller

`orchestrator` (ana oturum) · `analyst` eksik mi? · `scout` ucuz arama · `engineer` tasarım ve test stratejisi · `developer` kod · `test-writer` test ·
`devsecops` pipeline/altyapı · `reviewer` / `security-auditor` / `verifier` bağımsız ve salt okunur (`high` riskte `verifier-deep`, strong katman). Gerçekleştiren asla doğrulamaz.
Roller birbirini çağırmaz; arama gerekiyorsa `NEEDS-LOOKUP:` yazar, orchestrator `scout` çalıştırır.

## Hostlar ve stack'ler

| | Seçenekler |
|---|---|
| Host (`init.sh --host a,b`) | `claude` (varsayılan), `codex`, `opencode`, `cursor`, `gemini`. Proje klasörü her host için `.sdkit/` (eski kurulumlarda `.claude`/`.codex`/`.agentkit`); ayarlar ortak `sdkit.env` + kişisel `sdkit.local.env` |
| Stack (`--stack`, yoksa otomatik) | `go`, `spring-boot`, `nextjs`, `react-native` (algılama sırası bu; repo başına tek stack) |

Claude dışı hostlarda guard'lar commit/push anında (`.githooks`), host destekliyorsa araç çağrısında da çalışır; adapter'lar canlı kurulumda doğrulanmadı ([guide.md](guide.md) §13, §16).

## Paralel çalışma

```bash
<kit>/scripts/plan-waves.sh tasks.md      # bağımsız görevleri dalgalara ayırır
<kit>/scripts/worktree.sh add T3          # görev için izole worktree
<kit>/scripts/worktree.sh merge T3        # dalga sonunda birleştir, sonra verify --fast
```
Görev: `- [ ] T3 açıklama | role: developer | size: medium | writes: yol/ | after: T1`. Varsayılan sıralıdır; paralel yalnızca ayrık `writes:` ile ve en fazla `MAX_PARALLEL` (3) subagent. `size:` (small/medium/large → light/standard/strong) isteğe bağlıdır; yoksa rolün katmanı geçerli. Diğer host'larda: `run-role.sh <rol> --handoff F --tier light|standard|strong`.

## Durum, devam, maliyet

```bash
<kit>/scripts/state.sh <slug> show              # görev durumu (work/<slug>/state.json); /clear veya çökmeden sonra buradan devam
<kit>/scripts/usage.sh report [slug]            # rol/katman başına token + önbellek isabet oranı (USAGE_LOG=1 gerekir)
sdkit report task|session|latest|history [--detailed|--json|--markdown]   # Value Report: kim ne yaptı, ne harcadı, neyi tasarruf etti (VALUE_REPORT=on ile görev/oturum sonunda otomatik)
<kit>/scripts/usage.sh budget [slug]            # TOKEN_BUDGET_TASK'e göre kullanım (çıkış 3 uyarı, 4 aşıldı)
<kit>/scripts/telemetry.sh summary [slug] [--json]  # koşu özeti: faz/ajan süreleri, token (ölçülen/toplam), yeniden deneme, hata, doğrulama (TELEMETRY=1 gerekir)
<kit>/scripts/telemetry.sh archive <slug>         # kapanıştan önce: olayları work/_archive/ altına al
<kit>/bench/run.sh run all                         # simüle benchmark (ücretsiz); gerçek: --real --host H --yes
<kit>/bench/run.sh run contracts | overhead        # F02: 5 sözleşme fikstürü | sözleşmeli/sözleşmesiz ek yük (bayt, olay, betik çağrısı, gecikme)
<kit>/scripts/contract.sh issue F | check-result F --id I --role R --record   # ajan sözleşmesi (CONTRACTS=1): devri / cevabı doğrula (0 done, 1 partial|blocked|failed, 2 geçersiz; 0 "doğrulandı" DEĞİLDİR)
<kit>/scripts/sdd.sh start <slug> --risk R --profile small|standard|high-assurance --proposal P   # profil (varsayılan standard)
<kit>/scripts/sdd.sh transitions | policy [--json]   # geçerli faz geçişleri ve girişleri | görev için geçerli kurallar (workflow.sh)
<kit>/scripts/sdd.sh evidence [--json]            # yüksek risk: verifier/reviewer/security-auditor kanıtının durumu (valid|stale|untrusted|...)
<kit>/scripts/contract.sh pending | status      # cevapsız devirler | görevin tüm kimlikleri
<kit>/scripts/memory.sh candidates <slug>       # kapanışta bellek adayları (MEMORY=1); search | stale | add | promote
<kit>/scripts/lookup-cache.sh get <slug> "soru" # scout cevabı önbelleği; ıskada 1
<kit>/scripts/run-role.sh verifier --handoff F --cwd D --host H   # rolü ayrı süreçte çalıştır; VERIFIER_HOST ile başka sağlayıcı
<kit>/scripts/route.sh explain --role R [--risk L]   # yönlendirme kararı (ROUTING=on): adaptör, model, neden, bütçe; model çağrısı yok, kayıt yok
<kit>/scripts/route.sh registry | capabilities | validate   # model kayıt defteri | adaptör yetenekleri | ayar denetimi
<kit>/scripts/check-plan-parity.sh plan.md proposal.md [tasks.md]  # DoD satırları: D<n>: metin | Verified by: tür
```

## Claude durduğunda ne yapmalı

| Durum | Anlamı | Ne yap |
|---|---|---|
| "Risk rubriği yok" | `project.md`'de rubrik tanımlı değil | Rubriği sen yaz; Claude uydurmaz |
| "Test edilemiyor" seçenekleri | Kod gerçek altyapı olmadan test edilemiyor | Seçeneklerden birini seç (dar arayüz / kapsam dışı bırak ve kaydet / entegrasyon altyapısı) |
| Release dondurulmuş | Dal açılacak release `freeze/` etiketli | Hangi dalın kullanılacağına sen karar ver |
| Verifier `BLOCK` | DoD `FAIL` veya `CONFIRMED` bulgu | Uygulama hatasıysa bir otomatik deneme; spec boşluğuysa sana döner |
| İkinci `BLOCK` | Otomatik döngü bitti | Özeti oku, karar ver; üçüncü otomatik deneme yok |
| Hook `ask` | Korunan yol / prod `kubectl` / env branch push | Onayla veya reddet |
| Hook `deny` | Secret dosyası, donmuş test, yanlış dal kaynağı | Mesaj nedenini söyler; engeli aşmak yerine nedeni düzelt |
| Git hook reddetti (Claude dışı hostlar) | `guard.sh`: secret, donmuş test, korunan yol, korunan branch | Nedeni düzelt; onaylıysa `ALLOW_PROTECTED=1` / `ALLOW_PROTECTED_PUSH=1` |
| Stop sırasında "verify kırık" | Commit'siz değişiklik stack'in hızlı kontrolünde (ör. vet/build) kırık | Claude düzeltir; sonsuz döngü yok |

## Hook'lar tek bakışta

| Hook | Karar | Kapatan ayar |
|---|---|---|
| `guard-secrets` | deny: `.env*`, `*credentials*`, `*.pem` | `SECRET_GLOBS` boş |
| `guard-protected` | ask: `PROTECTED_PATHS` altı | `PROTECTED_PATHS` boş |
| `frozen-tests` | deny: `<project-dir>/.frozen` listesi | dosya yok |
| `guard-prod` | ask: prod cluster'a değiştirici `kubectl` | `PROD_KUBE_CLUSTERS` boş |
| `guard-git` | deny/ask: release akışı kuralları | `BASE_BRANCH_MODE` ≠ `release` |
| `post-edit-fmt` | stack'in biçimlendiricisi (ör. `gofmt -w`) | stack aracı yok |
| `stop-verify` | block: kırık vet/build ile "bitti" | verify betiği yok |
| `guard-readonly` | deny: salt okunur rolün dosya değiştirmesi | çağrıda rol yoksa kapalı |
| `value-report` | oturum bitişinde/başlangıcında Value Report oturum özeti (engellemez, stdout yok) | `VALUE_REPORT` ≠ `on` |
| `usage-log` | token defteri ve (`TELEMETRY=1`) `agent.end` olayı (engellemez) | `USAGE_LOG` ve `TELEMETRY` ≠ `1` |
| `guard-budget` | ask/uyarı: `MAX_SPAWNS` veya `TOKEN_BUDGET_TASK` aşıldı | ikisi de boş |
| `result-size` | uyarı: rol cevabı çok uzun | `SUBAGENT_RESULT_MAX_LINES` boş |
| `check-contract` | ask (strict, geçersiz devir) / uyarı: devir ya da `HANDOFF-RESULT` satırı sözleşmeye uymuyor; verdict'e dokunmaz | `CONTRACTS` ≠ `1` veya devirde `CONTRACT:` yok |
| `session-context`, `check-tools` | bilgi | |

Hook'lar emniyettir, güvenlik sınırı değil (regex tabanlı).

## Doğrulama

```bash
<kit>/stacks/<stack>/scripts/verify.sh              # tam: stack'in kontrolleri + verify.d (Go: gofmt, vet, build, test, lint)
<kit>/stacks/<stack>/scripts/verify.sh --fast       # yalnızca ucuz kontroller (Go: vet + build)
<kit>/stacks/<stack>/scripts/verify.sh --since-head # yalnızca commit'siz değişiklikler
<kit>/stacks/<stack>/scripts/verify.sh --no-cache   # aynı ağaç için yeşil sonuç önbelleğini yok say
<kit>/bin/doctor.sh <repo>                     # kurulum kontrolü
<kit>/bin/upgrade.sh <repo>                    # yeni kit sürümüne yükselt (önce /plugin ile plugin'i yenile)
<kit>/bin/build-adapters.sh --check            # (kit bakımcısı) roller ve üretilen dosyalar senkron mu
<kit>/tests/run.sh                             # (kit bakımcısı) betik/hook/init smoke testi
```

`verify.d` betiği: `<project-dir>/verify.d/NN-ad.sh`, `chmod +x`, `. "$VERIFY_LIB"`, sorun için `FAIL: ...` / `WARN: ...` basar.
`_` ile başlayanlar çalıştırılmaz; `init`'in getirdiği `.example` dosyaları uzantı silinene kadar kapalıdır.

## Hata çözüldükten sonra (`incident-to-rule`)

Sırayla ilk uyan: lint kuralı → `verify.d` politikası → regresyon testi → hook → `known-pitfalls.md` kaydı.
Koruma, hatayı üreten diff'te **kırılıp** düzeltmede **geçmeden** güvenilmez.

## Sık sorunlar

| Belirti | Neden / çözüm |
|---|---|
| Plugin istemi çıkmadı | `/plugin marketplace add <kit-repo-url>`, sonra `/plugin install spec-driven-kit@spec-driven-kit` |
| Proje izinleri/plugin devrede değil | Güven onayı verilmedi; proje ayarları ondan önce uygulanmaz |
| `verify.d` betiği çalışmıyor | `chmod +x` eksik, adı `_` ile başlıyor veya `.example` uzantılı |
| Guard çalışmıyor | İlgili ayar boş (yukarıdaki tablo) veya `doctor.sh` ile kurulumu kontrol et |
| Kit güncellendi, projede değişmedi | Plugin modu: `/plugin` ile güncelle. Copy modu: `sync.sh` |
| Claude dışı hostta guard çalışmıyor | `git config core.hooksPath .githooks` bu klonda çalıştırılmadı |
| "stack algılanamadı" | `init.sh --stack go\|spring-boot\|nextjs\|react-native` ver; başka stack için kit'e yenisi gerekir ([guide.md](guide.md) §14) |
| Verify "cached" dedi | Aynı ağaç daha önce yeşildi; yeniden çalıştırmak için `--no-cache` |
| PR açılmadı, kod 2 | `PR_HOST` Bitbucket değil; [hosts.md](hosts.md) |
