# Changelog

## [Unreleased]

## [0.15.1-1] - 2026-09-26

Initial release — `quickjs-ng` 0.15.1 as a single self-contained binary, built
natively for Linux, macOS, and Windows.

### Added

- Builds for Linux (x86_64, aarch64, armv7l, i686, ppc64le, riscv64), macOS
  (x86_64, aarch64), and Windows.
- The `qjs` interpreter and the `qjsc` bytecode compiler in the one binary —
  `unpin install quickjs-ng` creates both commands alongside `quickjs-ng`.
- The interactive REPL is built in; there is no companion script file.
