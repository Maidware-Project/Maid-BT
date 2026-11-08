{
  description = "Maid BT - bluetooth earbuds switching (Maidware)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        py = pkgs.python3;
        runtimePath = pkgs.lib.makeBinPath [
          pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.gawk pkgs.findutils pkgs.procps pkgs.util-linux
          pkgs.bluez pkgs.pulseaudio pkgs.libnotify pkgs.curl pkgs.systemd py
        ];
        maid-bt = pkgs.stdenv.mkDerivation {
          pname = "maid-bt";
          version = "0.1.0";
          src = self;
          nativeBuildInputs = [ pkgs.makeWrapper ];
          dontBuild = true;
          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin $out/libexec/maid-bt $out/share/maid-bt $out/share/applications
            cp -a bin/* $out/libexec/maid-bt/bin/ 2>/dev/null || true
            cp -a watcher $out/libexec/maid-bt/watcher 2>/dev/null || true
            cp -a systemd $out/share/maid-bt/systemd 2>/dev/null || true
            cp -a desktop $out/share/maid-bt/desktop 2>/dev/null || true
            cp -a plasmoid $out/share/maid-bt/plasmoid 2>/dev/null || true
            cp -a contrib $out/share/maid-bt/contrib 2>/dev/null || true
            cp -a README.md LICENSE THIRD-PARTY-NOTICES.md $out/share/maid-bt/ 2>/dev/null || true
            for s in $out/libexec/maid-bt/bin/*; do [ -f "$s" ] && chmod +x "$s" || true; done
            # expose key commands; scripts resolve helpers relative to BINDIR/HOME in places - wrappers set PATH
            for c in bluetooth-toggle.sh maid-switch maid-bt-helper maid-watcher buds-on.sh buds-off.sh buds-release.sh; do
              if [ -f "$out/libexec/maid-bt/bin/$c" ]; then
                makeWrapper "$out/libexec/maid-bt/bin/$c" "$out/bin/$c" --prefix PATH : ${runtimePath}:$out/libexec/maid-bt/bin
              fi
            done
            # desktop entries (best-effort; they reference installed paths on conventional systems)
            [ -d desktop ] && cp -a desktop/*.desktop $out/share/applications/ 2>/dev/null || true
            runHook postInstall
          '';
          meta = with pkgs.lib; {
            description = "bluetooth earbuds switching (Maidware)";
            homepage = "https://github.com/Maidware-Project/Maid-BT";
            license = licenses.gpl3Plus;
            platforms = platforms.linux;
            mainProgram = "bluetooth-toggle.sh";
          };
        };
      in {
        packages.default = maid-bt;
        packages.maid-bt = maid-bt;
        apps.default = { type = "app"; program = "${maid-bt}/bin/bluetooth-toggle.sh"; };
      }
    ) // {
      homeManagerModules.default = { config, lib, pkgs, ... }: {
        options.programs.maid-bt.enable = lib.mkEnableOption "Maid BT (Maidware)";
        config = lib.mkIf config.programs.maid-bt.enable {
          home.packages = [ self.packages.${pkgs.system}.default ];
          # systemd user units/plasmoid integration is system- and session-specific;
          # manage via home-manager services or the tool's own install/config as needed.
        };
      };
    };
}
