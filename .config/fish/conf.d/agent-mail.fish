# Agent Mail storage root.
#
# Moved off /c (drvfs) to / (wslfs) on 2026-09-15. SQLite in WAL mode on drvfs
# does not get the file locking and fsync behaviour it needs, and the store went
# corrupt on nearly every day from 2026-08-25. The old root at
# /c/users/oystein/.mcp_agent_mail_git_mailbox_repo is kept as a backup.
#
# wslfs is not reachable from Windows tools, which is part of the point: no
# Windows indexer or antivirus touches the database any more.
#
# The pm2 service sets the same value in ~/.config/pm2/ecosystem.config.js.
# This line is for the `am` CLI in interactive shells, so `am doctor` and
# friends look at the database the server is actually using.
# The server reads STORAGE_ROOT; the `am` CLI uses AGENT_MAIL_STORAGE_ROOT.
# Set both so they always agree.
set -gx STORAGE_ROOT /home/oystein/.mcp_agent_mail_git_mailbox_repo
set -gx AGENT_MAIL_STORAGE_ROOT /home/oystein/.mcp_agent_mail_git_mailbox_repo
