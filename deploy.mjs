import SftpClient from 'ssh2-sftp-client';
import { readFile } from 'fs/promises';
import { existsSync } from 'fs';
import { execSync } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Load .env manually (avoids needing dotenv as a dependency)
const envPath = path.join(__dirname, '.env');
if (existsSync(envPath)) {
  const env = await readFile(envPath, 'utf-8');
  for (const line of env.split('\n')) {
    const [key, ...rest] = line.split('=');
    const val = rest.join('=').trim();
    if (key && val !== undefined && val !== '') process.env[key.trim()] = val;
  }
}

const { SFTP_HOST, SFTP_USER, SFTP_PASSWORD } = process.env;
if (!SFTP_HOST || !SFTP_USER || !SFTP_PASSWORD) {
  console.error('Error: SFTP_HOST, SFTP_USER and SFTP_PASSWORD must be set in .env');
  process.exit(1);
}

const isDebug = process.argv.includes('--debug');
const shouldBuild = process.argv.includes('--build');
const buildType = isDebug ? 'debug' : 'release';

// Read version from pubspec.yaml
const pubspecPath = path.resolve(__dirname, 'pubspec.yaml');
if (!pubspecPath.startsWith(__dirname)) {
  console.error('Error: resolved pubspec path escapes project directory');
  process.exit(1);
}
const pubspec = await readFile(pubspecPath, 'utf-8');
const versionMatch = pubspec.match(/^version:\s*(.+)$/m);
const version = versionMatch ? versionMatch[1].trim() : 'unknown';

const localApk = path.resolve(__dirname, 'build', 'app', 'outputs', 'flutter-apk', `app-${buildType}.apk`);
if (!localApk.startsWith(__dirname)) {
  console.error('Error: resolved APK path escapes project directory');
  process.exit(1);
}
const remoteDir = 'audiovault.mattsteed.com/releases';
const apkName = `audiovault-${version}-${buildType}.apk`;
const remotePath = `${remoteDir}/${apkName}`;

// Optionally build
if (shouldBuild) {
  const gradlew = process.platform === 'win32'
    ? path.join(__dirname, 'android', 'gradlew.bat')
    : './gradlew';
  const gradleTask = isDebug ? 'assembleDebug' : 'assembleRelease';
  console.log(`Building ${buildType} APK...`);
  execSync(`${gradlew} ${gradleTask}`, { cwd: path.join(__dirname, 'android'), stdio: 'inherit' });
}

if (!existsSync(localApk)) {
  console.error(`APK not found: ${localApk}`);
  console.error(`Run with --build, or: flutter build apk${isDebug ? ' --debug' : ''}`);
  process.exit(1);
}

const sftp = new SftpClient();
try {
  console.log(`Connecting to ${SFTP_HOST}...`);
  await sftp.connect({ host: SFTP_HOST, username: SFTP_USER, password: SFTP_PASSWORD });
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
