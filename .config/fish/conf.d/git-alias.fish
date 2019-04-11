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
# abbres
#

# Git
abbr g 'git'

# Branch (b)
abbr gb 'git branch'
abbr gba 'git branch --all --verbose'
abbr gbc 'git checkout -b'
abbr gbd 'git branch --delete'
abbr gbD 'git branch --delete --force'
abbr gbl 'git branch --verbose'
abbr gbL 'git branch --all --verbose'
abbr gbm 'git branch --move'
abbr gbM 'git branch --move --force'
abbr gbr 'git branch --move'
abbr gbR 'git branch --move --force'
abbr gbs 'git show-branch'
abbr gbS 'git show-branch --all'
abbr gbv 'git branch --verbose'
abbr gbV 'git branch --verbose --verbose'
abbr gbx 'git branch --delete'
abbr gbX 'git branch --delete --force'

# Commit (c)
abbr gc 'git commit --verbose'
abbr gca 'git commit --verbose --all'
abbr gcm 'git commit --message'
abbr gcS 'git commit -S --verbose'
abbr gcSa 'git commit -S --verbose --all'
abbr gcSm 'git commit -S --message'
abbr gcam 'git commit --all --message'
abbr gcma 'git commit --all --message'
abbr gcx 'git commit --fixup'
abbr gco 'git checkout'
abbr gcO 'git checkout --patch'
abbr gcf 'git commit --amend --reuse-message HEAD'
abbr gcSf 'git commit -S --amend --reuse-message HEAD'
abbr gcF 'git commit --verbose --amend'
abbr gcSF 'git commit -S --verbose --amend'
abbr gcp 'git cherry-pick --ff'
abbr gcpx 'git cherry-pick -x'
abbr gcpff 'git cherry-pick --ff'
abbr gcP 'git cherry-pick --no-commit'
abbr gcpa 'git cherry-pick --abort'
abbr gcpc 'git cherry-pick --continue'
abbr gcr 'git revert'
abbr gcR 'git reset "HEAD^"'
abbr gcs 'git show'
abbr gcsS 'git show --pretty=short --show-signature'
abbr gcl 'git-commit-lost'
abbr gcy 'git cherry -v --abbrev'
abbr gcY 'git cherry -v'

# Conflict (C)
abbr gCl 'git --no-pager diff --name-only --diff-filter=U'
abbr gCa 'git add (gCl)'
abbr gCe 'git mergetool (gCl)'
abbr gCo 'git checkout --ours --'
abbr gCO 'gCo (gCl)'
abbr gCt 'git checkout --theirs --'
abbr gCT 'gCt (gCl)'

# Data (d)
abbr gd 'git ls-files'
abbr gdc 'git ls-files --cached'
abbr gdx 'git ls-files --deleted'
abbr gdm 'git ls-files --modified'
abbr gdu 'git ls-files --other --exclude-standard'
abbr gdk 'git ls-files --killed'
abbr gdi 'git status --porcelain --short --ignored | sed -n "s/^!! //p"'

# Fetch (f)
abbr gf 'git fetch'
abbr gfa 'git fetch --all'
abbr gfc 'git clone'
abbr gfcr 'git clone --recurse-submodules'
abbr gfm 'git pull'
abbr gfr 'git pull --rebase'

# Flow (F)
abbr gFi 'git flow init'
abbr gFf 'git flow feature'
abbr gFb 'git flow bugfix'
abbr gFl 'git flow release'
abbr gFh 'git flow hotfix'
abbr gFs 'git flow support'

abbr gFfl 'git flow feature list'
abbr gFfs 'git flow feature start'
abbr gFff 'git flow feature finish'
abbr gFfp 'git flow feature publish'
abbr gFft 'git flow feature track'
abbr gFfd 'git flow feature diff'
abbr gFfr 'git flow feature rebase'
abbr gFfc 'git flow feature checkout'
abbr gFfm 'git flow feature pull'
abbr gFfx 'git flow feature delete'

abbr gFbl 'git flow bugfix list'
abbr gFbs 'git flow bugfix start'
abbr gFbf 'git flow bugfix finish'
abbr gFbp 'git flow bugfix publish'
abbr gFbt 'git flow bugfix track'
abbr gFbd 'git flow bugfix diff'
abbr gFbr 'git flow bugfix rebase'
abbr gFbc 'git flow bugfix checkout'
abbr gFbm 'git flow bugfix pull'
abbr gFbx 'git flow bugfix delete'

abbr gFll 'git flow release list'
abbr gFls 'git flow release start'
abbr gFlf 'git flow release finish'
abbr gFlp 'git flow release publish'
abbr gFlt 'git flow release track'
abbr gFld 'git flow release diff'
abbr gFlr 'git flow release rebase'
abbr gFlc 'git flow release checkout'
abbr gFlm 'git flow release pull'
abbr gFlx 'git flow release delete'

abbr gFhl 'git flow hotfix list'
abbr gFhs 'git flow hotfix start'
abbr gFhf 'git flow hotfix finish'
abbr gFhp 'git flow hotfix publish'
abbr gFht 'git flow hotfix track'
abbr gFhd 'git flow hotfix diff'
abbr gFhr 'git flow hotfix rebase'
abbr gFhc 'git flow hotfix checkout'
abbr gFhm 'git flow hotfix pull'
abbr gFhx 'git flow hotfix delete'

abbr gFsl 'git flow support list'
abbr gFss 'git flow support start'
abbr gFsf 'git flow support finish'
abbr gFsp 'git flow support publish'
abbr gFst 'git flow support track'
abbr gFsd 'git flow support diff'
abbr gFsr 'git flow support rebase'
abbr gFsc 'git flow support checkout'
abbr gFsm 'git flow support pull'
abbr gFsx 'git flow support delete'

# Grep (g)
abbr gg 'git grep'
abbr ggi 'git grep --ignore-case'
abbr ggl 'git grep --files-with-matches'
abbr ggL 'git grep --files-without-matches'
abbr ggv 'git grep --invert-match'
abbr ggw 'git grep --word-regexp'

abbr ggph 'git-getparenthash'

# Index (i)
abbr gia 'git add'
abbr giaa 'git add --all'
abbr giA 'git add --patch'
abbr giu 'git add --update'
abbr gid 'git diff --no-ext-diff --cached'
abbr giD 'git diff --no-ext-diff --cached --word-diff'
abbr gii 'git update-index --assume-unchanged'
abbr giI 'git update-index --no-assume-unchanged'
abbr gir 'git reset'
abbr giR 'git reset --patch'
abbr gix 'git rm -r --cached'
abbr giX 'git rm -rf --cached'

# Log (l)
abbr gl 'git log --topo-order --pretty=format:"$_git_log_medium_format"'
abbr gls 'git log --topo-order --stat --pretty=format:"$_git_log_medium_format"'
abbr glss 'git log --graph --pretty=format:"$_git_log_short_format" --decorate --date=relative'
abbr gld 'git log --topo-order --stat --patch --full-diff --pretty=format:"$_git_log_medium_format"'
abbr glp 'git log --topo-order --stat --patch --pretty=format:"$_git_log_medium_format"'
abbr glo 'git log --topo-order --pretty=format:"$_git_log_oneline_format"'
abbr glg 'git log --topo-order --all --graph --pretty=format:"$_git_log_oneline_format"'
abbr glb 'git log --topo-order --pretty=format:"$_git_log_brief_format"'
abbr glc 'git shortlog --summary --numbered'
abbr glS 'git log --show-signature'
#abbr gll 'git log --oneline "$argv" |awk '{print $1}' |tac|xargs'

# Merge (m)
abbr gm 'git merge'
abbr gmC 'git merge --no-commit'
abbr gmF 'git merge --no-ff'
abbr gma 'git merge --abort'
abbr gmt 'git mergetool'

# Push (p)
abbr gp 'git push'
abbr gpf 'git push --force-with-lease'
abbr gpF 'git push --force'
abbr gpa 'git push --all'
abbr gpA 'git push --all && git push --tags'
abbr gpt 'git push --tags'
abbr gpc 'git push --set-upstream origin (__fish_git_current_branch)'
abbr gpp 'git pull origin (__fish_git_current_branch) && git push origin (__fish_git_current_branch)'

# Rebase (r)
abbr gr 'git rebase'
abbr gru 'git rebase @\{u\}'
abbr gra 'git rebase --abort'
abbr grc 'git rebase --continue'
abbr gri 'git rebase --interactive'
abbr gria 'git rebase --interactive --autosquash'
abbr griu 'git rebase --interactive @\{u\}' 
abbr griau 'git rebase --interactive --autosquash @\{u\}'
abbr grs 'git rebase --skip'

# Remote (R)
abbr gR 'git remote'
abbr gRl 'git remote --verbose'
abbr gRa 'git remote add'
abbr gRx 'git remote rm'
abbr gRm 'git remote rename'
abbr gRu 'git remote update'
abbr gRp 'git remote prune'
abbr gRs 'git remote show'
abbr gRb 'git-hub-browse'

# Stash (s)
abbr gs 'git stash'
abbr gsa 'git stash apply'
abbr gsx 'git stash drop'
abbr gsX 'git-stash-clear-interactive'
abbr gsl 'git stash list'
abbr gsL 'git-stash-dropped'
abbr gsd 'git stash show --patch --stat'
abbr gski 'git stash --keep-index'
abbr gsp 'git stash pop'
abbr gsP 'git stash --patch'
abbr gsr 'git-stash-recover'
abbr gss 'git stash save --include-untracked'
abbr gsS 'git stash save --patch --no-keep-index'
abbr gsw 'git stash save --include-untracked --keep-index'

# Submodule (S)
abbr gS 'git submodule'
abbr gSa 'git submodule add'
abbr gSf 'git submodule foreach'
abbr gSi 'git submodule init'
abbr gSI 'git submodule update --init --recursive'
abbr gSl 'git submodule status'
abbr gSm 'git-submodule-move'
abbr gSs 'git submodule sync'
abbr gSu 'git submodule foreach git pull origin master'
abbr gSx 'git-submodule-remove'

# Tag (t)
abbr gt 'git tag'
abbr gtl 'git tag -l'
abbr gts 'git tag -s'
abbr gtv 'git verify-tag'

# Working Copy (w)
abbr gws 'git status --ignore-submodules=$_git_status_ignore_submodules --short'
abbr gwS 'git status --ignore-submodules=$_git_status_ignore_submodules'
abbr gwd 'git diff --no-ext-diff'
abbr gwD 'git diff --no-ext-diff --word-diff'
abbr gwr 'git reset --soft'
abbr gwrm 'git reset --mixed'
abbr gwR 'git reset --hard'
abbr gwc 'git clean -n'
abbr gwC 'git clean -f'
abbr gwx 'git rm -r'
abbr gwX 'git rm -rf'
