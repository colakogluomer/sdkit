#!/usr/bin/env bash
# Smoke checks for the kit's deterministic scripts. Each case states whether it must pass or must fail.
# Usage: tests/run.sh      (exit 1 if any case misbehaves)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export PATH="$(cd "$(dirname "$0")" && pwd)/stubs:$PATH" OPENSPEC_STUB_LOG="${TMPDIR:-/tmp}/openspec-stub.$$.log"   # init must not need the real openspec
pass=0; failed=0
# expect <name> <exit-code> <command...>
expect() { local name="$1" want="$2"; shift 2; "$@" >"$tmp/out" 2>&1; local got=$?
  if [ "$got" = "$want" ]; then pass=$((pass + 1)); else failed=$((failed + 1)); echo "FAIL: $name (exit $got, wanted $want)"; sed 's/^/    /' "$tmp/out"; fi; }

# --- parse-verdict ---
cat > "$tmp/v-pass.txt" <<'X'
DOD
- D1 handles retry | PASS | retry_test.go:12
- D2 logs error | PASS | log_test.go:3
FINDINGS
- PLAUSIBLE | a.go:4 | maybe racy | two writers
VERIFY
- command: verify.sh | result: green | ok
VERDICT: PASS
X
sed 's/D2 logs error | PASS/D2 logs error | FAIL/; s/VERDICT: PASS/VERDICT: BLOCK/' "$tmp/v-pass.txt" > "$tmp/v-block.txt"
sed 's/VERDICT: PASS/VERDICT: BLOCK/' "$tmp/v-pass.txt" > "$tmp/v-inconsistent.txt"
grep -v '^FINDINGS' "$tmp/v-pass.txt" > "$tmp/v-nosection.txt"
printf '## Definition of Done\n- D1: a | Verified by: unit test\n- D2: b | Verified by: unit test\n- D3: c | Verified by: manual check\n' > "$tmp/prop3.md"
expect "verdict pass" 0 "$ROOT/scripts/parse-verdict.sh" "$tmp/v-pass.txt"
expect "verdict block" 1 "$ROOT/scripts/parse-verdict.sh" "$tmp/v-block.txt"
expect "verdict inconsistent with findings" 2 "$ROOT/scripts/parse-verdict.sh" "$tmp/v-inconsistent.txt"
expect "verdict missing section" 2 "$ROOT/scripts/parse-verdict.sh" "$tmp/v-nosection.txt"
expect "verdict skipped DoD item" 2 "$ROOT/scripts/parse-verdict.sh" "$tmp/v-pass.txt" --proposal "$tmp/prop3.md"

# --- check-plan-parity ---
cat > "$tmp/plan.md" <<'X'
# Plan
## 3. Definition of Done
- D1: Retries three times | Verified by: unit test
- D2: Logs the failure | Verified by: integration test
## 5. Execution plan
- [ ] T1 add retry | role: developer | writes: svc/ | after:
- [ ] T2 tests | role: test-writer | writes: svc/x_test.go | after: T1
X
cp "$tmp/plan.md" "$tmp/prop-ok.md"
sed 's/Retries three times/Retries twice/' "$tmp/plan.md" > "$tmp/prop-text.md"
sed 's/integration test/unit test/' "$tmp/plan.md" > "$tmp/prop-vb.md"
grep -v 'D2' "$tmp/plan.md" > "$tmp/prop-missing.md"
cp "$tmp/plan.md" "$tmp/tasks-ok.md"; sed 's/writes: svc\//writes: svc\/,pkg\//' "$tmp/plan.md" > "$tmp/tasks-bad.md"
expect "parity equal" 0 "$ROOT/scripts/check-plan-parity.sh" "$tmp/plan.md" "$tmp/prop-ok.md" "$tmp/tasks-ok.md"
expect "parity text differs" 1 "$ROOT/scripts/check-plan-parity.sh" "$tmp/plan.md" "$tmp/prop-text.md"
expect "parity text differs but --loose" 0 "$ROOT/scripts/check-plan-parity.sh" "$tmp/plan.md" "$tmp/prop-text.md" --loose
expect "parity verified-by differs" 1 "$ROOT/scripts/check-plan-parity.sh" "$tmp/plan.md" "$tmp/prop-vb.md"
expect "parity missing item" 1 "$ROOT/scripts/check-plan-parity.sh" "$tmp/plan.md" "$tmp/prop-missing.md"
expect "parity tasks differ" 1 "$ROOT/scripts/check-plan-parity.sh" "$tmp/plan.md" "$tmp/prop-ok.md" "$tmp/tasks-bad.md"

# --- state.sh, check-writes.sh (need a git repo with a project dir) ---
repo="$tmp/repo"; mkdir -p "$repo/.claude"; : > "$repo/.claude/project.env"
git -C "$repo" init -q && git -C "$repo" config user.email t@t && git -C "$repo" config user.name t
printf "work/\n" > "$repo/.claude/.gitignore"; mkdir -p "$repo/svc" "$repo/other"; echo a > "$repo/svc/a.go"; echo b > "$repo/other/b.go"
git -C "$repo" add -A && git -C "$repo" commit -qm init
cd "$repo" || exit 1
expect "state init" 0 "$ROOT/scripts/state.sh" demo init medium feat/x
expect "state task" 0 "$ROOT/scripts/state.sh" demo task T1 doing
expect "state bad status" 2 "$ROOT/scripts/state.sh" demo task T1 weird
expect "state first retry allowed" 0 "$ROOT/scripts/state.sh" demo retry T1
expect "state second retry refused" 1 "$ROOT/scripts/state.sh" demo retry T1
expect "state other task has own retry" 0 "$ROOT/scripts/state.sh" demo retry T2
[ "$("$ROOT/scripts/state.sh" demo get risk)" = medium ] && pass=$((pass + 1)) || { failed=$((failed + 1)); echo "FAIL: state get risk"; }
printf -- '- [ ] T1 impl | role: developer | writes: svc/ | after:\n- [ ] T2 docs | role: developer | after:\n' > "$tmp/tasks.md"
echo changed >> svc/a.go
expect "writes inside scope" 0 "$ROOT/scripts/check-writes.sh" "$tmp/tasks.md" T1 HEAD
echo changed >> other/b.go
expect "writes outside scope" 1 "$ROOT/scripts/check-writes.sh" "$tmp/tasks.md" T1 HEAD
expect "writes on read-only task" 1 "$ROOT/scripts/check-writes.sh" "$tmp/tasks.md" T2 HEAD
expect "writes unknown task" 2 "$ROOT/scripts/check-writes.sh" "$tmp/tasks.md" T9 HEAD
cd "$ROOT" || exit 1

# --- hooks: read-only roles and host adapters ---
hrepo="$tmp/hrepo"; mkdir -p "$hrepo/.claude"; printf 'SECRET_GLOBS=.env*\nPROTECTED_PATHS=infra\n' > "$hrepo/.claude/project.env"; git -C "$hrepo" init -q
ro() { printf '%s' "$1" | CLAUDE_PROJECT_DIR="$hrepo" "$ROOT/hooks/guard-readonly.sh"; }
denied() { ro "$1" | grep -q '"permissionDecision": "deny"'; }
allowed() { [ -z "$(ro "$1")" ]; }
expect "readonly role cannot Write" 0 denied '{"tool_name":"Write","tool_input":{"file_path":"a"},"agent_type":"spec-driven-kit:verifier"}'
expect "readonly role cannot redirect" 0 denied '{"tool_name":"Bash","tool_input":{"command":"echo x > f"},"agent_type":"reviewer"}'
expect "readonly role cannot chain git commit" 0 denied '{"tool_name":"Bash","tool_input":{"command":"git status && git commit -am x"},"agent_type":"reviewer"}'
expect "readonly role may git diff | tail" 0 allowed '{"tool_name":"Bash","tool_input":{"command":"git diff main...HEAD 2>&1 | tail -40"},"agent_type":"verifier"}'
expect "writer role may Write" 0 allowed '{"tool_name":"Write","tool_input":{"file_path":"a"},"agent_type":"developer"}'
expect "no agent_type: guard is off" 0 allowed '{"tool_name":"Write","tool_input":{"file_path":"a"}}'
gem() { printf '%s' "$1" | "$ROOT/hooks/adapt.sh" gemini guard-secrets.sh 2>/dev/null; }
expect "gemini adapter denies .env read (exit 2)" 2 gem '{"hook_event_name":"BeforeTool","tool_name":"read_file","tool_input":{"file_path":".env"},"cwd":"'"$hrepo"'"}'
expect "gemini adapter allows other file" 0 gem '{"hook_event_name":"BeforeTool","tool_name":"read_file","tool_input":{"file_path":"main.go"},"cwd":"'"$hrepo"'"}'
cur() { printf '%s' "$1" | "$ROOT/hooks/adapt.sh" cursor guard-secrets.sh | grep -q '"permission": "deny"'; }
expect "cursor adapter denies .env read" 0 cur '{"hook_event_name":"beforeReadFile","file_path":".env.local","workspace_roots":["'"$hrepo"'"]}'

has() { local pat="$1"; shift; "$@" | grep -q -- "$pat"; }
# --- plan-waves: size field, legacy format, MAX_PARALLEL cap ---
cat > "$tmp/w-old.md" <<'X'
- [ ] T1 a | role: developer | writes: a/
- [ ] T2 b | role: developer | writes: b/ | after: T1
- [ ] T3 c | role: test-writer | writes: a/x_test.go
- [ ] T4 d | role: developer | writes: d/
X
cat > "$tmp/w-sized.md" <<'X'
- [ ] T1 a | role: developer | size: large | writes: a/
- [ ] T2 b | role: developer | writes: b/ | size: small | after: T1
- [ ] T3 c | role: test-writer | writes: a/x_test.go | size: medium
- [ ] T4 d | role: developer | writes: d/
X
for i in 1 2 3 4 5; do printf -- '- [ ] P%s p | role: developer | writes: dir%s/\n' "$i" "$i"; done > "$tmp/w-wide.md"
pw() { env -u MAX_PARALLEL "$ROOT/scripts/plan-waves.sh" "$@"; }
nosize() { pw "$tmp/w-sized.md" | sed -E 's/,(small|medium|large)//g' > "$tmp/w-sized.out"; pw "$tmp/w-old.md" > "$tmp/w-old.out"; cmp -s "$tmp/w-sized.out" "$tmp/w-old.out"; }
maxwave() { local cap="$1" f="$2" widest; widest="$(MAX_PARALLEL="$cap" "$ROOT/scripts/plan-waves.sh" "$f" | awk -F'[|][|]' '{ if (NF > m) m = NF } END { print m + 0 }')"; [ "$widest" -le "$cap" ]; }
firstwave() { head -1 | grep -o 'P[0-9]' | wc -l | tr -d ' '; }
expect "plan-waves legacy format waves" 0 has 'wave 1: T1(developer)  ||  T4(developer)' pw "$tmp/w-old.md"
expect "plan-waves shows size" 0 has 'T1(developer,large)' pw "$tmp/w-sized.md"
expect "plan-waves size does not change grouping" 0 nosize
expect "plan-waves size parsed from any column" 0 has 'T2(developer,small)' pw "$tmp/w-sized.md"
expect "plan-waves default cap is 3" 0 bash -c "[ \"\$(env -u MAX_PARALLEL '$ROOT/scripts/plan-waves.sh' '$tmp/w-wide.md' | head -1 | grep -o 'P[0-9]' | wc -l | tr -d ' ')\" = 3 ]"
expect "plan-waves cap 1 holds" 0 maxwave 1 "$tmp/w-wide.md"
expect "plan-waves cap 2 holds" 0 maxwave 2 "$tmp/w-wide.md"
expect "plan-waves cap 3 holds" 0 maxwave 3 "$tmp/w-wide.md"
expect "plan-waves cap 2 keeps every task" 0 bash -c "[ \"\$(MAX_PARALLEL=2 '$ROOT/scripts/plan-waves.sh' '$tmp/w-wide.md' | grep -o 'P[0-9]' | sort -u | wc -l | tr -d ' ')\" = 5 ]"
expect "plan-waves invalid cap falls back to 3" 0 bash -c "[ \"\$(MAX_PARALLEL=0 '$ROOT/scripts/plan-waves.sh' '$tmp/w-wide.md' | head -1 | grep -o 'P[0-9]' | wc -l | tr -d ' ')\" = 3 ]"
pwrepo="$tmp/pwrepo"; mkdir -p "$pwrepo/.claude"; git -C "$pwrepo" init -q; echo MAX_PARALLEL=2 > "$pwrepo/.claude/project.env"; cp "$tmp/w-wide.md" "$pwrepo/tasks.md"
expect "plan-waves cap from project.env" 0 bash -c "[ \"\$(env -u MAX_PARALLEL '$ROOT/scripts/plan-waves.sh' '$pwrepo/tasks.md' | head -1 | grep -o 'P[0-9]' | wc -l | tr -d ' ')\" = 2 ]"
printf -- '- [ ] A x | after: B\n- [ ] B y | after: A\n' > "$tmp/w-cycle.md"
expect "plan-waves cycle still fails" 1 pw "$tmp/w-cycle.md"

# --- run-role: per-host command lines (dry run) ---
printf 'ROLE: verifier\nTASK: x\n' > "$tmp/handoff.md"
rr() { (cd "$hrepo" && "$ROOT/scripts/run-role.sh" "$@" --handoff "$tmp/handoff.md" --dry-run); }
expect "run-role codex read-only sandbox" 0 has '--sandbox read-only' rr verifier --host codex
expect "run-role codex writer sandbox" 0 has '--sandbox workspace-write' rr developer --host codex
expect "run-role gemini plan mode for read-only" 0 has '--approval-mode plan' rr verifier --host gemini
expect "run-role cursor ask mode for read-only" 0 has '--mode ask' rr reviewer --host cursor
expect "run-role opencode picks the agent" 0 has '--agent verifier-deep' rr verifier-deep --host opencode
expect "run-role unknown host" 2 rr verifier --host nope

# --- run-role: --tier picks the model by task size ---
trepo="$tmp/trepo"; mkdir -p "$trepo/.claude"; git -C "$trepo" init -q
printf 'RUN_ROLE_MODEL_LIGHT=m-light\nRUN_ROLE_MODEL_STANDARD=m-std\nRUN_ROLE_MODEL_STRONG=m-strong\n' > "$trepo/.claude/project.env"
rt() { (cd "$trepo" && "$ROOT/scripts/run-role.sh" "$@" --handoff "$tmp/handoff.md" --dry-run); }
expect "run-role --tier large picks the strong model" 0 has '--model m-strong' rt developer --host claude --tier large
expect "run-role --tier strong picks the strong model" 0 has '--model m-strong' rt developer --host claude --tier strong
expect "run-role --tier small lowers a writer" 0 has '--model m-light' rt developer --host claude --tier small
expect "run-role without --tier keeps the role tier" 0 has '--model m-std' rt developer --host claude
expect "run-role scout raised by --tier" 0 has '--model m-strong' rt scout --host claude --tier strong
expect "run-role independent role never drops below its tier" 0 has '--model m-std' rt verifier --host claude --tier light
expect "run-role independent role may go up" 0 has '--model m-strong' rt reviewer --host claude --tier large
expect "run-role verifier-deep stays strong" 0 has '--model m-strong' rt verifier-deep --host claude --tier light
expect "run-role --model beats --tier" 0 has '--model forced' rt developer --host claude --tier large --model forced
expect "run-role bad tier" 2 rt developer --host claude --tier huge
expect "run-role codex effort follows --tier" 0 has 'model_reasoning_effort=high' rt developer --host codex --tier large
expect "run-role codex effort low" 0 has 'model_reasoning_effort=low' rt developer --host codex --tier small
expect "run-role codex without --tier sets no effort" 1 has 'model_reasoning_effort' rt developer --host codex
prepo="$tmp/prepo"; mkdir -p "$prepo/.claude"; git -C "$prepo" init -q; : > "$prepo/.claude/project.env"
rp() { (cd "$prepo" && "$ROOT/scripts/run-role.sh" "$@" --handoff "$tmp/handoff.md" --dry-run); }
expect "run-role opencode --tier uses tiers.env default" 0 has '-m anthropic/claude-opus-5-5' rp developer --host opencode --tier large
expect "run-role opencode without --tier stays unpinned" 1 has ' -m ' rp developer --host opencode
expect "run-role cursor --tier leaves the model unset" 1 has '--model' rp developer --host cursor --tier large
expect "run-role gemini --tier leaves the model unset" 1 has ' -m ' rp developer --host gemini --tier large

# --- init: stack detection and per-stack install ---
for pair in "go:go.mod:module x" "spring-boot:pom.xml:<project><parent><artifactId>spring-boot-starter-parent</artifactId></parent></project>" "nextjs:package.json:{\"dependencies\":{\"next\":\"14\"}}" "react-native:package.json:{\"dependencies\":{\"react-native\":\"0.74\"}}" "python:pyproject.toml:[project]" "jvm:build.gradle.kts:plugins { kotlin(\"jvm\") }" "generic:README.md:hello"; do
  st="${pair%%:*}"; rest="${pair#*:}"; file="${rest%%:*}"; content="${rest#*:}"
  d="$tmp/init-$st"; mkdir -p "$d"; git -C "$d" init -q -b main; printf '%s' "$content" > "$d/$file"
  expect "init detects $st" 0 bash -c "'$ROOT/bin/init.sh' '$d' >/dev/null && grep -q '^STACK=$st' '$d/.sdkit/sdkit.env'"
done
# python / generic verify
pyd="$tmp/py-verify"; mkdir -p "$pyd"; git -C "$pyd" init -q -b main; ( cd "$pyd" && git config user.email t@t && git config user.name t && printf '[project]\n' > pyproject.toml && git add -A && git commit -qm b && git checkout -qb f ) >/dev/null 2>&1
echo 'def g(:' > "$pyd/bad.py"; expect "python verify fails on a syntax error" 1 bash -c "cd '$pyd' && '$ROOT/stacks/python/scripts/verify.sh' --fast --no-cache"
echo 'def g(): return 1' > "$pyd/bad.py"; expect "python verify passes on valid code" 0 bash -c "cd '$pyd' && '$ROOT/stacks/python/scripts/verify.sh' --fast --no-cache"
gd="$tmp/gen-verify"; mkdir -p "$gd/.claude"; git -C "$gd" init -q -b main; ( cd "$gd" && git config user.email t@t && git config user.name t && echo a > a && git add -A && git commit -qm b && git checkout -qb f && echo b > b ) >/dev/null 2>&1
printf 'STACK=generic\nVERIFY_TEST_CMD=false\n' > "$gd/.claude/project.env"; expect "generic verify fails when VERIFY_TEST_CMD fails" 1 bash -c "cd '$gd' && '$ROOT/stacks/generic/scripts/verify.sh' --no-cache"
printf 'STACK=generic\nVERIFY_TEST_CMD=true\n' > "$gd/.claude/project.env"; expect "generic verify passes when VERIFY_TEST_CMD passes" 0 bash -c "cd '$gd' && '$ROOT/stacks/generic/scripts/verify.sh' --no-cache"
# machine install, drift check, CI template
xdg="$tmp/xdg"; expect "install.sh registers the kit" 0 bash -c "XDG_CONFIG_HOME='$xdg' '$ROOT/bin/install.sh' >/dev/null && grep -qx '$ROOT' '$xdg/spec-driven-kit/home'"
expect "install.sh --status ok" 0 env XDG_CONFIG_HOME="$xdg" "$ROOT/bin/install.sh" --status
expect "install.sh --uninstall" 0 env XDG_CONFIG_HOME="$xdg" "$ROOT/bin/install.sh" --uninstall
expect "install.sh --status fails when unregistered" 1 env XDG_CONFIG_HOME="$xdg" "$ROOT/bin/install.sh" --status
ci="$tmp/ci-repo"; mkdir -p "$ci"; git -C "$ci" init -q -b main; printf 'module x' > "$ci/go.mod"
expect "init --ci bitbucket" 0 bash -c "'$ROOT/bin/init.sh' --ci bitbucket '$ci' >/dev/null && grep -qE 'sdd[.]sh.? ci-check' '$ci/bitbucket-pipelines.yml' && test -x '$ci/.sdkit/scripts/sdd.sh'"
ci_gl="$tmp/ci-gl"; mkdir -p "$ci_gl"; git -C "$ci_gl" init -q -b main; printf 'module x' > "$ci_gl/go.mod"
expect "init --ci gitlab" 0 bash -c "'$ROOT/bin/init.sh' --ci gitlab '$ci_gl' >/dev/null && grep -qE 'sdd[.]sh.? ci-check' '$ci_gl/.gitlab-ci.yml' && grep -q 'CI_MERGE_REQUEST_TARGET_BRANCH_NAME' '$ci_gl/.gitlab-ci.yml' && ! grep -q '__KIT_DIR__' '$ci_gl/.gitlab-ci.yml'"
expect "the CI gate's env.sh is not git-ignored" 1 git -C "$ci_gl" check-ignore -q .sdkit/scripts/env.sh
expect "doctor sees the GitLab CI gate" 0 bash -c "'$ROOT/bin/doctor.sh' '$ci_gl' 2>&1 | grep -q 'CI runs the spec-driven gate'"
expect "init --ci rejects unknown hosts" 2 "$ROOT/bin/init.sh" --ci svn "$ci"
expect "sync --check is clean after init" 0 "$ROOT/bin/sync.sh" --check "$ci"
echo "# local edit" >> "$ci/.sdkit/scripts/sdd.sh"
expect "sync --check reports drift" 1 "$ROOT/bin/sync.sh" --check "$ci"
expect "sync --check does not modify files" 0 bash -c "tail -1 '$ci/.sdkit/scripts/sdd.sh' | grep -q 'local edit'"
expect "doctor sees the CI gate" 0 bash -c "'$ROOT/bin/doctor.sh' '$ci' 2>&1 | grep -q 'CI runs the spec-driven gate'"
expect "doctor warns about drift" 0 bash -c "'$ROOT/bin/doctor.sh' '$ci' 2>&1 | grep -q 'differ from the kit'"
# OpenSpec: required, managed by init
osd="$tmp/os-repo"; mkdir -p "$osd"; git -C "$osd" init -q -b main; printf 'module x' > "$osd/go.mod"; : > "$OPENSPEC_STUB_LOG"
expect "init runs openspec init for the chosen hosts" 0 bash -c "'$ROOT/bin/init.sh' --host claude,codex '$osd' >/dev/null && grep -q -- '--tools claude,codex' '$OPENSPEC_STUB_LOG' && test -f '$osd/openspec/config.yaml'"
: > "$OPENSPEC_STUB_LOG"
expect "second init does not re-run openspec init" 0 bash -c "'$ROOT/bin/init.sh' --host claude,codex '$osd' >/dev/null; test ! -s '$OPENSPEC_STUB_LOG'"
nopath="$(printf '%s' "$PATH" | tr ':' '\n' | while IFS= read -r d; do [ -x "$d/openspec" ] || printf '%s\n' "$d"; done | paste -sd: -)"
osm="$tmp/os-missing"; mkdir -p "$osm"; git -C "$osm" init -q -b main; printf 'module x' > "$osm/go.mod"
expect "init without the CLI says openspec is missing" 0 bash -c "PATH='$nopath' '$ROOT/bin/init.sh' '$osm' 2>&1 | grep -q 'MISSING openspec CLI'"
expect "doctor fails without the CLI" 1 bash -c "PATH='$nopath' '$ROOT/bin/doctor.sh' '$osm' 2>&1 | grep -q 'FAIL  openspec CLI missing' && exit 1 || exit 0"
expect "doctor passes the openspec checks with the CLI" 0 bash -c "'$ROOT/bin/doctor.sh' '$osd' 2>&1 | grep -q 'openspec skills present for Claude Code'"
# Homebrew formula generator
expect "formula: head-only is generated" 0 bash -c "'$ROOT/packaging/homebrew/gen-formula.sh' --head-only --repo-url git@example.org:o/r.git | grep -q 'head \"git@example.org:o/r.git\", using: :git'"
gf="$tmp/gf"; mkdir -p "$gf/packaging/homebrew" "$gf/.claude-plugin"; cp "$ROOT/packaging/homebrew/gen-formula.sh" "$gf/packaging/homebrew/"; echo '{"version":"9.9.9"}' > "$gf/.claude-plugin/plugin.json"
git -C "$gf" init -q -b main; git -C "$gf" remote add origin git@example.org:o/r.git; git -C "$gf" -c user.email=t@t -c user.name=t commit -q --allow-empty -m x
expect "formula: refuses a release without its tag" 1 "$gf/packaging/homebrew/gen-formula.sh"
git -C "$gf" tag v9.9.9
gfrev="$(git -C "$gf" rev-parse HEAD)"
expect "formula: a tagged release pins tag and revision" 0 bash -c "'$gf/packaging/homebrew/gen-formula.sh' | grep -q 'revision: \"$gfrev\"'"
expect "formula: credentials in the URL are stripped" 0 bash -c "'$ROOT/packaging/homebrew/gen-formula.sh' --head-only --repo-url https://user:dummy-pw@example.org/r.git | grep -q 'dummy-pw' && exit 1 || exit 0"
expect "committed formula parses and uses git" 0 bash -c "ruby -c '$ROOT/Formula/sdkit.rb' >/dev/null && grep -q 'using: :git' '$ROOT/Formula/sdkit.rb' && grep -q '^class Sdkit' '$ROOT/Formula/sdkit.rb'"
expect "formula: homepage is a web address" 0 bash -c "grep -q 'homepage \"https://' '$ROOT/Formula/sdkit.rb'"
expect "formula: depends on jq and node" 0 bash -c "'$ROOT/packaging/homebrew/gen-formula.sh' --head-only --repo-url x.git | grep -q 'depends_on \"jq\"' && '$ROOT/packaging/homebrew/gen-formula.sh' --head-only --repo-url x.git | grep -q 'depends_on \"node\"'"
expect "git hook shims find the kit through sdkit" 0 grep -q 'sdkit where' "$ROOT/adapters/git/pre-push" "$ROOT/adapters/git/pre-commit"
# publishability scan: clean tree passes, a planted key is caught
expect "scan: this repository has no hard findings" 0 "$ROOT/packaging/scan-publishable.sh"
sd="$tmp/scan-repo"; mkdir -p "$sd/packaging"; git -C "$sd" init -q -b main; cp "$ROOT/packaging/scan-publishable.sh" "$sd/packaging/"
printf 'token = "%s"\nkey=%s\n' "abcdef1234567890" "ghp_$(printf 'a%.0s' $(seq 1 30))" > "$sd/leak.txt"; git -C "$sd" add -A
expect "scan: a planted token is caught" 1 bash -c "cd '$sd' && ./packaging/scan-publishable.sh"
# the single entry point
expect "sdkit version" 0 bash -c "'$ROOT/bin/sdkit' version | grep -q '^sdkit [0-9]'"
expect "sdkit rejects unknown commands" 2 "$ROOT/bin/sdkit" nope
ln -s "$ROOT/bin/sdkit" "$tmp/sk-link"
expect "sdkit works through a symlink (package managers)" 0 bash -c "test \"\$('$tmp/sk-link' where)\" = '$ROOT'"
expect "sdkit init dispatches to init.sh" 0 bash -c "'$ROOT/bin/sdkit' init --stack go --host claude '$tmp/sk-init' 2>&1 | grep -q 'host=claude' || (mkdir -p '$tmp/sk-init' && git -C '$tmp/sk-init' init -q -b main && '$ROOT/bin/sdkit' init --stack go '$tmp/sk-init' 2>&1 | grep -q 'stack=go')"
expect "init all hosts" 0 bash -c "'$ROOT/bin/init.sh' --host claude,codex,opencode,cursor,gemini --stack go '$tmp/init-go' >/dev/null && test -f '$tmp/init-go/.opencode/plugins/spec-driven-kit-guard.js' && test -f '$tmp/init-go/.gemini/settings.json'"
expect "adapters are up to date" 0 "$ROOT/bin/build-adapters.sh" --check

# --- open-pr.sh: host dispatch (gh/glab stubbed, no network) ---
pr="$tmp/pr-repo"; prbin="$tmp/pr-bin"; mkdir -p "$pr/.claude" "$prbin"; : > "$pr/.claude/project.env"
git -C "$pr" init -q -b main; ( cd "$pr" && git config user.email t@t && git config user.name t && echo a > a && git add -A && git commit -qm i && git checkout -qb feat ) >/dev/null 2>&1
for t in gh glab; do printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s $*" >> "%s/calls"\n' "$t" "$tmp" > "$prbin/$t"; chmod +x "$prbin/$t"; done
echo "the description" > "$tmp/pr-desc.md"
git -C "$pr" remote add origin https://github.com/o/r.git
expect "open-pr refuses an unpushed branch" 1 env PATH="$prbin:$PATH" PR_HOST=github bash -c "cd '$pr' && '$ROOT/scripts/open-pr.sh' T '$tmp/pr-desc.md' main"
git -C "$pr" update-ref refs/remotes/origin/feat HEAD
rm -f "$tmp/calls"; expect "open-pr github calls gh pr create" 0 bash -c "cd '$pr' && PATH='$prbin:$PATH' PR_HOST=github '$ROOT/scripts/open-pr.sh' 'My title' '$tmp/pr-desc.md' main && grep -qx 'gh pr create --base main --head feat --title My title --body-file $tmp/pr-desc.md' '$tmp/calls'"
rm -f "$tmp/calls"; expect "open-pr gitlab calls glab mr create" 0 bash -c "cd '$pr' && PATH='$prbin:$PATH' PR_HOST=gitlab '$ROOT/scripts/open-pr.sh' T '$tmp/pr-desc.md' main && grep -q '^glab mr create --source-branch feat --target-branch main --title T --description the description --yes' '$tmp/calls'"
rm -f "$tmp/calls"; expect "open-pr auto picks github from origin" 0 bash -c "cd '$pr' && PATH='$prbin:$PATH' PR_HOST=auto '$ROOT/scripts/open-pr.sh' T '$tmp/pr-desc.md' main && grep -q '^gh pr create' '$tmp/calls'"
git -C "$pr" remote set-url origin git@gitlab.example.com:g/r.git
rm -f "$tmp/calls"; expect "open-pr auto picks gitlab from origin" 0 bash -c "cd '$pr' && PATH='$prbin:$PATH' PR_HOST=auto '$ROOT/scripts/open-pr.sh' T '$tmp/pr-desc.md' main && grep -q '^glab mr create' '$tmp/calls'"
git -C "$pr" remote set-url origin https://git.example.org/g/r.git
expect "open-pr auto fails on an unknown origin" 2 env PATH="$prbin:$PATH" PR_HOST=auto bash -c "cd '$pr' && '$ROOT/scripts/open-pr.sh' T '$tmp/pr-desc.md' main"
expect "open-pr auto honours GH_HOST" 0 bash -c "cd '$pr' && PATH='$prbin:$PATH' PR_HOST=auto GH_HOST=git.example.org '$ROOT/scripts/open-pr.sh' T '$tmp/pr-desc.md' main"
expect "open-pr rejects unknown hosts" 2 env PR_HOST=svn bash -c "cd '$pr' && '$ROOT/scripts/open-pr.sh' T '$tmp/pr-desc.md' main"
expect "open-pr needs a readable description" 2 env PATH="$prbin:$PATH" PR_HOST=github bash -c "cd '$pr' && '$ROOT/scripts/open-pr.sh' T '$tmp/missing.md' main"

echo "tests: $pass passed, $failed failed"
[ "$failed" = 0 ]
