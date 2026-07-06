# Completions for ~/bin/with-secrets — key names before the `--` separator,
# then command completion after it (sudo-style wrapper).
function __with_secrets_before_separator
    not contains -- -- (commandline -opc)
end

complete -c with-secrets -f -n __with_secrets_before_separator -a "(secret --list)" -d "Secret key"
complete -c with-secrets -f -n __with_secrets_before_separator -a "--" -d "End of keys; command follows"
complete -c with-secrets -x -n "not __with_secrets_before_separator" -a "(__fish_complete_subcommand --fcs-skip=2)"
