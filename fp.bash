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
# It does not propagate any error from evaluating command.
fp.Each() {
  local command=$1 arg
  while IFS='' read -r arg; do
    eval "$command $arg"
  done
  return 0
}

# fp.KeepIf filters lines from stdin using command.
# It does not propagate any error from evaluating command.
fp.KeepIf() {
  local command=$1 arg
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

  local "$VARNAME"
  while IFS='' read -r "$VARNAME"; do
    eval "echo \"$EXPRESSION\""
  done
}

# fp.RemoveIf filters lines from stdin using the negation of command.
fp.RemoveIf() {
  local command=$1 arg
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
