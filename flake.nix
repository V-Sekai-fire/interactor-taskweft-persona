{
  description = "persona.elf, built offline from this repository";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    guest-runtime = {
      url = "github:V-Sekai-fire/contract-guest-runtime";
      flake = false;
    };
    lean-guest = {
      url = "github:V-Sekai-fire/interactor-lean-guest";
      flake = false;
    };
    riscv64-sysroot = {
      url = "github:V-Sekai-fire/repository-riscv64-sysroot";
      flake = false;
    };
    # The Lean release in lean-toolchain: the host compiler that emits the C.
    lean-toolchain = {
      url = "https://github.com/leanprover/lean4/releases/download/v4.34.1/lean-4.34.1-linux.tar.zst";
      flake = false;
    };
    # What interactor-lean-guest's cmake would download: the same release's
    # sources for the guest runtime, and the libuv it pins.
    lean4-src = {
      url = "github:leanprover/lean4/v4.34.1";
      flake = false;
    };
    libuv-src = {
      url = "github:libuv/libuv/v1.48.0";
      flake = false;
    };
    # The git packages of lake-manifest.json, at its revisions.
    plausible = {
      url = "github:leanprover-community/plausible/118aa17ee84656b8bd727fef7c458ee8c833385c";
      flake = false;
    };
    plausible-witness-dag = {
      url = "github:V-Sekai-fire/plausible-witness-dag/f18818941e8914b110f85ec330889a4785c01bf1";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      siblings = {
        "2-contract/guest-runtime" = inputs.guest-runtime;
        "3-interactor/lean-guest" = inputs.lean-guest;
        "5-repository/riscv64-sysroot" = inputs.riscv64-sysroot;
      };
      lakeGit = {
        "plausible" = inputs.plausible;
        "plausible-witness-dag" = inputs.plausible-witness-dag;
      };

      lean = { stdenv, autoPatchelfHook, zlib }:
        stdenv.mkDerivation {
          pname = "lean-bin";
          version = "4.34.1";
          src = inputs.lean-toolchain;
          nativeBuildInputs = [ autoPatchelfHook ];
          buildInputs = [ stdenv.cc.cc.lib zlib ];
          dontConfigure = true;
          dontBuild = true;
          dontStrip = true;
          installPhase = ''
            mkdir -p $out
            cp -r . $out/
          '';
        };

      persona = { lib, stdenvNoCC, cmake, ninja, python3, git, gnupatch, gcc
        , llvmPackages, lean-bin }:
        let
          place = path: src: ''
            mkdir -p weft/${dirOf path}
            cp -r ${src} weft/${path}
          '';
          placeLake = name: src: ''
            cp -r ${src} .lake/packages/${name}
          '';
          pin = path: src: "${path} ${src.rev}";
        in
        stdenvNoCC.mkDerivation {
          pname = "persona-elf";
          version = self.shortRev or "dirty";
          src = lib.cleanSourceWith {
            src = self;
            filter = path: _:
              !(builtins.elem (baseNameOf path) [
                "flake.nix"
                "flake.lock"
                ".github"
              ]);
          };
          nativeBuildInputs = [
            cmake
            ninja
            python3
            git
            gnupatch
            gcc
            lean-bin
            llvmPackages.clang-unwrapped
            llvmPackages.lld
            llvmPackages.bintools-unwrapped
          ];
          dontUseCmakeConfigure = true;
          # The guest ELF ships as the linker wrote it.
          dontFixup = true;
          buildPhase = ''
            export HOME=$TMPDIR LANG=C.UTF-8
            # The Lean release carries a clang for x86 only; the cross compiler must come first.
            export PATH=${llvmPackages.clang-unwrapped}/bin:${llvmPackages.lld}/bin:${llvmPackages.bintools-unwrapped}/bin:$PATH
            ${lib.concatStrings (lib.mapAttrsToList place siblings)}
            mkdir -p .lake/packages
            ${lib.concatStrings (lib.mapAttrsToList placeLake lakeGit)}
            cp -r ${inputs.lean4-src} lean4-src
            cp -r ${inputs.libuv-src} libuv-src
            chmod -R u+w weft .lake lean4-src libuv-src
            # Lake would clone the git packages; here they are the pinned copies, as path packages.
            python3 - <<'PY'
            import json
            m = json.load(open("lake-manifest.json"))
            for p in m["packages"]:
                if p["type"] == "git":
                    for k in ("url", "rev", "inputRev", "subDir"):
                        p.pop(k, None)
                    p["type"] = "path"
                    p["dir"] = ".lake/packages/" + p["name"].strip("«»")
            json.dump(m, open("lake-manifest.json", "w"), indent=1)
            PY
            (cd lean4-src && patch -p2 --forward --batch \
              -i $NIX_BUILD_TOP/$sourceRoot/weft/3-interactor/lean-guest/patches/runtime-guest.patch)
            cmake -S guest -B rv64 -G Ninja -DCMAKE_BUILD_TYPE=Release \
              -DCMAKE_TOOLCHAIN_FILE=$PWD/weft/5-repository/riscv64-sysroot/toolchain.cmake \
              -DGUEST_RUNTIME_ROOT=$PWD/weft/2-contract/guest-runtime \
              -DLEAN_GUEST_DIR=$PWD/weft/3-interactor/lean-guest \
              -DFETCHCONTENT_FULLY_DISCONNECTED=ON \
              -DFETCHCONTENT_SOURCE_DIR_LEAN4=$PWD/lean4-src \
              -DFETCHCONTENT_SOURCE_DIR_LIBUV=$PWD/libuv-src
            cmake --build rv64 --target persona
          '';
          doCheck = true;
          checkPhase = ''
            python3 tools/check_elf.py rv64/persona
            python3 - rv64/persona single.elf <<'PY'
            import sys
            b = bytearray(open(sys.argv[1], "rb").read())
            i = b.find(b"SBXV(\0\0\0")
            b[i + 4] = 24
            open(sys.argv[2], "wb").write(b)
            PY
            if python3 tools/check_elf.py single.elf; then
              echo "the check passed a 24-byte Variant"
              exit 1
            fi
          '';
          installPhase = ''
            mkdir -p $out
            cp rv64/persona $out/persona.elf
            cat > $out/persona.elf.siblings.txt <<'TXT'
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList pin siblings)}
            TXT
          '';
        };

      overlay = final: _: {
        lean-bin = final.callPackage lean { };
        persona-elf = final.callPackage persona {
          llvmPackages = final.llvmPackages_21;
        };
      };
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ overlay ];
      };
    in
    {
      overlays.default = overlay;
      packages.${system} = {
        persona-elf = pkgs.persona-elf;
        default = pkgs.persona-elf;
      };
    };
}
