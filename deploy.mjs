import SftpClient from 'ssh2-sftp-client';
import { readFile } from 'fs/promises';
import { existsSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Load .env manually (avoids needing dotenv as a dependency)
const envPath = path.join(__dirname, '.env');
if (existsSync(envPath)) {
  const env = await readFile(envPath, 'utf-8');
  for (const line of env.split('\n')) {
    const [key, ...rest] = line.split('=');
    if (key && rest.length) process.env[key.trim()] = rest.join('=').trim();
  }
}

const { SFTP_HOST, SFTP_USER, SFTP_PASSWORD } = process.env;
if (!SFTP_HOST || !SFTP_USER || !SFTP_PASSWORD) {
  console.error('Error: SFTP_HOST, SFTP_USER and SFTP_PASSWORD must be set in .env');
  process.exit(1);
}

// Parse --release / --debug flag (default: release)
const isDebug = process.argv.includes('--debug');
const buildType = isDebug ? 'debug' : 'release';

// Read version from pubspec.yaml
const pubspec = await readFile(path.join(__dirname, 'pubspec.yaml'), 'utf-8');
const versionMatch = pubspec.match(/^version:\s*(.+)$/m);
const version = versionMatch ? versionMatch[1].trim() : 'unknown';

const apkName = `audiovault-${version}-${buildType}.apk`;
const localApk = path.join(__dirname, 'build', 'app', 'outputs', 'flutter-apk', `app-${buildType}.apk`);
const remotePath = `audiovault.mattsteed.com/releases/${apkName}`;

if (!existsSync(localApk)) {
  console.error(`APK not found: ${localApk}`);
  console.error(`Run: flutter build apk${isDebug ? ' --debug' : ''}`);
  process.exit(1);
}

const sftp = new SftpClient();

try {
  console.log(`Connecting to ${SFTP_HOST}...`);
  await sftp.connect({
    host: SFTP_HOST,
    username: SFTP_USER,
    password: SFTP_PASSWORD,
  });

  // Ensure remote releases/ directory exists
  const remoteDir = 'audiovault.mattsteed.com/releases';
  await sftp.mkdir(remoteDir, true);

  console.log(`Uploading ${apkName} → ${remotePath}`);
  await sftp.put(localApk, remotePath);

  console.log(`Deploy complete: https://audiovault.mattsteed.com/releases/${apkName}`);
} catch (err) {
  console.error('Deploy failed:', err.message);
  process.exit(1);
} finally {
  await sftp.end();
}
