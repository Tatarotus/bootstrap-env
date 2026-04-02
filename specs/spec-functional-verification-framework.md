# Technical Specification: Functional Verification Framework

## Document Status

Draft

## Date

2026-04-02

## Summary

Implement a Bash-native functional verification framework inside [setup.sh](/home/sam/PARA/1.Projects/Code/bootstrap-new/setup.sh) to validate that each installed module is not only present, but operational. This specification follows ADR 0001 and stays within the current stack: Bash, GNU Stow, distro package managers, and existing script helpers.

## Background

The current bootstrap tool already supports:

- modular installation through `module_<name>` functions,
- OS and package-manager abstraction via `detect_os()` and `setup_package_manager()`,
- state persistence through `STATE_FILE`,
- execution wrapping via `execute()`,
- drift visibility through `status()`,
- user-aware behavior through `REAL_USER` and `REAL_HOME`.

These patterns are implemented in [setup.sh](/home/sam/PARA/1.Projects/Code/bootstrap-new/setup.sh) and documented in [README.md](/home/sam/PARA/1.Projects/Code/bootstrap-new/README.md), [GOAL.md](/home/sam/PARA/1.Projects/Code/bootstrap-new/GOAL.md), [TODO.md](/home/sam/PARA/1.Projects/Code/bootstrap-new/TODO.md), and [MEMORY.md](/home/sam/PARA/1.Projects/Code/bootstrap-new/MEMORY.md).

The gap is post-install validation. Today the script can install modules and report versions, but it cannot systematically prove the environment works.

## Goals

- Add a first-class `--verify` workflow to the bootstrap script.
- Provide module-level smoke tests for all modules currently in `ALL_MODULES`.
- Reuse existing Bash patterns and avoid introducing a new runtime.
- Produce clear pass/fail output and a non-zero exit code on failure.
- Keep verification safe to run repeatedly on a configured workstation or a fresh test container.

## Non-Goals

- Replacing full integration testing across all distributions.
- Adding a YAML manifest in this feature.
- Reinstalling or auto-healing failed modules during verification.
- Launching interactive UIs or requiring a graphical session.
- Persisting detailed historical verification results.

## Feature Overview

The script will gain a verification mode that:

1. Parses `--verify` similarly to the existing `--install` flow.
2. Selects either all modules or a user-provided comma-separated subset.
3. Runs one `verify_<module>` function per requested module.
4. Prints a summary showing pass/fail per module.
5. Exits `0` when all requested verifiers pass and non-zero otherwise.

Example commands:

```bash
./setup.sh --verify
./setup.sh --verify nvim,tmux,zsh
./setup.sh --verify --verbose
```

## Functional Requirements

### CLI and control flow

FR-1. The script shall support `--verify` as a top-level command.

FR-2. The script shall support `--verify <comma-separated-modules>` using the same comma-splitting pattern already used by `--install`.

FR-3. When `--verify` is provided without a module list, the script shall verify all modules in `ALL_MODULES`.

FR-4. The script shall reject unknown module names with a clear error.

FR-5. Verification mode shall not perform package installation, cloning, pulling, shell switching, or stowing.

FR-6. Verification mode shall return exit code `0` when all requested checks pass.

FR-7. Verification mode shall return a non-zero exit code when one or more checks fail.

FR-8. Verification mode shall print a final summary with passed and failed module counts.

### Shared verification behavior

FR-9. Each verifier shall use existing log helpers such as `info`, `warn`, and `success`.

FR-10. Each verifier shall be safe to run repeatedly and should avoid persistent mutations.

FR-11. Verifiers may use temporary files or temporary directories under `/tmp` when required for smoke checks, and must clean them up.

FR-12. Shared verifier dispatch shall follow the existing module naming pattern and map one module name to one verifier function.

FR-13. Verification mode shall run as the resolved `REAL_USER` context where user-owned files or user-specific configuration must be checked.

### Module-specific verification requirements

FR-14. `verify_nvim` shall confirm `nvim` exists, is executable, and returns a parseable version meeting `MIN_VERSIONS[nvim]`.

FR-15. `verify_nvim` shall confirm the Neovim dotfiles module exists under `$DOTFILES_DIR/nvim` when dotfiles are expected.

FR-16. `verify_zsh` shall confirm `zsh` exists and that the login shell for `REAL_USER` matches the discovered `zsh` path or report a warning/failure according to defined policy.

FR-17. `verify_starship` shall confirm `starship` exists and meets `MIN_VERSIONS[starship]`.

FR-18. `verify_alacritty` shall confirm `alacritty` exists and responds to a non-interactive version/help command.

FR-19. `verify_tmux` shall confirm `tmux` exists, meets `MIN_VERSIONS[tmux]`, and can create and destroy a detached test session.

FR-20. `verify_yazi` shall confirm `yazi` exists and responds to a non-interactive version/help command.

FR-21. `verify_gitconfig` shall confirm the expected global Git settings currently enforced by `module_gitconfig`:
- `init.defaultBranch=main`
- `pull.rebase=true`
- `core.editor=nvim`

FR-22. `verify_node` shall confirm `node` exists and returns a version string.

FR-23. `verify_aliases` shall confirm [setup.sh](/home/sam/PARA/1.Projects/Code/bootstrap-new/setup.sh) expected aliases or initialization lines are present in `$REAL_HOME/.zshrc`, including `zoxide init zsh`.

FR-24. `verify_fonts` shall confirm JetBrainsMono Nerd Font files are present under `$REAL_HOME/.local/share/fonts` and that `fc-list` can resolve JetBrainsMono entries when `fc-list` is available.

FR-25. For modules that currently call `stow_module`, verification shall check that the corresponding dotfiles module directory exists under `$DOTFILES_DIR/<module>` and report when the repo is missing or incomplete.

## Non-Functional Requirements

NFR-1. The implementation shall remain Bash-only and fit the current repository stack.

NFR-2. The feature shall preserve current install behavior and must not regress `--all`, `--install`, `--status`, `--list`, `--dry-run`, or `--verbose`.

NFR-3. The implementation shall follow existing naming conventions and coding style in [setup.sh](/home/sam/PARA/1.Projects/Code/bootstrap-new/setup.sh).

NFR-4. Verification output shall be human-readable and concise enough for terminal use on local machines and CI logs.

NFR-5. Verification mode should finish quickly on already-configured systems; expensive checks such as rebuilds or network access are prohibited.

NFR-6. The feature shall work on the currently documented supported distribution families: Debian/Ubuntu, Arch/Manjaro, and Fedora.

NFR-7. Temporary artifacts created during verification shall be cleaned up even on failure when practical.

NFR-8. The implementation should be structured so a later manifest feature can define required modules or expected versions without rewriting verifier architecture.

## Design Details

### New globals

Add:

- `VERIFY_MODE=0`
- `MODULES_TO_VERIFY=()`
- summary counters such as `VERIFY_PASS_COUNT` and `VERIFY_FAIL_COUNT`

These should mirror current global state patterns like `MODULES_TO_INSTALL`.

### Argument parsing changes

Extend `parse_args()` with:

- `--verify` with no following module list meaning verify all modules,
- `--verify <list>` meaning verify the supplied module subset.

Recommended behavior:

- If the next token after `--verify` is absent or starts with `--`, set `MODULES_TO_VERIFY=("${ALL_MODULES[@]}")`.
- Otherwise parse the comma-separated module list into `MODULES_TO_VERIFY`.

This keeps CLI behavior close to the existing install parser while avoiding ambiguous invocation.

### Verifier helpers

Add shared helper functions to minimize duplication:

- `verify_tool_exists <cmd>`
- `verify_tool_min_version <cmd> <required_version>`
- `verify_dotfiles_module_present <module>`
- `verify_git_config <key> <expected>`
- `record_verify_result <module> <pass|fail> <message>`

These helpers should reuse existing `get_tool_version()` and `version_ge()` where possible.

### Verifier dispatch

Add a dispatch function such as `run_verifier()` or `verify_modules()` with a case statement parallel to the current module install dispatch in `main()`.

This is preferred over reflection-based invocation because the current script already uses explicit case dispatch and it is easier to keep readable in Bash.

### Summary and exit behavior

After all requested verifiers run:

- print one summary block,
- include pass/fail counts,
- exit `1` if any verifier failed, otherwise `0`.

### Interaction with dry-run

Recommended policy:

- `--dry-run` has no effect in verification mode and should emit a warning explaining that verification is already non-mutating.

This avoids inventing a fake "simulation" for checks that are already intended to be read-only.

## Existing Code and Pattern References

The implementation should explicitly follow these existing patterns in [setup.sh](/home/sam/PARA/1.Projects/Code/bootstrap-new/setup.sh):

- `ALL_MODULES` as the source for valid module names.
- `MIN_VERSIONS` for version-based verification.
- `module_<name>` naming style as the template for `verify_<name>`.
- `status()` as the model for per-module reporting.
- `parse_args()` as the integration point for new CLI flags.
- `REAL_USER` and `REAL_HOME` for user-scoped checks.
- `STATE_FILE` and `LOG_FILE` for consistency in output and future extensibility.

## Acceptance Tests

### CLI behavior

AT-1. Running `./setup.sh --verify` on a configured system verifies every module in `ALL_MODULES` and exits `0` when all pass.

AT-2. Running `./setup.sh --verify nvim,tmux` verifies only `nvim` and `tmux`.

AT-3. Running `./setup.sh --verify doesnotexist` exits non-zero with a clear unknown-module error.

AT-4. Running `./setup.sh --verify --verbose` emits detailed verifier progress without changing verification results.

AT-5. Running `./setup.sh --verify --dry-run` prints a warning that dry-run is ignored for verification and still performs real checks.

### Module verification behavior

AT-6. If `nvim` is missing, `verify_nvim` fails and the script exits non-zero.

AT-7. If `tmux` exists but cannot create a detached session, `verify_tmux` fails.

AT-8. If global Git config differs from the values enforced by `module_gitconfig`, `verify_gitconfig` fails and identifies the mismatched key.

AT-9. If `$REAL_HOME/.zshrc` is missing expected alias lines or missing `zoxide init zsh`, `verify_aliases` fails.

AT-10. If JetBrainsMono Nerd Font files are absent from `$REAL_HOME/.local/share/fonts`, `verify_fonts` fails.

AT-11. If the dotfiles repo is missing a stowed module directory required by a verified module, that module verification fails with a dotfiles-specific message.

### Regression coverage

AT-12. Existing commands `./setup.sh --all --dry-run`, `./setup.sh --status`, and `./setup.sh --list` still behave as before after the feature is added.

AT-13. A full install followed by `./setup.sh --verify` passes in the currently supported distro test matrix used by the project: Ubuntu/Debian, Arch, and Fedora containers or equivalent test environments.

## Technical Tasks

1. Update `usage()` to document verification commands and behavior.
2. Add new globals for verification mode, selected modules, and result counters.
3. Extend `parse_args()` to support `--verify` with optional module list handling.
4. Add a module-name validation helper reusable by both install and verify flows if practical.
5. Add shared verifier helpers for tool existence, version checks, dotfiles presence, git config checks, and result recording.
6. Implement `verify_nvim`.
7. Implement `verify_zsh`.
8. Implement `verify_starship`.
9. Implement `verify_alacritty`.
10. Implement `verify_tmux`.
11. Implement `verify_yazi`.
12. Implement `verify_gitconfig`.
13. Implement `verify_node`.
14. Implement `verify_aliases`.
15. Implement `verify_fonts`.
16. Add a verifier dispatcher aligned with the current install dispatcher.
17. Integrate verification flow into `main()` without changing install semantics.
18. Add summary output and correct exit status handling.
19. Run regression checks for `--status`, `--list`, and `--all --dry-run`.
20. Run end-to-end verification checks in at least one local environment and, ideally, the documented distro matrix.
21. Update project docs later if the implementation changes user-visible CLI behavior beyond this spec.

## Risks

- Some tools expose inconsistent `--version` formats across distributions.
- User-local shell state may differ when the script was run manually outside the bootstrap flow.
- `alacritty` verification may require a conservative smoke test in headless environments.
- Font verification via `fc-list` may vary slightly by environment, so file presence should remain the authoritative baseline.

## Open Questions

1. Should a mismatched default shell in `verify_zsh` be a hard failure or a warning when `zsh` itself is installed correctly?
2. Should missing dotfiles directories be treated as hard failures for every stowed module, or only when the related binary/config check also depends on those files?
3. Should verification eventually write a summary artifact to `STATE_DIR`, or remain exit-code and log based only?

## Suggested Next Step After Approval

Implement the verifier framework directly in [setup.sh](/home/sam/PARA/1.Projects/Code/bootstrap-new/setup.sh), starting with shared helpers plus `verify_nvim`, `verify_tmux`, and `verify_gitconfig`, then expand to the remaining modules and run the existing dry-run/status regressions.
