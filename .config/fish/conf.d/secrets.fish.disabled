# Load secrets from ~/.config/secrets/.env
# Format: KEY=VALUE (one per line, no quotes needed)
if test -f ~/.config/secrets/.env
    while read -l line
        # skip empty lines and comments
        string match -qr '^\s*(#|$)' $line; and continue
        set -l parts (string split -m 1 '=' $line)
        if test (count $parts) -eq 2
            set -gx $parts[1] $parts[2]
        end
    end < ~/.config/secrets/.env
end
