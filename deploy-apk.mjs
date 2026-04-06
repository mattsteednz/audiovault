import SftpClient from 'ssh2-sftp-client';
import { readFile } from 'fs/promises';
import { existsSync } from 'fs';
import { execSync } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Load .env
const envPath = path.join(__dirname, '.env');
if (existsSync(envPath)) {
  const env = await readFile(envPath, 'utf-8');
  for (const line of env.split('\n')) {
    const [key, ...rest] = line.split('=');
    if (key && rest.length) process.env[key.trim()] = rest.join('=').trim();
  }
}

const mode = process.argv[2];
if (mode !== 'debug' && mode !== 'release') {
  console.error('Usage: node deploy-apk.mjs <debug|release>');
  process.exit(1);
}

const { SFTP_HOST, SFTP_USER, SFTP_PASSWORD } = process.env;
if (!SFTP_HOST || !SFTP_USER || !SFTP_PASSWORD) {
  console.error('Error: SFTP_HOST, SFTP_USER and SFTP_PASSWORD must be set in .env');
  process.exit(1);
}

const gradlew = process.platform === 'win32'
  ? path.join(__dirname, 'android', 'gradlew.bat')
  : './gradlew';
const gradleTask = mode === 'release' ? 'assembleRelease' : 'assembleDebug';
const apkName = mode === 'release' ? 'app-release.apk' : 'app-debug.apk';
const localApk = path.join(__dirname, `build/app/outputs/flutter-apk/${apkName}`);
const remoteApk = `audiovault.mattsteed.com/releases/${apkName}`;

// Build
console.log(`Building ${mode} APK...`);
execSync(`${gradlew} ${gradleTask}`, {
  cwd: path.join(__dirname, 'android'),
  stdio: 'inherit',
});

// Deploy
const sftp = new SftpClient();
try {
  console.log(`Connecting to ${SFTP_HOST}...`);
  await sftp.connect({
    host: SFTP_HOST,
    username: SFTP_USER,
    password: SFTP_PASSWORD,
  });
  console.log(`Uploading ${apkName} → ${remoteApk}`);
  await sftp.put(localApk, remoteApk);
  console.log('Deploy complete.');
} catch (err) {
  console.error('Deploy failed:', err.message);
  process.exit(1);
} finally {
  await sftp.end();
}
