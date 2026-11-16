{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  packages = with pkgs; [
    bash coreutils gnugrep gnused gawk findutils procps util-linux
    bluez pulseaudio libnotify curl systemd
    (python3.withPackages (ps: [ ps.dbus-python ps.pygobject3 ]))
    glib gobject-introspection gtk3
    shellcheck
  ];

  shellHook = ''
    export GI_TYPELIB_PATH=${pkgs.lib.makeSearchPath "lib/girepository-1.0" [
      pkgs.glib pkgs.gobject-introspection pkgs.gtk3
    ]}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}
    echo "Maid BT dev shell"
  '';
}
