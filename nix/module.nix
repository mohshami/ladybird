# A NixOS module that installs the Ladybird browser.
#
# Nixpkgs has a module of its own for it, which installs Nixpkgs' package.
# This one installs the package this flake builds instead, and it adds the
# fonts the browser needs, because its font fallback lists require fonts that
# a default NixOS installation does not have.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.ladybird;
in
{
  options.programs.ladybird = {
    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      defaultText = lib.literalExpression "null";
      example = lib.literalExpression "self.packages.${pkgs.stdenv.hostPlatform.system}.ladybird";
      description = ''
        The Ladybird package to install. When null, the package Nixpkgs
        provides is used.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Nixpkgs' module installs the package that Nixpkgs provides, so replace
    # it with the one that was chosen here.
    nixpkgs.overlays = [
      (final: prev: {
        ladybird = if cfg.package == null then prev.ladybird else cfg.package;
      })
    ];

    fonts.packages = with pkgs; [
      dejavu_fonts
      liberation_ttf
    ];

    fonts.fontconfig.enable = true;
  };
}
