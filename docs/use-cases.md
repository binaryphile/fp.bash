# fp.bash Use Cases

WHAT fp.bash is for, from the perspective of the bash script author calling
it. See `design.md` for HOW each function works internally (eval mechanics,
quoting, IFS handling).

## Actor-Goal List

| Actor | Goal |
|---|---|
| Script Author | Apply one command to every item in a list, without writing a raw `for` loop |
| Script Author | Filter a list down to items matching (or not matching) a condition |
| Script Author | Transform each line of a list into a new value |
| Script Author | Turn a fixed argument list into a line-oriented stream for piping |
| Script Author | Collect a piped line stream back into a single array-literal string |
| Script Author | Abort a script immediately with a one-line diagnostic |

Every goal above is a **Subfunction**-level use case on its own (seconds,
not independently valuable) — real value comes from composing them into
pipelines, which is why UC-1 below is written at **Summary** level.

## UC-1: Deploy a Set of Managed Files (Summary)

- **Primary Actor:** Script Author
- **Goal:** Apply a repeatable action (symlink, copy, install) across a
  filtered, transformed list of paths, expressed as one pipeline instead of
  an imperative loop.
- **Scope:** fp.bash's five pipeline primitives (`fp.Stream`, `fp.KeepIf`,
  `fp.RemoveIf`, `fp.Map`, `fp.Each`) composed via `|`.
- **Level:** Summary (encompasses the four subfunction UCs below; this is
  "that's not just one thing" — filtering, transforming, and acting are
  three separate concerns chained into one statement).
- **Stakeholders:**
  - Script Author — wants the pipeline to read as a table of intent (filter →
    transform → act), not a loop body with embedded conditionals.
  - Future Maintainer — wants each stage's failure mode to be locally
    reasoned about, not buried in loop state.
- **Preconditions:** `IFS=$'\n'; set -o noglob` in effect (per the bash
  style guide's safety preamble) — every fp.bash function assumes
  newline-delimited items, not space-delimited words.
- **Main Success Scenario:**
  1. Script Author has a fixed set of source items (an argument list or a
     heredoc).
  2. Script Author streams the items line-by-line with `fp.Stream` (from
     `"$@"`) or a bare heredoc.
  3. Script Author narrows the stream with zero or more `fp.KeepIf` /
     `fp.RemoveIf` stages, each a single predicate function name.
  4. Script Author reshapes each surviving line with `fp.Map`, producing a
     new value per line (e.g. a destination path derived from a source
     path).
  5. Script Author terminates the pipeline with `fp.Each`, applying the
     actual side-effecting command to each transformed line.
  6. The pipeline exits 0 regardless of individual item failures (fp.Each/
     KeepIf/RemoveIf all `return 0` unconditionally) — see Minimal
     Guarantee.
- **Extensions:**
  - 5a. The command needs more than one word (e.g. `try task.Ln
    nix-wrapper`, not just `task.Ln`): pass every word as a separate
    argument to `fp.Each`/`fp.KeepIf`/`fp.RemoveIf` — `fp.Each try task.Ln
    nix-wrapper <<<...`. All leading words join into one %q-escaped
    command; only the per-line value is a separate token.
    - *Failure mode this guards against*: dotfiles `update-env` shipped
      `fp.Each try task.Ln nix-wrapper <<'END' ...bin/go... END` for
      months. Before the fix, `fp.Each` only read `$1` ("try") as the
      command and silently dropped `task.Ln nix-wrapper`, so each line
      evaluated as `try <path>` — directly *executing* the wrapped `go`
      binary with zero arguments instead of symlinking it. The bug was
      invisible while the wrapped binary itself crashed on empty exec (a
      separate, unrelated bug); fixing that first is what made this one
      loud (bare `go --help` text, and — because the failing command's
      exit code propagated through `set -e` — the rest of `update-env`'s
      run silently never executed).
  - 5b. A downstream stage's predicate or command needs to see the *whole*
    remaining pipeline of one item (not just the current line): fp.bash
    has no such primitive — restructure as an `fp.Map` producing a
    delimited compound value, or drop to a raw loop (see the bash style
    guide's "When NOT to Use fluentfp" for the equivalent Go-side
    judgment call).
- **Minimal Guarantee:** No stage in the pipeline aborts the whole script on
  a single item's failure — `fp.Each`, `fp.KeepIf`, and `fp.RemoveIf` return
  0 unconditionally, by design (see design.md "Why errors don't
  propagate"). The trade-off: a failing action is silent unless the
  command itself prints a diagnostic (as `try` does).
- **Success Guarantee:** Every surviving, transformed line has had the
  terminal command applied to it exactly once, in stream order.

## UC-2: Filter a List Down to a Matching Subset (Subfunction)

- **Primary Actor:** Script Author
- **Goal:** Keep (or remove) lines from a stream based on a single-purpose
  predicate function.
- **Trigger:** Script Author has a candidate list (e.g. every file in a
  directory) but only some of them qualify for the next pipeline stage.
- **Main Success Scenario:**
  1. Script Author writes a predicate function that takes one line as `$1`
     (or more, per UC-1 Extension 5a) and returns 0 for "keep"/"true".
  2. Script Author pipes a stream into `fp.KeepIf predicateName` (or
     `fp.RemoveIf predicateName` for the negation).
  3. Each surviving line is echoed to stdout, preserving order, for the
     next pipeline stage.
- **Example (from dotfiles update-env):**
  ```bash
  fp.Stream ~/.claude/commands/*.md |
    fp.KeepIf isFile |
    fp.KeepIf isNotReadme |
    fp.Map path '$path ~/.claude/commands/$(basename $path)' |
    fp.Each task.Ln
  ```
- **Extensions:**
  - 1a. The predicate needs to be an inline check rather than a named
    function: define a one-line wrapper function first — `fp.KeepIf`
    always evals a *command name*, not an arbitrary expression.

## UC-3: Reshape Each Line Into a New Value (Subfunction)

- **Primary Actor:** Script Author
- **Goal:** Compute a new value per input line (e.g. derive a destination
  path from a source path) without a loop.
- **Main Success Scenario:**
  1. Script Author picks a variable name that is not `VARNAME` or
     `EXPRESSION` (fp.Map's own internal names — collision would shadow the
     caller's binding).
  2. Script Author writes a double-quoting-safe expression referencing
     `$<varname>`, e.g. `'$path ~/.claude/commands/$(basename $path)'`.
  3. Script Author pipes a stream into `fp.Map varname 'expression'`.
  4. Each input line is bound to `$<varname>`, the expression is evaluated
     and echoed, one output line per input line.
- **Extensions:**
  - 2a. The expression needs a literal double quote: not supported —
    `fp.Map`'s expression is spliced inside `eval "echo \"$EXPRESSION\""`,
    so an embedded unescaped `"` breaks quoting. Restructure to avoid it.

## UC-4: Turn a Fixed Argument List Into a Stream (Subfunction)

- **Primary Actor:** Script Author
- **Goal:** Feed `"$@"` or a delimited string into a line-oriented pipeline.
- **Main Success Scenario:**
  1. Script Author calls `fp.Stream "$@"` (or any argument list) — each
     argument becomes one line on stdout, via `IFS=$'\n'` join.
  2. For a single pre-delimited string (not yet split into arguments),
     Script Author calls `fp.StreamList "$list" [sep]` instead — splits on
     `sep` (default `$IFS`) then delegates to `fp.Stream`.
- **Extensions:**
  - 1a. No arguments given: `fp.Stream` with zero args produces no output
    (guarded explicitly — an empty `"$*"` would otherwise emit a blank
    line).

## UC-5: Collect a Stream Back Into One Value (Subfunction)

- **Primary Actor:** Script Author
- **Goal:** Reverse UC-4 — take a line stream (e.g. from a pipeline) and
  produce one array-literal string, for assignment or further eval.
- **Main Success Scenario:**
  1. Script Author pipes a line stream into `fp.Collect [sep]`.
  2. Each line is evaluated as an array-append expression (`results+=(
     $field )`) — so lines are expected to be glob/word-splittable content,
     not arbitrary text.
  3. `fp.Collect` echoes the resulting array as `"${results[*]}"`,
     sep-joined.

## UC-6: Abort with a Clear Diagnostic (Subfunction)

- **Primary Actor:** Script Author
- **Goal:** Stop script execution immediately with a one-line `fatal:
  <message>` and a specific exit code.
- **Main Success Scenario:**
  1. Script Author calls `fp.fatal "message" [rc]` from anywhere in the
     script.
  2. `fp.fatal` prints `fatal: <message>` and exits with `rc` (default:
     `$?` at the time of the call).
- **Preconditions:** Used internally by `fp.Map` to guard the `VARNAME`/
  `EXPRESSION` collision case; also safe to call directly from caller code.
