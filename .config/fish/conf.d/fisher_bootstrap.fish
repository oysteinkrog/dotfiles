# Bootstrap fisher if missing. Use a file test, not `functions -q fisher`:
# the latter forces fish to autoload (parse all ~430 lines of) fisher.fish on
# every shell start just to answer the existence check.
set -q XDG_CONFIG_HOME; or set -l XDG_CONFIG_HOME ~/.config
if not test -f $XDG_CONFIG_HOME/fish/functions/fisher.fish
    curl https://git.io/fisher --create-dirs -sLo $XDG_CONFIG_HOME/fish/functions/fisher.fish
    fish -c fisher
end
