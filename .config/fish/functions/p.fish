function p --description "cd to a project by tag (shorthand for grove cd)"
    if test (count $argv) -eq 0
        grove list --short
        return
    end
    grove cd $argv[1]
end

complete -c p -f -a "(grove list --tags-only 2>/dev/null)"
