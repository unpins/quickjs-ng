{
  description = "quickjs-ng (qjs + qjsc) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # qjs (the interpreter, with the REPL bytecode embedded) + qjsc (the bytecode
  # compiler) folded into one multicall binary at $out/bin/quickjs-ng (named
  # after the package, as the action-build gate requires), with `qjs` and `qjsc`
  # as argv[0]-dispatch UNPIN_META aliases. See ./multicall.nix.
  #
  # quickjs-ng is the community-maintained fork of Fabrice Bellard's QuickJS
  # (https://github.com/quickjs-ng/quickjs). nixpkgs pins v0.14.0; we take the
  # current upstream tag v0.15.1 straight from git so we ship the newest engine
  # (both this and Bellard's `quickjs` were last tagged 2026-06-04).
  #
  # Compared to Bellard's `quickjs`, quickjs-ng is friendlier for a single
  # static binary: the REPL *and* the standalone-loader bytecode ship
  # pre-generated in gen/ (no host-qjsc bootstrap needed), and qjsc carries no
  # baked CONFIG_CC / CONFIG_PREFIX store leak (it only emits C arrays / appends
  # bytecode, never shelling out to a compiler). It needs none of the VFS
  # machinery perl (@INC) / python (stdlib zip) require — the stdlib is C.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;

      # quickjs-ng upstream tag v0.15.1 (newer than nixpkgs' v0.14.0). Tag
      # tarballs are content-stable, so a plain fetchTarball is reproducible.
      ngSrc = tag: hash: builtins.fetchTarball {
        url = "https://github.com/quickjs-ng/quickjs/archive/refs/tags/${tag}.tar.gz";
        sha256 = hash;
      };

      # Repoint pkgsStatic.quickjs-ng at the v0.15.1 tag. We only borrow the
      # musl-static stdenv + src here; multicall.nix replaces the (CMake) build
      # with a direct compile of the .c files.
      retarget = drv: drv.overrideAttrs (_old: {
        version = "0.15.1";
        src = ngSrc "v0.15.1" "10llzyjmlmm85jc6g4wjnigsqj2mjvk4fxvg1jzfwf3bs0b897bp";
      });
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "quickjs-ng";
      pkgsAttr = "quickjs-ng";
      # quickjs-ng ships no man pages (docs are texi → info/html only), so there
      # is nothing to embed; disabling embedMan also avoids the windows
      # man-graft referencing the stock nixpkgs build.
      embedMan = false;
      # qjs has no `--version` flag (its banner only prints via `-h`, which
      # exits 1), so smoke by evaluating a computed marker — proves the
      # interpreter actually runs JS and exits 0.
      smoke = [ "-e" "console.log('quickjs-ng ' + 6 * 7)" ];
      smokePattern = "quickjs-ng 42";
      build = pkgs:
        let base = retarget pkgs.pkgsStatic.quickjs-ng; in
        import ./multicall.nix { lib = pkgs.lib // ulib; } { inherit pkgs; quickjs = base; };
      windowsBuild = pkgs:
        let
          cross = ulib.mingwStaticCross pkgs;
          # quickjs-ng includes <pthread.h> and links -lpthread (worker threads,
          # JS atomics) on every platform; mingw needs winpthreads for the
          # header + static lib (same as aom/vim's windows builds).
          base = (retarget cross.quickjs-ng).overrideAttrs (o: {
            buildInputs = (o.buildInputs or [ ]) ++ [ cross.windows.pthreads ];
          });
        in
        import ./multicall.nix { lib = pkgs.lib // ulib; } { inherit pkgs; quickjs = base; };
    };
}
