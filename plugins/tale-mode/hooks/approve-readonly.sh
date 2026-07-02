#!/usr/bin/env bash
# tale-mode — plan-mode read-only auto-approve (PreToolUse hook, matcher: Bash).
#
# WHAT IT DOES
#   In PLAN MODE ONLY, auto-approves a Bash tool call when the whole command is PROVABLY
#   read-only. Everything it cannot prove read-only gets NO decision (silent exit 0) and flows
#   to the normal permission dialog. Its ONLY possible output is an "allow"; it never denies or
#   asks, so it can only ever remove a dialog you would have approved — never block anything.
#
# WHY
#   Tale-mode's plan/kickoff ceremonies live in plan mode, where the harness prompts for every
#   shell command it can't prove read-only — turning a careful investigation phase into a wall
#   of permission dialogs. This hook removes the dialog for the provably-safe subset only.
#
# SECURITY MODEL (read this before touching the classifier)
#   For the **Bash** tool, this hook's "allow" is the SOLE gate on the command — plan mode blocks
#   the Edit/Write *tools*, but a shell command's own file writes / process execution are gated
#   ONLY by the permission dialog we are suppressing. So a classifier gap is not "a silent read";
#   it is arbitrary write/exec. The classifier is therefore DEFAULT-DENY and adversarial:
#     1. Reject any command containing shell expansion/escaping we cannot faithfully resolve:
#        `$` (var/arith/command/`${ }` funsub), backticks, backslash escapes, process
#        substitution `<( )` / `>( )`, heredocs `<<`. (Killing `$`+backtick removes all command
#        substitution; killing `\` makes quote-stripping below faithful.)
#     2. Reject any output redirect (only `>/dev/null` and fd-dups are stripped, at a token
#        boundary), read-write `<>`, and background `&`.
#     3. Split into pipeline/chain segments; each segment's argv[0] must be a BARE whitelisted
#        command name (no quotes/path/assignment).
#     4. A flag is honoured by the shell after quote removal, so an obfuscated flag like
#        `'-exec'` / `-'exec'` would evade a blocklist. Defence: any token that CONTAINS a quote
#        AND whose dequoted form starts with `-` is rejected (a flag must appear unquoted), and
#        all per-binary matching runs on the DEQUOTED tokens (our view == the shell's).
#     5. Per-binary guards are positive/narrow: pure-read binaries (audited to have no write or
#        exec flag) allow any args; every binary that DOES have a write/exec/mutate flag
#        (sort/find/rg/git/sed/date/jq/…) is guarded, and an unknown binary is rejected.
#   The residual risk this does NOT remove: a whitelisted READ of a file whose path isn't on the
#   sensitive-term denylist runs without its dialog (a substring denylist can't be complete).
#   See SECURITY.md for the honest write-up. Kill switch: TALE_PLAN_APPROVE=0.
#
# FAIL-CLOSED, ALWAYS: unparseable input, missing jq, an unknown binary or flag, confusing
#   quoting — all fall through to the normal prompt. The known false-rejects (they simply prompt
#   as before): quoted separators (grep -E "a|b"), any backslash (grep '\bword'), any `$`
#   (du -sh "$HOME"), multi-range sed scripts, env-prefixed commands. Safe > convenient.
set -uo pipefail
set -f  # no glob expansion while we word-split untrusted strings

INPUT=$(cat 2>/dev/null || true)

[ "${TALE_PLAN_APPROVE:-1}" = "0" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

MODE=$(printf '%s' "$INPUT" | jq -r '.permission_mode // ""' 2>/dev/null || true)
[ "$MODE" = "plan" ] || exit 0
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || true)
[ "$TOOL" = "Bash" ] || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || true)
[ -n "$CMD" ] || exit 0

# ---------- (1) global rejects: expansion / substitution / escaping we can't resolve ----------
case "$CMD" in
  *'$'* | *'`'* | *'\'* ) exit 0 ;;   # var/arith/cmd/funsub expansion; backtick; backslash escape
  *'<('* | *'>('* | *'<<'* ) exit 0 ;; # process substitution; heredoc
esac

# ---------- (2) redirects ----------
# Strip only the harmless forms at a token boundary: N>/dev/null, N>>/dev/null, &>/dev/null,
# fd-dups N>&M. The trailing (space|end) anchor is why `>/dev/null/../x` is NOT stripped -> its
# '>' survives -> rejected below.
STRIPPED=$(printf '%s' "$CMD" | sed -E \
  -e 's@[0-2]?>>?[[:space:]]*/dev/null([[:space:]]|$)@ @g' \
  -e 's@&>>?[[:space:]]*/dev/null([[:space:]]|$)@ @g' \
  -e 's@[0-2]?>&[0-2-]@ @g')
case "$STRIPPED" in *'<>'* ) exit 0 ;; esac   # read-write open is a write
case "$STRIPPED" in *'>'*  ) exit 0 ;; esac   # any surviving output redirect
# background job: mask the '&&' separator, then any lone '&' is a backgrounded command
case "$(printf '%s' "$STRIPPED" | sed 's/&&//g')" in *'&'* ) exit 0 ;; esac

# ---------- sensitive paths/terms (on a fully DEQUOTED, lowercased view: empty-quote evasion
# like ~/.ss""h/id_""rsa collapses back to the real path before we scan) ----------
DEQ=$(printf '%s' "$CMD" | sed "s/['\"]//g" | tr '[:upper:]' '[:lower:]')
case "$DEQ" in
  (*.ssh*|*id_rsa*|*id_ed25519*|*.pem*|*.key*|*.pass*|*secret*|*credential*|*.aws*|*.gnupg*|*.netrc*|*keychain*|*.env*|*token*|*/shadow*|*.p12*|*.pfx*)
    exit 0 ;;
esac

# ---------- (3-5) per-segment whitelist ----------
# Split on &&, ||, |, ;, newline. A quoted separator (e.g. "a|b") mis-splits into segments whose
# argv[0] fails the bare-name check -> reject (fail-closed).
SEGS=$(printf '%s' "$STRIPPED" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/|/\n/g' -e 's/;/\n/g')

# any_arg '<space-separated glob patterns>' args... -> 0 if any DEQUOTED arg matches any pattern.
any_arg() { local pats="$1" a p; shift; for a in "$@"; do for p in $pats; do case "$a" in ($p) return 0 ;; esac; done; done; return 1; }

BINS=""
while IFS= read -r seg; do
  # shellcheck disable=SC2086  # word-splitting is the point; set -f guards globs
  set -- $seg
  [ $# -ge 1 ] || continue
  bin="$1"; shift

  # (3) argv[0] must be a bare command name: quotes/path/assignment could change what runs.
  case "$bin" in (*[\'\"]*|*/*|*=*) exit 0 ;; esac

  # (4) reject any obfuscated flag: a token that contains a quote whose dequoted form is a flag.
  for a in "$@"; do
    case "$a" in
      (*[\'\"]*) d=$(printf '%s' "$a" | sed "s/['\"]//g"); case "$d" in (-*) exit 0 ;; esac ;;
    esac
  done
  # rebuild argv with quotes removed so every guard below sees exactly what the shell will run.
  dq=(); for a in "$@"; do dq+=( "$(printf '%s' "$a" | sed "s/['\"]//g")" ); done
  set -- ${dq[@]+"${dq[@]}"}

  # (5) per-binary guard.
  case "$bin" in
    # pure local reads — audited: no write/exec/mutate flag exists on these.
    ls|cat|head|tail|wc|stat|du|df|pwd|uname|which|whoami|id|ps|lsof|\
    basename|dirname|realpath|readlink|tr|cut|nl|column|diff|cmp|strings|\
    grep|egrep|fgrep|echo|printf|test|\[|type|true|false|\
    afinfo|otool|sw_vers|system_profiler)
      : ;;
    file)     any_arg '-C* -[!-]*C* --compile' "$@" && exit 0 ;;  # -C compiles/writes a .mgc (incl. bundled -bC)
    tree)     any_arg '-o* -[!-]*o* --output*' "$@" && exit 0 ;;  # -o <file> writes the listing (incl. bundled -Xo)
    sort)     any_arg '-o* -[!-]*o* --output* --compress-program*' "$@" && exit 0 ;;  # write + exec flags (incl. bundled -so)
    find)     any_arg '-exec* -ok* -delete -fprint* -fls' "$@" && exit 0 ;;  # exec + write flags
    rg)       any_arg '--pre --pre=* --hostname-bin --hostname-bin=*' "$@" && exit 0 ;;  # exec flags
    uniq)     n=0; for a in "$@"; do case "$a" in (-*) : ;; (*) n=$((n+1)) ;; esac; done
              [ "$n" -le 1 ] || exit 0 ;;  # `uniq in out` writes the 2nd positional
    command)  [ "${1:-}" = "-v" ] || exit 0 ;;
    plutil)   [ "${1:-}" = "-p" ] || exit 0 ;;
    defaults) case "${1:-}" in (read|read-type) : ;; (*) exit 0 ;; esac ;;  # never write/delete/import
    sysctl)   any_arg '-w* -[!-]*w* -f* -[!-]*f* -p* -[!-]*p* --load --load=* --system *=*' "$@" && exit 0 ;;  # -w write; -f/-p/--load/--system load name=value from a file (incl. bundled)
    date)     for a in "$@"; do case "$a" in (-s*|-[!-]*s*|--set|--set=*|[0-9]*) exit 0 ;; esac; done ;;  # clock set (GNU + BSD; incl. bundled -us)
    jq)       for a in "$@"; do case "$a" in (*env*|*import*|*include*|-L|-L*|--library-path*) exit 0 ;; esac; done ;;  # env dump / module file read
    sed)      # only the pure-print form: sed -n '<addr>p' [file...]
              [ "${1:-}" = "-n" ] || exit 0; shift
              script="${1:-}"; shift || true
              printf '%s' "$script" | grep -Eq '^[0-9]+(,[0-9]+)?p$' || exit 0  # no $ addr: the global $ reject already ate it
              any_arg '-*' "$@" && exit 0 ;;  # no flags after the script (blocks a trailing -i)
    git)      sub="${1:-}"; shift || true
              any_arg '--output --output=* -o*' "$@" && exit 0   # log/diff/grep write-to-file
              case "$sub" in
                status|log|diff|show|rev-parse|ls-files|blame|describe|shortlog) : ;;
                grep)    any_arg '-O* -[!-]*O* --open-files-in-pager --open-files-in-pager=*' "$@" && exit 0 ;;  # runs a command (incl. bundled -nO)
                branch)  for a in "$@"; do case "$a" in
                           (-a|-v|-vv|-r|-l|--list|--all|--remotes|--verbose|--show-current|--color|--color=*|--no-color) : ;;
                           (*) exit 0 ;;  # any name arg (create/rename) or write flag (--set-upstream-to, --edit-description, -d/-D/-m)
                         esac; done ;;
                remote)  case "$#" in (0) : ;; (1) [ "$1" = "-v" ] || exit 0 ;; (*) exit 0 ;; esac ;;
                stash|worktree) [ "${1:-}" = "list" ] || exit 0 ;;
                config)  case "${1:-}" in (--get|--get-all) : ;; (*) exit 0 ;; esac ;;  # named-key reads only: dump forms (--list/-l/--get-regexp) can spill credential-bearing config (token URLs, http.extraheader) into output; a named key is scanned by the denylist above
                *) exit 0 ;;  # unknown subcommand, or `-c`/`-C`/`--exec-path` as arg[0] (config/alias RCE)
              esac ;;
    *) exit 0 ;;  # unknown binary
  esac
  case " $BINS " in (*" $bin "*) : ;; (*) BINS="$BINS $bin" ;; esac
done < <(printf '%s\n' "$SEGS")

[ -n "$BINS" ] || exit 0

jq -cn --arg r "tale-mode: read-only in plan mode (${BINS# })" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}' \
  2>/dev/null || true
exit 0
