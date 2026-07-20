# fp.bash Design

HOW fp.bash's mechanisms work. See `use-cases.md` for WHAT each function is
for, from the calling script's perspective — this doc assumes that context
and doesn't repeat it.

## Mechanism: eval as bash's missing function value

Bash has no first-class function values — you cannot pass a function as
data and have a callee invoke it without either `eval`-ing a constructed
string or requiring the callee to already know the function's name
literally. fp.bash's five pipeline primitives (`fp.Each`, `fp.KeepIf`,
`fp.RemoveIf`, `fp.Map`) all use the same shape: accept a *command name* (or
multi-word command) as configuration, then `eval "$command $arg"` once per
stdin line. `fp.Collect` uses the same `eval` idiom in the opposite
direction — evaluating each stdin line as an array-append expression rather
than a command invocation.

This means every fp.bash caller is, structurally, writing code that gets
re-parsed by the shell a second time. The two correctness properties that
matter follow directly from that: (1) the *command* portion must survive
round-tripping through `eval` as the intended number of words, and (2) the
*per-line* portion must not be interpretable as anything other than data by
the eval'd command.

## Multi-word commands: the %q-join fix (era #24407-adjacent, dotfiles fix)

`fp.Each`, `fp.KeepIf`, and `fp.RemoveIf` all accept a command as their
*positional arguments* — not a single string. Prior to this fix, each
function's implementation only captured `$1`:

```bash
# Before: silently drops every word after the first.
fp.Each() {
  local command=$1 arg
  while IFS='' read -r arg; do
    eval "$command $arg"
  done
}
```

`fp.Each try task.Ln nix-wrapper <<<...` therefore ran `eval "try $line"`
per line — `task.Ln nix-wrapper` were captured into `$2`/`$3` and never
referenced. `try`'s own definition (`task.bash`: `try() { ...; "$@"; ... }`)
then executed `$line` *directly as a command* rather than as an argument to
`task.Ln`. This was invisible for a long time specifically because the
`$line` values in the one production call site that hit it
(`~/dotfiles/update-env`'s `sofdevsim-2026` section) were paths to a
`nix-wrapper` symlink that itself had an unrelated, independent bug
(exec'ing an empty `$prog` under `IN_NIX_SHELL=impure` — see the
`nix-wrapper` script's own history) — so "execute this path directly"
crashed too, for a different reason, and the two bugs were indistinguishable
by symptom until the first one was fixed. Once `nix-wrapper` started
working, `try <path-to-go>` started *succeeding* — printing bare `go`'s
help text — which is what surfaced this bug. Worse: because that failing
(or, post-nix-wrapper-fix, help-printing-then-nonzero-exiting) command's
exit code propagated through `set -e` in `update-env`, every section
*after* `sofdevsim-2026` in the script silently never ran, for as long as
this bug was live.

**Fix**: join all positional arguments with `printf -v command '%q ' "$@"`
before the eval loop. `%q` is bash's shell-quoting format specifier —
each argument round-trips as exactly one token when re-parsed, even if it
contains whitespace or shell metacharacters. `mk.bash`'s `mk.Cue` already
established this exact idiom in this codebase (`printf -v output '%q '
"$@"`), there to safely *display* a command before running it directly
(no second eval); fp.bash's usage is the same escaping technique applied to
a string that itself gets re-parsed by `eval`, which is the higher-stakes
case — a plain `"$*"` join would still be vulnerable to an argument
containing IFS characters or shell metacharacters silently changing the
eval'd token count.

```bash
# After: every argument is part of the command, %q-escaped.
fp.Each() {
  local command
  printf -v command '%q ' "$@"
  local arg
  while IFS='' read -r arg; do
    eval "$command $arg"
  done
}
```

`fp.RemoveIf` was left with the pre-fix single-arg signature at the time of
this writing — it shares the identical structural pattern and should
receive the same fix if any caller ever needs a multi-word predicate
command; no current call site does, so it wasn't changed speculatively.

## IFS handling differs per function, deliberately

- `fp.Each`/`fp.KeepIf`/`fp.RemoveIf`: `IFS='' read -r arg` — no trimming.
  A heredoc line's leading/trailing whitespace is data, not formatting, for
  these three (the caller controls indentation via the heredoc's own
  quoting).
- `fp.Map`: `IFS=' ' read -r "$VARNAME"` — deliberately *not* `IFS=''`.
  An indented heredoc line like `  era-serve` would otherwise round-trip
  with its leading space intact, then fragment into two words the next
  time the value passes through `eval` inside `$EXPRESSION`. This was a
  real bug (dotfiles update-env commit d2f0cd5, 2026-05-13) before the
  `IFS=' '` fix landed — documented inline at the call site since it's
  exactly the kind of "looks like it should be `IFS=''`, isn't" trap a
  future edit could reintroduce.
- `fp.Collect`: `IFS=$sep` for the read loop, `sep` defaulting to the
  *first character* of the ambient `$IFS` (`${IFS:0:1}`) — under the
  project-wide `IFS=$'\n'` convention, that default is newline, matching
  the line-oriented stream every other fp.bash function produces.

## Why errors don't propagate

`fp.Each`, `fp.KeepIf`, and `fp.RemoveIf` all `return 0` unconditionally,
regardless of whether the per-line `eval` succeeded. This is a deliberate
design choice, not an oversight: these functions exist to drive
batch/deploy-style operations (symlink N files, filter M candidates) where
one item's failure should not silently abort the whole batch under the
caller's `set -e`. The trade-off is that a failing action is invisible
unless the eval'd command itself prints a diagnostic on failure — which is
exactly what `task.bash`'s `try` wrapper is for (it's the conventional
command to pass as the first `fp.Each` argument specifically so per-item
failures surface as visible `[failed]`/`[error]` lines rather than
vanishing). A caller that needs per-item failure to actually abort should
not reach for `fp.Each`; a raw loop with explicit `|| return $?` is the
correct tool (see the bash style guide's "When NOT to Use fluentfp" for the
symmetric Go-side judgment call).

## fp.Stream's empty-args guard

```bash
fp.Stream() {
  local IFS=$'\n'
  (( $# == 0 )) || echo "$*"
}
```

Without the `$# == 0` guard, `echo "$*"` on zero arguments still emits a
single blank line (an empty string is not "no output"). Downstream
`fp.KeepIf`/`fp.Each` stages would then process one spurious empty-string
"item" per empty-input pipeline invocation. The guard makes "no items"
produce genuinely zero output lines.

## Known gaps

- **No test suite.** `fp.bash` currently has no `*_test.bash` file. The
  multi-word-command bug above went undetected specifically because
  nothing exercised `fp.Each`/`fp.KeepIf` with more than one command word —
  a `tesht` suite covering that case (and the `fp.Map` `IFS=' '` case,
  which has an independent historical incident of its own) would have
  caught both by construction. Not added as part of this doc-writing pass;
  worth a follow-up task.
- **`fp.RemoveIf`** still has the pre-fix single-argument signature (see
  above) — consistent with its current callers, but latent for the same
  reason `fp.Each` was.
