{
  pkgs,
  config,
  lib,
  ...
}:
let
  clipHandler = pkgs.writeShellScript "keyd-clip-handler" ''
    [ "$CLIPBOARD_STATE" = "sensitive" ] && exit 0
    cat > /etc/keyd/clip
  '';

in
{
  systemd.tmpfiles.rules = [
    "f /etc/keyd/clip 0720 root wheel -"
  ];
  systemd.user.services.keyd-clip = {
    description = "Mirror clipboard to keyd";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${clipHandler}";
      Restart = "on-failure";
    };
  };

  environment.systemPackages = [
    # add keyd-clip-status to your waybar
    (pkgs.writeShellScriptBin "keyd-clip-status" ''
      if systemctl --user is-active --quiet keyd-clip; then
        echo '{"text":"","tooltip":"Clipboard mirror active (click to stop)","class":"on"}'
      else
        echo '{"text":"","tooltip":"Clipboard mirror stopped (click to start)","class":"off"}'
      fi
    '')
    (pkgs.writeShellScriptBin "keyd-clip-toggle" ''
      if systemctl --user is-active --quiet keyd-clip; then
        systemctl --user stop --quiet keyd-clip
      else
        systemctl --user start --quiet keyd-clip
      fi
    '')
  ];

  systemd.services.keyd = {
    path = [
      pkgs.keyd
    ];
  };
  services.keyd = {
    enable = true;

    keyboards.default = {
      ids = [ "0001:0001" ];

      settings = {
        main = {
          rightalt = ''command(keyd input -t 10 "$(cat /etc/keyd/clip)")'';
        };

        "control+alt" = {
          v = "command()";
        };
      };
    };
  };
  #
  #
}
