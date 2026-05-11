function secret --description 'Read one secret from ~/.config/secrets/.env. Use --list to see keys.'
    set -l env_file ~/.config/secrets/.env

    if test "$argv[1]" = --list
        awk -F= '/^[A-Za-z_][A-Za-z0-9_]*=/ {print $1}' $env_file | sort -u
        return 0
    end

    if test (count $argv) -ne 1
        echo "usage: secret KEY  |  secret --list" >&2
        return 2
    end

    if not test -f $env_file
        echo "secret: $env_file not found" >&2
        return 1
    end

    set -l val (awk -F= -v k=$argv[1] '$1==k {sub(/^[^=]+=/,""); print; exit}' $env_file)
    if test -z "$val"
        echo "secret: $argv[1] not found in $env_file" >&2
        return 1
    end
    echo $val
end
