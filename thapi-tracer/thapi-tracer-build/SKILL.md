---
name: thapi-tracer-build
description: Configure, build, and install THAPI (Tracing Heterogeneous APIs) from a clone already prepared by thapi-tracer-environment-config — run configure with an in-tree prefix, make install, and verify the resulting iprof binary and backend libraries are sound. Use after the environment-config skill reports success, or when THAPI's build/install fails or produces a broken iprof.
title: "THAPI Tracer — Build"
category: software
systems:
  - aurora
tags:
  - thapi
  - tracing
  - build
  - autotools
last_verified: "2026-09"
alcf_docs_url: "https://github.com/argonne-lcf/THAPI"
---

# THAPI tracer — build

## Purpose

Configure, build, and install THAPI from the clone `thapi-tracer-environment-config`
prepared, producing a working `iprof` and its backend tracer libraries.
Running a workload under `iprof` on a compute node is the next skill,
`thapi-tracer-run`.

## Prerequisites

- `thapi-tracer-environment-config` has already run in **this same shell**
  and reported success — the module environment and the project-local venv
  do not persist across shells, so re-source them first if this is a new
  shell.
- A THAPI clone with `autogen.sh` already run (`configure` present at the
  clone root).

## Key Facts

- Install prefix must live **inside** the clone (e.g. `THAPI/build/ici`).
- "Build the tracer" means running the full Autotools build, not compiling
  one source file.
- `iprof --help`/`--version` need no GPU, no MPI job allocation, no compute
  node.

## Procedure

1. Confirm the environment is still sourced (same shell as
   `thapi-tracer-environment-config`, or re-run its steps 2-3 in a new one).

2. Configure with an in-tree prefix, using the project's own convention:
   ```bash
   cd THAPI
   mkdir -p build && cd build
   ../configure --prefix `pwd`/ici
   ```
   Add `--disable-sync-daemon-mpi` explicitly if `mpich` was **not** loaded,
   to avoid a spurious warning about missing MPI Sessions support (harmless
   either way, but cleaner output).

3. Build and install, **backgrounded** since it exceeds a short timeout:
   ```bash
   make -j"$(nproc)" install > ../../build.log 2>&1 &
   ```
   Monitor `build.log` for completion rather than blocking on it. Expect
   several minutes; the `ze` backend is the slowest.

4. Verify the install (the prefix is `build/ici` under the clone, per step 2):
   ```bash
   ls ici/bin/iprof                # present, executable
   ici/bin/iprof --version
   ici/bin/iprof --help            # backend-agnostic smoke test
   ```
   Both commands should print cleanly with exit code 0 and no `ruby ...
   too old` warning (that warning means the module Ruby isn't on PATH in
   this shell — re-source the environment-config skill's steps).

5. Spot-check a couple of installed backend libraries resolve their shared
   libs (no stale `rpath` from a copied/moved tree):
   ```bash
   ldd ici/lib/thapi/ze/libZEInterval.so | grep -i "not found"
   ```
   No output is a pass; any `not found` line means a bad `rpath` or a
   module that wasn't loaded at build time.

6. If MPI support was built (`mpich` loaded in step 2), a **login-node**
   `iprof --backends mpi -- <binary>` run will still fail — MPICH here
   needs a PBS job allocation to initialize. That's expected; the real MPI
   smoke test belongs to `thapi-tracer-run` on an allocated node, using
   `integration_tests/mpi_helloworld.c` from the THAPI repo as the
   workload.

7. Report back and hand off to `thapi-tracer-run`.

## Common Pitfalls

- Prefix outside the clone → libtool `.la` files bake in the absolute path; breaks if the tree moves or is copied.
- Blocking `make -j install` with a short timeout → it takes minutes; run it backgrounded.
- Running in a new shell without re-sourcing the environment → `configure`/`make` silently fall back to system Ruby/compiler.

## See Also

- `thapi-tracer-environment-config` — prepares the clone and shell this
  skill builds from.
- `thapi-tracer-run` — reserves a compute node and runs `iprof` against a
  real workload.
- https://github.com/argonne-lcf/THAPI — canonical THAPI repository.
