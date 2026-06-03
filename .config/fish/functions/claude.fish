# WSL1 fix: lxcore.sys returns ENOEXEC for ELF binaries that have a PT_LOAD
# segment with p_align greater than the page size (0x1000). Bun-compiled binaries
# (like Claude Code) emit a writable LOAD segment aligned to 0x4000, tripping this
# kernel bug.
#
# Old workaround was to launch via ld-linux, which bypasses the kernel's ELF
# parser. But that makes process.execPath point at the loader, which breaks Claude
# Code's bundled grep/find shell wrappers: they run `exec -a ugrep "$execpath" -G
# ...`, i.e. `ld-linux -G ...`, and the loader then tries to load a program named
# "-G" -> "-G: error while loading shared libraries: -G: cannot open shared object
# file".
#
# New fix: patch the binary's oversized p_align down to 0x1000 (idempotent, 8-byte
# edit via claude-wsl-elf-fix) so the kernel can exec it directly. Running it
# directly makes process.execPath the real binary, and the wrappers work. Falls
# back to ld-linux if patching is impossible, so claude always starts. The patch
# re-applies automatically after each auto-update (new versions ship unpatched).
# See: https://github.com/microsoft/WSL/issues/8219
#      https://github.com/microsoft/WSL/issues/12359
function claude --description 'Claude Code (native install + WSL1 p_align patch + dangerously-skip-permissions)'
    # Optional version pin: `CLAUDE_VERSION=2.1.159 claude`. Accepts a bare version
    # (resolved under versions/), an absolute path to a binary, or 'latest'/unset
    # for the newest (the ~/.local/bin/claude symlink). Same wrapper behavior either way.
    set -l bin "$HOME/.local/bin/claude"
    if set -q CLAUDE_VERSION; and test -n "$CLAUDE_VERSION"; and test "$CLAUDE_VERSION" != latest
        if string match -qr '^/' -- "$CLAUDE_VERSION"
            set bin "$CLAUDE_VERSION"
        else
            # Bare version: prefer the live managed dir, then the persistent archive
            # (~/.local/share/cc-versions) which the auto-updater's GC never prunes.
            set bin "$HOME/.local/share/claude/versions/$CLAUDE_VERSION"
            if not test -x "$bin"
                set bin "$HOME/.local/share/cc-versions/$CLAUDE_VERSION"
            end
        end
        if not test -x "$bin"
            echo "claude: version '$CLAUDE_VERSION' not found" >&2
            echo "managed:" (command ls "$HOME/.local/share/claude/versions/" 2>/dev/null) >&2
            echo "archived:" (command ls "$HOME/.local/share/cc-versions/" 2>/dev/null) >&2
            return 127
        end
    end
    if not test -x "$bin"
        echo "claude: native install not found at $bin" >&2
        return 127
    end
    set -l real (realpath "$bin")

    # Non-ELF (script shim): run directly.
    if test (head -c4 "$real" 2>/dev/null | command od -An -tx1 -N4 | string trim) != "7f 45 4c 46"
        command "$real" --dangerously-skip-permissions $argv
        return $status
    end

    # ELF: make it directly executable on WSL1, then run it directly so
    # process.execPath is the real binary. Fall back to ld-linux if we can't.
    if claude-wsl-elf-fix "$real"
        command "$real" --dangerously-skip-permissions $argv
    else
        /lib64/ld-linux-x86-64.so.2 "$real" --dangerously-skip-permissions $argv
    end
end
