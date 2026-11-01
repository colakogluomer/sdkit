# Güvenlik sertleştirme (F19)

Denetim, kitin **gerçekte zorladığı** şeyleri ayırır (hook/script kodu) ve yalnızca istemde yazılı olanları "zorlanmaz" sayar.

| Alan | Zorlama | Nerede |
|---|---|---|
| Salt-okunur roller | `agents/*.md` araç listesinde Edit/Write yok + `guard-readonly.sh` hook'u | `audit.sh policy` ikisini de denetler |
| Gizli bilgi | `guard-secrets.sh`; görünümlerde `redact.sh` (özet/zarf çıktıları, hata iletileri, denetim değerleri) | tam metin diskte **değiştirilmez** (kanıt bütünlüğü) |
| Sağlayıcıya veri çıkışı | `adapters.d/litellm.sh`: `LITELLM_EGRESS=allow`, ana makine izin listesi, metin-yalnız (bağımsız roller ve yazan roller reddedilir), anahtar stdin ile | denetim kaydı **önce** yazılır: kayıt yoksa istek yok |
| Denetim izi | `<project-dir>/audit.jsonl`, hash zincirli, yalnız üst veri (tür, rol, ana makine, bayt); istem/cevap/içerik yok, değer >120 karakter reddedilir | `audit.sh verify` ortadaki düzenleme/silmeyi bulur; **kuyruğu kesmeyi engelleyemez** |
| Harici adaptör | `adapters.d/*.sh` yazılabilir izinleri ve `capabilities` geçerliliği | `audit.sh policy` |

`redact.sh` bilinen biçimlerle çalışır (AWS anahtar kimliği, GitHub/Slack token'ları, `sk-…`, JWT, Bearer, `password=`, özel anahtar blokları). Bilinmeyen biçim geçer: **garanti değil, filtre**. Sandbox/worktree sınırı için `check-writes.sh` ve `worktree.sh merge` değişmedi. Bu turda denetimde bulunan kritik açık yok; kendi eklediğim yol için (litellm adaptörü) anahtarın `ps`'te görünmemesi ve hata iletilerinden maskelenmesi testle sabitlendi. Canlı sağlayıcı ve canlı Claude hook yükü denenmedi. `tests/security.test.sh`.
