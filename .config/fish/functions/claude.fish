# WSL1 workaround: lxcore.sys rejects ELF binaries with mismatched PT_LOAD p_align values.
# Bun-compiled binaries (like Claude Code) trigger this bug.
# Invoking via ld-linux bypasses the kernel's broken ELF parser.
# See: https://github.com/microsoft/WSL/issues/8219
#      https://github.com/microsoft/WSL/issues/12359
function claude --description 'Claude Code (native install + WSL1 ld-linux workaround + dangerously-skip-permissions)'
    set -l bin "$HOME/.local/bin/claude"
    if not test -x "$bin"
        echo "claude: native install not found at $bin" >&2
        return 127
    end
    set -l real (realpath "$bin")

    # Only use ld-linux workaround for ELF binaries (not scripts)
    if test (head -c4 "$real" 2>/dev/null | command od -An -tx1 -N4 | string trim) = "7f 45 4c 46"
        /lib64/ld-linux-x86-64.so.2 "$real" --dangerously-skip-permissions $argv
    else
        command "$real" --dangerously-skip-permissions $argv
    end
end
