# Print an optspec for argparse to handle cmd's options that are independent of any subcommand.
function __fish_grove_global_optspecs
	string join \n v/verbose repo= h/help V/version
end

function __fish_grove_needs_command
	# Figure out if the current invocation already has a command.
	set -l cmd (commandline -opc)
	set -e cmd[1]
	argparse -s (__fish_grove_global_optspecs) -- $cmd 2>/dev/null
	or return
	if set -q argv[1]
		# Also print the command, so this can be used to figure out what it is.
		echo $argv[1]
		return 1
	end
	return 0
end

function __fish_grove_using_subcommand
	set -l cmd (__fish_grove_needs_command)
	test -z "$cmd"
	and return 1
	contains -- $cmd[1] $argv
end

complete -c grove -n "__fish_grove_needs_command" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_needs_command" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_needs_command" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_needs_command" -s V -l version -d 'Print version'
complete -c grove -n "__fish_grove_needs_command" -f -a "new" -d 'Create a new worktree project'
complete -c grove -n "__fish_grove_needs_command" -f -a "fork" -d 'Fork an existing project\'s branch into a new worktree'
complete -c grove -n "__fish_grove_needs_command" -f -a "list" -d 'List all projects'
complete -c grove -n "__fish_grove_needs_command" -f -a "status" -d 'Show git status for projects'
complete -c grove -n "__fish_grove_needs_command" -f -a "path" -d 'Print the path to a project worktree'
complete -c grove -n "__fish_grove_needs_command" -f -a "cd" -d 'Change directory to a project worktree (prints path for shell integration)'
complete -c grove -n "__fish_grove_needs_command" -f -a "adopt" -d 'Import an existing worktree into the registry'
complete -c grove -n "__fish_grove_needs_command" -f -a "rename" -d 'Rename a project'
complete -c grove -n "__fish_grove_needs_command" -f -a "freeze" -d 'Exclude a project from grove launch'
complete -c grove -n "__fish_grove_needs_command" -f -a "thaw" -d 'Re-include a frozen project in grove launch'
complete -c grove -n "__fish_grove_needs_command" -f -a "repo" -d 'Manage repo configuration'
complete -c grove -n "__fish_grove_needs_command" -f -a "launch" -d 'Launch terminal tabs with Claude Code for projects'
complete -c grove -n "__fish_grove_needs_command" -f -a "done" -d 'Remove a worktree project (defaults to the current directory\'s worktree)'
complete -c grove -n "__fish_grove_needs_command" -f -a "__completions" -d 'Generate shell completion scripts'
complete -c grove -n "__fish_grove_needs_command" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c grove -n "__fish_grove_using_subcommand new" -l issue -r
complete -c grove -n "__fish_grove_using_subcommand new" -l branch -r
complete -c grove -n "__fish_grove_using_subcommand new" -l base -r
complete -c grove -n "__fish_grove_using_subcommand new" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand new" -l no-fetch
complete -c grove -n "__fish_grove_using_subcommand new" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand new" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand fork" -l issue -r
complete -c grove -n "__fish_grove_using_subcommand fork" -l branch -r
complete -c grove -n "__fish_grove_using_subcommand fork" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand fork" -l no-fetch
complete -c grove -n "__fish_grove_using_subcommand fork" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand fork" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand list" -l repo -r
complete -c grove -n "__fish_grove_using_subcommand list" -l short
complete -c grove -n "__fish_grove_using_subcommand list" -l json
complete -c grove -n "__fish_grove_using_subcommand list" -l no-status
complete -c grove -n "__fish_grove_using_subcommand list" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand list" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand status" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand status" -l json
complete -c grove -n "__fish_grove_using_subcommand status" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand status" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand path" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand path" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand path" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand cd" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand cd" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand cd" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand adopt" -l issue -r
complete -c grove -n "__fish_grove_using_subcommand adopt" -l base -r
complete -c grove -n "__fish_grove_using_subcommand adopt" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand adopt" -l move-dir
complete -c grove -n "__fish_grove_using_subcommand adopt" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand adopt" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand rename" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand rename" -l no-move
complete -c grove -n "__fish_grove_using_subcommand rename" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand rename" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand freeze" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand freeze" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand freeze" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand thaw" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand thaw" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand thaw" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand repo; and not __fish_seen_subcommand_from path add list show remove default help" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand repo; and not __fish_seen_subcommand_from path add list show remove default help" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand repo; and not __fish_seen_subcommand_from path add list show remove default help" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand repo; and not __fish_seen_subcommand_from path add list show remove default help" -f -a "path" -d 'Print the work_dir of the current or default repo'
complete -c grove -n "__fish_grove_using_subcommand repo; and not __fish_seen_subcommand_from path add list show remove default help" -f -a "add" -d 'Add a repo to repos.json'
complete -c grove -n "__fish_grove_using_subcommand repo; and not __fish_seen_subcommand_from path add list show remove default help" -f -a "list" -d 'List configured repos'
complete -c grove -n "__fish_grove_using_subcommand repo; and not __fish_seen_subcommand_from path add list show remove default help" -f -a "show" -d 'Show full details for one repo'
complete -c grove -n "__fish_grove_using_subcommand repo; and not __fish_seen_subcommand_from path add list show remove default help" -f -a "remove" -d 'Remove a repo from repos.json'
complete -c grove -n "__fish_grove_using_subcommand repo; and not __fish_seen_subcommand_from path add list show remove default help" -f -a "default" -d 'Set the default_repo in repos.json'
complete -c grove -n "__fish_grove_using_subcommand repo; and not __fish_seen_subcommand_from path add list show remove default help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from path" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from path" -l default
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from path" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from path" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from add" -l id -r
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from add" -l issue-prefix -r
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from add" -l upstream -r
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from add" -l fork -r
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from add" -l default-base -r
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from add" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from add" -l default
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from add" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from add" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from list" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from list" -l json
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from list" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from list" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from show" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from show" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from show" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from remove" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from remove" -l force
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from remove" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from remove" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from default" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from default" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from default" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from help" -f -a "path" -d 'Print the work_dir of the current or default repo'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from help" -f -a "add" -d 'Add a repo to repos.json'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from help" -f -a "list" -d 'List configured repos'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from help" -f -a "show" -d 'Show full details for one repo'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from help" -f -a "remove" -d 'Remove a repo from repos.json'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from help" -f -a "default" -d 'Set the default_repo in repos.json'
complete -c grove -n "__fish_grove_using_subcommand repo; and __fish_seen_subcommand_from help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c grove -n "__fish_grove_using_subcommand launch" -l only -r
complete -c grove -n "__fish_grove_using_subcommand launch" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand launch" -l dry-run
complete -c grove -n "__fish_grove_using_subcommand launch" -l no-claude
complete -c grove -n "__fish_grove_using_subcommand launch" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand launch" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand done" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand done" -l force
complete -c grove -n "__fish_grove_using_subcommand done" -l keep-local
complete -c grove -n "__fish_grove_using_subcommand done" -l keep-remote
complete -c grove -n "__fish_grove_using_subcommand done" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand done" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand __completions" -l repo -d 'Operate on this specific repo (overrides cwd-based detection)' -r
complete -c grove -n "__fish_grove_using_subcommand __completions" -s v -l verbose -d 'Increase log verbosity (-v = INFO, -vv = DEBUG, -vvv = TRACE)'
complete -c grove -n "__fish_grove_using_subcommand __completions" -s h -l help -d 'Print help'
complete -c grove -n "__fish_grove_using_subcommand help; and not __fish_seen_subcommand_from new fork list status path cd adopt rename freeze thaw repo launch done __completions help" -f -a "new" -d 'Create a new worktree project'
complete -c grove -n "__fish_grove_using_subcommand help; and not __fish_seen_subcommand_from new fork list status path cd adopt rename freeze thaw repo launch done __completions help" -f -a "fork" -d 'Fork an existing project\'s branch into a new worktree'
complete -c grove -n "__fish_grove_using_subcommand help; and not __fish_seen_subcommand_from new fork list status path cd adopt rename freeze thaw repo launch done __completions help" -f -a "list" -d 'List all projects'
complete -c grove -n "__fish_grove_using_subcommand help; and not __fish_seen_subcommand_from new fork list status path cd adopt rename freeze thaw repo launch done __completions help" -f -a "status" -d 'Show git status for projects'
complete -c grove -n "__fish_grove_using_subcommand help; and not __fish_seen_subcommand_from new fork list status path cd adopt rename freeze thaw repo launch done __completions help" -f -a "path" -d 'Print the path to a project worktree'
complete -c grove -n "__fish_grove_using_subcommand help; and not __fish_seen_subcommand_from new fork list status path cd adopt rename freeze thaw repo launch done __completions help" -f -a "cd" -d 'Change directory to a project worktree (prints path for shell integration)'
complete -c grove -n "__fish_grove_using_subcommand help; and not __fish_seen_subcommand_from new fork list status path cd adopt rename freeze thaw repo launch done __completions help" -f -a "adopt" -d 'Import an existing worktree into the registry'
complete -c grove -n "__fish_grove_using_subcommand help; and not __fish_seen_subcommand_from new fork list status path cd adopt rename freeze thaw repo launch done __completions help" -f -a "rename" -d 'Rename a project'
complete -c grove -n "__fish_grove_using_subcommand help; and not __fish_seen_subcommand_from new fork list status path cd adopt rename freeze thaw repo launch done __completions help" -f -a "freeze" -d 'Exclude a project from grove launch'
complete -c grove -n "__fish_grove_using_subcommand help; and not __fish_seen_subcommand_from new fork list status path cd adopt rename freeze thaw repo launch done __completions help" -f -a "thaw" -d 'Re-include a frozen project in grove launch'
complete -c grove -n "__fish_grove_using_subcommand help; and not __fish_seen_subcommand_from new fork list status path cd adopt rename freeze thaw repo launch done __completions help" -f -a "repo" -d 'Manage repo configuration'
complete -c grove -n "__fish_grove_using_subcommand help; and not __fish_seen_subcommand_from new fork list status path cd adopt rename freeze thaw repo launch done __completions help" -f -a "launch" -d 'Launch terminal tabs with Claude Code for projects'
complete -c grove -n "__fish_grove_using_subcommand help; and not __fish_seen_subcommand_from new fork list status path cd adopt rename freeze thaw repo launch done __completions help" -f -a "done" -d 'Remove a worktree project (defaults to the current directory\'s worktree)'
complete -c grove -n "__fish_grove_using_subcommand help; and not __fish_seen_subcommand_from new fork list status path cd adopt rename freeze thaw repo launch done __completions help" -f -a "__completions" -d 'Generate shell completion scripts'
complete -c grove -n "__fish_grove_using_subcommand help; and not __fish_seen_subcommand_from new fork list status path cd adopt rename freeze thaw repo launch done __completions help" -f -a "help" -d 'Print this message or the help of the given subcommand(s)'
complete -c grove -n "__fish_grove_using_subcommand help; and __fish_seen_subcommand_from repo" -f -a "path" -d 'Print the work_dir of the current or default repo'
complete -c grove -n "__fish_grove_using_subcommand help; and __fish_seen_subcommand_from repo" -f -a "add" -d 'Add a repo to repos.json'
complete -c grove -n "__fish_grove_using_subcommand help; and __fish_seen_subcommand_from repo" -f -a "list" -d 'List configured repos'
complete -c grove -n "__fish_grove_using_subcommand help; and __fish_seen_subcommand_from repo" -f -a "show" -d 'Show full details for one repo'
complete -c grove -n "__fish_grove_using_subcommand help; and __fish_seen_subcommand_from repo" -f -a "remove" -d 'Remove a repo from repos.json'
complete -c grove -n "__fish_grove_using_subcommand help; and __fish_seen_subcommand_from repo" -f -a "default" -d 'Set the default_repo in repos.json'
