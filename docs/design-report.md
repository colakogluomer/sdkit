# Value Report: görev ve oturum değer raporu

`scripts/report.sh` (`sdkit report ...`), SDKit'in bir görevde ve bir oturumda **ne yaptığını, kimin yaptığını, ne harcadığını ve neyi gösterilebilir biçimde tasarruf ettirdiğini** otomatik raporlar. Yeni bir telemetri sistemi **değildir**: yalnızca kitin zaten tuttuğu kayıtları okur. Hiçbir LLM çağrısı yapmaz (testle sabit: host CLI'ları tuzaklanmış PATH'te hiç çağrılmaz). Doğrulama: `tests/report.test.sh`.

## 1. Neyi yeniden kullanır

| İhtiyaç | Kaynak | Bu özellik ne ekler |
|---|---|---|
| Token, önbellek kategorileri, tekilleştirme, fiyat çözümü, maliyet | `usage.sh report --json` (F07) | Yalnızca `rows[]` (uzlaştırılmış koşular) ve `--as-model M` ("aynı koşu M modelinde olsaydı" fiyatı; **aynı** fiyat çözücü). Başka fiyat hesabı yok |
| Faz süreleri, test, doğrulama, kapı reddi, sözleşme sonucu, workflow kararı | `telemetry.sh summary --json` (F01) | yok |
| Yönlendirme kararları (reuse / duplicate / optional-skipped / bütçe) | `work/<slug>/routing.jsonl` (F06) | yok |
| Bağlam görünümleri (bayt) | `work/<slug>/context.jsonl` (`digest.sh`, F09) | yok |
| Test seçimi | `work/<slug>/selection.jsonl` | `test-select.sh` artık her koşuda bir satır yazar (yalnızca sayı ve saniye; önbellekteki yeşil koşunun süresi önbellek dosyasında saklanır) |
| Görev/oturum yaşam döngüsü | `sdd.sh advance done`, `sdd.sh abort [failed\|blocked\|partial]`, `SessionEnd`/`SessionStart` hook'u | `hooks/value-report.sh` |

Depolama: `<project-dir>/work/_reports/` (kişisel, git dışı): `task/<slug>@<run>.json`, `session/<id>.json`, `index.jsonl` (rapor başına bir satır), `sessions.jsonl` (oturum bitiş sinyalleri). Markdown ve metin çıktıları JSON'dan **her seferinde üretilir**, ayrıca saklanmaz. Rapor istem, transkript, dosya içeriği veya yol içermez; yalnızca kimlik, rol, model, sayı ve neden kodları. Tipik rapor birkaç KB.

## 2. Ne zaman çıkar

| Olay | Tetik | Çıktı |
|---|---|---|
| Görev tamamlandı | `sdd.sh advance done` | kompakt rapor stderr'e; `completed` |
| Görev bitti ama bitmedi | `sdd.sh abort` → `aborted`; `abort failed` / `abort blocked` / `abort partial` | aynı; durum açıkça yazılır |
| Oturum bitti | Claude Code `SessionEnd` hook'u (gerçek bitiş sinyali) | oturum özeti saklanır (`ended`) |
| Oturum sinyalsiz kesildi | sonraki `SessionStart`'ta `recover`: kaydı olup bitiş sinyali olmayan eski oturumlar | özet saklanır, **`interrupted`** (bitti denmez). `report regenerate session ID` sonradan yeniler |

`VALUE_REPORT=on` (`sdkit.local.env`, yeni kurulumlarda şablondan gelir; boş = kapalı, sessiz). Komutlar (`sdkit report ...`) ayardan bağımsız çalışır. **Tek seferlik:** `finalize` aynı `slug@run` için raporu bir kez yazar; ikinci çağrı "zaten var" der ve dosyaya dokunmaz (`--force` yeniden yazar). Rapor hatası görevi etkilemez: `finalize`, `session-end`, `recover` her zaman 0 ile çıkar; çıktı stderr'e gider, aracın kendi çıktısına, sözleşme/verdict ayrıştırmasına karışmaz.

Durum: `completed | failed | blocked | partial | aborted`; açık görevin canlı görünümü `in-progress` (saklanmaz, "terminal değil" yazar). `completed` istenmiş ama bir ajan sonucu `partial/blocked/failed` ise rapor **`partial`** der (`status_requested` yine `completed`). Başarısız bir görev asla başarılı diye anlatılmaz.

## 3. Komutlar

```
sdkit report task [slug|latest] [--run ID] [--detailed|--json|--markdown]
sdkit report session [id|latest|current] [--detailed|--json|--markdown]
sdkit report latest [--detailed|--json|--markdown]
sdkit report history [--json]                 # saklanan her rapor, tek satır (geçmiş karşılaştırma)
sdkit report regenerate task|session ID       # kayıtlardan yeniden kur (durum korunur)
```
`scripts/report.sh` doğrudan da çalışır. `--json` makine okunur (`schema: value-report/1`), `--markdown` A–D bölümlerinin tam tablolarıdır, varsayılan kompakt, `--detailed` ek olarak yöntem tablosu, "neden çalıştı", doğrulama ve uyarıları verir.

## 4. Ölçülen ve tahmin edilen

| Değer | Tür |
|---|---|
| Token kategorileri (in, out, cache_read, cache_write), koşu sayısı, süre, test/doğrulama sonucu | **ölçülen** (host'un yazdığı kayıt). Ölçülemeyen koşu `unavailable`/`N/A`'dır, **0 değil** (`tq: unavailable`); toplam alt sınır diye işaretlenir |
| API-eşdeğeri maliyet | **tahmin**: token × `pricing.json`. Fatura değil; `billed` daima "unavailable" |
| Kaçınılan yürütme sayısı (reuse, duplicate, optional-skipped) | **ölçülen sayı** (yönlendirme kararı) |
| Kaçınılan yürütmenin token/maliyeti | **tahmin**, yalnızca savunulabilir karşılaştırılabilir koşu varsa |
| Yönlendirme tasarrufu | **tahmin** (karşı-olgu) |
| Test seçimi | ölçülen sayı ve önbellek süresi; atlanan süitlerin süresi **ölçülmedi**; token iddiası yok |
| Bağlam optimizasyonu | **sezgisel** (~4 bayt/token), tasarruf oranına **girmez** |
| Bütçe / workflow zorlaması | **niteliksel**: kayıtlı karar ve ret sayısı, dolar iddiası yok |

Yalnızca **gözlenen** optimizasyonlar listelenir; bir özelliğin açık olması tek başına tasarruf sayılmaz. Önbellek okuması SDKit tasarrufu değildir (sağlayıcı özelliği): maliyet bölümünde ayrı satırda "prompt caching" olarak verilir, tasarruf oranına girmez ve yeni üretilmiş token sayılmaz.

## 5. Tasarruf metodolojisi

Kanıt sırası: (1) karşılaştırılabilir SDKit'siz gerçek koşu, (2) önceden kaydedilmiş benzer koşular, (3) açık tanımlı karşı-olgu, (4) açıkça etiketli sezgi, (5) **N/A**. Bugünkü kitte (1) yoktur; kullanılanlar (2) ve (3)'tür.

**Token** (yalnızca kaçınılan yürütmelerden):
- Kaçınılan yürütme = yönlendirme kararı `reuse` (`EVIDENCE_REUSED`), `DUPLICATE_COMPLETED/IN_FLIGHT` veya `OPTIONAL_SKIPPED`.
- Karşılaştırılabilir koşu: önce **aynı görevde aynı rolün** ölçülmüş koşuları (güven: medium), yoksa **önceki saklanmış raporlardaki** aynı rolün koşuları (low). Hiçbiri yoksa yürütme sayılır ama fiyatlanmaz.
- `taze token = in + out + cache_write` (önbellek okuması hariç; `usage.sh budget` ile aynı tanım). Taban = gerçek taze + kaçınılan tahmini taze; `oran = (taban − gerçek) / taban × 100`. Taban ve gerçek aynı kapsamdadır (görev). Hiçbir yürütme fiyatlanamıyorsa "N/A — insufficient baseline data".
- Yönlendirme token sayısını değiştirmez (fiyatını değiştirir), bu yüzden token tasarrufuna girmez. Kabuk betiği işi için token değeri **atanmaz**.

**Maliyet** (token ile karıştırılmaz, ayrı yüzde):
- Yönlendirme: `REPORT_BASELINE_MODEL` (`sdkit.env`, `pricing.json`'daki model kimliği; **boşsa N/A**, kit varsayım üretmez). Orkestratör dışı, ölçülmüş, fiyatlanmış her koşunun **aynı token'ları** taban modelde `usage.sh --as-model` ile fiyatlanır; `delta = Σ(taban maliyet − gerçek maliyet)`. Taban modelde koşan 0 katkı verir; **daha pahalı modelde koşan negatif** katkı verir (gerileme gösterilir, gizlenmez). Güven: low (farklı model aynı sayıda token üretmeyebilir).
- Kaçınılan yürütme maliyeti: karşılaştırılabilir koşuların ortalama maliyeti × sayı (yalnızca hepsi fiyatlıysa).
- `taban maliyet = gerçek fiyatlı maliyet + yönlendirme delta + kaçınılan`; `tasarruf = taban − gerçek`; `oran = tasarruf / taban × 100`. Fiyatsız koşular dışarıda kalır ve kapsam satırında ("3 of 4 run(s) priced") yazılır.
- Her tasarruf: taban kaynağı, yöntem, kapsam, güven, ölçülen/tahmin ayrımı ile gelir.

## 6. Çift sayımın önlenmesi

Tüm sayılar `usage.sh`'ın uzlaştırılmış satırlarından gelir: anahtar `(yürütme kimliği, model)`; snapshot final'i ezmez, küçük okuma büyüğü ezmez. Aynı koşunun iki kez yazılması, iç içe ajanın ana oturumda tekrar görünmesi tek koşudur. Oturum özeti görev raporlarını **toplamaz**; defter satırlarını oturum kimliğiyle süzer, bu yüzden birden çok oturuma yayılan görev oturumlar arasında bölünür ama hiçbiri iki kez sayılmaz. Kaçınılan yürütmeler yalnızca tamamen o oturumun içindeki görevlerden toplanır; yayılan görevler özette not edilir.

Rol ile fiziksel koşu ayrıdır: tabloda `rol (tür)`, tür `orchestrator` (ana oturum), `subagent` (devredilen ajan) veya `host-agent` (`run-role.sh` ile ayrı host süreci; kimliği `rr-…`). Aynı rol iki modelde koştuysa iki satır; koşu sayısı tekil kimliktir.

## 7. Sınırlar

- Karşı-olgu tahmindir: taban modelin aynı işte aynı token'ı kullanacağı varsayılır. Güven "low" yazılır.
- `REPORT_BASELINE_MODEL` boşsa yönlendirme tasarrufu N/A'dır; kit varsayılan model uydurmaz.
- Yönlendirme kararları yalnızca kaydedildiğinde (`--reserve`, `ROUTING=on`) kaçınılan yürütme olarak sayılır; kararsız yolda atlanan işler görünmez.
- Codex, OpenCode, Cursor token bildirmez: rapor bunları `unmeasured` sayar, maliyet/tasarruf alt sınırdır (F07 sınırları aynen geçerli).
- Oturum bitiş sinyali yalnızca Claude Code `SessionEnd` hook'unda var. Diğer host'larda oturum raporu `sdkit report session ID` ile istenir; `running`/`interrupted` durumları bitiş sinyali olmadığını söyler.
- `SessionEnd` çıktısı kullanıcıya gösterilmeyebilir; özet her durumda saklanır ve `sdkit report latest` ile okunur.
- Görev kaydı `work/<slug>` silinirse kayıtlar arşivdedir (`telemetry.sh archive` artık routing/context/selection dosyalarını da kopyalar); arşiv yoksa `regenerate` saklı raporu bozmadan bırakır.
- "Değişen dosya" `git diff <base>` + izlenmeyen dosyalardır; birleşmeden sonra boş çıkarsa `N/A`.
- Test seçimi için atlanan süitlerin süresi hiç ölçülmediğinden zaman tasarrufu yalnızca önbellekten yeniden kullanılan yeşil koşular için raporlanır.

## 8. Ek yük

Bir görev raporu: `usage.sh` + `telemetry.sh summary` + `resolve-base.sh` + birkaç `jq`; ölçüm `tests/report.test.sh` çıktısında ve teslim notunda. Rapor yalnızca görev/oturum sonunda üretilir, araç çağrısı başına değil.
