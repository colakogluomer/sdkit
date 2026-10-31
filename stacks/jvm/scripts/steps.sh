# Java/Kotlin (Maven/Gradle) checks for the shared verify engine (scripts/verify-core.sh). Sourced by verify.sh; do not run directly.
STACK_SOURCE_RE='\.(java|kt|kts)$'

BUILD_FILE_RE='(^|/)(pom\.xml|build\.gradle|build\.gradle\.kts)$'

# nearest directory with a Maven/Gradle build file for a file, empty if none
module_of() {
  dir="$(dirname "$1")"
  while [ "$dir" != "." ] && [ "$dir" != "/" ]; do
    [ -f "$dir/pom.xml" ] || [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ] && { echo "$dir"; return; }
    dir="$(dirname "$dir")"
  done
  if [ -f pom.xml ] || [ -f build.gradle ] || [ -f build.gradle.kts ]; then echo "."; fi
}

# build_tool_of <module>: maven|gradle (JAVA_BUILD_TOOL overrides)
build_tool_of() {
  case "${JAVA_BUILD_TOOL:-}" in maven|gradle) echo "$JAVA_BUILD_TOOL"; return ;; esac
  if [ -f "$1/pom.xml" ]; then echo maven; else echo gradle; fi
}

# wrapper_of <module> <mvnw|gradlew>: absolute path of the wrapper at the module or repo root, else the system tool
wrapper_of() {
  local w
  for w in "$ROOT/$1/$2" "$ROOT/$2"; do
    [ -x "$w" ] && { echo "$w"; return; }
  done
  case "$2" in mvnw) command -v mvn ;; gradlew) command -v gradle ;; esac
}

# build_mentions <module> <word>: does the module's (or root) build file mention the plugin?
build_mentions() {
  local f
  for f in "$1/pom.xml" "$1/build.gradle" "$1/build.gradle.kts" pom.xml build.gradle build.gradle.kts; do
    [ -f "$f" ] && grep -qi "$2" "$f" && return 0
  done
  return 1
}

stack_run() {
  local f mod tool cmd MODULES
  MODULES="$(printf '%s\n%s\n' "$CHANGED_SRC" "$(printf '%s\n' "$CHANGED" | grep -E "$BUILD_FILE_RE" || true)" |
    while IFS= read -r f; do [ -n "$f" ] && [ -f "$f" ] && module_of "$f"; done | sort -u)"

  for mod in $MODULES; do
    tool="$(build_tool_of "$mod")"
    if [ "$tool" = maven ]; then cmd="$(wrapper_of "$mod" mvnw)"; else cmd="$(wrapper_of "$mod" gradlew)"; fi
    if [ -z "$cmd" ]; then
      warn "no $tool wrapper or installation found, module $mod skipped"
      continue
    fi

    step "module $mod: compile ($tool)"
    if [ "$tool" = maven ]; then
      (cd "$mod" && "$cmd" -q compile 2>&1) || fail "compile: $mod"
    else
      (cd "$mod" && "$cmd" -q classes 2>&1) || fail "compile: $mod"
    fi
    [ "$FAST" = 1 ] && continue

    # modules matching INTEGRATION_MODULE_GLOB (default empty) hit real infrastructure: compiled, never tested here
    if [ -n "${INTEGRATION_MODULE_GLOB:-}" ]; then
      case "$mod" in
        ${INTEGRATION_MODULE_GLOB}) continue ;;
      esac
    fi
    step "module $mod: test"
    (cd "$mod" && "$cmd" -q test 2>&1) || fail "test: $mod"

    if build_mentions "$mod" spotless; then
      step "module $mod: spotless"
      if [ "$tool" = maven ]; then
        (cd "$mod" && "$cmd" -q spotless:check 2>&1) || fail "spotless: $mod"
      else
        (cd "$mod" && "$cmd" -q spotlessCheck 2>&1) || fail "spotless: $mod"
      fi
    fi
    if build_mentions "$mod" checkstyle; then
      step "module $mod: checkstyle"
      if [ "$tool" = maven ]; then
        (cd "$mod" && "$cmd" -q checkstyle:check 2>&1) || fail "checkstyle: $mod"
      else
        (cd "$mod" && "$cmd" -q checkstyleMain checkstyleTest 2>&1) || fail "checkstyle: $mod"
      fi
    fi
  done
}
