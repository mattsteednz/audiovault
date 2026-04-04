# Cross-Feature Dependencies

| Feature | Depends On | Reason |
|---------|-----------|--------|
| Remote Repo (PRD 2) | Metadata Enrichment (PRD 0) | Must fetch metadata from remote sources before displaying books |
| AZW3 (PRD 5) | Metadata Enrichment (PRD 0) | Must extract/enrich metadata from AZW3 files |
| Google Cast (PRD 1) | Position Persistence (PRD 3) | Must resume from saved position on Cast device |
| Google Drive (PRD 6) | Metadata Enrichment (PRD 0) | Must enrich Drive files with cover/author/description |
| Google Drive (PRD 6) | Remote Repo (PRD 2) | File loading infrastructure shared |
| Remote Repo (PRD 2) | AZW3 Support (PRD 5) | Must support AZW3 files from feeds |
| AZW3 (PRD 5) | Position Persistence (PRD 3) | Must track position in AZW3 books |
