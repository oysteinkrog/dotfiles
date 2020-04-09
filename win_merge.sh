#!/usr/bin/env sh

#LOCAL = $2
#REMOTE = $3
#BASE = $4
#MERGED = $5

get_filename() {
    echo "$1" | sed 's:.*/::'
}

resolve_path() {
    pushd "$(dirname "$1")" >/dev/null
    local base_path="$(pwd -P | sed 's:/mnt/::;s_/_:/_;s:/:\\:g')"
    echo "$base_path\\$(get_filename "$1")"
    popd >/dev/null
}

do_diff() {
    local tmp_local="$(get_filename $1)"
    local remote="$(resolve_path "$2")"
    cp "$1" "/mnt/c/Windows/Temp/$tmp_local"
    "$VS_MERGE" /t "C:\\Windows\\Temp\\$tmp_local" "$remote" Source Target
}

winpath()
{
    set -e
    if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null ; then
        $(wslpath -wa $@)
    else
        $(cygpath -wa $@)
        echo "Anything else"
    fi
    #if {
        #[ -e /proc/sys/kernel/osrelease ] &&
            #IFS= read -r os < /proc/sys/kernel/osrelease &&
            #[[ $os == *Microsoft  ]]
    #} ; then
    #else
    #fi
}

case "$1" in
    diff)  do_diff "$2" "$3" ;;
    semanticmerge)
        TOOL='/mnt/c/Users/oyste/AppData/Local/semanticmerge/semanticmergetool.exe'
        // remove first parameter
        shift
        "$TOOL" $@ ;;
    tortoisemerge)
        TOOL='/mnt/c/Program Files/TortoiseGit/bin/TortoiseGitMerge.exe'
        "$TOOL" -mine:"$(wslpath -wa $2)" -theirs:"$(wslpath -wa $3)" -base:"$(wslpath -wa $4)" -merged:"$(wslpath -wa $5)" ;;
esac
