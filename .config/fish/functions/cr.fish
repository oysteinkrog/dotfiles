function cr --description 'Claude Code (resume) via aiolos-rc (load-balanced proxy + remote-control), skip-permissions'
    test "$HERDR_ENV" = 1; and set -lx HERDR_AGENT claude # herdr: see claude.fish
    ~/.config/aiolos-rc/aiolos-rc --no-pin -r $argv
end
