---
name: thapi-tracer-environment-config
description: Prepare an Aurora shell to build THAPI (Tracing Heterogeneous APIs) with only the modules the build actually needs — ask the user for the THAPI repo URL/branch, clone it fresh, load the build-time module set, create a project-local venv with h2yaml, and run autogen.sh. Use before building THAPI, or when its configure script fails on a missing tool or Ruby gem.
title: "THAPI Tracer — Environment Config"
category: software
systems:
  - aurora
tags:
  - thapi
  - tracing
  - build
  - modules
last_verified: "2026-09"
alcf_docs_url: "https://github.com/argonne-lcf/THAPI"
---

# THAPI tracer — environment config

## Purpose

Get a THAPI source tree cloned and an Aurora shell ready for `configure` to
succeed, using the minimal module set the build actually requires. Running
`configure`/`make` is the next skill, `thapi-tracer-build`.

## Prerequisites

- Aurora login-node shell (building THAPI needs no GPU/compute node).
- `git`.
- The **THAPI repository URL** (and branch, if not the default) — ask the
  user for this every time; never hardcode a URL. Never reuse an existing
  local clone — always start from a fresh `git clone` so the tree is
  reproducible and free of stale generated files.

## Key Facts

| Requirement | Why |
|---|---|
| `oneapi/release/2025.3.1` | Only source of a C++17-capable compiler (`icx`/`icpx`) on PATH. It does not set `CC`/`CXX` itself — `AC_PROG_CXX`/`AC_PROG_CC` just pick up whichever compiler is first on PATH. |
| `ruby-cast-to-yaml`, `ruby-nokogiri`, `ruby-metababel` | `configure` checks for the `nokogiri` and `metababel` Ruby extensions directly; metababel drives the tracepoint codegen. |
| `ruby-babeltrace2`, `ruby-ffi`, `ruby-narray-ffi` | Not analysis-only despite appearances — `configure` fails at `checking ruby extension: babeltrace2... no` without these loaded. |
| `gmake/4.4.1`, `protobuf/3.28.2` | `make` and `protoc`, both checked by `configure`. |
| `babeltrace2/2.1.2-archive`, `lttng-tools/2.14.0-archive` | Provide `babeltrace2`, `lttng-gen-tp`, and the `pkg-config` files for `libbabeltrace2`/`lttng-ust` that `configure` checks via `PKG_CHECK_MODULES`. |
| `python/3.12.12` (bare) | h2yaml needs Python >= 3.11 (uses pattern matching); system `/usr/bin/python3` is 3.6. Do **not** load `frameworks` for this — it's ML tooling THAPI has no use for; bare `python` is enough. |
| `mpich/opt/5.0.0.aurora_test.3c70a61` — opt-in | Only needed for the `mpi` backend (`AX_MPI`/`AX_MPI_SESSION` checks). THAPI builds fine without it. Load only when the user asks for MPI tracing. |

## Procedure

1. Ask for the repo URL/branch if not already given, then clone fresh:
   ```bash
   git clone --branch <branch> <repo-url> THAPI   # omit --branch for default
   ```

2. Load the build-time modules, in this order:
   ```bash
   module load oneapi/release/2025.3.1
   module load ruby-cast-to-yaml/0.1.1-tepbhny ruby-nokogiri/1.16.7-rnvmyfk \
               ruby-metababel/1.1.4-jlmde4f ruby-babeltrace2/0.1.5-htyldlz \
               ruby-ffi/1.17.2-obrr273 ruby-narray-ffi/1.4.4-fzwgodb
   module load gmake/4.4.1 protobuf/3.28.2
   module load babeltrace2/2.1.2-archive lttng-tools/2.14.0-archive
   module load python/3.12.12
   # Only if the user wants MPI backend tracing:
   module load mpich/opt/5.0.0.aurora_test.3c70a61
   ```

3. Create the project-local venv and install h2yaml, in the same shell,
   next to the clone:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   command -v h2yaml >/dev/null 2>&1 || \
     pip install "git+https://github.com/TApplencourt/h2yaml.git"
   h2yaml --version      # must be >= 0.4.3
   ```

4. Run `autogen.sh` inside the clone, same shell:
   ```bash
   cd THAPI && ./autogen.sh
   ```
   Should end in `autoreconf: Leaving directory '.'` with no errors.

5. Confirm the toolchain, same shell:
   ```bash
   ruby --version    # >= 2.7.0 — must resolve to the ruby-* module tree
   command -v erb metababel lttng-gen-tp babeltrace2 patch protoc
   pkg-config --exists 'libffi >= 3.2' && echo libffi OK
   pkg-config --exists 'babeltrace2 >= 2.0' && echo babeltrace2-pc OK
   pkg-config --exists 'lttng-ust >= 2.10' && echo lttng-ust-pc OK
   pkg-config --exists 'protobuf >= 3.0' && echo protobuf-pc OK
   ```

6. Report back what was cloned (path, URL, branch), which modules loaded,
   the `autogen.sh` result, and the toolchain check — then hand off to
   `thapi-tracer-build`.

## Common Pitfalls

- Module reports "Unable to find" via `module avail`/`spider` → it's hidden;
  use `module --show_hidden -t avail <name>` (Lmod prints this to
  **stderr**, so redirect `2>&1` if capturing it).
- A tool resolves to `/usr/bin/...` instead of the module tree (e.g.
  `ruby --version` shows `2.5.x`) → a module load was skipped or failed
  silently — re-check step 2.
- Loading `frameworks` "for a newer Python" → unnecessary and pulls in
  unrelated ML/SYCL tooling; bare `python/3.12.12` is enough for h2yaml.
- `mpich` loaded by default → load it only when MPI backend tracing is
  actually wanted.
- h2yaml install/first run fails on missing `libclang` → load a `clang`/
  `llvm` module and retry (not needed on Aurora as tested).
- Module env does not propagate across shells or to a compute node reached
  over `ssh` — re-source in every new shell.

## See Also

- `thapi-tracer-build` — configure, build, and verify THAPI from the clone
  this skill prepares.
- https://github.com/argonne-lcf/THAPI — canonical THAPI repository.
