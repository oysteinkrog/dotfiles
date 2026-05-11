function with-secrets --description 'Run CMD with named secrets in its env. Usage: with-secrets KEY [KEY ...] -- CMD [ARGS]'
    set -l vars
    while set -q argv[1]; and test "$argv[1]" != --
        set -a vars $argv[1]
        set -e argv[1]
    end

    if test (count $argv) -lt 2; or test "$argv[1]" != --
        echo "usage: with-secrets KEY [KEY ...] -- CMD [ARGS ...]" >&2
        return 2
    end
    set -e argv[1]  # drop the literal --

    if test (count $vars) -eq 0
        echo "with-secrets: no keys given before --" >&2
        return 2
    end

    for v in $vars
        set -l val (secret $v)
        or return $status
        set -fx $v $val
    end
    $argv
end
