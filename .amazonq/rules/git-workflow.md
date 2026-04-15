# Git Workflow

- Default branch: `main`
- Create a new branch for each feature or fix: `git checkout -b <type>/<short-description>`
  - Types: `feature/`, `fix/`, `security/`, `chore/`
- Keep commits focused; write descriptive commit messages
- Merge via fast-forward where possible; no merge commits on `main`
- Before merging to `main`, run `flutter analyze` and `flutter test` and confirm both pass — warnings and infos are acceptable, errors are not
- Push to origin after merging: `git push origin main`
