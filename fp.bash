# fp.bash -- functional programming in bash

# Naming Policy:
#
# All function and variable names are camelCased, but they may begin with uppercase letters.
#
# Function names are prefixed with "fp." (always lowercase) so they are namespaced.
#
# Local variable names begin with lowercase letters.
# Global variable names begin with uppercase letters.
# Global variable names are namespaced by suffixing them with the randomly-generated letter F.
#
# Private function names begin with lowercase letters.
# Public function names begin with uppercase letters.

# fp.Collect collects a stream into a string.
fp.Collect() {
  local sep=${1:-${IFS:0:1}}

  local IFS=$sep field results=()
  while IFS='' read -r field; do
    eval "results+=( $field )"
  done
  echo "${results[*]}"
}

# fp.Each applies its arguments as a command to each argument from stdin.
# Multiple arguments join into one command, e.g. `fp.Each try task.Ln
# nix-wrapper <<<...` runs `try task.Ln nix-wrapper $line` per stdin line --
# NOT `try` with the other two words silently dropped. %q-escaped so a
# command word containing whitespace or shell metacharacters round-trips
# through eval as one token rather than fragmenting (mk.bash's mk.Cue uses
# the same printf -v '%q ' idiom, there for display rather than re-eval).
# It does not propagate any error from evaluating command.
fp.Each() {
  local command
  printf -v command '%q ' "$@"
  local arg
  while IFS='' read -r arg; do
    eval "$command $arg"
  done
  return 0
}

# fp.KeepIf filters lines from stdin using command. Multiple arguments join
# into one command, same %q-escaped joining as fp.Each.
# It does not propagate any error from evaluating command.
fp.KeepIf() {
  local command
  printf -v command '%q ' "$@"
  local arg
  while IFS='' read -r arg; do
    eval "$command $arg" && echo "$arg"
  done
  return 0
}

# fp.Map returns $EXPRESSION evaluated with the value of stdin as $VARNAME.
# $EXPRESSION must respect double-quoting rules and so can't contain naked quotes.
# $VARNAME may not be "VARNAME" or "EXPRESSION".
fp.Map() {
  local VARNAME=$1 EXPRESSION=$2  # borrow a different namespace since we're passing a variable name
  case $VARNAME in VARNAME|EXPRESSION ) fp.fatal "fp.Map: VARNAME may not be 'VARNAME' or 'EXPRESSION'";; esac

  local "$VARNAME"
  # IFS=' ' (not '') strips leading/trailing spaces from each line, so callers
  # can feed an indented heredoc without embedding leading whitespace in the
  # value -- see dotfiles update-env commit d2f0cd5 (2026-05-13), which found
  # a real bug from IFS='' here: a value like "  era-serve" (embedded space)
  # fragments into two words the next time it round-trips through eval.
  while IFS=' ' read -r "$VARNAME"; do
    eval "echo \"$EXPRESSION\""
  done
}

# fp.RemoveIf filters lines from stdin using the negation of command.
# Multiple arguments join into one command, same %q-escaped joining as
# fp.Each/fp.KeepIf.
fp.RemoveIf() {
  local command
  printf -v command '%q ' "$@"
  local arg
  while IFS='' read -r arg; do
    eval "! $command $arg" && echo "$arg"
  done
}

# fp.Stream converts its arguments to a newline-separated output stream.
fp.Stream() {
  local IFS=$'\n'
  (( $# == 0 )) || echo "$*"
}

# fp.StreamList streams the elements of list, splitting on sep.
fp.StreamList() {
  local list=$1 IFS=${2:-$IFS}
  fp.Stream $list
}

# logging

fp.fatal() {
  local msg=$1 rc=${2:-$?}
  echo "fatal: $msg"
  exit "$rc"
}
