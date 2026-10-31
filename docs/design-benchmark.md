# Görev benchmark'ı (F05-A)

Aynı yazılım görevini farklı stratejilerle (sıradan ajanlı geliştirme, SDKit standart, SDKit yüksek güvence) çözdürüp **doğruluğu ve kaynak harcamasını** ölçen altyapı. F05-A yalnızca altyapıdır: gerçek model çağrısı yoktur, SDKit iş akışı davranışı değişmedi. Gerçek ölçüm F05-B'nin işidir (§9).

`bench/run.sh` (F01–F03) kitin kendi iş akışının maliyetini senaryolarda ölçer. `bench/tbench.sh` ise "iş doğru yapıldı mı, kaç token'a, hangi stratejiyle" sorusunu yanıtlar. İkisi ayrıdır; telemetri (`scripts/telemetry.sh`) yeniden kullanılır, ikinci bir defter yoktur.

## 1. Mimari

```
bench/tbench.sh              sürücü: tasks strategies validate seal fixtures run preflight ingest verify report
bench/tasks/<ID>-<slug>/     task.json (manifest), task.md (ajanın gördüğü metin), starter/ (ajanın gördüğü depo + açık testler)
bench/tasks/registry.json    id@sürüm -> manifest özeti (mühürlenmiş sürüm değişmez)
bench/evaluator/<ID>-<slug>/ YALNIZ değerlendirici: hidden/ (gizli kabul testleri), variants/{reference,partial}/
bench/strategies/*.json      baseline, sdkit-standard, sdkit-high-assurance
bench/sim/sim.json           simülasyon fikstürü (elle yazılmış sayılar; etiketli)
bench/lib/                   runlimited.py (zaman aşımı, çıktı sınırı, süreç grubu), ingest.jq, from-telemetry.jq, report.jq, report-md.jq, sim-agent.sh
tests/tbench.test.sh         otomatik testler
```

Yeniden kullanılanlar: `telemetry.sh summary --json` biçimi (`from-telemetry.jq` ile içe alınır), `usage.sh`/`run-role.sh` ile aynı kalite etiketleri (ölçülen/tahmini/yok), `bench/run.sh`'in "simüle varsayılan, `--real` + `--yes` ile gerçek" kuralı.

Sonuç dizini (`--out DIR`, kit ağacının **dışında** olmalı):
`DIR/runs/<run-id>/{result.json, result.sha256, agent.log, public.log, hidden.log, diagnostics/}` ve geçici `DIR/work/`.

## 2. Görev kaydı

Her görev: kimlik+sürüm, açıklama, risk, zorluk, başlangıç deposu (yerel fikstür, git ağaç kimliği, köken), açık test komutu, gizli test komutu ve en az test sayısı, gereksinimler (R1…Rn), düzenlenebilir yollar, sınırlar (ajan süresi, test süresi, çıktı baytı), ortam, iki içerik özeti (`visible_sha256`: task.md + starter; `evaluator_sha256`: hidden + variants). `seal` özetleri yazar; `validate` yeniden hesaplar. Aynı `id@sürüm` farklı içerikle yeniden mühürlenemez (çıkış 5): sürümü artır.

| ID | Zorluk / risk | Görev | Kasıtlı kusur |
|---|---|---|---|
| T01 | düşük / low | null işleme ve hata yayılımı | `None` profilde çöker, tüm hatalar `""` olarak yutulur |
| T02 | düşük / low | girdi doğrulama, uç durumlar | `int()` `+5`, `1_000`, Unicode rakam, sınırsız değer kabul eder; SKU doğrulanmaz |
| T03 | orta / medium | sayfalı REST API | sayfalama yok, sıra garantisiz |
| T04 | orta / medium | eşzamanlı önbellek yarışı | yükleyici aynı anahtar için N kez çalışır; `invalidate` yarışı |
| T05 | yüksek / high | yetki atlatma | sahiplik/paylaşım denetimi yok, `owner_id` ezilebilir, pasif kullanıcı geçer |
| T06 | yüksek / high | çok bileşenli işlem tutarlılığı | stok/ödeme/sipariş atomik değil, iade yok, idempotency yok |

Hepsi yalnız Python 3 standart kütüphanesi (unittest, threading, sqlite3), ağ yok, saniyeler içinde koşar. Fikstür doğrulaması (`tbench.sh fixtures`, testlerde de koşar) her görev için dört durumu kanıtlar:

| Durum | Açık testler | Gizli testler |
|---|---|---|
| başlangıç (kusurlu) | geçer | **kalır** |
| `partial` (yarım çözüm) | geçer | **kalır** |
| `reference` (referans çözüm, yalnız değerlendiricide) | geçer | **geçer** |
| testleri boşaltmak (`tamper`) | geçer | **kalır** (değerlendirici yalnız `app/` alır) |

## 3. Yalıtım ve değerlendirme

Her koşu: kendi çalışma dizini, saf başlangıçtan yeni bir git deposu (sabit kimlik ve tarih; ağaç kimliği manifestle eşleşmezse çıkış 5), benzersiz koşu kimliği (`mkdir` atomik; var olan kimlik çıkış 4), ayrı sonuç dizini, başarısızlıkta çalışma dizini `diagnostics/` altında korunur. Kitin kendi deposuna hiçbir git komutu uygulanmaz; silme yalnızca `work/<id>` altında ve işaretli dizinde yapılır.

Değerlendirme ajanın ortamının **dışında**, ajan bittikten sonra: taze bir ağaç = saf başlangıç + ajanın **yalnız** `editable` yolları (sembolik bağ varsa reddedilir) + gizli testler. Ajanın yazdığı/değiştirdiği testler yok sayılır; açık testler regresyon denetimi olarak saf haliyle koşar. Gizli testler en az `min_tests` kadar koşmalı, atlanamaz; sonuç gereksinim başına (`test_R<n>_*`) kaydedilir. LLM yargıcı yoktur.

Ajana verilen ortam `env -i` ile yalnız izinli değişkenlerdir (PATH, HOME, çalışma yolu, istem dosyası); değerlendirici yolu hiçbir değişkende yoktur. Koşu öncesi çalışma dizininde değerlendirici dosyalarının özeti aranır, bulunursa durulur.

### Güvenlik sınırı (açık söylenir)

**Git worktree'si veya geçici dizin bir sandbox değildir.** Aynı kullanıcıyla kabuk erişimi olan bir süreç `bench/evaluator/` dizinini okuyabilir. Bu yüzden:

- Simülasyon gizli test yalıtımı **iddia etmez** (sonuçta `hidden_test_isolation: "not claimed"`); sahte ajan harness kodudur.
- Gerçek koşu (`--real --yes`) bir yalıtım mekanizması ister (`SDKIT_TBENCH_ISOLATION_CMD`, örn. kapsayıcı veya `sandbox-exec` sarmalayıcısı). `tbench.sh preflight` onun değerlendirici varlıklarını gerçekten gizlediğini sınar (gizli test dosyasını `cat`, dizini `ls`, referansı `cat` etmeyi dener, hepsi başarısız olmalı; basit bir programı çalıştırabilmeli). Mekanizma yoksa ya da gizlemiyorsa **kapalı kalır** (çıkış 3). Sınama yalnız değerlendirici varlıklarını yoklar; tam sandbox kanıtı değildir.
- Ağ erişimi kısıtlanmaz; ajan dışarıdan çözüm arayabilir (F05-B'de yalıtım mekanizması bunu da kapsamalı).

## 4. Stratejiler

| Strateji | İş akışı | Profil | Bağımsız doğrulama | Risk tabanı |
|---|---|---|---|---|
| `baseline` | yok: tek kodlama ajanı, görev metni, depo, araçlar | - | yok | n/a |
| `sdkit-standard` | `sdd.sh start --profile standard` | standard | riske göre (orta, yüksek) | devralınır |
| `sdkit-high-assurance` | `--profile high-assurance` | high-assurance | her riskte; yüksek riskte reviewer + security-auditor da | devralınır |

Model, sağlayıcı, araçlar, görev metni, başlangıç revizyonu ve sınırlar tüm stratejilerde aynıdır (`same_as_other_strategies`); fark `result.strategy.differs_from_baseline` alanında kayıtlıdır. `baseline`'a SDKit yaşam döngüsü dayatılmaz. SDKit stratejileri `SDD_MODE`, `RISK_FLOOR*`, `HOOK*`, `SDKIT_*` ayarlarını `env` ile değiştiremez; `risk_floor` `inherit` olmak zorundadır (`tbench.sh strategies` doğrular). Yüksek riskli T05/T06'da kitin zorunlu üç rol kanıtı olduğu gibi işler.

## 5. Metrikler

Koşu başına (`result.json`): token (girdi, çıktı, önbellek okuma/yazma, toplam ve toplamın dayanağı), **sağlayıcı maliyeti** (ölçülen, ayrı) ve **tahmini API-eşdeğeri maliyet** (yalnız fiyat tablosundan, ayrı), LLM çağrı sayısı, ajan çağrı sayısı, süre, yeniden deneme, profil, görev riski, model/sağlayıcı/fatura türü (`metered|subscription|unknown`), çıkış durumu, açık/gizli test sonucu, kod değişikliği (dosya, satır, dokunulan test dosyası), faz süreleri, rol başına token. Her alan `measured | estimated | unavailable`; eksik ya da geçersiz sayı **null** olur, asla 0 olmaz; etiketsiz sayı "estimated" sayılır. Abonelik faturasında bildirilen USD "ölçülen harcama" değil tahmin olarak saklanır.

Host başına destek (bugünkü `run-role.sh` okuyucularına göre; canlı CLI'lara karşı doğrulanmadı):

| Host | Token (girdi/çıktı) | Önbellek | Sağlayıcı maliyeti | LLM çağrı sayısı | Not |
|---|---|---|---|---|---|
| Claude Code | ölçülen (JSON çıktı `usage`) | okuma/yazma ölçülen | JSON'da `total_cost_usd` var, `run-role.sh` henüz okumuyor | yok | abonelikte bu değer API-eşdeğeridir |
| Gemini CLI | ölçülen | yok (null) | yok | yok | toplam alt sınırdır |
| Codex, OpenCode, Cursor | **yok** (null) | yok | yok | yok | yalnız süre, ajan sayısı, yeniden deneme |

Hiçbir host LLM çağrı sayısını vermez; bu alan ancak harness bir vekil/izleme ile sayarsa dolar (F05-B). Telemetri ayrıca ajan başına token'ı "kısmi" bildirir: `ingest` bunu "alt sınır" uyarısıyla işaretler.

## 6. Simülasyon

`tbench.sh run --simulate`: model yok. Sahte ajan (`lib/sim-agent.sh`) stratejinin yerine geçer ve bir sonucu oynar: `reference`, `partial`, `starter`, `tests-only`, `crash`, `hang`, `flood` (`--sim-force`). Sayılar `bench/sim/sim.json`'da elle yazılmıştır; sonuç dosyasında `simulated: true` ve etiket vardır, rapor gerçek ölçüm yoksa başlıkta "SIMULATED / NO REAL MEASUREMENTS" der, simüle koşular gerçek rakamlara **karışmaz** ve `conclusions_allowed=false` olur. Simülasyon yüklemeyi, çalışma dizinini, strateji seçimini, metrik içe almayı (baseline `agent-metrics/1`, SDKit stratejileri `telemetry.sh summary` biçimi, biri tamamen kullanımsız), değerlendirmeyi, kalıcılığı, raporu ve hata kurtarmayı (çökme, zaman aşımı, çıktı taşması, kesinti) sınar.

## 7. Raporlama

`tbench.sh report --results DIR` JSON ve Markdown üretir (`DIR/reports/`, üzerine yazmaz). İçerik: strateji başına koşu/başarı/başarı oranı, hata kategorileri, token (medyan; toplam yalnız **her** koşuda varsa), maliyet, gecikme, yeniden deneme, ajan/LLM çağrıları, görev × strateji tablosu, veri bütünlüğü (ölçülen/tahmini/yok sayıları), baseline karşılaştırması (yalnız eşleşen görevlerde, yüzde puan farkı, medyan token oranı, bayraklar), ölçüm sınırları. **Başarılı görev başına maliyet** = stratejinin TÜM koşularının (başarısızlar dahil) toplamı / başarı sayısı; yalnızca n ≥ `--min-n` (varsayılan 5), en az bir başarı ve metrik tüm koşularda varsa hesaplanır, aksi halde nedeni yazılır. Başarısızlar her paydada kalır. Rapor strateji sıralaması yapmaz; "daha ucuz ama daha az doğru" ve "baseline'dan daha az doğru" bayrakları üretir. Değiştirilmiş (özet uyuşmayan) ve tamamlanmamış (kesinti/çökme) koşular dışlanır ve adıyla listelenir.

## 8. Bütünlük

Her koşu şunları kaydeder: görev sürümü ve özetleri, başlangıç commit ve ağaç kimliği, çalıştırıcı sürümü/commit/kirli bayrağı/kod özeti (`evaluator.code_sha256`), strateji yapılandırması, model, ortam (işletim sistemi, mimari, bash/jq/python/git sürümleri; ana makine adı ve kullanıcı yok), zaman damgası. `result.json` yazıldıktan sonra özeti `result.sha256`'ya mühürlenir ve salt okunur yapılır; `tbench.sh verify` değişikliği saptar (çıkış 6). Koşu kimliği yeniden kullanılamaz. Kesinti (SIGTERM): süreç grubu öldürülür, sonuç `interrupted` olarak mühürlenir, çıkış 130. SIGKILL gibi sert çöküşte `RUNNING` işareti kalır ve koşu raporda "tamamlanmamış" diye listelenir.

Çıkış kodları: 0 tamam, 1 hata, 2 kullanım, 3 reddedildi (kapalı kalma), 4 koşu kimliği var, 5 görev bütünlüğü, 6 mühürlü sonuç değişmiş, 130 kesildi.

## 9. F05-B için kalan önkoşullar

1. **Gerçek yalıtım**: değerlendirici varlıklarını gizleyen, ağı kısıtlayan bir mekanizma (kapsayıcı/VM) ve onunla `preflight` geçişi.
2. **Gerçek strateji bağdaştırıcıları**: baseline için tek ajan koşusu; SDKit için depoda `init`, `sdd.sh start --profile`, `TELEMETRY=1`, bittiğinde `telemetry.sh summary --json` (harness `telemetry-summary.json` olarak toplar). Şu an `run --real` kapıdan sonra durur.
3. **Aynı model/araç** sabitleme ve `--model/--provider/--billing` kaydı.
4. **Sağlayıcı maliyeti**: Claude `total_cost_usd` okuması (`run-role.sh` bunu henüz yakalamıyor) ve Codex/OpenCode/Cursor için kullanım kaynağı; yoksa bu hostlarda yalnız süre/doğruluk karşılaştırılabilir.
5. **LLM çağrı sayısı** için vekil ya da host günlüğü.
6. **Örneklem**: görev başına ≥ 5 tekrar (`--reps`), değişkenlik için sabit tohum olmayan modeller; güven aralığı hesabı eklenmeli.
7. Telemetri `agent.end` olaylarının host'un kendi alt ajanlarında (Codex vb.) eksik kalması: ajan başına token alt sınırdır (rapor uyarır).
8. Gizli testlerin yeterliliği sonlu: görev kümesi genişledikçe `partial` varyantları yeni kusur sınıflarıyla sınanmalı.
9. Ücretli koşu bütçesi ve onay (`--yes`) politikası.
