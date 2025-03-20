# fp.bash -- functional programming in bash

# Naming Policy:
#
# All function and variable names are camelCased, but they may begin with uppercase letters.
#
# Function names are prefixed with "task." (always lowercase) so they are namespaced.
# Keyword function names are the exception to this.
# They are all lowercase letters and attempt to be five letters or shorter.
#
# Local variable names begin with lowercase letters.
# Global variable names begin with uppercase letters.
# Global variable names are namespaced by suffixing them with the randomly-generated letter C.
#
# Private function names begin with lowercase letters.
# Public function names begin with uppercase letters.

# fp.Each applies its arguments as a command to each argument from stdin.
fp.Each() {
  local command=$1 arg
  while IFS='' read -r arg; do
    eval "$command $arg"
  done
}

# fp.KeepIf filters lines from stdin using command.
fp.KeepIf() {
  local command=$1 arg
  while IFS='' read -r arg; do
    eval "$command $arg" && echo "$arg"
  done
}

# fp.Map returns $EXPRESSION evaluated with the value of stdin as $VARNAME.
# $EXPRESSION must respect double-quoting rules and so can't contain naked quotes.
# $VARNAME may not be "VARNAME" or "EXPRESSION".
fp.Map() {
  local VARNAME EXPRESSION  # borrow a different namespace since we're passing a variable name
  case $VARNAME in VARNAME|EXPRESSION ) fp.fatal "fp.Map: VARNAME may not be 'VARNAME' or 'EXPRESSION'";; esac

  local "$VARNAME"
  while IFS='' read -r "$VARNAME"; do
    eval "echo \"$EXPRESSION\""
  done
}

# fp.Stream echoes arguments escaped and separated by newline.
fp.Stream() {
  local arg
  for arg in $*; do
    printf '%q\n' "$arg"
  done
}

# logging

fp.fatal() {
  local msg=$1 rc=${2:-$?}
  echo "fatal: $msg"
  exit "$rc"
}
