#
# Defines Git abbres.
#
# Authors:
#   Øystein Krog <oystein.krog@gmail.com>
#   Sorin Ionescu <sorin.ionescu@gmail.com>

# Log
set _git_log_medium_format '%C(bold)Commit:%C(reset) %C(green)%H%C(red)%d%n%C(bold)Author:%C(reset) %C(cyan)%an <%ae>%n%C(bold)Date:%C(reset)   %C(blue)%ai (%ar)%C(reset)%n%+B'
set _git_log_oneline_format '%C(green)%h%C(reset) %s%C(red)%d%C(reset)%n'
set _git_log_brief_format '%C(green)%h%C(reset) %s%n%C(blue)(%ar by %an)%C(red)%d%C(reset)%n'
set _git_log_short_format '%C(green)%h %C(yellow)[%<(14)%ad] %Creset%s%Cred%d%Cblue [%an] [%cn]'

# Status
set _git_status_ignore_submodules 'none'

#
# functions
#
#

# strip out ansi color and movement sequences
function strip_ansi
  sed "s,\x1B\[[0-9;]*[a-zA-Z],,g" $argv
end

# Transform branch arguments: if single argument is just digits, prepend "issue/"
function _git_transform_branch_args
  if test (count $argv) -eq 1 && string match -r '^\d+$' $argv[1] >/dev/null
    echo "issue/$argv[1]"
  else
    for arg in $argv
      echo $arg
    end
  end
end

# strip out ansi color sequences
function strip_colors
  sed "s,\x1B\[[0-9;]*m,,g"
end

function select_line
  fzf --reverse --ansi --no-sort $argv | strip_ansi
  #fzy $argv | strip_ansi
  #~/.skim/bin/sk --ansi --layout=reverse-list $argv
end

function git_log_get_commit
  cut -d' ' -f2
end

function git_status_get_commit
  awk '{print $2}'
  #cut -d' ' -f3
end

function select_line_commit
  select_line | git_log_get_commit
end

function select_line_status
  select_line | git_status_get_commit
end

# Git
function g
  git $argv
end

function gup
  gfr && gRu
end


# Branch (b)
function gb
  git branch --sort=-committerdate $argv
end
abbr -a gba 'git branch --all --verbose'
function gbc
  git checkout -b $argv
end
function gbd
  git branch --delete (_git_transform_branch_args $argv)
end
function gbD
  git branch --delete --force (_git_transform_branch_args $argv)
end
abbr -a gbl 'git branch --verbose'
abbr -a gbL 'git branch --all --verbose'
function gbm
  git branch --move $argv
end
function gbM
  git branch --move --force $argv
end
function gbr
  git branch --move $argv
end
function gbR
  git branch --move --force $argv
end
abbr -a gbs 'git show-branch'
abbr -a gbS 'git show-branch --all'
abbr -a gbv 'git branch --verbose'
abbr -a gbV 'git branch --verbose --verbose'
function gbx
  git branch --delete $argv
end
function gbX
  git branch --delete --force $argv
end

# Issue branch variants (i)
function ib
    gb "issue/$argv"
end

function ibc
    gbc "issue/$argv"
end

function ibd
    gbd "issue/$argv"
end

function ibD
    gbD "issue/$argv"
end

function ibm
    gbm "issue/$argv"
end

function ibM
    gbM "issue/$argv"
end

function ibr
    gbr "issue/$argv"
end

function ibR
    gbR "issue/$argv"
end

function ibx
    gbx "issue/$argv"
end

function ibX
    gbX "issue/$argv"
end

# Commit (c)
abbr -a gc 'git commit --verbose'
abbr -a gca 'git commit --verbose --all'
abbr -a gcm 'git commit --message'
abbr -a gcS 'git commit -S --verbose'
abbr -a gcSa 'git commit -S --verbose --all'
abbr -a gcSm 'git commit -S --message'
abbr -a gcam 'git commit --all --message'
abbr -a gcma 'git commit --all --message'
function gcx
  if count $argv > /dev/null
      git commit --fixup $argv
  else
      git log --graph --pretty=format:"$_git_log_short_format" --decorate --date=relative --color=always | select_line_commit | xargs git commit --fixup
  end
end
function fcx
  gcx $argv
end
function gco
  # If argument is just digits (e.g., "12345"), prepend "issue/" to checkout "issue/12345"
  # Otherwise, pass through arguments unchanged for normal git checkout behavior
  git checkout (_git_transform_branch_args $argv)
end
function fcof
  gws --color=always | git_status_get_commit | xargs git checkout --force
end
abbr -a gcO 'git checkout --patch'
abbr -a gcf 'git commit --amend --reuse-message HEAD'
abbr -a gcSf 'git commit -S --amend --reuse-message HEAD'
abbr -a gcF 'git commit --verbose --amend'
abbr -a gcSF 'git commit -S --verbose --amend'
function gcp
  if test (count $argv) -eq 1 && string match -r '^\d+$' $argv[1] >/dev/null
    git cherry-pick --ff "issue/$argv[1]"
  else
    git cherry-pick --ff $argv
  end
end
function fcp --description 'git cherry pick with line selection'
    glss --color=always $argv | select_line_commit | xargs git cherry-pick --ff
end
function gcpx
  if test (count $argv) -eq 1 && string match -r '^\d+$' $argv[1] >/dev/null
    git cherry-pick -x "issue/$argv[1]"
  else
    git cherry-pick -x $argv
  end
end
function fcpx --description 'git cherry pick -x with line selection'
    glss --color=always $argv | select_line_commit | xargs git cherry-pick --x
end
function gcpff
  if test (count $argv) -eq 1 && string match -r '^\d+$' $argv[1] >/dev/null
    git cherry-pick --ff "issue/$argv[1]"
  else
    git cherry-pick --ff $argv
  end
end
function gcP
  if test (count $argv) -eq 1 && string match -r '^\d+$' $argv[1] >/dev/null
    git cherry-pick --no-commit "issue/$argv[1]"
  else
    git cherry-pick --no-commit $argv
  end
end
abbr -a gcpa 'git cherry-pick --abort'
abbr -a gcpc 'git cherry-pick --continue'
abbr -a gcr 'git revert'
function fcr
  glss --color=always $argv | select_line_commit | xargs git revert $argv
end
function gcR
  git reset "HEAD^" $argv
end
function gcs
  if test (count $argv) -eq 1 && string match -r '^\d+$' $argv[1] >/dev/null
    git show "issue/$argv[1]"
  else
    git show $argv
  end
end
function gcsS
  if test (count $argv) -eq 1 && string match -r '^\d+$' $argv[1] >/dev/null
    git show --pretty=short --show-signature "issue/$argv[1]"
  else
    git show --pretty=short --show-signature $argv
  end
end
abbr -a gcl 'git-commit-lost'
abbr -a gcy 'git cherry -v --abbrev'
abbr -a gcY 'git cherry -v'

# Conflict (C)
function gCl
  git --no-pager diff --name-only --diff-filter=U $argv
end
function gCa
  git add (gCl) $argv
end
function gCe
  git mergetool (gCl) $argv
end
function gCo
  git checkout --ours -- $argv
end
function gCO
  gCo (gCl) $argv
end
function gCt
  git checkout --theirs -- $argv
end
function gCT
  gCt (gCl) $argv
end

# Data (d)
abbr -a gd 'git ls-files'
abbr -a gdc 'git ls-files --cached'
abbr -a gdx 'git ls-files --deleted'
abbr -a gdm 'git ls-files --modified'
abbr -a gdu 'git ls-files --other --exclude-standard'
abbr -a gdk 'git ls-files --killed'
function gdi
  git status --porcelain --short --ignored | sed -n "s/^!! //p" $argv
end

# Fetch (f)
abbr -a gf 'git fetch'
abbr -a gfa 'git fetch --all'
abbr -a gfc 'git clone'
abbr -a gfcr 'git clone --recurse-submodules'
abbr -a gfm 'git pull'
function gfr
  git pull --rebase $argv
end

# Flow (F)
abbr -a gFi 'git flow init'
abbr -a gFf 'git flow feature'
abbr -a gFb 'git flow bugfix'
abbr -a gFl 'git flow release'
abbr -a gFh 'git flow hotfix'
abbr -a gFs 'git flow support'

abbr -a gFfl 'git flow feature list'
abbr -a gFfs 'git flow feature start'
abbr -a gFff 'git flow feature finish'
abbr -a gFfp 'git flow feature publish'
abbr -a gFft 'git flow feature track'
abbr -a gFfd 'git flow feature diff'
abbr -a gFfr 'git flow feature rebase'
abbr -a gFfc 'git flow feature checkout'
abbr -a gFfm 'git flow feature pull'
abbr -a gFfx 'git flow feature delete'

abbr -a gFbl 'git flow bugfix list'
abbr -a gFbs 'git flow bugfix start'
abbr -a gFbf 'git flow bugfix finish'
abbr -a gFbp 'git flow bugfix publish'
abbr -a gFbt 'git flow bugfix track'
abbr -a gFbd 'git flow bugfix diff'
abbr -a gFbr 'git flow bugfix rebase'
abbr -a gFbc 'git flow bugfix checkout'
abbr -a gFbm 'git flow bugfix pull'
abbr -a gFbx 'git flow bugfix delete'

abbr -a gFll 'git flow release list'
abbr -a gFls 'git flow release start'
abbr -a gFlf 'git flow release finish'
abbr -a gFlp 'git flow release publish'
abbr -a gFlt 'git flow release track'
abbr -a gFld 'git flow release diff'
abbr -a gFlr 'git flow release rebase'
abbr -a gFlc 'git flow release checkout'
abbr -a gFlm 'git flow release pull'
abbr -a gFlx 'git flow release delete'

abbr -a gFhl 'git flow hotfix list'
abbr -a gFhs 'git flow hotfix start'
abbr -a gFhf 'git flow hotfix finish'
abbr -a gFhp 'git flow hotfix publish'
abbr -a gFht 'git flow hotfix track'
abbr -a gFhd 'git flow hotfix diff'
abbr -a gFhr 'git flow hotfix rebase'
abbr -a gFhc 'git flow hotfix checkout'
abbr -a gFhm 'git flow hotfix pull'
abbr -a gFhx 'git flow hotfix delete'

abbr -a gFsl 'git flow support list'
abbr -a gFss 'git flow support start'
abbr -a gFsf 'git flow support finish'
abbr -a gFsp 'git flow support publish'
abbr -a gFst 'git flow support track'
abbr -a gFsd 'git flow support diff'
abbr -a gFsr 'git flow support rebase'
abbr -a gFsc 'git flow support checkout'
abbr -a gFsm 'git flow support pull'
abbr -a gFsx 'git flow support delete'

# Grep (g)
abbr -a gg 'git grep'
abbr -a ggi 'git grep --ignore-case'
abbr -a ggl 'git grep --files-with-matches'
abbr -a ggL 'git grep --files-without-matches'
abbr -a ggv 'git grep --invert-match'
abbr -a ggw 'git grep --word-regexp'

abbr -a ggph 'git-getparenthash'

# Index (i)
abbr -a gia 'git add'
function fia
  git -c color.status=always status --ignore-submodules=$_git_status_ignore_submodules --short $argv | select_line | awk '{print $2}' | xargs git add $argv
end
function fir
  git -c color.status=always status --ignore-submodules=$_git_status_ignore_submodules --short $argv | select_line | awk '{print $2}' | xargs git reset $argv
end
abbr -a giaa 'git add --all'
function giaf
  git add "**/*.$argv"
end
abbr -a giA 'git add --patch'
function fiA
  git -c color.status=always status --ignore-submodules=$_git_status_ignore_submodules --short $argv | select_line_status | awk '{print $2}' | xargs git add --patch $argv
end
abbr -a giu 'git add --update'
abbr -a gid 'git diff --no-ext-diff --cached'
abbr -a giD 'git diff --no-ext-diff --cached --word-diff'
abbr -a gii 'git update-index --assume-unchanged'
abbr -a giI 'git update-index --no-assume-unchanged'
abbr -a gir 'git reset'
abbr -a giR 'git reset --patch'
abbr -a gix 'git rm -r --cached'
abbr -a giX 'git rm -rf --cached'

# Log (l)
function gl
  if test (count $argv) -eq 1 && string match -r '^\d+$' $argv[1] >/dev/null
    git log --topo-order --pretty=format:"$_git_log_medium_format" "issue/$argv[1]"
  else
    git log --topo-order --pretty=format:"$_git_log_medium_format" $argv
  end
end
function gls
  if test (count $argv) -eq 1 && string match -r '^\d+$' $argv[1] >/dev/null
    git log --topo-order --stat --pretty=format:"$_git_log_medium_format" "issue/$argv[1]"
  else
    git log --topo-order --stat --pretty=format:"$_git_log_medium_format" $argv
  end
end
function glss
  git log --graph --pretty=format:"$_git_log_short_format" --decorate --date=relative (_git_transform_branch_args $argv)
end
function gld
  if test (count $argv) -eq 1 && string match -r '^\d+$' $argv[1] >/dev/null
    git log --topo-order --stat --patch --full-diff --pretty=format:"$_git_log_medium_format" "issue/$argv[1]"
  else
    git log --topo-order --stat --patch --full-diff --pretty=format:"$_git_log_medium_format" $argv
  end
end
function fld
  glss --color=always $argv | select_line_commit | xargs git log --topo-order --stat --patch --full-diff --pretty=format:"$_git_log_medium_format" $argv
end
function glp
  if test (count $argv) -eq 1 && string match -r '^\d+$' $argv[1] >/dev/null
    git log --topo-order --stat --patch --pretty=format:"$_git_log_medium_format" "issue/$argv[1]"
  else
    git log --topo-order --stat --patch --pretty=format:"$_git_log_medium_format" $argv
  end
end
function flp
  gwsc | select_line_status | xargs git log --topo-order --stat --patch --pretty=format:"$_git_log_medium_format" $argv 
end
function glo
  if test (count $argv) -eq 1 && string match -r '^\d+$' $argv[1] >/dev/null
    git log --topo-order --pretty=format:"$_git_log_oneline_format" "issue/$argv[1]"
  else
    git log --topo-order --pretty=format:"$_git_log_oneline_format" $argv
  end
end
function glg
  git log --topo-order --all --graph --pretty=format:"$_git_log_oneline_format" $argv
end
function glb
  if test (count $argv) -eq 1 && string match -r '^\d+$' $argv[1] >/dev/null
    git log --topo-order --pretty=format:"$_git_log_brief_format" "issue/$argv[1]"
  else
    git log --topo-order --pretty=format:"$_git_log_brief_format" $argv
  end
end
abbr -a glc 'git shortlog --summary --numbered'
function glS
  if test (count $argv) -eq 1 && string match -r '^\d+$' $argv[1] >/dev/null
    git log --show-signature "issue/$argv[1]"
  else
    git log --show-signature $argv
  end
end
function gll
    git log --oneline "$argv" |awk  \'{print $1}\' |tac|xargs $argv
end

# Merge (m)
function gm
  if test (count $argv) -eq 1 && string match -r '^\d+$' $argv[1] >/dev/null
    git merge "issue/$argv[1]"
  else
    git merge $argv
  end
end
abbr -a gmC 'git merge --no-commit'
abbr -a gmF 'git merge --no-ff'
abbr -a gma 'git merge --abort'
abbr -a gmt 'git mergetool'

# Push (p)
abbr -a gp 'git push'
abbr -a gpf 'git push --force-with-lease'
abbr -a gpF 'git push --force'
abbr -a gpa 'git push --all'
function gpA
  git push --all && git push --tags $argv
end
abbr -a gpt 'git push --tags'
function gpc
  git push --set-upstream origin (__fish_git_current_branch) $argv
end
function gpp
  git pull origin (__fish_git_current_branch) && git push origin (__fish_git_current_branch) $argv
end

# Rebase (r)
# `gr` (git rebase) removed 2026-07-06: it shadowed the grove
# shorthand autoloaded from functions/gr.fish. Use gri/gru/gra/grc etc.
function gru
  git rebase @\{u\} $argv
end
abbr -a gra 'git rebase --abort'
abbr -a grc 'git rebase --continue'
abbr -a gri 'git rebase --interactive'
abbr -a gria 'git rebase --interactive --autosquash'
function griu
  git rebase --interactive @\{u\} $argv
end
function griau
  git rebase --interactive --autosquash @\{u\} $argv
end
abbr -a grs 'git rebase --skip'

# Remote (R)
abbr -a gR 'git remote'
abbr -a gRl 'git remote --verbose'
abbr -a gRa 'git remote add'
abbr -a gRx 'git remote rm'
abbr -a gRm 'git remote rename'
function gRu
  git remote update $argv
end
abbr -a gRp 'git remote prune'
abbr -a gRs 'git remote show'
abbr -a gRb 'git-hub-browse'

# Stash (s)
abbr -a gs 'git stash'
abbr -a gsa 'git stash apply'
abbr -a gsx 'git stash drop'
abbr -a gsX 'git-stash-clear-interactive'
abbr -a gsl 'git stash list'
abbr -a gsL 'git-stash-dropped'
abbr -a gsd 'git stash show --patch --stat'
abbr -a gski 'git stash --keep-index'
abbr -a gsp 'git stash pop'
abbr -a gsP 'git stash --patch'
abbr -a gsr 'git-stash-recover'
abbr -a gss 'git stash save --include-untracked'
abbr -a gsS 'git stash save --patch --no-keep-index'
abbr -a gsw 'git stash save --include-untracked --keep-index'

# Submodule (S)
abbr -a gS 'git submodule'
abbr -a gSa 'git submodule add'
abbr -a gSf 'git submodule foreach'
abbr -a gSi 'git submodule init'
abbr -a gSI 'git submodule update --init --recursive'
abbr -a gSl 'git submodule status'
abbr -a gSm 'git-submodule-move'
abbr -a gSs 'git submodule sync'
abbr -a gSu 'git submodule foreach git pull origin master'
abbr -a gSx 'git-submodule-remove'

# Tag (t)
abbr -a gt 'git tag'
abbr -a gtl 'git tag -l'
abbr -a gts 'git tag -s'
abbr -a gtv 'git verify-tag'

# Working Copy (w)
function gws
  git status --ignore-submodules=$_git_status_ignore_submodules --short $argv
end
function gwsc
  git -c color.status=always status --ignore-submodules=$_git_status_ignore_submodules --short $argv
end
function gwS
  git status --ignore-submodules=$_git_status_ignore_submodules $argv
end
function gwd
  if test (count $argv) -eq 1 && string match -r '^\d+$' $argv[1] >/dev/null
    git diff --no-ext-diff "issue/$argv[1]"
  else
    git diff --no-ext-diff $argv
  end
end
function gwD
  if test (count $argv) -eq 1 && string match -r '^\d+$' $argv[1] >/dev/null
    git diff --no-ext-diff --word-diff "issue/$argv[1]"
  else
    git diff --no-ext-diff --word-diff $argv
  end
end
function fwd
  gws --color=always | select_line_status | xargs git diff --no-ext-diff $argv
end
function gwr
  git reset --soft (_git_transform_branch_args $argv)
end
abbr -a gwrm 'git reset --mixed'
function gwR
  git reset --hard (_git_transform_branch_args $argv)
end
abbr -a gwc 'git clean -n'
abbr -a gwC 'git clean -f'
abbr -a gwx 'git rm -r'
abbr -a gwX 'git rm -rf'
