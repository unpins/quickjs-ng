# quickjs-ng ships two real programs — `qjs` (the interpreter) and `qjsc` (the
# bytecode compiler) — built from the same source tree. We fold them into one
# multicall binary at $out/bin/quickjs-ng (named after the package, as the CI
# gate requires), with `qjs` and `qjsc` as argv[0]-dispatch UNPIN_META aliases.
#
# Both mains pull in the same library objects (quickjs/dtoa/libregexp/
# libunicode/quickjs-libc — cutils is header-only in ng), and `nm` confirms
# qjs.c and qjsc.c each define exactly TWO clashing globals (`main` and `help`).
# So we compile the library objects ONCE, compile the two mains, rename
# `main`/`help` → `qjs_*`/`qjsc_*`, and link everything (shared objects linked a
# single time) with the canonical dispatcher.
#
# Unlike Bellard's quickjs we DON'T bootstrap a host qjsc: quickjs-ng ships the
# REPL bytecode (gen/repl.c) AND the standalone-module loader bytecode
# (gen/standalone.c) pre-generated in the tarball, and both are
# architecture-independent, so we just compile them for every target. qjs.c
# references both as `qjsc_repl[]` / `qjsc_standalone[]`.
#
# Store-path hygiene: quickjs-ng's qjsc carries no CONFIG_CC / CONFIG_PREFIX
# (the Bellard store leak) — it only emits C bytecode arrays and appends
# bytecode to a copy of the qjs binary for "standalone" executables, never
# shelling out to a compiler — so there is nothing to neutralize here.
{ lib }:
{ pkgs, quickjs }:
let
  hostPlat = quickjs.stdenv.hostPlatform;
  isWindows = hostPlat.isWindows or false;
  isDarwin = hostPlat.isDarwin or false;

  # The objects that make up libqjs + the libc bindings. quickjs-ng's
  # qjs_sources is dtoa/libregexp/libunicode/quickjs, plus quickjs-libc
  # (a separate static lib in CMake, QJS_BUILD_LIBC off). cutils is header-only.
  libObjs = "quickjs dtoa libregexp libunicode quickjs-libc";

  # Per-OS link libraries (catalog "ship every feature"):
  #  - Linux:  -lm -ldl -lpthread (loadlib via dlopen, worker threads).
  #  - Darwin: -lm -lpthread       (dlopen + pthread live in libSystem; no -ldl).
  #  - Windows: -lm -lpthread      (winpthreads).
  syslibs =
    if isWindows then "-lm -lpthread"
    else if isDarwin then "-lm -lpthread"
    else "-lm -ldl -lpthread";

  # quickjs-ng's required compile definitions (from CMakeLists): _GNU_SOURCE
  # everywhere, QUICKJS_NG_BUILD to get JS_LIBC_EXTERN's linkage right, and on
  # Windows the lean-headers + Win7 baseline the source assumes.
  defs = "-D_GNU_SOURCE -DQUICKJS_NG_BUILD"
    + lib.optionalString isWindows " -DWIN32_LEAN_AND_MEAN -D_WIN32_WINNT=0x0601";

  multicall = quickjs.overrideAttrs (old: {
    pname = "quickjs-ng-multi";
    outputs = [ "out" ];
    # We drive our own compile; skip the stock CMake configure + its toolchain.
    dontConfigure = true;
    dontUseCmakeConfigure = true;
    nativeBuildInputs = lib.filter
      (x: !(builtins.elem (x.pname or "") [ "cmake" "texinfo" ]))
      (old.nativeBuildInputs or [ ]);
    doInstallCheck = false;

    buildPhase = ''
      runHook preBuild
      set -e
      mkdir -p multicall/obj

      CF="-O2 ${defs}"
      for s in ${libObjs}; do
        $CC $CF -c "$s.c" -o "multicall/obj/$s.o"
      done
      $CC $CF -c qjs.c  -o multicall/obj/qjs.o
      $CC $CF -c qjsc.c -o multicall/obj/qjsc.o
      # The interpreter's embedded bytecode: the REPL and the standalone-module
      # loader. Both ship pre-generated in gen/ and are arch-neutral.
      $CC $CF -c gen/repl.c       -o multicall/obj/repl.o
      $CC $CF -c gen/standalone.c -o multicall/obj/standalone.o

      # Mach-O leads C symbols with '_'; detect once from qjs.o's `main`.
      if $NM --defined-only multicall/obj/qjs.o 2>/dev/null \
           | awk '$3=="_main"{f=1} END{exit !f}'; then up=_; else up=""; fi

      # qjs.o and qjsc.o each define exactly two clashing globals (nm-verified):
      # `main` and `help`. Rename both per interpreter; objcopy rewrites the
      # definition and the in-object references together, so each program's
      # `main`→…_main lands in the dispatcher and its `help` stays self-consistent.
      for sym in main help; do
        printf '%s%s %sqjs_%s\n'  "$up" "$sym" "$up" "$sym" >> multicall/qjs.redef
        printf '%s%s %sqjsc_%s\n' "$up" "$sym" "$up" "$sym" >> multicall/qjsc.redef
      done
      $OBJCOPY --redefine-syms=multicall/qjs.redef  multicall/obj/qjs.o
      $OBJCOPY --redefine-syms=multicall/qjsc.redef multicall/obj/qjsc.o

      # Dispatcher (shared canonical generator). The canonical binary is named
      # after the package (`quickjs-ng`), which is not itself an applet, so
      # defaultApplet=qjs makes a bare `quickjs-ng script.js` run the
      # interpreter; an argv[0] of `qjs` does the same and `qjsc` runs the
      # compiler. The generator sanitizes applet→symbol names, so the package's
      # hyphen is irrelevant (only the `qjs`/`qjsc` applets become symbols).
      printf '%s\n' qjs qjsc > multicall/apps.list
${lib.multicallTableDispatcherC { name = "quickjs-ng"; defaultApplet = "qjs"; }}
      $CC -O2 -c -o multicall/dispatcher.o multicall/dispatcher.c

      # Final link. On mingw, force a fully static exe (-static folds libc,
      # libwinpthread and libgcc in — otherwise -lpthread pulls libwinpthread-1.dll
      # as a runtime dependency, failing both wine and the no-companion-DLL gate).
      # gc-sections on native only (on windows `pkgs` is the x86_64-linux root, so
      # its lld flags would be wrong here). Library objects linked once; both
      # *_main present.
      $CC multicall/obj/*.o multicall/dispatcher.o \
        ${if isWindows then "-static -static-libgcc" else (lib.gcSectionsFlag pkgs)} \
        ${syslibs} \
        -o multicall/quickjs-ng
      [ -f multicall/quickjs-ng ] || mv multicall/quickjs-ng.exe multicall/quickjs-ng
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin"
      install -m755 multicall/quickjs-ng "$out/bin/quickjs-ng"
      ln -s quickjs-ng "$out/bin/qjs"
      ln -s quickjs-ng "$out/bin/qjsc"
      runHook postInstall
    '';

    # nixpkgs' postBuild/postInstall build texi docs + a lib/include tree we
    # don't ship.
    postBuild = "";
    postInstall = "";
  });

  aliased = lib.withAliases pkgs
    {
      primary = "quickjs-ng";
      aliasesFromSymlinksIn = "bin";
    }
    multicall;
in
if isWindows
then aliased.overrideAttrs (o: {
  postFixup = (o.postFixup or "") + ''
    [ -f "$out/bin/quickjs-ng" ] && mv "$out/bin/quickjs-ng" "$out/bin/quickjs-ng.exe"
  '';
})
else aliased
