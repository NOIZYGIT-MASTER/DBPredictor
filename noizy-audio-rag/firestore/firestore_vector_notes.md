# Firestore vector mirror notes

Rules:

- Metadata only.
- No raw stems.
- No full WAVs.
- No sensitive masters.
- No delete operations.

Canonical payload:

```json
{
  "asset_id": "",
  "sha256": "",
  "tags": [],
  "embedding": [],
  "quality_score": 0,
  "owner": ""
}
```

Collections:

- assets
- receipts
- consent_records
- lineage
- sync_state
- quality_reports
- duplicate_groups
