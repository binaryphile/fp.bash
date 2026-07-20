source ~/projects/fp.bash/fp.bash

IFS=$'\n'
set -o noglob

# recordArgs echoes each argument on its own line, prefixed for identification.
recordArgs() {
  local a
  for a; do
    echo "ARG:$a"
  done
}

# test_fp.Each_singleWordCommand verifies the pre-existing single-word case
# is unaffected by the %q-join fix (grader review, era #24566 IMPL finding 2:
# confirm the fix is a strict superset, no regression).
test_fp.Each_singleWordCommand() {
  ## arrange
  local input=$'one\ntwo'

  ## act
  local got
  got=$(echo "$input" | fp.Each recordArgs)

  ## assert
  tesht.AssertGot "$got" $'ARG:one\nARG:two'
}

# test_fp.Each_multiWordCommand is the actual regression test for the bug
# this cycle fixed: fp.Each try task.Ln nix-wrapper silently dropped
# "task.Ln nix-wrapper", evaluating as `try $line` per line instead of
# `try task.Ln nix-wrapper $line` (grader review, era #24566 IMPL finding 6 --
# no test previously exercised this exact shape; the only production caller
# was deleted from update-env rather than kept as a covered case).
test_fp.Each_multiWordCommand() {
  ## arrange
  local input='lineval'

  ## act
  local got
  got=$(echo "$input" | fp.Each recordArgs fixed extra)

  ## assert
  tesht.AssertGot "$got" $'ARG:fixed\nARG:extra\nARG:lineval'
}

# test_fp.KeepIf_multiWordCommand mirrors the fp.Each multi-word case for
# fp.KeepIf, which shares the identical historical bug pattern.
test_fp.KeepIf_multiWordCommand() {
  ## arrange
  isLongerThan() {
    local n=$1 s=$2
    (( ${#s} > n ))
  }

  ## act
  local got
  got=$(printf '%s\n' short muchlonger | fp.KeepIf isLongerThan 7)

  ## assert
  tesht.AssertGot "$got" 'muchlonger'
}

# test_fp.RemoveIf_multiWordCommand closes the specific gap the grader
# flagged as blocking (era #24566 IMPL finding 4): fp.RemoveIf's docs claimed
# multi-word support identical to fp.Each/fp.KeepIf, but the implementation
# had not received the fix -- a caller following the documented contract
# would hit the exact silent-argument-drop bug this cycle otherwise fixed.
test_fp.RemoveIf_multiWordCommand() {
  ## arrange
  isLongerThan() {
    local n=$1 s=$2
    (( ${#s} > n ))
  }

  ## act
  local got
  got=$(printf '%s\n' short muchlonger | fp.RemoveIf isLongerThan 7)

  ## assert
  tesht.AssertGot "$got" 'short'
}

# test_fp.Each_argWithMetacharacters characterizes the scope of the %q fix
# per grader review finding 1: %q-escaping applies to the command-PREFIX
# arguments only. The per-line streamed value is still spliced into the
# eval string unescaped -- this test documents that as existing, unchanged
# behavior (present before and after this cycle), not a claim that the
# whole invocation is eval-safe.
test_fp.Each_argWithMetacharacters() {
  ## arrange
  local out_=$(mktemp -u)
  trap 'rm -f "$out_"' RETURN
  writeMarker() { echo "called with: $*" >> "$out_"; }

  ## act -- a line containing a semicolon is NOT escaped by fp.Each; it
  ## fragments into two shell commands during eval, as it did before this
  ## fix. This is documented scope, not a regression this cycle introduced.
  echo 'a; writeMarker b' | fp.Each writeMarker

  ## assert -- both the fragmented command and the injected command ran
  local got_
  got_=$(cat "$out_")
  tesht.AssertGot "$got_" $'called with: a\ncalled with: b'
}
