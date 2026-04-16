function mt --description "MidTerm terminal multiplexer (port 9104)"
    # ASP.NET watches CWD recursively via inotify; launching from ~ hangs on WSL1
    # due to tens of thousands of subdirectories. Use an empty content root instead.
    mkdir -p /tmp/mt-run
    cd /tmp/mt-run; and command mt --port 9104 $argv; cd -
end
