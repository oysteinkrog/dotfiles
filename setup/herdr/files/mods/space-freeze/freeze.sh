#!/bin/bash
# The old path of freeze.sh, mods/space-freeze/freeze.sh in the app folder. The old space-freeze
# mod (the krog layout before helm), the herdr-sessions skill and the manager sessions call it
# there. herdr-setup installs this file at that path until they all call mods/helm/bin/freeze.sh;
# it runs helm's copy, found beside this file, with the same arguments. helm's copy has the same
# commands and JSON output, plus a `version` command.
exec bash "$(dirname "$(readlink -f "$0")")/../helm/bin/freeze.sh" "$@"
