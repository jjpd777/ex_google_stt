{ pkgs, lib, ... }:

{
  # https://devenv.sh/languages/
  languages = {
    nix = {
      enable = true;
    };

    elixir = {
      enable = true;
      package = pkgs.beam.packages.erlangR26.elixir_1_14;
    };
  };



  enterShell = ''
    echo "Entering ex_google_stt..."
  '';
}
