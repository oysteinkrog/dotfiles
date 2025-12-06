# Completions for git alias functions
# Define local helper functions that work even before git.fish is loaded

function __git_alias_branches
    command git for-each-ref --format='%(refname:strip=2)' refs/heads/ refs/remotes/ 2>/dev/null
end

function __git_alias_local_branches
    command git for-each-ref --format='%(refname:strip=2)' refs/heads/ 2>/dev/null
end

function __git_alias_tags
    command git tag --sort=-creatordate 2>/dev/null
end

function __git_alias_remotes
    command git remote 2>/dev/null
end

# Checkout (gco) - branches and tags
complete -c gco -f -a '(__git_alias_branches)'
complete -c gco -f -a '(__git_alias_tags)'

# Branch delete (gbd, gbD, gbx, gbX) - local branches only
complete -c gbd -f -a '(__git_alias_local_branches)'
complete -c gbD -f -a '(__git_alias_local_branches)'
complete -c gbx -f -a '(__git_alias_local_branches)'
complete -c gbX -f -a '(__git_alias_local_branches)'

# Branch move/rename (gbm, gbM, gbr, gbR)
complete -c gbm -f -a '(__git_alias_local_branches)'
complete -c gbM -f -a '(__git_alias_local_branches)'
complete -c gbr -f -a '(__git_alias_local_branches)'
complete -c gbR -f -a '(__git_alias_local_branches)'

# Issue branch variants
complete -c ibd -f -a '(__git_alias_local_branches)'
complete -c ibD -f -a '(__git_alias_local_branches)'
complete -c ibm -f -a '(__git_alias_local_branches)'
complete -c ibM -f -a '(__git_alias_local_branches)'
complete -c ibr -f -a '(__git_alias_local_branches)'
complete -c ibR -f -a '(__git_alias_local_branches)'
complete -c ibx -f -a '(__git_alias_local_branches)'
complete -c ibX -f -a '(__git_alias_local_branches)'

# Merge (gm) - branches
complete -c gm -f -a '(__git_alias_branches)'

# Rebase (gr, gri, gria, griu, griau) - branches
complete -c gr -f -a '(__git_alias_branches)'
complete -c gri -f -a '(__git_alias_branches)'
complete -c gria -f -a '(__git_alias_branches)'
complete -c griu -f -a '(__git_alias_branches)'
complete -c griau -f -a '(__git_alias_branches)'

# Cherry-pick (gcp, gcP, gcpx, gcpff) - branches
complete -c gcp -f -a '(__git_alias_branches)'
complete -c gcP -f -a '(__git_alias_branches)'
complete -c gcpx -f -a '(__git_alias_branches)'
complete -c gcpff -f -a '(__git_alias_branches)'

# Show (gcs, gcsS) - branches
complete -c gcs -f -a '(__git_alias_branches)'
complete -c gcsS -f -a '(__git_alias_branches)'

# Reset (gwr, gwR, gir) - branches
complete -c gwr -f -a '(__git_alias_branches)'
complete -c gwR -f -a '(__git_alias_branches)'
complete -c gir -f -a '(__git_alias_branches)'

# Diff (gwd, gwD) - branches
complete -c gwd -f -a '(__git_alias_branches)'
complete -c gwD -f -a '(__git_alias_branches)'

# Log variants - branches
complete -c gl -f -a '(__git_alias_branches)'
complete -c gls -f -a '(__git_alias_branches)'
complete -c glss -f -a '(__git_alias_branches)'
complete -c gld -f -a '(__git_alias_branches)'
complete -c glp -f -a '(__git_alias_branches)'
complete -c glo -f -a '(__git_alias_branches)'
complete -c glb -f -a '(__git_alias_branches)'
complete -c glS -f -a '(__git_alias_branches)'

# Push - remotes then branches
complete -c gp -f -a '(__git_alias_remotes)'
complete -c gpf -f -a '(__git_alias_remotes)'
complete -c gpF -f -a '(__git_alias_remotes)'

# Fetch - remotes
complete -c gf -f -a '(__git_alias_remotes)'
complete -c gfa -f -a '(__git_alias_remotes)'

# Remote show - remotes
complete -c gRs -f -a '(__git_alias_remotes)'

# Generic git wrapper - wraps git completions
complete -c g -w git
