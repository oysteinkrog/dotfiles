function fish_title
    if set -q GROVE_TAB_TITLE
        echo $GROVE_TAB_TITLE
    else if set -q PROJECT_TAB_TITLE
        echo $PROJECT_TAB_TITLE
    else
        echo (status current-command) (prompt_pwd)
    end
end
