# Kullanım ve maliyet muhasebesi (F07)

`usage.sh` defteri artık eksiksiz, tekilleştirilmiş, model farkında ve yeniden hesaplanabilir. Hiçbir LLM çağrısı yok; fiyat ve kullanım **uydurulmaz**. Doğrulama: `tests/usage.test.sh`.

## 1. Kök neden analizi

Kod okunarak ve gerçek Claude Code transkriptleri (`~/.claude/projects`) üzerinde ölçülerek bulundu.

| # | Belirti | Kök neden | Kanıt |
|---|---|---|---|
| R1 | Alt agent çıktı token'ları eksik | `hooks/usage-log.sh` mesaj başına `unique_by(.id)` ile **ilk** tekrarı tutuyordu; akışlı mesaj aynı `id` ile büyüyen `output_tokens` ile tekrarlanır | 6177 tekrarlı mesaj kimliğinden 853'ünde değerler farklı; alt agent transkriptlerinde çıktı **%31,4 eksik** (1.904.471 → 2.776.239). Örnek agent: 6.544 yerine 16.165 |
| R2 | Mesajlar silinebilir | Kimliği olmayan mesajlar tek grupta birleşirdi (`unique_by` null anahtar) | kod okuma; testle sabitlendi |
| R3 | Ana oturum usage'ı alt agent'a yazılabilir | `SubagentStop` için `agent_transcript_path // transcript_path`: yol yoksa **ana** transkript okunur, tüm oturum alt agent rolüne (ör. analyst) yazılırdı | kod okuma. Alt agent transkriptleri ayrı dosyada: `<oturum>/subagents/agent-<id>.jsonl` (+ `.meta.json`) |
| R4 | Eksik agent yürütmeleri (ör. analyst) | Transkript okunamazsa hook sessizce çıkıyordu; `run-role.sh` host hata verince (rc≠0, zaman aşımı) hiç satır yazmıyordu. Boşluk görünmezdi | kod okuma |
| R5 | Orkestratör eksik/yarım | Orkestratör yalnızca `Stop`'ta (tur sonu) anlık görüntü alır; kesilen oturumda hiç yazılmaz. Anlık görüntü ile son kayıt ayrımı yoktu: geç/küçük bir görüntü büyüğünü ezebilirdi | kod okuma |
| R6 | Model bazında maliyet yok | Satır başına tek model (son görülen); oturum model değiştirirse tümü son modelin fiyatından. Sağlayıcı, oturum, köken alanı yoktu | defter şeması v1 |
| R7 | `cost_est` 0 / hiç yok | `usage.sh report` maliyet hesaplamıyordu. Fiyat yalnızca `telemetry.sh`/`route.sh`'ta, düz `{model:{in,out}}` biçiminde, tarih/sağlayıcı yok, tablo yoksa sessizce "unavailable" | kod okuma |
| R8 | Önbellek oranı doğrulanmamış | Formül doğru (`cache_read/(in+cache_read+cache_write)`) ama testsiz, `floor` yüzdesi, kısmi/tekrarlı satırları dışlamıyordu | `tests/usage.test.sh` elle hesaplı |
| R9 | Proje toplamı yok | Kapanışta `work/<slug>` silinir; rapor yalnızca açık görevleri toplardı | `telemetry.sh archive` zaten `_archive/<slug>.usage.jsonl` kopyalıyor, rapor okumuyordu |

R1'in etkisi: ana oturum transkriptlerinde tekrarlar çoğunlukla aynıdır (ölçülen örnekte eski ve yeni sonuç eşit); fark alt agent transkriptlerinde (akış ara değerleri) çıkar.

## 2. Defter (`work/<slug>/usage.jsonl`) – şema v2

Eski alanlar aynen durur; yeni alanlar eklemelidir (eksikse eski satır sayılır).

| Alan | Anlam |
|---|---|
| `in` | **önbellek hariç** giriş token'ı |
| `out`, `cache_read`, `cache_write` | çıkış, önbellekten okunan, önbelleğe yazılan |
| `model`, `provider` | model kimliği; sağlayıcı yalnızca kaynaktan görülürse (`msg_bdrk_`→bedrock, `msg_vrtx_`→vertex, `msg_`→anthropic), yoksa boş |
| `role`, `tier`, `host`, `ts` | rol, katman, host, UTC zaman |
| `session` | oturum kimliği |
| `id` | kararlı **yürütme kimliği** (alt agent: `agent_id`; orkestratör: `session-<oturum>`; `run-role`: `rr-…`) |
| `origin` | `sdk` (hook / run-role kaydetti) veya `observed` (`usage.sh scan` transkriptten okudu) |
| `kind` | `snapshot` (artabilir) veya `final` (bitti) |
| `status` | `interrupted` (yarıda kalan koşu) |
| `tq` | `unavailable`: token okunamadı; sıfırlar **ölçülmemiş** demektir |
| `cost_est_usd`, `cost_src` | host'un kendi tahmini (fatura değil); kit hesabından ayrı |

**Tekilleştirme.** Anahtar `(id, model)`. Yazarken: snapshot `final`'i ezmez, küçük okuma büyüğü ezmez (sayaçlar yalnızca artar), gerçek sayılar `unavailable` işaretini ezer. Rapor aynı kuralı okurken de uygular (kanıt sırası: final > ölçülmüş > büyük toplam > geç), böylece sıra dışı/çift satırlar da tek sayılır. Kimliksiz eski satırlar eşleştirilemez: her biri sayılır ve uyarı verilir.

**Çok model.** Bir transkript birden çok model kullanırsa model başına bir satır yazılır (aynı `id`); her biri kendi fiyatından hesaplanır, koşu sayısı tekil `id`'dir.

**SDK ve gözlenen.** Hook'lar `origin: sdk` yazar. `usage.sh scan` hook'un hiç görmediği (kapalı hook, kesilen, harici) Claude Code oturumlarını transkriptten okur ve aynı `id`'lerle `observed` yazar; hook zaten yazdıysa **çift sayılmaz**. Varsayılan: en son oturum; `--session`, `--since`, `--dir`.

## 3. Fiyatlandırma

`<project-dir>/pricing.json` (veya `TELEMETRY_PRICES`). **Kit fiyat içermez**; değerleri kendi sözleşmenizden doldurun. USD / milyon token.

```json
{ "version": 2, "currency": "USD",
  "models": [
    { "model": "<model-kimliği>", "provider": "bedrock", "effective_from": "2026-01-01", "effective_to": null,
      "in": 0.0, "out": 0.0, "cache_read": 0.0, "cache_write": 0.0, "source": "<fiyat sayfası/sözleşme>" } ] }
```

Eski düz biçim (`{"<model>": {"in":…, "out":…}}`) çalışmaya devam eder (sürümsüz, tarihsiz, sağlayıcısız). `telemetry.sh` ve `route.sh` v2 tablosunu `sdkit_prices_flat` ile bugün geçerli düz tabloya çevirerek okur.

**Çözüm yolu (belirleyici, bu sırayla):** (1) tablo: `TELEMETRY_PRICES` → `<project-dir>/pricing.json` → yok; (2) model: tam eşleşme, yoksa `-YYYYMMDD` soneki atılmış taban kimlik; (3) sağlayıcı: kaydın sağlayıcısı biliniyorsa girdi aynı sağlayıcıda veya sağlayıcısız olmalı; bilinmiyorsa ve ≥2 farklı sağlayıcı aday ise `ambiguous_provider`; (4) etkin tarih: kaydın günü `[effective_from, effective_to]` içinde; (5) birden çok aday: önce sağlayıcıya özgü olan, sonra en son `effective_from`.

**Çözülemezse maliyet `null`dur, sıfır değil:** `no_pricing_table`, `pricing_table_has_no_models`, `unknown_model` (model kimliği yok dahil), `provider_mismatch`, `ambiguous_provider`, `not_effective_on_record_date`, `missing_rate:<tür>` (token'ı olan bir tür için oran yok; token'ı 0 olan tür için oran gerekmez), `tokens_unavailable`. Okunamayan tablo ve USD dışı para birimi uyarı verir.

## 4. Maliyet ve rapor

Maliyet deftere **yazılmaz**; her raporda token × yürürlükteki tablo ile hesaplanır. Fiyat güncellenince tüm geçmiş yeniden hesaplanır. İç hesap tam duyarlıklıdır (jq çift duyarlık), yalnızca gösterimde 4 ondalığa yuvarlanır. Token sayıları ve maliyet ayrı kalır.

Üç ayrı tutar, birbirine karıştırılmaz: **API-eşdeğeri tahmin** (token × `pricing.json`, bu rapor), **host tahmini** (Claude Code `total_cost_usd`, fatura değil) ve **faturalanan** (`billed`, daima "unavailable": hiçbir kaynak bildirmez; Claude Code aboneliğinde token başına fatura yoktur, tahmin yalnızca aynı token'ların API fiyatıyla maliyetidir).

```bash
usage.sh report [slug] [--project] [--session ID|current] [--json]
usage.sh prices [--json]
usage.sh scan [--session ID | --since YYYY-MM-DD] [--dir DIR] [--slug S]
usage.sh extract <transkript>
```

Rapor: rol, model, oturum tabloları; önbellek isabeti (`cache_read / (in + cache_read + cache_write)`, 1 ondalık) ve API-eşdeğeri tasarruf; tahmini maliyet; kapsama satırı. **Toplam `PARTIAL`** olur (alt sınır) şu durumlarda: fiyatsız koşu, ölçülmemiş koşu (`tq: unavailable`), fiyat tablosu yok/okunamıyor, orkestratör kaydı olmayan oturum (`scan` önerilir), kaydedilen spawn sayısından az ajan kaydı (`state.json .spawns`), kimliksiz eski satır. `--project` arşivlenmiş görevleri (`work/_archive/*.usage.jsonl`, `telemetry.sh archive` yazar) ekler; varsayılan kapsam eskisi gibi açık görevlerdir.

## 5. Önce / sonra

Gerçek bir Claude Code alt agent transkripti (`Explore`, claude-sonnet-5-5) üzerinde:

```
ÖNCE                                                  SONRA (usage.sh scan + report, örnek fiyatlarla)
role     tier runs in  out   cache_read cache_write   role          runs in  out    cache_read cache_write est_usd
Explore  -    1    60  6544  2549093    139803         Explore       1    60  16165  2549093    139803      $1.5316
TOTAL    -    1    60  6544  2549093    139803         orchestrator  1    202 65568  13210783   284495      $6.0142
cache hit rate: 94%                                    TOTAL         2    262 81733  15759876   424298      $7.5459
(model yok, maliyet yok, kapsam yok)                   model claude-sonnet-5-5 / bedrock; hit rate 97.4%; billed: unavailable
```

Çıktı token'ı 6544 → 16165 (akış ara değeri değil, son değer); orkestratör satırı artık yazılıyor; model/sağlayıcı kırılımı, maliyet ve kapsam uyarıları var. (Fiyatlar yalnızca gösterim içindir.)

## 6. Kalan sınırlar ve doğruluk garantileri

**Garanti:** token sayıları, transkriptte kaydedilen `usage` değerleridir (mesaj başına bir kez, akış tekrarlarında en büyüğü); aynı `id` iki kez sayılmaz; maliyet yalnızca çözümlenen bir fiyat girdisiyle hesaplanır, aksi halde `null` ve uyarı; toplam eksik veride `PARTIAL`; maliyet saklanmadığı için fiyat değişince tutarlı yeniden hesaplanır; aynı defter + aynı tablo = aynı sonuç.

**Sınırlar:**
- Kayıt hiç yazılmamış bir yürütme **kanıtlanamaz**: kapsam yalnızca ipuçlarıyla (spawn sayacı, orkestratörsüz oturum, `unavailable` işareti) uyarılır. "Tam" rapor, kaydedilen veri için tamdır.
- Codex, OpenCode, Cursor token bildirmez (`unavailable`); Gemini önbellek bildirmez. Bunların maliyeti hesaplanamaz.
- `scan` ve hook kimliklerinin aynı olduğu varsayımı: alt agent kimliği `agent_id` = `agent-<id>.jsonl` dosya adı. Farklı bir Claude Code sürümünde bu tutmazsa çift sayım olabilir; gerçek hook yüküyle doğrulanmadı (yalnızca dosya adlandırması ve `.meta.json` gerçek transkriptlerde görüldü).
- `scan` bir oturumun tamamını görev defterine yazar; oturum görev dışı iş de içeriyorsa görev fazla görünür.
- Sağlayıcı yalnızca transkript mesaj kimliği ön ekinden çıkarılır; sunucu/geçit (proxy) arkasında yanlış veya boş olabilir (boşsa sağlayıcısız fiyat girdisi kullanılır).
- Fiyatlar kullanıcıdan gelir; yanlış tablo yanlış maliyet üretir. Uzun vadeli/ayrı fiyat (1 saatlik önbellek yazımı, toplu/öncelikli katman, uzun bağlam eşiği) modellenmez: `cache_write` tek orandır.
- Gerçek faturalanan tutar bilinmez; abonelik kullanımında bu rapor yalnızca API-eşdeğeridir.
- Kapanışta `work/<slug>` silinir; proje toplamı için önce `telemetry.sh archive` (TELEMETRY=1) çalışmış olmalıdır.
- Hata sınırı: eşzamanlı yazmalar `sdkit_lock` ile korunur; kilidin kırılma süreleri aynıdır (3 sn / 10 sn).
