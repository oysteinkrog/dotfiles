function gr --description "Shorthand for grove cd / grove list"
    if test (count $argv) -eq 0
        grove list --short
        return
    end
    grove cd $argv[1]
end

complete -c gr -f -a "(grove list --tags-only 2>/dev/null)"
