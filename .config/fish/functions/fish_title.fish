function fish_title
    if set -q PROJECT_TAB_TITLE
        echo $PROJECT_TAB_TITLE
    else
        echo (status current-command) (prompt_pwd)
    end
end
