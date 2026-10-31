# Projeleri güncelleme

Kit iki yerde yaşar, ikisi ayrı güncellenir.

| Parça | Nerede | Nasıl güncellenir |
|---|---|---|
| **Plugin tarafı** (skill, rol, hook, script) | Claude Code'un plugin önbelleği | Kit repo'sunda sürüm artar ve değişiklik marketplace kaynağına (kit'in git remote'u) ulaşır; projede plugin yenilenir |
| **Proje tarafı** (`<project-dir>`: `project.md`, `project.env`, `rules/`, ...) | Projenin kendi repo'su | `bin/upgrade.sh`: yeni dosyaları ekler, sizin dosyalarınıza dokunmaz |

## Adımlar (Claude Code, plugin modu)

1. **Kit'te yayın:** değişiklikler kit'in marketplace'in baktığı dala (varsayılan branch) girmiş ve `plugin.json` + `marketplace.json` sürümü artmış olmalı. Sürüm artmadan Claude Code yeni sürümü görmez.
2. **Projede plugin'i yenile:** Claude Code'da `/plugin` ile `spec-driven-kit` marketplace'ini güncelle, sonra plugin'i güncelle; sonra Claude Code'u (oturumu) yeniden başlat. Komut adları sürüme göre değişebilir, `/plugin` menüsü her zaman çalışır.
3. **Proje tarafını yükselt:** kit'in bir checkout'undan
   ```bash
   <kit>/bin/upgrade.sh /yol/proje
   ```
   Host, mod ve stack'i kendisi bulur. Yeni dosyaları (ör. `rules/test-first.md`) ekler, `.gitignore`'a eksik satırları ekler, copy modunda `sync.sh` çalıştırır, en sonda `doctor.sh` çalıştırır.
4. Aşağıdaki "sürüme göre elle yapılacaklar"a bak, `git diff` ile gözden geçir, commit'le.

Güncel olup olmadığını görmek için: `<project-dir>/.scaffold-version` projenin son yükseltildiği kit sürümüdür; plugin tarafı sürümü `/plugin` menüsünde görünür.

Copy modu ve Claude dışı hostlar (Codex, OpenCode, Cursor, Gemini): plugin yoktur; 3. adım yeterlidir (`sync.sh` yönetilen dosyaları günceller, yerel düzenlediklerinde çakışmayı farkla gösterir).

Birden çok proje: her biri için `upgrade.sh` bir kez çalıştırılır. Toplu yapmak için:
```bash
for p in ~/code/projeA ~/code/projeB; do <kit>/bin/upgrade.sh "$p"; done
```

## Sürüme göre elle yapılacaklar

### 0.3 → 0.4
`upgrade.sh` şunları kendisi yapar: yeni dosyaları ekler (yeni script ve hook'lar, `verifier-deep` rol dosyası, yeni stack betikleri), `.gitignore`'a eksik satırları ekler, yönetilen kopyaları `sync.sh` ile günceller (copy modu ve Claude dışı hostlar). Sizde kalanlar:

- **Copy modunda Claude projeleri:** yeni hook'ları kendi `.claude/settings.json`'ınıza birleştirin (dosya proje dosyasıdır, ezilmez; örnek: kit'teki `templates/settings.copy.json`). `guard-readonly`: `PreToolUse`, matcher `Bash|Edit|Write|NotebookEdit`. `usage-log`: `Stop` ve `SubagentStop`. Plugin modunda bunlar plugin ile gelir.
- **`.verify-cache/`:** verify artık yeşil sonucu aynı ağaç için önbellekler. `<project-dir>/.gitignore`'a `.verify-cache/` eklenir (`upgrade.sh` şablondaki eksik satırları ekler); yoksa elle ekleyin.
- **Yeni `project.env` anahtarları isteğe bağlıdır** (`USAGE_LOG`, `RUN_ROLE_HOST`, `VERIFIER_HOST`, `RUN_ROLE_MODEL_*`, `NODE_PM`, `VERIFY_BUILD`, `JAVA_BUILD_TOOL`, `EXTRA_REVIEW_SKILLS`). Boş = kapalı. Dosya sizindir, ezilmez; açıklamalar için `templates/project.env`'e bakın.
- **DoD satırı biçimi:** `check-plan-parity.sh` plan, `proposal.md` ve `tasks.md` eşitliğini betikle denetler. DoD maddelerini `D<n>: metin | Verified by: tür` biçiminde yazın; eski serbest biçimli maddelerde betik madde bulamaz (çıkış 2).
- **`high` riskte** doğrulayıcı artık `verifier-deep`'tir (strong katman, kit tarafında üretilir); ek ayar gerekmez. Başka bir sağlayıcıdan doğrulatmak için `VERIFIER_HOST` ayarlayın (`scripts/run-role.sh`).
- **Stack betikleri:** `verify.sh` artık ince bir giriş; mantık `steps.sh` (stack) ve `scripts/verify-core.sh` (ortak) içinde. Hepsi yönetilen dosyadır, `sync.sh` günceller. Kopyalanmış `verify.sh`'ı özelleştirdiyseniz `sync.sh` ÇAKIŞMA gösterir: özelleştirmeyi `verify.d/` politikasına veya `VERIFY_CMD`'ye taşıyıp yeni dosyayı alın.
- **Kullanım kaydı kapalıdır:** token defteri için `project.env`'e `USAGE_LOG=1` yazın; rapor `scripts/usage.sh report`.
- **Yeni davranışlar:** görev durumu `work/<slug>/state.json`'da tutulur (devam etme, tek otomatik yeniden deneme); verifier çıktısı `parse-verdict.sh` ile doğrulanır; paralel görevlerde `writes:` kapsamı `check-writes.sh` ile denetlenir; handoff'a `WORKTREE:` eklenir. Rollerde salt okunur kısıt artık her hostta uygulanır.
- **Kit bakımcıları:** `bin/build-adapters.sh --check` ve `tests/run.sh` çalıştırın; projeler için gerekmez.
- **Yeni host eklemek isterseniz:** `<kit>/bin/init.sh --host <host> /yol/proje` (ör. `opencode`, `cursor`, `gemini`); proje klasörü adı değişmez (var olan korunur).

### 0.2.x → 0.3.0
`upgrade.sh` şunları kendisi yapar: `rules/test-first.md` ve `rules/token-economy.md` eklenir, `.gitignore`'a `work/` eklenir. Sizde kalanlar:

- **`CLAUDE.md` haritası** (`.claude/CLAUDE.md`): proje dosyasıdır, ezilmez. Yeni rolleri ve plan kapısını anlatan güncel metin için `templates/CLAUDE.md`'ye bakıp isteğinize göre birleştirin. Zorunlu değil; skill'ler kendi akışını taşır.
- **`project.md`'de rubrik** zorunlu olmaya devam eder; yeni bir alan yoktur. Test düzeni bölümünü doldurun: plan kapısı "Verified by" için buraya bakar.
- **Davranış değişiklikleri:** `spec-driven-dev` artık `propose`'dan önce plan kapısında sizi detaylıca sorgular; `analyst` rolü görevi inceler; `medium`/`high`'da DoD maddeleri "Verified by" taşımak zorundadır. Mevcut açık `openspec` change'lerinizi etkilemez.
- **Yeni roller** (`analyst`, `scout`, `engineer`, `developer`, `devsecops`) plugin ile gelir; ek ayar gerekmez. Model seviyeleri `core/tiers.env`'de (kit tarafında) tanımlıdır.
- **Proje klasörü adı** eski projelerde `.claude` olarak kalır; kit onu adıyla bulur. Taşımak zorunda değilsiniz.
- **Codex'e geçmek isterseniz:** `<kit>/bin/init.sh --host claude,codex /yol/proje` yeni dosyaları (`AGENTS.md`, `.agents/`, `.codex/`, `.githooks/`) ekler; proje klasörü `.claude` olarak kalır (var olan korunur). Her klonda `git config core.hooksPath .githooks`.

## Shared files (AGENTS.md, CLAUDE.md, settings.json, hooks.json, config.toml)

From this version the kit writes only its own part of these files (a `spec-driven-kit:begin/end` block in text files, only kit-owned keys and entries in JSON) and `sync.sh`/`upgrade.sh` refresh just that part. The first `upgrade.sh` on an existing repo appends the block to an unmarked `AGENTS.md`/`CLAUDE.md`; if an older kit generated text there, delete that text once. New: `<project-dir>/roles.d/<role>.md` (project addendum for a role), `OPENCODE_SHELL_KEY` in `project.env`.

## Server-side gate, machine install and drift check (0.4.0, phase gate)

- Run `<kit>/bin/install.sh` once per machine so the git hooks find the kit in repos that carry no copy of the scripts.
- `init.sh` now also copies `sdd.sh` and `resolve-base.sh` into `<project-dir>/scripts/` in every mode (CI runs them). `upgrade.sh` adds them and keeps them in sync.
- Add the CI gate with `init.sh --ci bitbucket|github` (merge it into an existing pipeline file by hand), mark the check required, and protect `<project-dir>/attestations/` with code review.
- Tasks that finish `verified` now write `<project-dir>/attestations/<task>.json`; commit it with the change.
- `sync.sh --check` fails on drift between the managed copies and the kit; `doctor.sh` reports drift, the CI gate and the machine registration.

## Memory, token budgets and a hook fix (0.5.0)

- **Everything new is off by default.** Add the keys you want to `project.env` (existing files are never overwritten; copy them from `templates/project.env`): `MEMORY*` (project memory), `TOKEN_BUDGET_TASK`, `TOKEN_BUDGET_WARN_PCT`, `MAX_SPAWNS`, `SUBAGENT_RESULT_MAX_LINES`. `upgrade.sh` adds the new scripts (`memory.sh`, `lookup-cache.sh`) and hooks (`guard-budget.sh`, `result-size.sh`) and changes nothing else.
- **Project memory is opt-in:** `sdkit init --memory [--memory-vcs commit|ignore]` creates `<project-dir>/knowledge/INDEX.md`, sets `MEMORY=1` in `project.env` and, for `ignore`, adds the directory to `<project-dir>/.gitignore`. Use `MEMORY_VCS` to say whether the team shares the entries.
- **Fix, worth a look:** `hooks/hooks.json` (and `templates/settings.copy.json`) declared `SubagentStop` twice, so only `record-verdict` ever ran and per-subagent token usage was never logged on Claude Code. It is one list now. Copy-mode projects: `upgrade.sh` merges the missing entries into `.claude/settings.json`; check that `SubagentStop` there lists `record-verdict.sh`, `usage-log.sh` and `result-size.sh`, and that `PreToolUse` has the `Agent|Task` entry for `guard-budget.sh`.
- Roles now keep answers to 15 lines plus their block and may be handed an `OUT:` path; run `sdkit sync` to refresh the role files.

## 1.0.0: one shared `.sdkit/` directory and a personal `sdkit.env`

What changes for a repo set up with 0.x (everything keeps working until you migrate):

- **New layout.** The project directory is `.sdkit/` for every host. It is committed and identical for everyone, except `sdkit.env` (personal settings: limits, memory, hosts), `work/` and generated files, which `.sdkit/.gitignore` keeps out. `project.env` is now `sdkit.env`; the old file name is still read.
- **Migrate when you are ready:** `sdkit upgrade --migrate` shows a dry run; add `--apply` to do it (backup first in `.git/sdkit-migrate-*.tgz`). It `git mv`s the kit-owned files (`project.md`, `rules/`, `known-pitfalls.md`, `adr/`, `verify.d/`, `roles.d/`, `attestations/`, `knowledge/` -> `memory/`), takes `sdkit.env` out of git (it stays on disk), removes the kit's generated copies from the old directory and the kit's plugin/hook keys from `.claude/settings.json`, then rebuilds the rest. Your own skills, commands, agents and `.claude/memory/` are not touched. Commit the result; teammates run `sdkit init` once on their machine.
- **Host files are per machine now.** On Claude the kit writes `.claude/settings.local.json` instead of `settings.json`; roles, hooks, `.agents/`, `.githooks/` are generated and hidden in `.git/info/exclude`. Only `AGENTS.md` and the kit block in `.claude/CLAUDE.md` are meant to be committed.
- **Defaults arrive by themselves.** `sdkit init` and `sdkit upgrade` append every setting that is new in the template to your `sdkit.env` / `project.env` with its default and comment; your lines and values are never changed. That includes `MEMORY=1` and `USAGE_LOG=1` (on by default from 1.0): set them empty to turn them off. The limits (`TOKEN_BUDGET_TASK`, `MAX_SPAWNS`, `SUBAGENT_RESULT_MAX_LINES`) stay empty.
- **Memory moved:** the directory is `memory/` (was `knowledge/` in 0.5) and is shared through git; `--memory-vcs ignore` keeps it personal.
- **CI gate** (`init --ci`, `attestations/`) stays optional. CI runs without your `sdkit.env`, so the defaults apply; set `SDD_FREE_GLOBS` and the like as CI environment variables if you need them there. `.sdkit/scripts/sdd.sh` and `resolve-base.sh` are committed for that reason.
- **Old kits** (0.5.x and earlier) do not find `.sdkit/sdkit.env`; upgrade the machine's kit first (`brew upgrade sdkit`). The legacy lookup (`.claude`, `.codex`, `.agentkit` with `project.env`) stays in 1.x and is planned to go in the next major release.

## 1.0.1: marketplace address with a Homebrew install

With 0.5.0 and 1.0.0, `sdkit init` run from a Homebrew install wrote the wrong plugin address (`https://github.com/Homebrew/brew`) into the Claude settings, because the kit's folder sits inside Homebrew's own git repository. From 1.0.1 a packaged kit uses the `repository` field of `.claude-plugin/plugin.json`. If you ran `init` or `upgrade` with an affected version, check `extraKnownMarketplaces` in `.claude/settings.json` / `settings.local.json`; `sdkit upgrade --migrate` removes the old entry and writes the right one, or pass `--marketplace-url` to `init`.

## 1.1.0: team settings in a shared `sdkit.env`, personal ones in `sdkit.local.env`

In 1.0.0 the settings file was personal and git-ignored, which left the team's own rules (release flow, protected paths and branches, production cluster, secret patterns, stack) on one developer's machine. From 1.1.0:

- **`.sdkit/sdkit.env` is committed** and holds the team's policy. **`.sdkit/sdkit.local.env` is personal** (git-ignored, read after `sdkit.env`, so it wins): token budget and limits, `USAGE_LOG`, `MAX_PARALLEL`, memory behaviour, hosts and models.
- **Nothing to do by hand.** `sdkit upgrade` (or `sdkit init`) on a 1.0.0 repo moves the personal keys with their values into `sdkit.local.env`, removes them (and the comments the kit wrote above them) from `sdkit.env`, flips `.sdkit/.gitignore` and adds `!sdkit.env` so a root `*.env` rule cannot hide the shared file. Then **commit `sdkit.env`**; teammates get the same policy and run `sdkit init` once for their personal file.
- `sdkit upgrade --migrate` from a pre-1.0 repo does the same split while moving `project.env` to `sdkit.env` (the file stays in git, renamed).
- A pre-1.0 layout keeps a single `project.env` with every setting; both templates' new settings are appended to it.

## 2.0.0 (not yet released): settings files are parsed, not run; optional risk floor

This is a breaking change, so it targets 2.0.0 (the version files are not bumped yet). Settings files are parsed (below); everything else in this section needs no action.

### Settings files are parsed, not run

`sdkit.env`, `sdkit.local.env` and a pre-1.0 `project.env` used to be `source`d, so any line in them ran as shell at every hook, git hook and script. They are now read by `scripts/env.sh`, which only assigns values. Most repos need nothing.

**Still works, with the same meaning:** `KEY=value`, `KEY="value"`, `KEY='value'` (literal), `export KEY=value`, `: "${KEY:=default}"`, blank lines, `# comments` and a trailing ` # comment` after an unquoted value. A value may use `$NAME` or `${NAME}` (a setting read earlier, `sdkit.local.env` after `sdkit.env`). Commands in `VERIFY_CMD`, `DIFF_BASE_CMD` and the like are values: they are still run, when the kit calls them, not when it reads the file.

**Ignored (reported on stderr and by `sdkit doctor` as `file:line`, never with the content):** command substitution (`$(...)`, backticks), `;` `&&` `|` `>`, an unquoted space (`KEY=a b`: quote it), `${NAME:-x}` and other expansions, multi-line values, bare commands (`source other.env`, `cd`, `if ...`), and keys that change how the shell runs (`PATH`, `IFS`, `HOME`, `BASH_*`, `LD_*`, `DYLD_*`, `TMPDIR`, `KIT_DIR`, ...).

**What to do**
1. `sdkit upgrade`, not only `sdkit sync`: it adds the new managed `scripts/env.sh` next to the scripts you vendored (copy mode, non-Claude hosts, the CI gate). A script that finds no `env.sh` stops and says so; hooks stay silent and read no settings.
2. `sdkit doctor` lists every line the kit now ignores. Fix each one: write the value out, or move the logic into a script and point `VERIFY_CMD` (or another command setting) at it.
3. `STACK` empty or missing still means `go` (the documented default, unchanged for repos from before stacks existed). Every script now takes that default from one place, and `doctor` warns when `STACK` is not set. One behaviour changes: `sdd.sh advance verified` for `low` risk used to fall back to the `generic` stack in that case and now uses `go`, like the hooks and git hooks did.

### Risk floor (optional, off by default)
`RISK_FLOOR_GLOBS` in `sdkit.env` (empty after `sdkit upgrade` appends it, so nothing changes until you set it): `level:glob,level:glob`, e.g. `high:services/payments/*,medium:migrations/*.sql,medium:*/auth/*`. A task whose diff touches a matching file may not carry a lower risk label than the strictest matching level. The label stays the user's choice; the floor only stops it from being too low for what the diff really touches.
- Checked by `sdd.sh advance green` and `advance verified` (strict refuses, guided warns, off ignores), on the files that really changed (the same set the fingerprint covers, untracked files included), and by `sdd.sh ci-check`, which recomputes the floor itself, ignores the attestation's `floor` field, and rejects an attestation whose `risk` is below it. A raised `risk` written by hand into an attestation still needs `verdict: PASS`.
- CI also reads `RISK_FLOOR_GLOBS` and `SDD_MODE` from the **base branch's** committed `sdkit.env`: a pull request that empties the floor or sets `SDD_MODE=off` is still held to the base. A file matching a floor entry needs an attestation even where `SDD_FREE_GLOBS` or the docs globs would free it.
- A malformed value fails closed: `sdd.sh start`, `ci-check` and `sdkit doctor` refuse it (`sdd.sh floor --validate` checks it). `sdd.sh floor` prints the floor of the current diff.
- Limits: it constrains the label, it does not choose it, and a reviewer must still protect `sdkit.env` and `attestations/` (CODEOWNERS); an attestation whose JSON is forged outright (a `high` label with `PASS`) is the documented attestation limit. A personal `sdkit.local.env` can relax the local check, never CI. Putting a path under a floor changes the diff fingerprint (it edits `sdkit.env`), so attestations made before that need to be re-verified. Existing attestations without the `floor` field are still accepted.

### Also in this release (no action needed)
- Claude Code: the `SubagentStop` hook now validates the verifier's block with `parse-verdict.sh` and records only a well-formed one; a malformed or contradictory block is reported to the orchestrator and records nothing. The skill no longer tells Claude to pass `--record` (the `guard-pr` hook denied it there); other hosts still do, and `guard-pr` allows it for them.
- Spawn counts, task state, the usage ledger and the SDD state are written under a lock, so parallel agents no longer lose updates. Budget and ledger follow the task the phase machine has open (`sdd.sh task`), falling back to the newest `work/*/state.json` as before.
- `lookup-cache.sh` answers are dropped when an untracked file is added or edited.
- New, off by default: `TELEMETRY=1` in `sdkit.local.env` records structured run events in `work/<slug>/events.jsonl` (`scripts/telemetry.sh summary`), and `bench/` holds a benchmark runner. Nothing changes while the setting is empty; `sdkit upgrade` adds the empty line. Details: [design-telemetry.md](design-telemetry.md).
- `sdkit_lock` no longer waits on a directory nobody can write to.
- New, off by default: `CONTRACTS=1` in `sdkit.env` (a team setting) turns on agent contracts. A handoff with a `CONTRACT:` line is validated and its answer's `HANDOFF-RESULT/1` line is checked by `scripts/contract.sh` (Claude Code hook `check-contract`, and `run-role.sh` on every host, which then also exits 4/5 on a broken or non-done contract). Handoffs without that line behave exactly as before; nothing to migrate. Copy-mode installs get the hook through `templates/settings.copy.json` after `sdkit sync`. Details and host limits: [design-contracts.md](design-contracts.md).
- New, opt-in per task: `sdd.sh start --profile small|standard|high-assurance` (default `standard`, i.e. unchanged). `high-assurance` requires an independent verifier PASS at every risk and agent contracts for writing and deciding roles; `small` is low risk only. `sdd.sh transitions` and `sdd.sh policy` print the rules. Behaviour changes that apply to everyone: a refused move now records a `reason` (telemetry), two simultaneous `advance`/`start` calls no longer both succeed, and `sdd.sh advance verified` is accepted again after a late edit (it used to be refused from `verified`, so the "re-verify" hint could not be followed). Tasks opened before this have no profile and read as `standard`. See docs/design-workflow.md.
- **High risk now enforces independent evidence (F04, [design-evidence.md](design-evidence.md)).** `sdd.sh advance verified|pr|done` on a `--risk high` task refuse unless verifier, reviewer and security-auditor each have a PASS from a *registered* agent run on the current diff. **Action:** on Claude Code nothing, the hooks (`guard-budget.sh` registers the spawn, `record-verdict.sh` records) already do it; on Codex, OpenCode, Cursor and Gemini run all three roles with `run-role.sh` (a verdict recorded by hand with `parse-verdict.sh --record` is kept but refused at `high`). `reviewer` and `security-auditor` now end with `SUMMARY` and `VERDICT: PASS|BLOCK` (`sdkit sync` regenerates the role files). `ci-check` requires the same three PASSes in a `high` attestation, so an attestation written before this release no longer satisfies a new `high` diff: verify it again. Low and medium risk are unchanged. Also: a refused or lost `advance` never leaves a partial change or an attestation behind, and `sdd.sh evidence` shows each role's evidence state.

## 1.2.0: routing and orchestration (opt-in), GitHub distribution

Nothing changes until you opt in. `ROUTING=off` stays the default, so `run-role.sh`, budgets and the benchmarks behave as in 1.1.0.

- **Move the install to GitHub** (the kit left Bitbucket): `brew untap <the old tap>` (uninstall `sdkit` first, by its full `<tap>/sdkit` name if two taps provide it), `brew tap wecii/sdkit https://github.com/wecii/sdkit.git`, `brew trust wecii/sdkit`, `brew install wecii/sdkit/sdkit`.
  Claude Code: `claude plugin marketplace remove spec-driven-kit`, `claude plugin marketplace add wecii/sdkit`, reinstall `spec-driven-kit@spec-driven-kit` in each project. `brew uninstall` may also remove `jq` and `node` if nothing else needs them: reinstall them.
- **Per repo:** `sdkit upgrade <repo>` appends the new `ROUTING` / `ROUTE_*` settings to `sdkit.env` (all optional, `ROUTING=off`) and the personal limits to `sdkit.local.env`. It never rewrites your values. Do it on a clean branch.
- **Exit codes of `run-role.sh` with `ROUTING=on`:** 7 = valid evidence already exists (nothing to run, do not retry), 8 = routing declined to run and there is no valid result (never a pass). Scripts that call `run-role.sh` must handle both.
- **Turning it on:** set `RUN_ROLE_HOST` (and `VERIFIER_HOST` for independent roles), then `ROUTING=on`; look at a decision first with `route.sh explain --role <role>`. Details and limits: [design-routing.md](design-routing.md).
