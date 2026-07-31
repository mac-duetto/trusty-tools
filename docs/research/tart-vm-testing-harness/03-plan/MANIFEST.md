# MANIFEST — `vmtest-harness/` implementation progress

**Format version:** 1
**Plan:** [01-implementation-plan.md](./01-implementation-plan.md) (DOC-3)
**Design:** [DOC-1](../02-design/01-vm-install-harness.md), [DOC-2](../02-design/02-harness-contracts.md)
**Location is deliberate:** this file lives beside the plan in `03-plan/`, **not**
inside `vmtest-harness/`. It records the history of building that directory and
must survive independently of it — including the case where a phase fails and the
directory is deleted and started again.

## Why this file exists

The plan is executed **autonomously**, in sessions that may end at any point. This
file is **the only durable progress record between sessions.** An agent resuming
work reads DOC-1, DOC-2, the plan, and then this file — and this file is the only
one of the four that tells it what has actually happened.

Treat it accordingly:

- **Observed results are pasted output, never claims.** "Checkpoint passed" is not
  an observed result. The terminal output is.
- **It is append-only in spirit.** Correct a wrong entry by adding a dated
  correction beneath it, not by deleting it. A record whose history is rewritten is
  a record nobody can audit — the same principle DOC-1 D2 applies to reversed
  design decisions.
- **A deviation is never omitted for being small.** The deviations field is where
  the next agent finds out why the code does not match the plan.

---

## Schema

### Summary table

One row per phase. Kept in sync with the phase sections below; the sections are
authoritative and the table is the index.

| Column | Values | Rule |
|---|---|---|
| `Phase` | `P1`…`P8` | Fixed. Matches the plan's phase numbers. |
| `State` | `not-started` \| `in-progress` \| `complete` \| `blocked` | See state rules below. |
| `Updated` | `YYYY-MM-DD` (UTC) | Date of the last change to this phase's section. |
| `Commit` | short SHA, or `—` | The commit whose tree the observed result was produced from. |

### Per-phase section

Every phase has a section with **exactly these seven fields, in this order**. A
field is never removed; an empty one carries its stated placeholder.

| Field | Content | Placeholder when empty |
|---|---|---|
| **State** | one of the four values | `not-started` |
| **Pass condition** | the checkpoint pass condition, **copied verbatim from the plan**. Copied rather than referenced so a stale plan and a stale record cannot silently agree. | (always populated from the start) |
| **Observed result** | the **actual output** of running the checkpoint: the command line, its output, its exit status, and the UTC date it was run. Pasted, not paraphrased. | `— not run` |
| **Files delivered** | every path created or modified, marked `create` / `modify` / `delete`. Repo-relative. | `— none` |
| **Measurements** | numeric findings this phase produced, each with the command that produced it. Several phases exist partly to produce these. | `— none` |
| **Deviations from plan** | anything done differently, with the reason, and the §F item if it resolves one. | `None.` |
| **Tasks** | task IDs completed, e.g. `P1-T1..P1-T7 complete; P1-T8 in progress`. | `— none complete` |

### State rules

- `not-started` → `in-progress` when the phase's **first task** is committed.
- `in-progress` → `complete` **only** when the checkpoint has been **run** and its
  output is pasted into `Observed result`. A phase is never `complete` on the
  strength of its tasks being done; the checkpoint is the gate.
- `in-progress` → `blocked` when a task cannot proceed and the plan does not
  resolve it. `blocked` **requires** a Deviations entry naming what is needed to
  unblock, and it halts the plan — a later phase does not start around it.
- `complete` → `in-progress` is legal (rework). Add a dated note; do not erase the
  previous observed result.

### The update rule

**Updating this file is the final numbered task of every phase in the plan** —
P1-T11, P2-T8, P3-T7, P4-T5, P5-T9, P6-T5, P7-T5, P8-T6. It is a task with an
acceptance check, not a convention and not a footnote. A phase whose final task has
not been completed is not complete, regardless of what its code does.

### Worked example of a filled section

```markdown
### Phase 1 — Transport spike

- **State:** complete
- **Pass condition:** `bash vmtest-harness/spike/spike-transport.sh` exits 0 and …
- **Observed result:** (run 2026-08-04 UTC)
  ```
  $ bash vmtest-harness/spike/spike-transport.sh; echo "exit=$?"
  READY after 33s
  N1 PASS (cargo=127 rustc=127 rustup=127)
  streamed 84930112 bytes / 5311 files
  trusty-search 0.40.0
  exit=0
  $ tart list | grep vmtest-spike | wc -l
         0
  ```
- **Files delivered:** create `vmtest-harness/spike/spike-transport.sh`;
  create `vmtest-harness/base-image.pin`
- **Measurements:** streamed bytes 84,930,112 (`… | wc -c`); …
- **Deviations from plan:** §F-10(d) resolved by narrowest reading — `tart-run.pid`
  reaped after `vm_wait_for_stopped` returned, not killed.
- **Tasks:** P1-T1..P1-T11 complete
```

---

## Summary

| Phase | State | Updated | Commit |
|---|---|---|---|
| **P1** — Transport spike (thin vertical slice) | `complete` | 2026-07-31 | `7df36745` |
| **P2** — Host-side skeleton | `not-started` | — | — |
| **P3** — Guest bring-up | `not-started` | — | — |
| **P4** — Expectation table and `--check-table` | `not-started` | — | — |
| **P5** — Pattern (c) complete: installs, N2, oracle | `not-started` | — | — |
| **P6** — Pattern (b): branch | `not-started` | — | — |
| **P7** — Pattern (a): released | `not-started` | — | — |
| **P8** — Hardening, docs, measurement write-back | `not-started` | — | — |

**Plan status:** Phase 1 complete, 2026-07-31. `vmtest-harness/` **exists**. Phase 2
is the next phase to start.

**Open items carried into execution** (from DOC-1 §14 and DOC-2 open items):

- **RC-1 — unified daemon health envelope.** Does not exist. **Scoped around, not
  a blocker**: the oracle asserts **liveness only** for daemon health (plan P5-T7).
- **RC-2 — `tctl install` cargo-absent exit code.** Unpinned at
  `crates/trusty-installer/src/commands/install.rs:826`. **Pinned by plan P5-T2**;
  N2's predicate stays deliberately weak until then.
- **Full base-image digest.** ~~Placeholder.~~ **CLOSED 2026-07-31 by P1-T3.**
  `sha256:a8e1c8305758643f513fdccdd829c2243687c60791083dea42f73f0b7aeb435c`,
  captured untruncated from `tart list --format json` and committed as
  `vmtest-harness/base-image.pin`. DOC-2 §3.3's introspection branch applies; the
  **by-construction variant was not needed**. P2-T5 is unblocked.
- **Pattern (c) tar transport, end-to-end.** ~~Never measured.~~ **CLOSED
  2026-07-31 by Phase 1 — the transport WORKS.** 96,788,480 bytes / 5,337 files
  streamed host→guest through `git ls-files -co --exclude-standard | tar |
  tart exec -i` in 4 s, unpacked with an exact file-count match, and
  `trusty-search` built and installed from the unpacked tree in 105 s. DOC-1 §14's
  headline gap and devil's-advocate critique #9 are retired. DOC-1 D4's fallback
  re-ordering to (b) → (c) → (a) is **not** triggered.
- **Full-stack timing.** The 4–8 min figure is an extrapolation for six crates
  against what is now an eight-crate scope (widened twice on 2026-07-31: D2's
  reversal, then D3's `trusty-review` addition). **Replaced by plan P5-T8.**
- **Daemon time-to-ready.** Wholly unmeasured; DOC-2 §10.1's 60 s maximum is a
  guess. Revisited in P8-T2.
- **NEW, opened by Phase 1 — DOC-1 §6.1's payload figure is a *content* figure,
  not a *wire* figure.** The two differ by tar framing and the doc set does not
  currently distinguish them. See Phase 1 Measurements; written back in P8-T4.
- **NEW, opened by Phase 1 — P2-T4's acceptance grep cannot pass while
  `spike/` exists.** See Phase 1 Deviations item 4. Phase 2 must resolve it.
- **NEW, opened by Phase 1 — pattern (c)'s defining property is still untested.**
  The Phase 1 run streamed a **clean** worktree, so `-o` contributed zero files and
  *"it includes uncommitted work"* (DOC-1 §6.1) was never exercised. The transport
  is verified; the thing that makes it pattern (c) rather than a slower pattern (b)
  is not. Run it once against a dirty worktree — P3-T4 or P5.

---

## Phase 1 — Transport spike (thin vertical slice)

- **State:** `complete`
- **Pass condition:** `bash vmtest-harness/spike/spike-transport.sh` **exits 0** and
  its final three log lines report: (i) a streamed byte count greater than
  80,000,000; (ii) the guest's `trusty-search --version` output on stdout;
  (iii) `tart list` containing **no** `vmtest-spike-*` entry after teardown.
- **Observed result:** **MET.** (run 2026-07-31 UTC, tree `7df36745`, host: Apple
  M5 Pro, 18 physical cores, 64 GiB, macOS 26.5.2 arm64, tart 2.32.1.)

  The three checkpoint lines, verbatim, from the script's **stdout**:

  ```
  $ bash vmtest-harness/spike/spike-transport.sh > run.out 2> run.err; echo "EXIT=$?"
  $ cat run.out
  STREAMED_BYTES 96788480 FILES 5337
  trusty-search 0.40.0
  TART_LIST vmtest-spike-* entries after teardown: 0
  EXIT=0
  ```

  Condition by condition: (i) `96788480 > 80000000` — **met**; (ii)
  `trusty-search 0.40.0`, the guest's own `trusty-search --version` output —
  **met**; (iii) zero surviving entries — **met**, and independently confirmed
  below.

  The full run log (**stderr**), verbatim:

  ```
  [23:46:12] spike-transport.sh starting (pid 55130)
  [23:46:12] host repo: /Users/mac/workspace/trusty-tools-fork-worktrees/agent-a2706961fee0e64fa
  [23:46:12] --- P1-T1: host dependency set ---
  [23:46:12] tart  2.32.1
  [23:46:12] git version 2.50.1 (Apple Git-155)
  [23:46:12] jq    jq-1.7.1-apple
  [23:46:13] cargo 1.91.1 (ea2d97820 2025-10-10)
  [23:46:13] bash  3.2.57(1)-release
  [23:46:13] P1-T1 PASS (JQ_OK)
  [23:46:13] --- P1-T3: base-image pin ---
  [23:46:13] pin OK: ghcr.io/cirruslabs/macos-tahoe-base@sha256:a8e1c8305758643f513fdccdd829c2243687c60791083dea42f73f0b7aeb435c
  [23:46:13] P1-T3 PASS
  [23:46:13] --- P1-T2: clone, size, boot, poll ready ---
  [23:46:13] clone tahoe-base -> vmtest-spike-20260731T234613Z-55130
  [23:46:14] size --cpu 8 --memory 16384
  [23:46:14] boot (tart run --no-graphics, backgrounded)
  [23:46:32] READY after 18s
  [23:46:32] state: running
  [23:46:32] P1-T2 PASS
  [23:46:32] --- P1-T4: N1 precondition probe ---
  [23:46:33] N1 PASS (cargo=1 rustc=1 rustup=1)
  [23:46:33] --- P1-T5: provisioning ---
  mise WARN  mise version 2026.7.18 available
  mise WARN  mise version 2026.7.18 available
  [23:46:35] mise detected at /opt/homebrew/bin/mise (2026.6.0 macos-arm64 (2026-06-03)) — REUSED, not installed
  [23:46:36] gh detected at /opt/homebrew/bin/gh — REUSED, not installed
  [23:47:16] provisioning wall clock 40s (measured baseline PROVISION_MS=30079, i.e. 30.079s)
  [23:47:16] rustc from /Users/admin: rustc 1.91.1 (ed61e7d7e 2025-11-07)
  [23:47:16] P1-T5 PASS
  [23:47:16] --- P1-T6: THE SLICE — stream the worktree ---
  [23:47:16] host repo (read-only): /Users/mac/workspace/trusty-tools-fork-worktrees/agent-a2706961fee0e64fa
  [23:47:16] host file count (git ls-files -co --exclude-standard | wc -l): 5337
  [23:47:21] streamed 96788480 bytes in 4s
  [23:47:22] guest file count (find ! -type d): 5337
  [23:47:22] guest file count (find -type f, the plan's literal command): 5333
  [23:47:22] file counts match: G == H == 5337
  [23:47:22] target/ absent in guest, by construction
  [23:47:22] P1-T6 PASS
  [23:47:22] --- P1-T7: build trusty-search from the unpacked tree ---
  [23:47:22] rustc in crates/trusty-search: rustc 1.91.1 (ed61e7d7e 2025-11-07)
  [23:49:07] build+install wall clock 105s (measured baseline: 112s for trusty-search, 409 crates, 8 vCPU)
  [23:49:08] trusty-search installed at /Users/admin/.cargo/bin/trusty-search
  [23:49:09] trusty-search --version -> trusty-search 0.40.0
  [23:49:09] P1-T7 PASS
  [23:49:09] --- P1-T8: teardown and host-cleanliness assertion ---
  [23:49:09] teardown: vm_request_stop vmtest-spike-20260731T234613Z-55130
  [23:49:10] teardown: state 'stopped' observed 0s after vm_request_stop returned
  [23:49:11] teardown: deleted vmtest-spike-20260731T234613Z-55130
  [23:49:11] host clean: no vmtest-spike-* VM in tart list
  [23:49:11] P1-T8 PASS
  [23:49:11] === MEASUREMENTS (P1-T9) ===
  [23:49:11] boot_to_ready_s          18
  [23:49:11] provision_s              40
  [23:49:11] stream_s                 4
  [23:49:11] streamed_bytes           96788480
  [23:49:11] streamed_files           5337
  [23:49:11] build_install_s          105
  [23:49:11] stop_to_stopped_s        0
  [23:49:11] base_image_digest        sha256:a8e1c8305758643f513fdccdd829c2243687c60791083dea42f73f0b7aeb435c
  [23:49:11] total_wall_clock_s       179
  [23:49:11] === end measurements ===
  ```

  Independent host-cleanliness proof, run from a separate shell **after** the
  script exited — raw `tart list`, unedited:

  ```
  $ tart list
  Source Name                                                                                                        Disk Size Accessed      State
  local  tahoe-base                                                                                                  50   33   4 minutes ago stopped
  OCI    ghcr.io/cirruslabs/macos-tahoe-base:latest                                                                  50   32   2 weeks ago   stopped
  OCI    ghcr.io/cirruslabs/macos-tahoe-base@sha256:a8e1c8305758643f513fdccdd829c2243687c60791083dea42f73f0b7aeb435c 50   32   2 weeks ago   stopped
  ```

  No `vmtest-spike-*` entry survives. The three pre-existing images are byte-for-byte
  the same rows as before the run (`Disk 50`, `Size 33`/`32`, `stopped`); only
  `tahoe-base`'s `Accessed` timestamp moved, which is what an APFS CoW clone does
  to its source. The base image was **not** modified, re-pulled or re-tagged.

  P1-T3 acceptance, separately:

  ```
  $ grep -Eq '^digest<TAB>sha256:[0-9a-f]{64}$' vmtest-harness/base-image.pin && echo PIN_REAL
  PIN_REAL
  ```
- **Files delivered:**
  - create `vmtest-harness/base-image.pin`
  - create `vmtest-harness/spike/spike-transport.sh`
  - modify `docs/research/tart-vm-testing-harness/03-plan/MANIFEST.md`
- **Measurements:** all six the plan asks for (P1-T9), plus the digest. Each is
  the value the script logged, with the command that produced it.

  | # | Measurement | Value | Command / source | Compared against |
  |---|---|---|---|---|
  | 1a | **streamed byte count** | **96,788,480 B** (92.3 MiB) | `git ls-files -co --exclude-standard -z \| tar -cf - --null -T - \| dd bs=1048576 \| tart exec -i …`; `dd`'s `bytes transferred` | DOC-1 §6.1's **~81 MiB** estimate — see the note below, they measure different things |
  | 1b | **streamed file count** | **5,337** | `git ls-files -co --exclude-standard \| wc -l` (host) and `find /Users/admin/vmtest-src ! -type d \| wc -l` (guest) — **equal** | DOC-1 §6.1's 5,306 (`git archive`, tracked only) |
  | 2 | **boot to ready** | **18 s** | poll `tart exec <vm> /bin/sh -c 'exit 0'` @ 2 s, from `tart run` | DOC-2 §10.1: 34.4 s first boot, **18.0 s subsequent** — this is a subsequent boot and it lands on the measured value exactly |
  | 3 | **provisioning** | **40 s** | wall clock across mise detect + `mise use -g rust@1.91` + `mise use -g uv@latest` + `~/.zshenv` | measured `PROVISION_MS=30079`. **1.33×** — inside P1-T5's 3× acceptance bound |
  | 4 | **`trusty-search` build + install** | **105 s** | `cargo install --path /Users/admin/vmtest-src/crates/trusty-search` under the §7.3 prelude, watchdogged at 900 s | measured **112 s** (409 crates, 8 vCPU, `SKIP_UI_BUILD=1`). **0.94×** |
  | 5 | **`vm_request_stop` → `stopped`** | **< 1 s** (logged `0 s`) | `date +%s` delta across `vm_request_stop` returning → first `tart list` reporting `stopped` | DOC-2 §10.1's **120 s** maximum. See the note below |
  | 6 | **base-image digest** | `sha256:a8e1c8305758643f513fdccdd829c2243687c60791083dea42f73f0b7aeb435c` | `tart list --format json \| jq -r '.[] \| .Name'` → the `…@sha256:…` OCI row | research had it **truncated only** (`sha256:a8e1…`, `vm-install-probe-findings.md:652`, `:685`) |

  Also recorded: transport throughput **≈24 MB/s** (96,788,480 B in 4 s), and
  **total run wall clock 179 s** (clone → teardown, single crate).

  **Note on 1a — DOC-1 §6.1's figure is a *content* figure; the streamed figure is
  a *wire* figure. The doc set does not distinguish them, and it should.** The raw
  content of the delivered file set measures **81,762,761 B (78.0 MiB)** across the
  same 5,337 files (`git ls-files -co --exclude-standard -z | xargs -0 stat -f '%z'
  | awk '{s+=$1} END {print s}'`), which is very close to DOC-1 §6.1's ~81 MiB. The
  **96,788,480 B actually crossing the pipe** is that content plus **15,025,719 B
  (+18.4%) of `tar` framing** — a 512-byte header per entry plus 512-byte block
  padding, which is large in relative terms precisely because this repo is many
  small files. So DOC-1 §6.1 was not wrong about the payload; it was answering a
  different question from the one it asked the implementation to answer. Both
  numbers clear the checkpoint's 80,000,000 threshold, but the content figure only
  just does — an implementation that had counted content bytes instead of wire
  bytes would have passed by 2%, on a quantity the pass condition does not name.
  P8-T4 should write back **both**, labelled.

  **Note on 1b — CORRECTION. The `-o` hypothesis is wrong, and this run did not
  test it at all.** The first draft of this entry attributed the 5,337 vs 5,306
  delta to `-o` adding untracked-but-not-ignored files, which is the mechanism
  DOC-1 §6.1 predicts. **That is false for this run.** Measured after the fact:

  ```
  $ git ls-files | wc -l                          # tracked only
      5337
  $ git ls-files -o --exclude-standard | wc -l     # untracked, not ignored
         0
  $ git status --short                             # (no output)
  ```

  The delivery worktree was **clean**, so `-o` contributed **zero** files and the
  streamed set was exactly the tracked set. The +31 over 5,306 is simply repository
  growth since the research measured it. **Consequence: DOC-1 §6.1's stated concern
  — that its figure is a "lower bound / close proxy" because `-o` adds files
  `git archive` never sees — remains UNTESTED.** The one property that most
  distinguishes pattern (c) from pattern (b), *"it includes uncommitted work"*
  (DOC-1 §6.1), was **not exercised by this run**, because there was no uncommitted
  work to include. Phase 3's promotion of this pipeline (P3-T4) or Phase 5 should
  deliberately run it against a dirty worktree at least once.

  Recorded as a correction rather than a silent edit, per this file's append-only
  rule — and because it is the same failure mode §F-3 catalogues: reasoning from a
  plausible mechanism instead of running the command.

  **Note on 5 — the interval is below the harness's own observational floor, and
  that is the finding.** `vm_wait_for_stopped`'s **first** poll — issued
  immediately after `vm_request_stop` returned, before any `sleep` — already
  observed `stopped`. So the true interval is bounded above by the duration of one
  `tart list --format json | jq` round-trip, and cannot be resolved more finely by
  a poll whose interval is 1 s (DOC-2 §10.1). DOC-2 §10.1 labelled its 120 s
  maximum "a **judgment call** … worst-case flush duration was never measured";
  it is now known to be conservative by **more than two orders of magnitude** in
  the nominal case, and there is no reason to tighten it — an unnecessarily loose
  bound on a path that never approaches it costs nothing, and DOC-2 §10.3's
  "no retry, ever" means the budget is only ever spent on a genuinely stuck VM.
  **This does not contradict the research's K1/K1b/K1c asynchrony finding**, which
  was about *durability* — "the state flag is not a durability flag"
  (`vm-install-probe-findings.md:814-817`) — not about how fast the flag flips.
  One run is one data point; it is not a distribution.

  **Finding — N1's observed exit code is 1, not 127, and DOC-2 §6.2 called it.**
  All three of `cargo`, `rustc`, `rustup` returned **exit 1** with empty stdout
  under `command -v` at the measured base PATH. DOC-2 §6.2 wrote: *"127 is what the
  research measured for an absent `cargo` … `command -v` itself returns **1** on
  not-found; the harness asserts **non-zero**, which both satisfy … pinning a code
  that was measured for a different command would be exactly the kind of false
  precision this doc set avoids."* A harness that had pinned 127 would have failed
  **every run**. Recorded because the reasoning was right for a reason that is now
  observed rather than argued.

  **Finding — the transport imposes no build-time penalty.** The 105 s build ran
  against a tree delivered by tar-over-`tart exec -i`; the 112 s baseline (K3) ran
  against a tree delivered by guest-side `git clone`. Same crate, same sizing, and
  the tar-delivered build was marginally *faster*. The transport is not a
  build-performance risk, only — until now — a correctness one.
- **Deviations from plan:**
  1. **P1-T6 acceptance: the guest file count is asserted on `find … ! -type d`,
     not the plan's literal `find … -type f`.** This repo carries **4 tracked
     symlinks** (`git ls-files -s | awk '$1=="120000"' | wc -l` → 4), which `tar`
     transfers correctly as symlinks and which `-type f` does not count. The
     plan's literal command therefore reports `G = H − 4` on a **perfectly correct
     transfer** and would fail its own acceptance. Both counts are computed and
     logged every run (`5337` and `5333`); the equality assertion uses the
     comparable set. **The plan's check is wrong as written, not merely
     inconvenient** — P3-T4 should carry `! -type d` into `lib/source.sh`.
  2. **Byte counting uses `dd` as a pipeline element, not `tee >(wc -c)`.** The
     plan says only "count the bytes crossing the pipe". A process substitution's
     writer is not synchronised with the pipeline's return, so `tee >(wc -c >file)`
     races the read of `file`; `dd` is *in* the pipeline, so its
     `bytes transferred` total is complete before the pipeline exits. No new host
     dependency — `dd` is base macOS, and DOC-2's host set (`tart`, `git`, `jq`,
     `cargo`, bash ≥ 3.2) is unchanged.
  3. **P1-T3 also exercises DOC-2 §3.3's comparison and §3.2's unknown-key rule,
     one phase early.** The plan asks only that the pin file be written. The spike
     additionally reads it with the shared `awk` TSV reader, rejects unknown keys,
     refuses §3.2's placeholder digest by name, and queries `tart list` for
     `<oci_ref>@<digest>`. Purely additive; it de-risks P2-T5 and it is what
     produced the `pin OK:` line above. **The by-construction variant was not
     needed** — `tart list --format json` exposes the untruncated digest as the
     `Name` field of the OCI row, which DOC-2 §3.3 flagged as a genuine unknown and
     which is now answered.
  4. **FORWARD CONFLICT, opened here for Phase 2: P2-T4's acceptance grep cannot
     pass while `spike/` exists.** P2-T4 requires
     `grep -rln 'tart' vmtest-harness --include='*.sh' --include='vmtest'` to list
     **only** `lib/vm.sh`. `spike/spike-transport.sh` necessarily contains `tart`
     and is only deleted at **P3-T4**, one phase later. As written the two tasks
     are unsatisfiable together. **Not resolved here** — the stop rule applies and
     this is a plan defect, not an implementation decision. Suggested narrowest
     readings, for whoever owns Phase 2: exclude `spike/` from the grep with a
     comment naming P3-T4, **or** move the spike deletion forward to P2-T4. Do not
     weaken the invariant itself; it is DOC-1 §3.2.
  5. **§F-10(c) applied one phase early — the spike writes `~/.zshenv`.** DOC-2
     §11.4's rule (write it, never read it) is honoured with the reconciliation
     stated in a comment at the write site, as §11.4 requires. Nothing in the
     script reads, sources, or conditions on it.
  6. **P1-T5 also detects `gh`.** DOC-2 §11.2's table lists `gh` as detect-and-reuse
     alongside `mise`; P1-T5's prose names only `mise`. Detected at
     `/opt/homebrew/bin/gh` and reused, never installed. Additive.
  7. **The spike implements DOC-2 §10.4 watchdogs (provisioning 300 s, install
     900 s) that Phase 1 does not require.** Built from `kill -0` polling, no
     `timeout(1)`/`gtimeout`. Included because an unbounded hang would defeat the
     teardown guarantee under an externally imposed kill. Additive.
  8. **Task execution order within the phase: P1-T1 → P1-T3 → P1-T2 → P1-T4 …**
     P1-T3's `Depends` line says P1-T2, and the *digest capture* it describes does
     require a live `tart`. But `tart list` needs no VM, and the digest was already
     captured read-only before this phase began (see Measurement 6). Verifying the
     pin **before** cloning is strictly safer: a drifted base image is refused
     before a VM exists rather than after. No task's actual dependency is violated.

  **Not deviations, recorded so the next agent does not re-litigate them:** §F-9
  is resolved at source, so `vm_request_stop` was implemented as specified with no
  decision to make; the plan's own note that P1-T3 "reduces to recording and
  verifying" the already-captured digest was followed; **P1-T10 is `N/A —
  transport verified`**, so no `blocked` state and no product-owner sign-off is
  pending, and DOC-1 D4's (b)-first fallback is **not** invoked.
- **Tasks:** P1-T1 … P1-T11 complete. (P1-T10 recorded `N/A — transport verified`.)

## Phase 2 — Host-side skeleton: driver, config, registry, `lib/vm.sh`, preflight, `clean`

- **State:** `not-started`
- **Pass condition:** all three hold, in one session —
  1. `vmtest run local --dry-run` **exits 0**, prints an effective-configuration
     banner in which every key carries an origin marker (`default` / `env` /
     `flag`), and `tart list` afterwards shows **no new VM**.
  2. `VMTEST_CPU=4 vmtest run local --dry-run` prints `cpu 4 (env)`, and
     `vmtest run local --cpu 2 --dry-run` prints `cpu 2 (flag)`.
  3. `vmtest clean --dry-run` correctly classifies a hand-created stopped
     `vmtest-*` VM as `ORPHANED (would delete)` and a `keep`-marked one as
     `KEPT (would not delete)`, deleting neither.
- **Observed result:** — not run
- **Files delivered:** — none
- **Measurements:** — none
- **Deviations from plan:** None. *(Expected entries: §F-1 `run --dry-run`
  definition; §F-5 TSV-reader placement. §F-9's shutdown initiator is **no longer a
  deviation to record** — `vm_request_stop` is specified in DOC-2 §12.2 as of
  2026-07-31.)*
- **Tasks:** — none complete *(P2-T1 … P2-T8)*

## Phase 3 — Guest bring-up: N1, provisioning, toolchain hand-off, source delivery

- **State:** `not-started`
- **Pass condition:** `vmtest run local` **exits 0**, and its log shows, in order:
  `N1 PASS` with a non-zero exit recorded for each of `cargo`, `rustc`, `rustup`; a
  provisioning block ending with `rustc_version 1.91.1`; a streamed byte count
  > 80,000,000; and a teardown after which `tart list` contains **no** `vmtest-*`
  entry. `$VMTEST_RUNDIR` is removed, and
  `ls "${VMTEST_STATE_DIR:-$HOME/.local/state/vmtest-harness}/runs/"` is empty.
- **Observed result:** — not run
- **Files delivered:** — none
- **Measurements:** — none *(expected: subsequent-boot ready time, for comparison
  with P1's first boot and the measured ~18 s)*
- **Deviations from plan:** None. *(Expected entry: §F-4 negative-probe module
  placement.)*
- **Tasks:** — none complete *(P3-T1 … P3-T7)*

## Phase 4 — `expected-binaries.tsv` and `--check-table`

- **State:** `not-started`
- **Pass condition:** `vmtest --check-table` **exits 0** against the workspace as it
  stands, printing no ADDED/REMOVED/CHANGED findings. Then, with one row
  deliberately deleted from `expected-binaries.tsv`, it **exits 60** and prints
  exactly one `REMOVED` finding naming that `(package, binary)` pair. The row is
  restored afterwards and the command exits 0 again.
- **Observed result:** — not run
- **Files delivered:** — none
- **Measurements:** — none
- **Deviations from plan:** None. *(Expected entry: any workspace drift from DOC-2
  §9.3's seed found by P4-T3. **§F-3 deduplication is no longer a deviation to
  record** — it was resolved on 2026-07-31: the decision was always right, its
  rationale was corrected, and P4-T4's and P5-T8's tripwires now enforce it.)*
- **Tasks:** — none complete *(P4-T1 … P4-T5)*

## Phase 5 — Pattern (c) complete: install steps, N2, and the full oracle

- **State:** `not-started`
- **Pass condition:** `vmtest run local` **exits 0**, and the run log shows:
  Counts below are **derived**, with today's value as the expected literal; if the
  TSV has changed, the derivation is the condition and the literal follows it.
  (i) one `cargo install --path` per value of `tsv_scope_crate_dirs` (**8** today),
  and no directory installed twice, each preceded by a `rustc --version` line
  emitted from inside that crate's directory;
  (ii) `verify_binaries` reporting **N/N in-scope binaries present**, where N is the
  count of `in_scope=yes` rows (**13** today);
  (iii) `tctl stack doctor --json` parsed, with every one of `tsv_scope_packages`'
  values (**8** today) — **including `trusty-mpm`** — satisfying
  `health ∈ {healthy, stale}`, `on_path == true`, `version != null`;
  (iv) one `verify_single_install` passing per multi-binary in-scope package
  (**4** today): `trusty-search` (2 binaries), `trusty-memory` (**3**),
  `trusty-installer` (2), and `trusty-mpm` (2);
  (v) N2 recorded with its observed exit code and stderr;
  (vi) a total wall clock, logged, which is recorded here as the **first full-stack
  measurement**.
- **Observed result:** — not run
- **Files delivered:** — none
- **Measurements:** — none *(expected: **the first full-stack wall clock**, which
  replaces DOC-1 §9's 4–8 min extrapolation; **RC-2's observed exit code and
  stderr** from P5-T2; the RC-1 / §F-7 daemon-liveness disposition)*
- **Deviations from plan:** None. *(Expected entries: §F-7 daemon start and port
  discovery, including the BLOCKED branch if it fires. The fourth
  `verify_single_install` call for `trusty-mpm` is **no longer a deviation to
  record** — DOC-2 §12.5's skeleton was amended at source on 2026-07-31 and carries
  it. Neither is §F-2's `tsv_version` contradiction — DOC-2 §1.2 was amended at
  source on the same date.)*
- **Tasks:** — none complete *(P5-T1 … P5-T9)*

## Phase 6 — Pattern (b): branch

- **State:** `not-started`
- **Pass condition:** `vmtest run branch` **exits 0** with the **same derived binary
  and package assertions as Phase 5** — N/N where N is the count of `in_scope=yes`
  rows (**13** today), over `tsv_scope_packages`' values (**8** today) — and the run
  log shows a
  guest-side `git clone` (no host→guest byte stream) and the checked-out branch
  name.
- **Observed result:** — not run
- **Files delivered:** — none
- **Measurements:** — none *(expected: guest `git clone` duration for comparison
  with the measured `GIT_CLONE_MS=50131`; total wall clock beside Phase 5's — the
  first side-by-side comparison of the two transports)*
- **Deviations from plan:** None. *(Record here if `install-branch.sh` needed
  anything beyond a different step 1 and pattern letter — that would mean the
  scenario abstraction leaked, which is a finding.)*
- **Tasks:** — none complete *(P6-T1 … P6-T5)*

## Phase 7 — Pattern (a): released

- **State:** `not-started`
- **Pass condition:** `vmtest run released` **exits 0**, and the run log shows one
  `cargo install <pkg> --locked` invocation per value of `tsv_scope_packages`
  (**8** today) — including **`cargo install tga --locked`**, **`cargo install
  trusty-mpm --locked`** and **`cargo install trusty-review --locked`** — followed
  by `verify_binaries` reporting **N/N present**, where N is the count of
  `in_scope=yes` rows (**13** today), with `tm` and `trusty-mpm` explicitly among
  them, and `tctl stack doctor --json` reporting `trusty-mpm` as installed.
- **Observed result:** — not run
- **Files delivered:** — none
- **Measurements:** — none *(expected: total wall clock; the published versions
  installed, which will legitimately differ from the working tree)*
- **Deviations from plan:** None. *(If `cargo install trusty-mpm --locked` fails
  because the crate is not on crates.io, record it verbatim and stop — that
  contradicts both `cargo search trusty-mpm` → `1.0.2` and a manifest with no
  `publish` key, and is a design-level finding about the D2 reversal, not a harness
  bug.)*
- **Tasks:** — none complete *(P7-T1 … P7-T5)*

## Phase 8 — Hardening, documentation, and measurement write-back

- **State:** `not-started`
- **Pass condition:** all four hold — (i) the `~/.zshenv` deletion drill passes:
  every assertion still passes with the file removed mid-run; (ii)
  `vmtest.defaults` timeouts are grounded in Phase 5–7 measurements, each with a
  comment naming the measurement; (iii) `vmtest-harness/README.md` exists and a
  reader who has never seen the doc set can run `vmtest run local` from it alone;
  (iv) `git grep -n 'publish = false' docs/research/tart-vm-testing-harness/`
  returns **no** claim that `trusty-mpm` is unpublished.
- **Observed result:** — not run
- **Files delivered:** — none
- **Measurements:** — none
- **Deviations from plan:** None. *(No entry expected for §F-8: the
  `02-design/README.md` correction was made at source on 2026-07-31, and P8-T5 is
  now a verification check that should deliver no diff.)*
- **Tasks:** — none complete *(P8-T1 … P8-T6)*

---

## Appendix — resuming work

A future agent picking this up, in order:

1. Read [DOC-1](../02-design/01-vm-install-harness.md) and
   [DOC-2](../02-design/02-harness-contracts.md) in full. **Do not re-litigate a
   settled decision**; note in particular that D2/D3 were **reversed on
   2026-07-31** — `trusty-mpm` is published at v1.0.2, pattern (a) covers all
   **seven** crates, and `tm` is asserted **present**, not absent. Note that **D3
   was widened again the same day** — `trusty-review` was added by owner decision,
   so the scope is **eight** crates and **thirteen** in-scope binaries (plan §A.1b).
   A doc that says "seven" is recording the state between the two amendments.
2. Read [the plan](./01-implementation-plan.md), including **§F** — the flagged
   under-specifications and their decision rules. **Ten were flagged; four (§F-2,
   §F-3, §F-8, §F-9) are resolved and six remain open.** If you hit a decision the plan
   and DOC-2 do not settle and §F does not cover, **stop and record it here**
   rather than inventing a contract.
3. Read this file's summary table. Start at the first phase that is not `complete`.
   If any phase is `blocked`, resolve that first — the plan does not route around a
   blocked phase.
4. Verify before trusting. This file records what was true when it was written; the
   repo records what is true now. If they disagree, the repo wins, and this file
   gets a dated correction.
