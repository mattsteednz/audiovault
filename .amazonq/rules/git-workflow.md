# Git Workflow

- Default branch: `main`
- Create a new branch for each feature or fix: `git checkout -b <type>/<short-description>`
  - Types: `feature/`, `fix/`, `security/`, `chore/`
- Keep commits focused; write descriptive commit messages
- Merge via fast-forward where possible; no merge commits on `main`
- Always test before merging to `main`
- Push to origin after merging: `git push origin main`
