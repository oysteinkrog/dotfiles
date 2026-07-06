# Completions for ~/bin/secret — offer key names from the store (names only,
# never values).
complete -c secret -f
complete -c secret -f -n "test (count (commandline -opc)) -eq 1" -a "(secret --list)" -d "Secret key"
complete -c secret -f -n "test (count (commandline -opc)) -eq 1" -a "--list" -d "List available keys"
