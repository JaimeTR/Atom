{llvm ? 10, musl ? false, system ? builtins.currentSystem}:

let
  nixpkgs = import (builtins.fetchTarball {
    name = "nixpkgs-20.03";
    url = "https://github.com/NixOS/nixpkgs/archive/2d580cd2793a7b5f4b8b6b88fb2ccec700ee1ae6.tar.gz";
    sha256 = "1nbanzrir1y0yi2mv70h60sars9scwmm0hsxnify2ldpczir9n37";
  }) {
    inherit system;
  };

  pkgs = if musl then nixpkgs.pkgsMusl else nixpkgs;

  genericBinary = { url, sha256 }:
    pkgs.stdenv.mkDerivation rec {
      name = "atomlang-binary";
      src = builtins.fetchTarball { inherit url sha256; };

      # Extract only the compiler binary
      buildCommand = ''
        mkdir -p $out/bin

        # Darwin packages use embedded/bin/atomlang
        [ ! -f "${src}/embedded/bin/atomlang" ] || cp ${src}/embedded/bin/atomlang $out/bin/

        # Linux packages use lib/atomlang/bin/atomlang
        [ ! -f "${src}/lib/atomlang/bin/atomlang" ] || cp ${src}/lib/atomlang/bin/atomlang $out/bin/
      '';
    };

  # Hashes obtained using `nix-prefetch-url --unpack <url>`
  latestAtomLangBinary = genericBinary ({
    x86_64-darwin = {
      url = "https://github.com/AtomLanguage/atomlang/releases/download/1.1.0/atomlang-1.1.0-1-darwin-x86_64.tar.gz";
      sha256 = "sha256:0dk893g5v3y11hfmr6viskhajnlippwcs8ra8azxa9rjh47lx8zg";
    };

    x86_64-linux = {
      url = "https://github.com/AtomLanguage/atomlang/releases/download/1.1.0/atomlang-1.1.0-1-linux-x86_64.tar.gz";
      sha256 = "sha256:1n967087p0km0v4pr7xyl4gg5cfl1zap7kas94gw4cs4a90irwgd";
    };

    i686-linux = {
      url = "https://github.com/AtomLanguage/atomlang/releases/download/1.1.0/atomlang-1.1.0-1-linux-i686.tar.gz";
      sha256 = "sha256:06qzhrq4la7fkk1y6nr5kq52gxfnrlbnh9lg7ppbxqglr39ygml3";
    };
  }.${pkgs.stdenv.system});

  pkgconfig = pkgs.pkgconfig;

  llvm_suite = ({
    llvm_10 = {
      llvm = pkgs.llvm_10;
      extra = [ pkgs.lld_10 pkgs.lldb_10 ];
    };
    llvm_9 = {
      llvm = pkgs.llvm_9;
      extra = [ ]; # lldb it fails to compile on Darwin
    };
    llvm_8 = {
      llvm = pkgs.llvm_8;
      extra = [ ]; # lldb it fails to compile on Darwin
    };
    llvm_7 = {
      llvm = pkgs.llvm;
      extra = [ pkgs.lldb ];
    };
    llvm_6 = {
      llvm = pkgs.llvm_6;
      extra = [ ]; # lldb it fails to compile on Darwin
    };
  }."llvm_${toString llvm}");

  libatomic_ops = builtins.fetchurl {
    url = "https://github.com/ivmai/libatomic_ops/releases/download/v7.6.10/libatomic_ops-7.6.10.tar.gz";
    sha256 = "1bwry043f62pc4mgdd37zx3fif19qyrs8f5bw7qxlmkzh5hdyzjq";
  };

  boehmgc = pkgs.stdenv.mkDerivation rec {
    pname = "boehm-gc";
    version = "8.0.4";

    src = builtins.fetchTarball {
      url = "https://github.com/ivmai/bdwgc/releases/download/v${version}/gc-${version}.tar.gz";
      sha256 = "16ic5dwfw51r5lcl88vx3qrkg3g2iynblazkri3sl9brnqiyzjk7";
    };

    patches = [
      (pkgs.fetchpatch {
        url = "https://github.com/ivmai/bdwgc/commit/5668de71107022a316ee967162bc16c10754b9ce.patch";
        sha256 = "02f0rlxl4fsqk1xiq0pabkhwydnmyiqdik2llygkc6ixhxbii8xw";
      })
    ];

    postUnpack = ''
      mkdir $sourceRoot/libatomic_ops
      tar -xzf ${libatomic_ops} -C $sourceRoot/libatomic_ops --strip-components 1
    '';

    configureFlags = [
      "--disable-debug"
      "--disable-dependency-tracking"
      "--disable-shared"
      "--enable-large-config"
    ];

    enableParallelBuilding = true;
  };

  stdLibDeps = with pkgs; [
      boehmgc gmp libevent libiconv libxml2 libyaml openssl pcre zlib
    ] ++ stdenv.lib.optionals stdenv.isDarwin [ libiconv ];

  tools = [ pkgs.hostname pkgs.git llvm_suite.extra ];
in

pkgs.stdenv.mkDerivation rec {
  name = "atomlang-dev";

  buildInputs = tools ++ stdLibDeps ++ [
    latestAtomLangBinary
    pkgconfig
    llvm_suite.llvm
  ];

  LLVM_CONFIG = "${llvm_suite.llvm}/bin/llvm-config";

  MACOSX_DEPLOYMENT_TARGET = "10.11";
}