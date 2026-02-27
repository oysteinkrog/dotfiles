function claude-backup --description "Backup critical ~/.claude.json settings"
    set -l config "$HOME/.claude.json"
    set -l patch "$HOME/.claude-defaults.json"

    if not test -f "$config"
        echo "Error: $config not found."
        return 1
    end

    jq '{theme, mcpServers, bypassPermissionsModeAccepted}' "$config" > "$patch"
    if test $status -eq 0
        echo "Backed up critical settings to $patch"
    else
        rm -f "$patch"
        echo "Error: jq extract failed."
        return 1
    end
end
