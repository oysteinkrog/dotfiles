function claude-restore --description "Restore critical settings to ~/.claude.json"
    set -l config "$HOME/.claude.json"
    set -l patch "$HOME/.claude-defaults.json"

    if not test -f "$patch"
        echo "Error: $patch not found. Run claude-backup first."
        return 1
    end

    if not test -f "$config"
        echo "Error: $config not found."
        return 1
    end

    set -l tmp (mktemp)
    jq -s '.[0] * .[1]' "$config" "$patch" > "$tmp"
    if test $status -eq 0
        mv "$tmp" "$config"
        echo "Restored settings from $patch into $config"
    else
        rm -f "$tmp"
        echo "Error: jq merge failed."
        return 1
    end
end
