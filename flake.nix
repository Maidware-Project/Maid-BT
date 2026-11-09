{
  description = "Maid BT - bluetooth earbuds switching (Maidware)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          pythonEnv = pkgs.python3.withPackages (ps: [
            ps.dbus-python
            ps.pygobject3
          ]);
          runtimePath = pkgs.lib.makeBinPath [
            pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.gawk pkgs.findutils pkgs.procps pkgs.util-linux
            pkgs.bluez pkgs.pulseaudio pkgs.libnotify pkgs.curl pkgs.systemd pythonEnv
            pkgs.glib pkgs.gobject-introspection
          ];
          giTypelibPath = pkgs.lib.makeSearchPath "lib/girepository-1.0" [
            pkgs.glib
            pkgs.gobject-introspection
            pkgs.gtk3
          ];
          maid-bt = pkgs.stdenv.mkDerivation {
            pname = "maid-bt";
            version = "0.1.0";
            src = self;
            nativeBuildInputs = [ pkgs.makeWrapper ];
            dontBuild = true;
            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin $out/libexec/maid-bt $out/share/maid-bt $out/share/applications $out/share/plasma/plasmoids
              cp -a bin $out/libexec/maid-bt/bin
              cp -a watcher $out/libexec/maid-bt/watcher 2>/dev/null || true
              cp -a systemd $out/share/maid-bt/systemd 2>/dev/null || true
              cp -a desktop $out/share/maid-bt/desktop 2>/dev/null || true
              cp -a plasmoid $out/share/maid-bt/plasmoid 2>/dev/null || true
              cp -a contrib $out/share/maid-bt/contrib 2>/dev/null || true
              cp -a README.md LICENSE THIRD-PARTY-NOTICES.md $out/share/maid-bt/ 2>/dev/null || true
              find $out/libexec/maid-bt/bin -type f -exec chmod +x {} +
              [ -f $out/libexec/maid-bt/watcher/maid-watcher ] && chmod +x $out/libexec/maid-bt/watcher/maid-watcher || true
              for c in bluetooth-toggle.sh maid-switch maid-bt-helper maid-bt-config maid-soundcore maid-watcher buds-on.sh buds-off.sh buds-release.sh buds-fallback.sh bt-intent-server.py; do
                if [ -f "$out/libexec/maid-bt/bin/$c" ]; then
                  if [ "$c" = "maid-watcher" ]; then
                    makeWrapper "$out/libexec/maid-bt/bin/$c" "$out/bin/$c" \
                      --prefix PATH : ${runtimePath}:$out/libexec/maid-bt/bin \
                      --prefix GI_TYPELIB_PATH : ${giTypelibPath}
                  else
                    makeWrapper "$out/libexec/maid-bt/bin/$c" "$out/bin/$c" --prefix PATH : ${runtimePath}:$out/libexec/maid-bt/bin
                  fi
                fi
              done
              # watcher entry may live under watcher/
              if [ -f "$out/libexec/maid-bt/watcher/maid-watcher" ] && [ ! -e "$out/bin/maid-watcher" ]; then
                makeWrapper "$out/libexec/maid-bt/watcher/maid-watcher" "$out/bin/maid-watcher" \
                  --prefix PATH : ${runtimePath}:$out/libexec/maid-bt/bin:$out/libexec/maid-bt/watcher \
                  --prefix GI_TYPELIB_PATH : ${giTypelibPath}
              fi
              # if bin/maid-watcher existed and was wrapped without GI path, replace with GI-aware wrapper from watcher source when available
              if [ -f "$out/libexec/maid-bt/watcher/maid-watcher" ] && [ -e "$out/bin/maid-watcher" ]; then
                rm -f "$out/bin/maid-watcher"
                makeWrapper "$out/libexec/maid-bt/watcher/maid-watcher" "$out/bin/maid-watcher" \
                  --prefix PATH : ${runtimePath}:$out/libexec/maid-bt/bin:$out/libexec/maid-bt/watcher \
                  --prefix GI_TYPELIB_PATH : ${giTypelibPath}
              fi
              [ -d desktop ] && cp -a desktop/*.desktop $out/share/applications/ 2>/dev/null || true
              # fix desktop entries for Nix (upstream uses @HOME@/.local/bin/...)
              find $out/share/applications $out/share/maid-bt/desktop -name '*.desktop' -type f 2>/dev/null | while IFS= read -r f; do
                sed -i "s|@HOME@/.local/bin/||g; s|@HOME@|$HOME|g" "$f"
              done
              # install plasmoid for Plasma discovery and patch tool paths for Nix/PATH
              if [ -d "$out/share/maid-bt/plasmoid/com.local.btearbuds" ]; then
                cp -a "$out/share/maid-bt/plasmoid/com.local.btearbuds" "$out/share/plasma/plasmoids/"
                find "$out/share/plasma/plasmoids/com.local.btearbuds" \( -name '*.qml' -o -name '*.js' -o -name '*.json' \) -type f | while IFS= read -r f; do
                  sed -i "s|@HOME@/.local/bin/||g; s|@HOME@|$HOME|g" "$f"
                done
              fi
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
        in { default = maid-bt; maid-bt = maid-bt; });

      apps = forAllSystems (system: {
        default = { type = "app"; program = "${self.packages.${system}.default}/bin/bluetooth-toggle.sh"; };
      });

      checks = forAllSystems (system: {
        package = self.packages.${system}.default;
      });

      # easy home-manager: imports = [ inputs.maid-bt.homeManagerModules.default ];
      # then: programs.maid-bt.enable = true; services.maid-bt.watcher.enable = true;
      homeManagerModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.programs.maid-bt;
          svc = config.services.maid-bt;
          pkg = cfg.package;
          json = pkgs.formats.json {};
        in {
          options.programs.maid-bt = {
            enable = lib.mkEnableOption "Maid BT (Maidware)";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              description = "Maid BT package to use.";
            };
          };
          options.services.maid-bt = {
            watcher.enable = lib.mkEnableOption "Maid BT buds fallback watcher (user service)";
            intentListener.enable = lib.mkEnableOption "Maid BT phone intent listener (user service, LAN)";
            maidWatcher.enable = lib.mkEnableOption "Maid Watcher daemon (calls/battery/reconnect)";
            maidWatcher.settings = lib.mkOption {
              type = json.type;
              default = {};
              description = "Written to ~/.config/maid-watcher/config.json when set (non-empty).";
            };
          };
          config = lib.mkMerge [
            (lib.mkIf cfg.enable { home.packages = [ pkg ]; })
            (lib.mkIf (svc.maidWatcher.enable && svc.maidWatcher.settings != {}) {
              xdg.configFile."maid-watcher/config.json".source = json.generate "maid-watcher-config.json" svc.maidWatcher.settings;
            })
            (lib.mkIf svc.watcher.enable {
              systemd.user.services.maid-bt-watcher = {
                Unit = { Description = "Maid BT earbuds watcher (auto-connect + fallback sink park)"; After = [ "pipewire.service" "wireplumber.service" "bluetooth.service" ]; Wants = [ "pipewire.service" "wireplumber.service" ]; };
                Service = { ExecStart = "${pkg}/bin/buds-fallback.sh"; Restart = "always"; RestartSec = 3; };
                Install = { WantedBy = [ "default.target" ]; };
              };
            })
            (lib.mkIf svc.intentListener.enable {
              systemd.user.services.maid-bt-intent = {
                Unit = { Description = "Maid BT intent HTTP listener (phone -> PC)"; After = [ "network-online.target" ]; Wants = [ "network-online.target" ]; };
                Service = { ExecStart = "${pkg}/bin/bt-intent-server.py"; Restart = "always"; RestartSec = 3; };
                Install = { WantedBy = [ "default.target" ]; };
              };
            })
            (lib.mkIf svc.maidWatcher.enable {
              systemd.user.services.maid-watcher = {
                Unit = { Description = "Maid Watcher (earbuds connection/call/battery manager)"; After = [ "bluetooth.service" ]; Wants = [ "bluetooth.service" ]; };
                Service = { ExecStart = "${pkg}/bin/maid-watcher run"; Restart = "on-failure"; RestartSec = 10; };
                Install = { WantedBy = [ "default.target" ]; };
              };
            })
          ];
        };

      homeModules = self.homeManagerModules;

      nixosModules.default = { lib, ... }: {
        # Maid BT is primarily a user-session tool; system needs bluetooth/pipewire.
        # enable hardware.bluetooth / services.pipewire in your NixOS config as usual.
        options.services.maid-bt.enableNote = lib.mkEnableOption "Maid BT note (user-session tool; use home-manager module)";
      };
    };
}
