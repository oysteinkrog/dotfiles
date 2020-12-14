function fish_user_key_bindings --description "User key bindings for fish"
    fish_vi_key_bindings

    # vi mode colemak/custom overrides
    #
    # Default (command) mode
    bind -s --preset -M default n backward-char
    bind -s --preset -M default i forward-char
    bind -s --preset -m insert l force-repaint
    bind -s --preset -m insert L beginning-of-line force-repaint

    #bind -s --preset \cr fzy_select_history
    bind -s --preset \cr re_search

    bind -s --preset u up-or-search
    bind -s --preset e down-or-search

    #hybrid_bindings
    #fish_vi_key_bindings

    bind \cr re_search
    #bind \cr 'fzy_select_history (commandline -b)'
    bind -M insert \cr 'fzy_select_history (commandline -b)'

    bind \cf 'fzy_select_directory'
end


fzf_key_bindings
