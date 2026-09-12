#!/usr/bin/env bash
# verify.sh — headless verification for a Godot 4 project, safe to run unattended.
#
#   import -> load-all -> boot -> each --script        (every step under a timeout)
#
# Why a wrapper instead of calling godot directly (all observed on Godot 4.7):
#   * Exit codes don't reflect script errors: runtime SCRIPT ERRORs, push_error(),
#     even a -s script that fails to parse all exit 0. Pass/fail here is decided
#     from the output as well as the exit code.
#   * A -s script that errors before quit() never exits, and a headless
#     --quit-after boot on macOS can stall for many minutes when its per-frame
#     sleeps get throttled. Every step runs under a timeout, and every run uses
#     --fixed-fps (no per-frame sleep, deterministic frame count).
#
# Usage: verify.sh [options]
#   --project DIR    project root (default: nearest directory above $PWD with project.godot)
#   --script PATH    headless test to run with -s (a SceneTree script); repeatable.
#                    Its exit code is its verdict: ERROR:/WARNING: lines it prints are
#                    listed but don't fail it (tests hit error paths on purpose);
#                    SCRIPT ERROR lines always do.
#   --scene PATH     boot this scene instead of the main scene; repeatable
#   --frames N       frames per boot (default 120)
#   --timeout SEC    per-step timeout in seconds (default 120). Steps normally take
#                    seconds, so hitting it means a hang; raise it only for the first
#                    --import of a large project.
#   --skip-import    skip `godot --import`
#   --skip-load-all  skip loading every .gd/.tscn/.tres once
#   --skip-boot      skip booting scenes
#   -v, --verbose    print the full Godot output of every step
#   -h, --help       show this help
# Environment: GODOT=/path/to/godot overrides binary discovery.
# Exit status: 0 = every step passed, 1 = a step failed, 2 = usage/setup error.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project=""
scripts=()
scenes=()
frames=120
timeout_sec=120
do_import=1
do_load_all=1
do_boot=1
verbose=0

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }
die_usage() { echo "verify: $1 (see --help)" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --project) [ $# -ge 2 ] || die_usage "--project needs a value"; project="$2"; shift 2 ;;
    --script) [ $# -ge 2 ] || die_usage "--script needs a value"; scripts+=("$2"); shift 2 ;;
    --scene) [ $# -ge 2 ] || die_usage "--scene needs a value"; scenes+=("$2"); shift 2 ;;
    --frames) [ $# -ge 2 ] || die_usage "--frames needs a value"; frames="$2"; shift 2 ;;
    --timeout) [ $# -ge 2 ] || die_usage "--timeout needs a value"; timeout_sec="$2"; shift 2 ;;
    --skip-import) do_import=0; shift ;;
    --skip-load-all) do_load_all=0; shift ;;
    --skip-boot) do_boot=0; shift ;;
    -v|--verbose) verbose=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die_usage "unknown option: $1" ;;
  esac
done

# --- setup -------------------------------------------------------------------

if [ -z "$project" ]; then
  project="$PWD"
  while [ "$project" != "/" ] && [ ! -f "$project/project.godot" ]; do
    project="$(dirname "$project")"
  done
fi
[ -f "$project/project.godot" ] || die_usage "no project.godot found (pass --project DIR)"
project="$(cd "$project" && pwd)"

godot_bin="${GODOT:-}"
if [ -z "$godot_bin" ]; then
  for candidate in godot godot4 Godot; do
    if command -v "$candidate" >/dev/null 2>&1; then
      godot_bin="$(command -v "$candidate")"
      break
    fi
  done
fi
if [ -z "$godot_bin" ] && [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
  godot_bin=/Applications/Godot.app/Contents/MacOS/Godot
fi
[ -n "$godot_bin" ] || { echo "verify: Godot binary not found; set GODOT=/path/to/godot" >&2; exit 2; }
command -v perl >/dev/null 2>&1 || { echo "verify: perl is required (used for step timeouts)" >&2; exit 2; }

engine_version="$("$godot_bin" --version 2>/dev/null | head -n 1)"
project_version="$(grep -o 'config/features=PackedStringArray("[0-9][0-9.]*' "$project/project.godot" | grep -o '[0-9][0-9.]*$')"
echo "verify: project $project (features ${project_version:-unknown})"
echo "verify: engine  $godot_bin ($engine_version)"
if [ -n "$project_version" ]; then
  case "$engine_version" in
    "$project_version"*) ;;
    *) echo "verify: WARNING engine $engine_version does not match project version $project_version" ;;
  esac
fi

# load_all.gd is run with -s; prefer a res:// path when this skill lives inside the project.
case "$here/" in
  "$project/"*) load_all_script="res://${here#"$project/"}/load_all.gd" ;;
  *) load_all_script="$here/load_all.gd" ;;
esac

# --- step runner -------------------------------------------------------------

SCRIPT_ERROR_RE='SCRIPT ERROR|Parse Error|Failed to load script'
ENGINE_ERROR_RE='^(USER )?ERROR:'
WARNING_RE='^(USER )?WARNING:'
EXIT_NOISE_RE='leaked at exit|still in use at exit'
TIMEOUT_STATUS=124

# run_with_timeout <seconds> <command...>: exits 124 if the command had to be
# killed, like GNU timeout (which macOS doesn't ship).
run_with_timeout() {
  perl -e '
    my $seconds = shift @ARGV;
    my $pid = fork();
    die "fork failed: $!\n" unless defined $pid;
    if ($pid == 0) { exec @ARGV or die "exec failed: $!\n"; }
    $SIG{ALRM} = sub { kill "KILL", $pid; waitpid($pid, 0); exit 124; };
    alarm $seconds;
    waitpid($pid, 0);
    exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);
  ' "$@"
}

total=0
failures=0

# run_step <label> <strict|test> <godot args...>
#   strict: any engine ERROR: line fails the step (import, load-all, boot).
#   test:   the script's exit code is the verdict; ERROR: lines are only listed.
run_step() {
  label="$1"
  mode="$2"
  shift 2
  total=$((total + 1))
  out="$(mktemp "${TMPDIR:-/tmp}/godot-verify.XXXXXX")"

  started=$(date +%s)
  run_with_timeout "$timeout_sec" "$godot_bin" --headless --path "$project" "$@" >"$out" 2>&1
  status=$?
  elapsed=$(( $(date +%s) - started ))
  perl -pi -e 's/\e\[[0-9;]*[A-Za-z]//g' "$out" # strip ANSI colors before matching

  error_lines="$(grep -E "$ENGINE_ERROR_RE" "$out" | grep -vE "$EXIT_NOISE_RE")"
  error_count=0
  [ -n "$error_lines" ] && error_count=$(printf '%s\n' "$error_lines" | wc -l | tr -d ' ')
  warning_count=$(grep -cE "$WARNING_RE" "$out")

  verdict=PASS
  reason=""
  if [ "$status" -eq "$TIMEOUT_STATUS" ]; then
    verdict=FAIL; reason="timed out after ${timeout_sec}s"
  elif grep -qE "$SCRIPT_ERROR_RE" "$out"; then
    verdict=FAIL; reason="script error"
  elif [ "$status" -ne 0 ]; then
    verdict=FAIL; reason="exit status $status"
  elif [ "$mode" = strict ] && [ "$error_count" -gt 0 ]; then
    verdict=FAIL; reason="engine ERROR"
  fi

  printf '%s  %s  [%ss, exit %s, %s ERROR, %s WARNING]%s\n' \
    "$verdict" "$label" "$elapsed" "$status" "$error_count" "$warning_count" "${reason:+  <- $reason}"

  if [ "$verbose" -eq 1 ]; then
    sed 's/^/    | /' "$out"
  elif [ "$verdict" = FAIL ]; then
    # Each error plus its "at: file:line" line; the raw tail if nothing matched.
    details="$(grep -E -A1 "$SCRIPT_ERROR_RE|$ENGINE_ERROR_RE|FAIL" "$out" | grep -v '^--$' | head -n 40)"
    [ -n "$details" ] || details="$(tail -n 15 "$out")"
    printf '%s\n' "$details" | sed 's/^/    | /'
  elif [ "$error_count" -gt 0 ] || [ "$warning_count" -gt 0 ]; then
    grep -E "$ENGINE_ERROR_RE|$WARNING_RE" "$out" | grep -vE "$EXIT_NOISE_RE" | head -n 15 | sed 's/^/    | /'
  fi
  if [ "$mode" = test ] && [ "$verbose" -eq 0 ] && [ "$status" -ne "$TIMEOUT_STATUS" ]; then
    # The test's own summary (last lines that aren't blank or backtrace detail).
    grep -vE '^[[:space:]]|^$' "$out" | tail -n 3 | sed 's/^/    > /'
  fi

  [ "$verdict" = FAIL ] && failures=$((failures + 1))
  rm -f "$out"
}

# --- steps -------------------------------------------------------------------

[ "$do_import" -eq 1 ] && run_step "import" strict --import --fixed-fps 60
[ "$do_load_all" -eq 1 ] && run_step "load every script/scene/resource" strict --fixed-fps 60 -s "$load_all_script"
if [ "$do_boot" -eq 1 ]; then
  if [ "${#scenes[@]}" -eq 0 ]; then
    run_step "boot main scene ($frames frames)" strict --quit-after "$frames" --fixed-fps 60
  else
    for scene in "${scenes[@]}"; do
      run_step "boot $scene ($frames frames)" strict --scene "$scene" --quit-after "$frames" --fixed-fps 60
    done
  fi
fi
if [ "${#scripts[@]}" -gt 0 ]; then
  for test_script in "${scripts[@]}"; do
    run_step "test $test_script" test --fixed-fps 60 -s "$test_script"
  done
fi

echo "verify: $((total - failures))/$total steps passed"
[ "$failures" -eq 0 ]
