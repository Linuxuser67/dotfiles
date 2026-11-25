---
name: replace-with-established-api
description: Use when auditing code for hand-rolled logic (file I/O, threading, RNG, path handling, formatting, parsing) that a dependency already provides.
---

# Replace with Established API

## Overview

Hand-written code that duplicates an existing API is a maintenance liability: it misses edge cases the library handles, it doesn't get security fixes, and every reader must verify it from scratch. This skill encodes the workflow for finding such code and replacing it safely.

This is a **process skill** (methodology, not a tool wrapper). It teaches judgment: when to replace, when to keep, and how to verify the swap.

## When to use

- Auditing a codebase for hand-rolled logic that a std, library, or platform API already covers.
- Reviewing a PR that adds custom code for something like atomic file writes, thread spawning, random numbers, XDG paths, size/duration formatting, or URL parsing.
- The user asks to "simplify", "use the platform API", or "stop hand-rolling X".

## When NOT to use

- The hand-rolled version is **deliberately stricter** than the API (e.g., a custom `rename_noreplace` that avoids a check-then-act race in GLib's move).
- The hand-rolled version **exists to bypass** the API's default (e.g., a custom `real_home_dir` that bypasses Flatpak's `$HOME` remap which `glib::home_dir()` prefers).
- The API **can't express** the required semantics (e.g., reqwest's `Policy::limited` returns an error where you need the 3xx response; it can't refuse https→http downgrades).
- No dependency provides the functionality (e.g., Content-Range parsing, custom-alphabet base64).

When in doubt, keep the hand-rolled version and document *why* in a comment. A wrong replacement is worse than duplication.

## Process

### 1. Locate candidates

Grep for hand-rolled patterns. Common hunting grounds:

| Domain | Hand-rolled smell | Established API to check first |
|---|---|---|
| Atomic file writes | temp file + `sync_all` + `rename` + dir sync | `gio::File::replace_contents`, `std::fs` atomic patterns |
| Background work | `std::thread::spawn`, manual channels, drain loops | `tokio::sync::watch` (coalescing), `tokio::task::spawn_blocking` |
| Randomness | `SystemTime` nanos, PID, counters as entropy | `glib::random_int_range`, `rand` crate |
| XDG / platform dirs | manual `env::var("XDG_*")` with fallbacks | `glib::user_data_dir`, `glib::user_cache_dir`, `glib::user_runtime_dir`, `dirs` crate |
| Formatting | hand-rolled size/duration/ETA formatters | `glib::format_size`, `humantime`, `chrono` |
| URL handling | `starts_with("http://")`, string splitting | `url::Url::scheme()`, `url::Url::host_str()` |
| Process spawning | raw `Command` with shell strings | typed `Command` builders, `tokio::process` |
| Test fixtures | shelling out to `touch`, `mkdir`, `date` | `std::fs::File::set_modified`, `std::fs::create_dir_all` |

Read each hit in context. A grep match is a candidate, not a verdict.

### 2. Verify the API actually covers the semantics

Before replacing, confirm **all** of these:

1. **Edge cases:** Does the API handle the cases your code handles? (Example: `gio::File::replace_contents` fsyncs before rename when the dest exists, but *skips* fsync on first write. If you need first-write durability, keep your fsync or add it.)
2. **Error behavior:** Does the API fail the way you need? (Example: reqwest's redirect policy returns an error; if you need the 3xx response object, keep the manual policy.)
3. **Side effects:** Does the API do anything extra? (Example: GLib caches `user_data_dir()` on first call — breaks tests that mutate `XDG_DATA_HOME` at runtime.)
4. **No new dependency:** Prefer APIs already in the dependency tree. Adding a crate for one call site is rarely worth it.

Check the API's source or docs, not just its name. A plausible-sounding API with different semantics is the most common bad replacement.

### 3. Replace

- Delete the hand-rolled code entirely. Don't leave it commented out "just in case."
- If you investigated and **kept** the hand-rolled version, add a comment naming the API you rejected and why. Future auditors will thank you:
  ```rust
  // Not glib::user_data_dir(): GLib caches this on first call, but tests
  // mutate XDG_DATA_HOME at runtime (see video.rs).
  ```
- Keep any surrounding logic the API doesn't cover (e.g., keep your directory `sync_all` after `replace_contents`, since GLib doesn't fsync directories).

### 4. Validate

- Run the existing tests for the affected module. They should pass unchanged — a correct replacement is behavior-preserving.
- If no test covers the replaced code, add one that pins the behavior (not the implementation). Example: for an atomic-write replacement, assert the file content after write, not which temp-file strategy was used.
- Run the linter (`cargo clippy`, `cargo fmt --check`, or the project's equivalent). Replacements often remove now-unused imports.

## Guardrails

- **One replacement per commit** when the changes are in different modules. A bad replacement is easier to revert in isolation.
- **Never replace** in the same commit as a behavior change. The replacement must be behavior-preserving; mixing it with new behavior makes regressions untraceable.
- **Don't add a dependency** for a single call site unless the hand-rolled version is >20 lines or security-sensitive (crypto, auth, parsing untrusted input).
- **Document rejections.** If you find hand-rolled code and deliberately keep it, the comment explaining why is part of the work.

## Evaluation

The replacement is done when:

- [ ] The hand-rolled code is deleted (or kept with a documented reason).
- [ ] Existing tests pass without modification (behavior preserved).
- [ ] `clippy` / `fmt` are clean (no dead imports, no new warnings).
- [ ] The diff is smaller than the original (or the same size with a comment explaining the kept code).
