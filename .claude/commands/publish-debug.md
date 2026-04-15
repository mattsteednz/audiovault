---
name: publish-debug
description: Build a debug APK from main and deploy to remote releases via SFTP
---

# /publish-debug — Build and publish a debug APK from main

Ensures you're on the latest main, builds a debug APK, and deploys it to the remote releases server via SFTP.

## Steps

### 1. Switch to main and pull latest

```bash
git checkout main && git pull origin main
```

### 2. Build debug APK

```bash
flutter build apk --debug
```

Fix any build errors before continuing.

### 3. Deploy via deploy.mjs

```bash
node deploy.mjs --build --debug
```

This reads SFTP credentials from `.env`, builds if needed (already built above, but the flag is harmless), and uploads the APK to the remote releases folder.

### 4. Report result

Confirm the version number deployed (read from `pubspec.yaml`) and that the upload succeeded.
