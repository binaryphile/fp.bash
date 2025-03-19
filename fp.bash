# fp.bash -- functional programming in bash

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

# fp.Map returns $expression evaluated with the value of stdin as $varname.
# $expression must respect double-quoting rules and so can't contain naked quotes.
# $varname may not be "varname" or "expression".
fp.Map() {
  local VarnameC=$1 ExpressionC=$2
  case $VarnameC in VarnameC|ExpressionC ) fp.fatal "fp.Map: VarnameC may not be 'VarnameC' or 'ExpressionC'";; esac
  local $VarnameC
  while IFS='' read -r "$VarnameC"; do
    eval "echo \"$ExpressionC\""
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
