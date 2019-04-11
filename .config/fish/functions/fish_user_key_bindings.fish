fish_vi_keybindings

# vi mode colemak/custom overrides
#
# Default (command) mode
bind -s --preset -M default n backward-char
bind -s --preset -M default i forward-char
bind -s --preset -m insert l force-repaint
bind -s --preset -m insert L beginning-of-line force-repaint

bind -s --preset \cr fzy_select_history

bind -s --preset u up-or-search
bind -s --preset e down-or-search
bind \cr re_search
