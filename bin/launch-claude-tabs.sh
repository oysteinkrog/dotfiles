#!/bin/bash
# Launch 10 Windows Terminal tabs for desktop_master worktrees, each running claude

cmd="wt.exe -w 0"

for i in {1..10}; do
    if [ $i -eq 1 ]; then
        dir="C:\\WORK\\desktop_master"
    else
        dir="C:\\WORK\\desktop_master$i"
    fi

    cmd="$cmd nt -p Ubuntu -d '$dir' --title $i wsl.exe -e fish -c \"claude --dangerously-skip-permissions --continue\" \\;"
done

# Remove trailing \; and execute
cmd="${cmd% \\;}"
eval "$cmd"
