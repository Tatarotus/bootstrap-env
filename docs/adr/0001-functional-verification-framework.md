# ADR 0001: Add a Bash-Native Functional Verification Framework

## Status

Proposed

## Date

2026-04-02

## Context

This repository currently centers on a single Bash entrypoint, [setup.sh](/home/sam/PARA/1.Projects/Code/bootstrap-new/setup.sh), that bootstraps a Linux development environment across multiple distributions. The existing project documentation establishes a clear direction:

- [README.md](/home/sam/PARA/1.Projects/Code/bootstrap-new/README.md) describes a modular, architecture-aware, cross-distribution bootstrap script with dry-run support.
- [GOAL.md](/home/sam/PARA/1.Projects/Code/bootstrap-new/GOAL.md) defines the project as a deterministic, idempotent, extensible "environment compiler" and explicitly calls out a testing strategy for fresh systems, reruns, partial installs, and dry runs.
- [TODO.md](/home/sam/PARA/1.Projects/Code/bootstrap-new/TODO.md) shows the core refactor, module work, dependency layer, state tracking, logging, and status reporting as completed.
- [MEMORY.md](/home/sam/PARA/1.Projects/Code/bootstrap-new/MEMORY.md) identifies two remaining roadmap items: functional verifiers and a YAML manifest.

The current implementation already contains the right primitives for a first-class verification feature:

- Modular install functions such as `module_nvim`, `module_tmux`, and `module_fonts` in [setup.sh](/home/sam/PARA/1.Projects/Code/bootstrap-new/setup.sh).
- State tracking through `set_state` and `STATE_FILE`.
- Drift detection via `status()`.
- Shared execution semantics through `execute()`.
- Logging through `LOG_FILE` and the `ERR` trap.

What is still missing is a way to confirm that "installed" also means "usable". Today the script can report version/state drift, but it does not perform module-level smoke checks such as:

- whether `nvim` launches and reports a version,
- whether `tmux` can create a detached session,
- whether `yazi` is executable,
- whether required dotfile-managed files are actually present after stow,
- whether non-binary modules such as `aliases`, `gitconfig`, and `fonts` are functionally active.

Because this project is still a single-script Bash tool, introducing a second runtime or test framework would add complexity before the repository has enough scale to justify it.

## Decision

We will add a Bash-native functional verification framework to [setup.sh](/home/sam/PARA/1.Projects/Code/bootstrap-new/setup.sh).

The framework will:

1. Introduce a dedicated verification command surface, initially `--verify` and `--verify <module list>`.
2. Implement one verifier function per supported module using the existing module naming style, for example `verify_nvim`, `verify_tmux`, and `verify_fonts`.
3. Reuse current script primitives wherever possible:
   - `REAL_USER` and `REAL_HOME` for user-scoped checks,
   - `info`, `warn`, `error`, and `success` for output,
   - `STATE_FILE` and `LOG_FILE` for continuity with current operations,
   - `detect_os` and package-manager setup only when needed by shared initialization.
4. Keep verification read-mostly and side-effect-minimizing. Verifiers may create safe ephemeral artifacts under `/tmp` when necessary, but must not mutate user configuration or reinstall packages.
5. Return non-zero exit status if any requested verifier fails, so the feature is suitable for local validation and CI/container smoke tests.
6. Integrate verification results with the existing module list and status concepts rather than creating a separate subsystem or language runtime.

## Decision Drivers

- Preserve the current tech stack: Bash is the existing control plane and no change is completely necessary here.
- Keep the feature aligned with the repository's current single-file operational model.
- Improve confidence in idempotency and install quality beyond version checks alone.
- Support the documented testing matrix in [GOAL.md](/home/sam/PARA/1.Projects/Code/bootstrap-new/GOAL.md).
- Reuse current naming and command patterns instead of introducing a parallel architecture too early.

## Considered Options

### Option A: Add Bash-native verifiers inside `setup.sh`

Pros:

- Fits the existing architecture directly.
- Reuses current helpers, logging, and environment-detection logic.
- Lowest implementation and maintenance overhead.
- Easiest to run on fresh systems and inside distro containers.

Cons:

- Keeps `setup.sh` growing in size.
- Bash is less ergonomic than a richer language for structured test output.

### Option B: Add an external test harness in Python

Pros:

- Better data structures and easier report generation.
- More maintainable if the verification matrix becomes very complex.

Cons:

- Introduces a second runtime and dependency model.
- Increases bootstrap complexity on exactly the systems this script is meant to simplify.
- Not justified by the current repository size.

### Option C: Use a shell test framework such as Bats

Pros:

- Better test ergonomics than raw Bash.
- Good fit for shell-driven behavior.

Cons:

- Adds another tool dependency and execution model.
- Still requires implementation of real smoke checks.
- Does not replace the need for an end-user-facing verification command in `setup.sh`.

## Outcome

Option A is selected.

Verification will be implemented as a first-class Bash capability inside the existing script, with an internal structure that can later be extracted if the project grows.

## Scope

Initial verification coverage should include all currently supported modules listed in `ALL_MODULES`:

- `nvim`
- `zsh`
- `starship`
- `alacritty`
- `tmux`
- `yazi`
- `gitconfig`
- `node`
- `aliases`
- `fonts`

The framework should also verify shared prerequisites where relevant, such as dotfiles presence for modules that rely on `stow_module`.

## Consequences

### Positive

- The project gains a missing confidence layer between installation and actual usability.
- Future regressions become easier to detect in local runs and container validation.
- The feature reinforces the project's "deterministic" and "idempotent" goals with executable checks.
- Verification output can become the basis for future CI automation without introducing a new stack immediately.

### Negative

- `setup.sh` becomes larger and needs careful organization to stay maintainable.
- Some verifiers will require distro-aware exceptions because behavior differs by package source and runtime environment.
- A few checks, especially for terminal applications, may need pragmatic smoke tests rather than deep end-to-end validation.

## Risks and Mitigations

- Risk: Verifiers accidentally mutate the system.
  Mitigation: Define verifiers as read-only except for temporary artifacts in `/tmp`, and ban package installs inside verifier functions.

- Risk: False failures on headless or minimal systems.
  Mitigation: Favor non-interactive smoke checks such as `--version`, detached sessions, or file existence rather than UI launches.

- Risk: Drift between module install logic and verifier expectations.
  Mitigation: Keep verifier naming and module mapping parallel to install functions in the same script.

## Implementation Notes

- Follow current naming conventions already used in [setup.sh](/home/sam/PARA/1.Projects/Code/bootstrap-new/setup.sh): `module_<name>`, `status()`, `parse_args()`, `main()`.
- Extend `usage()` to advertise verification commands.
- Keep verification summary output consistent with the current colored log helpers.
- Store no new persistent data in the first iteration unless it becomes necessary; current logs plus exit codes are sufficient.

## Deferred Decisions

- Whether verification results should later be persisted in `STATE_FILE`.
- Whether verification output should support JSON or machine-readable formats.
- Whether the later YAML manifest feature should drive verifier expectations such as required modules or versions.

## References

- [README.md](/home/sam/PARA/1.Projects/Code/bootstrap-new/README.md)
- [GOAL.md](/home/sam/PARA/1.Projects/Code/bootstrap-new/GOAL.md)
- [TODO.md](/home/sam/PARA/1.Projects/Code/bootstrap-new/TODO.md)
- [MEMORY.md](/home/sam/PARA/1.Projects/Code/bootstrap-new/MEMORY.md)
- [setup.sh](/home/sam/PARA/1.Projects/Code/bootstrap-new/setup.sh)
