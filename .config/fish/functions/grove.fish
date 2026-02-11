function grove --description "Git worktree manager (with shell cd support)"
    set -l subcmd $argv[1]

    if test "$subcmd" = cd -o "$subcmd" = new -o "$subcmd" = fork -o "$subcmd" = rename -o "$subcmd" = done -o "$subcmd" = mv
        # On Windows/WSL, directories can't be moved/deleted while any process
        # has its CWD inside them.  cd the shell out before running the command.
        # The Python script prints __POSTCD__<path> to tell us where to land.
        set -l saved_dir (pwd -P)

        # Tell the Python script where we really were (for auto-detection)
        set -lx GROVE_ORIG_CWD $saved_dir

        # cd to work_dir parent so the worktree directory is unlocked
        cd /c/WORK

        # Run the real command, streaming stdout in real-time while
        # capturing __POSTCD__ directives.  stderr goes directly to the
        # terminal (used for prompts, warnings, progress).  Python's
        # line-buffering (set in grove when piped) ensures lines appear
        # immediately.
        set -l postcd ""
        command grove $argv | while read -l line
            if string match -q '__POSTCD__*' $line
                set postcd (string replace '__POSTCD__' '' $line)
            else
                echo $line
            end
        end
        set -l cmd_status $pipestatus[1]

        if test $cmd_status -ne 0
            # Command failed, go back
            cd $saved_dir 2>/dev/null; or cd /c/WORK
        else if test -n "$postcd" -a -d "$postcd"
            cd $postcd
        else
            cd $saved_dir 2>/dev/null; or cd /c/WORK
        end

        return $cmd_status
    else
        command grove $argv
    end
end

complete -c grove -f -a "(grove list --tags-only 2>/dev/null)" -n "__fish_use_subcommand"
complete -c grove -f -n "__fish_use_subcommand" -a "new" -d "Create new worktree project"
complete -c grove -f -n "__fish_use_subcommand" -a "cd" -d "Change directory to project"
complete -c grove -f -n "__fish_use_subcommand" -a "list ls" -d "List projects"
complete -c grove -f -n "__fish_use_subcommand" -a "done" -d "Remove project"
complete -c grove -f -n "__fish_use_subcommand" -a "fork" -d "Fork existing project"
complete -c grove -f -n "__fish_use_subcommand" -a "launch" -d "Open terminal tabs"
complete -c grove -f -n "__fish_use_subcommand" -a "adopt" -d "Import existing worktree"
complete -c grove -f -n "__fish_use_subcommand" -a "rename mv" -d "Rename project"
complete -c grove -f -n "__fish_use_subcommand" -a "freeze" -d "Freeze project"
complete -c grove -f -n "__fish_use_subcommand" -a "thaw" -d "Unfreeze project"
complete -c grove -f -n "__fish_use_subcommand" -a "path" -d "Print worktree path"
complete -c grove -f -n "__fish_use_subcommand" -a "config" -d "Manage configuration"
complete -c grove -f -n "__fish_seen_subcommand_from cd done freeze thaw path" -a "(grove list --tags-only 2>/dev/null)"
