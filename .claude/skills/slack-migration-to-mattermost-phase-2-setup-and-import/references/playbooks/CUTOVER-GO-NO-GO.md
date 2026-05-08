# Cutover Go / No-Go

Ask these questions immediately before final import.

## Go Only If

- latest handoff bundle is validated
- final delta window is explicit
- production backups are fresh
- staging evidence is still representative
- comms and helpdesk are ready

## No-Go If

- any critical validation report is red
- unresolved gaps became larger than accepted
- the final delta is not bounded
- nobody owns rollback
