# Kit'e katkı

Bu dosya **kit'in kendisini** değiştirenler içindir. Kit'i bir projede kullanmak için [README.md](README.md) ve
[docs/README.md](docs/README.md).

## Temel kural: kit genel kalır

Skill, agent, hook ve script'lere **projeye özel hiçbir şey gömülmez**: branch adı, cluster adı, servis adı, takım jargonu, risk ölçütü yok.
Bunlar projedeki `<project-dir>/sdkit.env` ve `project.md`'den gelir. Bir değişiklik için "bu yalnızca bizim projede doğru" diyorsan yeri
kit değil, o projenin proje klasörüdür (`<project-dir>` = `.sdkit/`; 1.0 öncesi kurulumlarda `.claude`, `.codex` veya `.agentkit`). (Geçmişte bu yüzden bir düzeltme yapıldı: `fix: keep project-specific wording out of the generic hooks and agents`.)

İkinci kural: **proje tarafı dosyalarının üzerine yazma.** `init.sh` var olan `project.*`, `rules/`, `settings.json` dosyalarını `--force` ile bile ezmez;
`--force` yalnızca copy modunun yönetilen dosyaları içindir.

## Neyi nereye eklerim

| Eklemek istediğim | Yer | Ayrıca |
|---|---|---|
| Skill | `skills/<ad>/SKILL.md` (frontmatter: `name`, `description`, `license`, `metadata`) | `description` "ne zaman kullanılır"ı söylemeli; `docs/guide.md` §5 ve README tabloları |
| Rol (agent) | `core/roles/<ad>.md` (frontmatter: `name`, `description`, `kind`, `access`, `tier`, `independent`, isteğe bağlı `deep`), sonra `bin/build-adapters.sh` | **`agents/` ve `adapters/<host>/` üretilmiştir, elle düzenleme.** Erişimi en dar tut (bağımsız roller `read-only`); çıktı formatını sabitle; `core/roles/README.md` ve `guide.md` §6 |
| Hook | `hooks/<ad>.sh` + `hooks/hooks.json` bağlantısı | `hooks/lib.sh`'daki `jget`/`decide`'ı kullan; kapatan ayarı (`sdkit.env`) belgele; `guide.md` §7 tablosu; `init`/`doctor`'ın copy modu bağlantısı |
| `sdkit.env` ayarı | ekip politikasıysa `templates/sdkit.env`, kişiselse (limit, bütçe, host/model, memory davranışı) `templates/sdkit.local.env`; varsayılan satırlar mevcut dosyalara `init`/`upgrade` ile otomatik eklenir. Anahtarı kişisel yaparsan `split_personal_env` de onu taşır | Varsayılanı güvenli seç (boş = özellik kapalı); `guide.md` §10 |
| Genel kural | `core/rules/` | Dilden bağımsız olmalı; `init.sh` projeye kopyalar |
| Akış adımı / ayrıntı | `skills/spec-driven-dev/SKILL.md` kısa kalır; ayrıntı `references/` altına | Token ekonomisi: referans yalnızca ilgili adımda okunur; `SKILL.md`'yi şişirme |
| Yeni host | Aşağıdaki "Yeni host eklemek" listesi | `guide.md` §14, §16 |
| Araçtan bağımsız guard | `scripts/guard.sh` + `adapters/git/` | Claude hook'larıyla aynı kural, commit/push anında |
| Dil/stack | `stacks/<ad>/` | Aşağıdaki "Yeni stack eklemek" listesi, `guide.md` §14 |
| Proje şablonu | `templates/` | `init.sh` bunu yazar, `doctor.sh` kontrol eder; ikisini de güncelle |
| Örnek `verify.d` politikası | `stacks/<stack>/verify.d.example/*.sh.example` | `FAIL:`/`WARN:` protokolü |

## Hook yazma kuralları

- Girdi stdin'de JSON'dur; `jq` ile oku. Sonuç `permissionDecision` (`deny` / `ask`) JSON'u ya da Stop için block'tur.
- **Kapalı olmayı varsayılan yap**: ayar boşsa sessizce çık (`exit 0`). Ayarsız bir hook her projede gürültü çıkarır.
- Yalnızca bilerek engelle: karar vermen gereken durum dışında çıkış kodu 0 olsun, hook'un kendi hatası oturumu kilitlememeli.
- Deny/ask mesajı nedeni ve çıkış yolunu söylemeli ("`project.md`'ye bak", "aktif release branch'i X").
- Hook'lar güvenlik sınırı değil emniyettir; kaçış yollarını `guide.md` §13'e yaz.
- Bu hook'lar Claude Code içindir; Gemini ve Cursor aynılarını `hooks/adapt.sh` kabuğuyla, OpenCode eklentiyle çağırır. Her yerde karşılığı `scripts/guard.sh`'tır (git hook): yeni bir koruma ekliyorsan hepsini birlikte düşün.
- Stop hook'ları `stop_hook_active` kontrolü yapmalı (sonsuz döngü olmasın) ve `hooks.json`'da zaman aşımı vermeli.

## Doğrulama (göndermeden önce)

Önce smoke test: `tests/run.sh` betikleri (verdict, plan eşitliği, yazma kapsamı, state, usage), hook'ları, `run-role.sh --dry-run`'ı ve `init`'i fixture'larla dener (her durum geçmeli mi kalmalı mı diye belirtir); bir betik veya hook değiştirdiysen buraya bir durum ekle. Sonra elle:

```bash
tests/run.sh                                                        # smoke test
tests/sdd.test.sh && tests/shared.test.sh                          # faz makinesi, paylaşılan dosyalar
tests/memory.test.sh && tests/budget.test.sh                       # proje belleği, token bütçesi, hook bağlantıları
tests/sdkit-dir.test.sh                                            # .sdkit düzeni, eksik ayar ekleme, eski düzen, --migrate
tests/risk-floor.test.sh                                            # risk floor (RISK_FLOOR_GLOBS): etiket tabanı, CI atlatma denemeleri
tests/hardening.test.sh                                            # F00.5: verdict doğrulama, eşzamanlı yazım, ayar dosyası çalıştırmama, görev çözümü, önbellek, STACK
tests/report.test.sh                                               # Value Report: görev/oturum raporu, tasarruf aritmetiği, çift sayım, tek seferlik üretim, LLM çağrısı yok
tests/workflow.test.sh                                             # F03: profiller, geçiş tablosu, red nedenleri, sözleşme politikası, eşzamanlılık, telemetri
tests/usage.test.sh                                               # F07: kullanım/maliyet muhasebesi, fiyat çözümü, tekilleştirme, kapsam uyarıları
tests/efficiency.test.sh                                           # F08: verdict normalizasyonu, format/semantic ayrımı, kanıtsız PASS, erken DoD denetimi
tests/context.test.sh                                              # F09: sınırlı çıktı, ENVELOPE/1, hata satırları korunur
tests/selection.test.sh                                            # F10: değişen dosya → test eşlemesi, pipe hatası, önbellek
tests/costbase.test.sh                                             # F11: sabit-veri taban çizgisi ve karşılaştırma korumaları
tests/adapter.test.sh                                              # F12: adaptör sözleşmesi, sahte harici adaptör
tests/litellm.test.sh                                              # F13: OpenAI uyumlu adaptör (sahte curl): politika, çıkış izni, sır
tests/costroute.test.sh                                            # F14: sert maliyet politikası, rezervasyon, bilinmeyen
tests/dispatch.test.sh                                             # F15: paralel dağıtım kuralları
tests/knowledge.test.sh                                            # F16: içerik hash'li notlar
tests/trace.test.sh                                                # F17: iz (içeriksiz)
tests/recover.test.sh                                              # F18: kurtarma, idempotent
tests/security.test.sh                                             # F19: redaksiyon, denetim zinciri, statik politika
tests/ci.test.sh                                                   # F20: ucuz PR denetimi, regresyon geçmişi
tests/evidence.test.sh                                             # F04: yüksek risk kanıtı (3 rol), güven/kimlik, bayatlık, sahtecilik, eşzamanlılık, adaptör iddiaları
tests/contract.test.sh                                             # F02: ajan sözleşmeleri (doğrulama, kayıt, hook, run-role, verifier bağımsızlığı, geriye uyum, sözleşme benchmark'ları)
tests/route.test.sh                                               # F06: yönlendirme kararları, kayıt defteri, zamanlama, yeniden deneme/yükseltme, bütçe, run-role bütünleşmesi (sahte CLI; model çağrısı yok)
tests/tbench.test.sh                                               # F05-A: görev benchmark'ı (görev kaydı, yalıtım, gizli test ayrımı, metrik içe alma, mühür, rapor, gerçek koşu kapısı; model çağrısı yok)
tests/telemetry.test.sh                                            # F01: olay şeması, korelasyon, eşzamanlılık, hata yalıtımı, benchmark (simüle; gerçek LLM koşusu yok)
bin/build-adapters.sh --check                                       # roller ile üretilen dosyalar senkron mu
bash -n hooks/*.sh bin/*.sh bin/emit/*.sh scripts/*.sh stacks/*/scripts/*.sh adapters/git/*  # sözdizimi
jq . hooks/hooks.json .claude-plugin/*.json templates/settings.*.json >/dev/null
shellcheck hooks/*.sh bin/*.sh scripts/*.sh                         # kuruluysa
```

Sonra bir çöp repoda uçtan uca dene:

```bash
tmp="$(mktemp -d)" && git -C "$tmp" init -q && cd "$tmp"
<kit>/bin/init.sh --stack go "$tmp"              # plugin modu (boş repoda stack algılanamaz, --stack şart)
<kit>/bin/doctor.sh "$tmp"                          # beklenen FAIL'ler: yalnızca TODO'lu project.md ve (commit yoksa) BASE_BRANCH
<kit>/bin/init.sh --mode copy --stack go "$tmp2"    # copy modu için ayrı bir çöp repo
<kit>/bin/init.sh --host claude,codex --stack go "$tmp3"   # Codex dosyaları: AGENTS.md, .agents/, .codex/, .githooks/
<kit>/bin/init.sh --host opencode,cursor,gemini --stack go "$tmp4"   # .sdkit/, .opencode/, .cursor/, .gemini/
```

Paralel araçlar için örnek bir `tasks.md` ile `scripts/plan-waves.sh` (dalgaları, bilinmeyen id'yi ve döngüyü dene) ve geçici bir repoda `scripts/worktree.sh add|merge|clean`;
`scripts/guard.sh` için geçici repoda `.env` / korunan yol / donmuş test stage'leyip `git commit` dene (reddetmeli), temiz dosya geçmeli.

Bir hook değiştirdiysen tetikleyen ve **tetiklemeyen** bir girdiyle elle çalıştır:

```bash
echo '{"tool_name":"Read","tool_input":{"file_path":".env"}}' | CLAUDE_PROJECT_DIR="$tmp" <kit>/hooks/guard-secrets.sh
```

Bir koruma "kırılıp geçmeden" güvenilmez: hem engellemesi gereken hem izin vermesi gereken durumu dene.

## Yeni host eklemek

1. `bin/emit/<host>.sh`: `emit_<host>_begin` ve `emit_<host>_role`, çıktı `adapters/<host>/`; `bin/build-adapters.sh`'a bağla, çalıştır, üretilen dosyaları commit'le.
2. `core/hosts.env` (araç ve izin adları, salt okunur kabuk izin listesi) ve `core/tiers.env` (`<HOST>_MODEL_LIGHT|STANDARD|STRONG`; boş = oturumun modeli).
3. `bin/init.sh` (`--host` değerleri, proje klasörü adı, host dosyaları), `bin/doctor.sh` (host kontrolleri, CLI notu), `bin/upgrade.sh` (host algılama).
4. Guard bağlantısı: host Claude hook JSON'una benzemiyorsa `hooks/adapt.sh`'a bir durum ekle veya OpenCode gibi bir eklenti yaz; yoksa yalnızca git hook'ları (`adapters/git/`) kalır.
5. `scripts/run-role.sh`'a host için bir `case` (başsız çalıştırma bayrakları) ve `--dry-run` ile kontrol.
6. `skills/spec-driven-dev/references/hosts.md` tablosu, `README.md`, `docs/guide.md` §13, §14, §16 ve `core/roles/README.md` tablosu.
7. `tests/run.sh`'a durumlar: `run-role.sh --dry-run`, `init.sh --host <host>` çıktısı, varsa `adapt.sh` girdisi. Canlı kurulumda denemediysen README "Limits" ve guide.md §13'te doğrulanmadı olarak belirt.

## Yeni stack eklemek

1. `stacks/<ad>/` sözleşmesi [stacks/README.md](stacks/README.md)'de: `detect.sh`, `scripts/verify.sh` (ince giriş), `scripts/steps.sh` (`STACK_SOURCE_RE`, `stack_run`), `scripts/fmt.sh`, `scripts/tools.sh`, `permissions.txt`, `rules/`, `verify.d.example/`.
2. `bin/init.sh` algılama sırası (`STACKS` değişkeni: go, spring-boot, react-native, nextjs; ilk eşleşen kazanır): `detect.sh` yanlış pozitif vermemeli.
3. `scripts/tools.sh`'taki `required|` / `optional|` satırlarını `hooks/check-tools.sh` okur; araç eksikse `warn`, `fail` değil.
4. `permissions.txt`: Claude `settings.json` "allow" listesine eklenecek kalıplar (en dar halleri).
5. Ortak mantık `scripts/verify-core.sh`'ta kalır; stack yalnızca `stack_run` yazar. Node tabanlı stack'ler `stacks/_node/scripts/node-lib.sh`'i paylaşır.
6. `templates/sdkit.env` (yeni stack ayarı varsa), `README.md`, `docs/guide.md` §14 ve `docs/cheatsheet.md`; `tests/run.sh`'a bir fixture eklenebilir.

## Sürüm ve yayın

1. Değişikliği yap. Rolleri `core/roles/`'ta değiştirdiysen `bin/build-adapters.sh` çalıştır ve üretilen dosyaları da commit'le. `docs/guide.md` ve README'deki ilgili tabloları güncelle (parça sayıları dahil: skill/rol/hook/script adedi; şu an 4 skill, 10 rol, 16 hook, 17 script).
2. `.claude-plugin/plugin.json` **ve** `.claude-plugin/marketplace.json` içindeki sürümü birlikte artır (ikisi aynı olmalı).
   - patch: düzeltme, belge
   - minor: yeni skill/agent/hook/ayar (varsayılanı kapalı)
   - major: var olan projelerin proje klasöründeki dosyalarını elle güncellemesini gerektiren değişiklik
3. Sürümle ilgili elle yapılması gereken bir şey varsa `docs/upgrading.md`'ye "X → Y" bölümü ekle (`upgrade.sh` yeni dosyaları kendisi ekler, geri kalanı oraya yazılır).
4. Push et ve marketplace'in baktığı dala (varsayılan branch) al; sürüm artmadan veya o dala girmeden projeler yeni sürümü görmez. Plugin kullanan repolar `/plugin` ile günceller; copy modundakiler `sync.sh` çalıştırır, bu yüzden yönetilen dosyaların
   yolunu değiştirmek copy modundaki projeleri etkiler.

## Commit ve branch

[core/rules/git.md](core/rules/git.md) geçerlidir: `<type>(<scope>): <açıklama>`, emir kipi, konu ≤ 72 karakter, branch `<type>/<kısa-ad>`.
Bu repoda scope kit parçasıdır (`hooks`, `skills`, `verify`, `init` ...); belge değişikliği `docs:`.

## Belgeler

- `README.md` İngilizce ve kısa tutulur: ne olduğu, kurulum, bağlantılar.
- `docs/` Türkçedir. Ayrıntı `guide.md`'de yaşar; `cheatsheet.md` ve README yalnızca özet verir ve guide'a bağlanır, bilgiyi çoğaltma.
- Bir sayı veya tablo birden çok dosyada geçiyorsa (hook adedi, ayar listesi) hepsini aynı değişiklikte güncelle.
