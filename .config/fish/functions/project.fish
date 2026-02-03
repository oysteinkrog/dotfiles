function project --description "Git worktree manager (with shell cd support)"
    set -l subcmd $argv[1]

    if test "$subcmd" = rename -o "$subcmd" = done -o "$subcmd" = mv
        # On Windows/WSL, directories can't be moved/deleted while any process
        # has its CWD inside them.  cd the shell out before running the command.
        # The Python script prints __POSTCD__<path> to tell us where to land.
        set -l saved_dir (pwd -P)

        # Tell the Python script where we really were (for auto-detection)
        set -lx PROJECT_ORIG_CWD $saved_dir

        # cd to work_dir parent so the worktree directory is unlocked
        cd /c/WORK

        # Run the real command, capture output
        set -l tmpout (mktemp)
        command project $argv >$tmpout 2>&1
        set -l cmd_status $status

        # Print output, filtering out __POSTCD__ directive
        grep -v '^__POSTCD__' $tmpout

        # Extract __POSTCD__ path
        set -l postcd (grep '^__POSTCD__' $tmpout | sed 's/^__POSTCD__//')
        rm -f $tmpout

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
        command project $argv
    end
end
