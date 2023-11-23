{ pkgs, lib, ... }:

{
  # The follow two env vars are required to run local dev
  env.OPENAI_API_KEY = "replaceme";
  env.GOOGLE_APPLICATION_CREDENTIALS = "replaceme";

  enterShell = ''
  '';
}
