# quickjs-ng

[quickjs-ng](https://github.com/quickjs-ng/quickjs) — the community-maintained
fork of Fabrice Bellard's QuickJS JavaScript engine. A single self-contained
binary (`qjs` + `qjsc`), built natively for Linux, macOS, and Windows.

[![CI](https://github.com/unpins/quickjs-ng/actions/workflows/quickjs-ng.yml/badge.svg)](https://github.com/unpins/quickjs-ng/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) catalog; install it with [`unpin`](https://github.com/unpins/unpin): `unpin install quickjs-ng`.

> Looking for Fabrice Bellard's original engine? See [`quickjs`](https://github.com/unpins/quickjs).
> Both packages provide `qjs`/`qjsc`; quickjs-ng tracks the actively-developed
> fork (newer ECMAScript coverage, ongoing fixes).

## Usage

Run the interpreter with [unpin](https://github.com/unpins/unpin):

```bash
unpin quickjs-ng --unpin-program=qjs script.js              # run a script
unpin quickjs-ng --unpin-program=qjs -e 'console.log(1+1)'  # run a one-liner
unpin quickjs-ng --unpin-program=qjs -i                     # interactive REPL
```

To install it onto your PATH:

```bash
unpin install quickjs-ng
```

This installs the `quickjs-ng` command plus the `qjs` (interpreter) and `qjsc`
(bytecode compiler) aliases:

```bash
qjsc -e -o out.c script.js       # compile to a C bytecode array
```

## Build locally

```bash
nix build github:unpins/quickjs-ng
./result/bin/quickjs-ng --unpin-program=qjs -e 'console.log("hi")'
```

Or run directly:

```bash
nix run github:unpins/quickjs-ng -- --unpin-program=qjs -e 'console.log("hi")'
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/quickjs-ng/releases) page has standalone binaries for manual download.

## Build notes

- **Upstream source, not nixpkgs.** We build from the quickjs-ng upstream tag
  `v0.15.1`. nixpkgs pins the older `v0.14.0`; tracking upstream ships the
  newest engine.
- **Single multicall binary.** `qjs` (interpreter) and `qjsc` (bytecode
  compiler) are folded into one binary at `$out/bin/quickjs-ng`, with `qjs` and
  `qjsc` as `argv[0]`-dispatch aliases. The binary is named after the package
  (the catalog convention / CI portability gate), and is not a program of its
  own, so a bare `quickjs-ng` lists the two and exits 1;
  `quickjs-ng --unpin-program=qjsc …` reaches the compiler. The fold is done by
  the unpin-llvm engine (per-program
  bitcode module) on every platform, Windows included.
- **REPL + standalone loader embedded as bytecode.** quickjs-ng ships the
  interactive REPL (`repl.js`) and the standalone-module loader (`standalone.js`)
  pre-compiled to QuickJS bytecode (`gen/repl.c`, `gen/standalone.c`) right in
  the tarball, and that bytecode is architecture-independent — so there is no
  host-`qjsc` bootstrap and no external `.js` file to ship.
- **No store-path leak.** quickjs-ng's `qjsc` emits C bytecode arrays (and can
  append bytecode to a copy of the binary for "standalone" executables); it
  never bakes in or shells out to a C compiler, so unlike Bellard's QuickJS
  there is no `CONFIG_CC`/`CONFIG_PREFIX` path to neutralize.
- **No VFS / embedded data needed.** quickjs-ng's standard library is C. `import`
  of external *JS* modules still works from the filesystem; loading external
  *native* (`.so`) modules does not, as expected for one static binary.
- **Static linking, per target.** Linux/macOS link fully static (musl) /
  libSystem-only; on Windows `-static` folds libc, libwinpthread and libgcc in,
  so the `.exe` imports only system DLLs.
- **Tests.** quickjs-ng's suite is the ECMAScript `test262` conformance corpus —
  a large external data set run by a separate harness, not a quick in-tree `make
  check` — so it isn't wired into the build. The release smoke test evaluates a
  computed expression to confirm the interpreter runs JS.
