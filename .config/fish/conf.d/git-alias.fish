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
    echo $argv
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
  git branch $argv
end
function gba
  git branch --all --verbose $argv
end
function gbc
  git checkout -b $argv
end
function gbd
  git branch --delete $argv
end
function gbD
  git branch --delete --force $argv
end
function gbl
  git branch --verbose $argv
end
function gbL
  git branch --all --verbose $argv
end
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
function gbs
  git show-branch $argv
end
function gbS
  git show-branch --all $argv
end
function gbv
  git branch --verbose $argv
end
function gbV
  git branch --verbose --verbose $argv
end
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
function gc
  git commit --verbose $argv
end
function gca
  git commit --verbose --all $argv
end
function gcm
  git commit --message $argv
end
function gcS
  git commit -S --verbose $argv
end
function gcSa
  git commit -S --verbose --all $argv
end
function gcSm
  git commit -S --message $argv
end
function gcam
  git commit --all --message $argv
end
function gcma
  git commit --all --message $argv
end
function gcx
  if count $argv > /dev/null
      git commit --fixup $argv
  else
      glss --color=always $argv | select_line_commit | xargs git commit --fixup
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
function gcO
  git checkout --patch $argv
end
function gcf
  git commit --amend --reuse-message HEAD $argv
end
function gcSf
  git commit -S --amend --reuse-message HEAD $argv
end
function gcF
  git commit --verbose --amend $argv
end
function gcSF
  git commit -S --verbose --amend $argv
end
function gcp
  git cherry-pick --ff (_git_transform_branch_args $argv)
end
function fcp --description 'git cherry pick with line selection'
    glss --color=always $argv | select_line_commit | xargs git cherry-pick --ff
end
function gcpx
  git cherry-pick -x (_git_transform_branch_args $argv)
end
function fcpx --description 'git cherry pick -x with line selection'
    glss --color=always $argv | select_line_commit | xargs git cherry-pick --x
end
function gcpff
  git cherry-pick --ff (_git_transform_branch_args $argv)
end
function gcP
  git cherry-pick --no-commit (_git_transform_branch_args $argv)
end
function gcpa
  git cherry-pick --abort $argv
end
function gcpc
  git cherry-pick --continue $argv
end
function gcr
  git revert $argv
end
function fcr
  glss --color=always $argv | select_line_commit | xargs git revert $argv
end
function gcR
  git reset "HEAD^" $argv
end
function gcs
  git show (_git_transform_branch_args $argv)
end
function gcsS
  git show --pretty=short --show-signature (_git_transform_branch_args $argv)
end
function gcl
  git-commit-lost $argv
end
function gcy
  git cherry -v --abbrev $argv
end
function gcY
  git cherry -v $argv
end

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
function gd
  git ls-files $argv
end
function gdc
  git ls-files --cached $argv
end
function gdx
  git ls-files --deleted $argv
end
function gdm
  git ls-files --modified $argv
end
function gdu
  git ls-files --other --exclude-standard $argv
end
function gdk
  git ls-files --killed $argv
end
function gdi
  git status --porcelain --short --ignored | sed -n "s/^!! //p" $argv
end

# Fetch (f)
function gf
  git fetch $argv
end
function gfa
  git fetch --all $argv
end
function gfc
  git clone $argv
end
function gfcr
  git clone --recurse-submodules $argv
end
function gfm
  git pull $argv
end
function gfr
  git pull --rebase $argv
end

# Flow (F)
function gFi
  git flow init $argv
end
function gFf
  git flow feature $argv
end
function gFb
  git flow bugfix $argv
end
function gFl
  git flow release $argv
end
function gFh
  git flow hotfix $argv
end
function gFs
  git flow support $argv
end

function gFfl
  git flow feature list $argv
end
function gFfs
  git flow feature start $argv
end
function gFff
  git flow feature finish $argv
end
function gFfp
  git flow feature publish $argv
end
function gFft
  git flow feature track $argv
end
function gFfd
  git flow feature diff $argv
end
function gFfr
  git flow feature rebase $argv
end
function gFfc
  git flow feature checkout $argv
end
function gFfm
  git flow feature pull $argv
end
function gFfx
  git flow feature delete $argv
end

function gFbl
  git flow bugfix list $argv
end
function gFbs
  git flow bugfix start $argv
end
function gFbf
  git flow bugfix finish $argv
end
function gFbp
  git flow bugfix publish $argv
end
function gFbt
  git flow bugfix track $argv
end
function gFbd
  git flow bugfix diff $argv
end
function gFbr
  git flow bugfix rebase $argv
end
function gFbc
  git flow bugfix checkout $argv
end
function gFbm
  git flow bugfix pull $argv
end
function gFbx
  git flow bugfix delete $argv
end

function gFll
  git flow release list $argv
end
function gFls
  git flow release start $argv
end
function gFlf
  git flow release finish $argv
end
function gFlp
  git flow release publish $argv
end
function gFlt
  git flow release track $argv
end
function gFld
  git flow release diff $argv
end
function gFlr
  git flow release rebase $argv
end
function gFlc
  git flow release checkout $argv
end
function gFlm
  git flow release pull $argv
end
function gFlx
  git flow release delete $argv
end

function gFhl
  git flow hotfix list $argv
end
function gFhs
  git flow hotfix start $argv
end
function gFhf
  git flow hotfix finish $argv
end
function gFhp
  git flow hotfix publish $argv
end
function gFht
  git flow hotfix track $argv
end
function gFhd
  git flow hotfix diff $argv
end
function gFhr
  git flow hotfix rebase $argv
end
function gFhc
  git flow hotfix checkout $argv
end
function gFhm
  git flow hotfix pull $argv
end
function gFhx
  git flow hotfix delete $argv
end

function gFsl
  git flow support list $argv
end
function gFss
  git flow support start $argv
end
function gFsf
  git flow support finish $argv
end
function gFsp
  git flow support publish $argv
end
function gFst
  git flow support track $argv
end
function gFsd
  git flow support diff $argv
end
function gFsr
  git flow support rebase $argv
end
function gFsc
  git flow support checkout $argv
end
function gFsm
  git flow support pull $argv
end
function gFsx
  git flow support delete $argv
end

# Grep (g)
function gg
  git grep $argv
end
function ggi
  git grep --ignore-case $argv
end
function ggl
  git grep --files-with-matches $argv
end
function ggL
  git grep --files-without-matches $argv
end
function ggv
  git grep --invert-match $argv
end
function ggw
  git grep --word-regexp $argv
end

function ggph
  git-getparenthash $argv
end

# Index (i)
function gia
  git add $argv
end
function fia
  git -c color.status=always status --ignore-submodules=$_git_status_ignore_submodules --short $argv | select_line | awk '{print $2}' | xargs git add $argv
end
function fir
  git -c color.status=always status --ignore-submodules=$_git_status_ignore_submodules --short $argv | select_line | awk '{print $2}' | xargs git reset $argv
end
function giaa
  git add --all $argv
end
function giaf
  git add "**/*.$argv"
end
function giA
  git add --patch $argv
end
function fiA
  git -c color.status=always status --ignore-submodules=$_git_status_ignore_submodules --short $argv | select_line_status | awk '{print $2}' | xargs git add --patch $argv
end
function giu
  git add --update $argv
end
function gid
  git diff --no-ext-diff --cached $argv
end
function giD
  git diff --no-ext-diff --cached --word-diff $argv
end
function gii
  git update-index --assume-unchanged $argv
end
function giI
  git update-index --no-assume-unchanged $argv
end
function gir
  git reset $argv
end
function giR
  git reset --patch $argv
end
function gix
  git rm -r --cached $argv
end
function giX
  git rm -rf --cached $argv
end

# Log (l)
function gl
  git log --topo-order --pretty=format:"$_git_log_medium_format" (_git_transform_branch_args $argv)
end
function gls
  git log --topo-order --stat --pretty=format:"$_git_log_medium_format" (_git_transform_branch_args $argv)
end
function glss
  git log --graph --pretty=format:"$_git_log_short_format" --decorate --date=relative (_git_transform_branch_args $argv)
end
function gld
  git log --topo-order --stat --patch --full-diff --pretty=format:"$_git_log_medium_format" (_git_transform_branch_args $argv)
end
function fld
  glss --color=always $argv | select_line_commit | xargs git log --topo-order --stat --patch --full-diff --pretty=format:"$_git_log_medium_format" $argv
end
function glp
  git log --topo-order --stat --patch --pretty=format:"$_git_log_medium_format" (_git_transform_branch_args $argv)
end
function flp
  gwsc | select_line_status | xargs git log --topo-order --stat --patch --pretty=format:"$_git_log_medium_format" $argv 
end
function glo
  git log --topo-order --pretty=format:"$_git_log_oneline_format" (_git_transform_branch_args $argv)
end
function glg
  git log --topo-order --all --graph --pretty=format:"$_git_log_oneline_format" $argv
end
function glb
  git log --topo-order --pretty=format:"$_git_log_brief_format" (_git_transform_branch_args $argv)
end
function glc
  git shortlog --summary --numbered $argv
end
function glS
  git log --show-signature (_git_transform_branch_args $argv)
end
function gll
    git log --oneline "$argv" |awk  \'{print $1}\' |tac|xargs $argv
end

# Merge (m)
function gm
  git merge (_git_transform_branch_args $argv)
end
function gmC
  git merge --no-commit $argv
end
function gmF
  git merge --no-ff $argv
end
function gma
  git merge --abort $argv
end
function gmt
  git mergetool $argv
end

# Push (p)
function gp
  git push $argv
end
function gpf
  git push --force-with-lease $argv
end
function gpF
  git push --force $argv
end
function gpa
  git push --all $argv
end
function gpA
  git push --all && git push --tags $argv
end
function gpt
  git push --tags $argv
end
function gpc
  git push --set-upstream origin (__fish_git_current_branch) $argv
end
function gpp
  git pull origin (__fish_git_current_branch) && git push origin (__fish_git_current_branch) $argv
end

# Rebase (r)
function gr
  git rebase (_git_transform_branch_args $argv)
end
function gru
  git rebase @\{u\} $argv
end
function gra
  git rebase --abort $argv
end
function grc
  git rebase --continue $argv
end
function gri
  git rebase --interactive $argv
end
function gria
  git rebase --interactive --autosquash $argv
end
function griu
  git rebase --interactive @\{u\} $argv
end 
function griau
  git rebase --interactive --autosquash @\{u\} $argv
end
function grs
  git rebase --skip $argv
end

# Remote (R)
function gR
  git remote $argv
end
function gRl
  git remote --verbose $argv
end
function gRa
  git remote add $argv
end
function gRx
  git remote rm $argv
end
function gRm
  git remote rename $argv
end
function gRu
  git remote update $argv
end
function gRp
  git remote prune $argv
end
function gRs
  git remote show $argv
end
function gRb
  git-hub-browse $argv
end

# Stash (s)
function gs
  git stash $argv
end
function gsa
  git stash apply $argv
end
function gsx
  git stash drop $argv
end
function gsX
  git-stash-clear-interactive $argv
end
function gsl
  git stash list $argv
end
function gsL
  git-stash-dropped $argv
end
function gsd
  git stash show --patch --stat $argv
end
function gski
  git stash --keep-index $argv
end
function gsp
  git stash pop $argv
end
function gsP
  git stash --patch $argv
end
function gsr
  git-stash-recover $argv
end
function gss
  git stash save --include-untracked $argv
end
function gsS
  git stash save --patch --no-keep-index $argv
end
function gsw
  git stash save --include-untracked --keep-index $argv
end

# Submodule (S)
function gS
  git submodule $argv
end
function gSa
  git submodule add $argv
end
function gSf
  git submodule foreach $argv
end
function gSi
  git submodule init $argv
end
function gSI
  git submodule update --init --recursive $argv
end
function gSl
  git submodule status $argv
end
function gSm
  git-submodule-move $argv
end
function gSs
  git submodule sync $argv
end
function gSu
  git submodule foreach git pull origin master $argv
end
function gSx
  git-submodule-remove $argv
end

# Tag (t)
function gt
  git tag $argv
end
function gtl
  git tag -l $argv
end
function gts
  git tag -s $argv
end
function gtv
  git verify-tag $argv
end

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
  git diff --no-ext-diff (_git_transform_branch_args $argv)
end
function gwD
  git diff --no-ext-diff --word-diff (_git_transform_branch_args $argv)
end
function fwd
  gws --color=always | select_line_status | xargs git diff --no-ext-diff $argv
end
function gwr
  git reset --soft $argv
end
function gwrm
  git reset --mixed $argv
end
function gwR
  git reset --hard $argv
end
function gwc
  git clean -n $argv
end
function gwC
  git clean -f $argv
end
function gwx
  git rm -r $argv
end
function gwX
  git rm -rf $argv
end
