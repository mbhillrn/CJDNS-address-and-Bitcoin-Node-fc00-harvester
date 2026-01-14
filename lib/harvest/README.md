# lib/harvest

Harvester modules used by `harvest.sh`.

Main responsibilities in this directory:
- ingest sources (NodeStore / remote NodeStore / Frontier / Bitcoin Core)
- candidate selection + filtering
- `addnode ... onetry` dispatch and attempt tracking
- batch confirmation via Core pre/post peer snapshots
- CLI probe helpers + host parsing/canonicalization callsites
