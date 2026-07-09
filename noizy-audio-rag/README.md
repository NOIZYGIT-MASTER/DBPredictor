# noizy-audio-rag

Audio RAG scaffold for NOIZY workflows:

- ingest stems and metadata into Papyrus (SQLite)
- fingerprint audio references
- build/query embeddings and FAISS index
- mirror searchable metadata to Firestore
- connect orchestration through n8n and MC96 receipt stubs

## Local stack

- VSCodium
- Continue
- Ollama
- MC96
- Local MCP Mesh

## Quick start

1. Copy `.env.example` to `.env` and fill values.
2. Initialize Papyrus schema:
   - `sqlite3 papyrus/papyrus.db < papyrus/schema.sql`
3. Run ingest/embedding scripts as needed.

## Layout

- `config/audio_rag.yaml`: pipeline settings
- `papyrus/`: schema + local SQLite database
- `ingest/`: ingest + fingerprint + metadata writers
- `embeddings/`: embedding/index/query scripts
- `firestore/`: metadata mirroring notes/scripts
- `n8n/`: automation workflow export
- `mc96/`: receipt integration stubs

## Sync flow

Downloads  
↓  
INBOX  
↓  
QUARANTINE  
↓  
VALIDATED  
↓  
CANONICAL
