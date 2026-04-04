# Audiobook App PRDs

This directory contains individual Product Requirements Documents for the AudioVault Audiobook Player app.

## PRD Files

### Core Features
- **[prd-0-metadata-enrichment.md](prd-0-metadata-enrichment.md)** — Automatically enrich audiobook metadata from open sources (ISBN lookup, cover art, descriptions)
- **[prd-1-google-cast.md](prd-1-google-cast.md)** — Cast audiobook playback to Chromecast and Google Home devices
- **[prd-2-remote-repository.md](prd-2-remote-repository.md)** — Load audiobooks from external XML/HTTP repositories and feeds
- **[prd-5-azw3-support.md](prd-5-azw3-support.md)** — Support Amazon's AZW3 (Kindle) audiobook format
- **[prd-6-google-drive.md](prd-6-google-drive.md)** — Stream and download audiobooks from Google Drive with mobile data warnings

### Done ✅
- **[done/prd-3-position-persistence.md](done/prd-3-position-persistence.md)** — Track and persist playback position with mini player quick-access
- **[done/prd-4-last-played-sort.md](done/prd-4-last-played-sort.md)** — Sort library by most recently played book

### UI Polish & Enhancement
- **[prd-7-mini-player-safe-area.md](prd-7-mini-player-safe-area.md)** — Handle Android gesture bar safe areas in mini player

### Infrastructure & Analytics
- **[prd-8-telemetry.md](prd-8-telemetry.md)** — Track app opens, user actions, and crashes with opt-in consent

### Foundation & Setup
- **[prd-9-audiovault-rebranding.md](prd-9-audiovault-rebranding.md)** — Rename app to AudioVault, update package names, configure Firebase
- **[prd-10-settings-screen.md](prd-10-settings-screen.md)** — Settings screen with folder selection and telemetry preferences

## Planning & Dependencies
- **[roadmap.md](roadmap.md)** — Implementation timeline across 3 phases
- **[dependencies.md](dependencies.md)** — Cross-feature dependencies and ordering constraints

## Quick Reference

| PRD | Name | Priority | Status |
|-----|------|----------|--------|
| 0 | Metadata Enrichment | High | Phase 1 |
| 1 | Google Cast | High | Phase 3 |
| 2 | Remote Repository | High | Phase 2 |
| 3 | Position Persistence | Critical | ✅ Done |
| 4 | Last Played Sort | Medium | ✅ Done |
| 5 | AZW3 Support | High | Phase 2 |
| 6 | Google Drive | High | Phase 3 |
| 7 | Mini Player Safe Area | Medium | Phase 1 |
| 8 | Telemetry & Analytics | Medium | Post-Phase 1 |
| 9 | AudioVault Rebranding | High | Foundation |
| 10 | Settings Screen | High | Foundation |
