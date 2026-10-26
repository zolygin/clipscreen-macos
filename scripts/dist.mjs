import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { parseEnv } from 'node:util';
import { spawnSync } from 'node:child_process';

const PROJECT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SIGNING_KEYS = new Set(['APPLE_ID', 'APPLE_TEAM_ID', 'APPLE_APP_SPECIFIC_PASSWORD', 'APPLE_ID_PASSWORD',
  'APPLE_KEYCHAIN_PROFILE', 'CLIPSCREEN_NOTARY_PROFILE', 'CSC_NAME', 'CLIPSCREEN_SIGNING_IDENTITY', 'CLIPSCREEN_BUNDLE_ID']);

export function redact(value, secrets = []) {
  return secrets.filter(Boolean).sort((a, b) => b.length - a.length)
    .reduce((text, secret) => text.split(secret).join('[redacted]'), String(value));
}

export function loadSigningEnvironment(root, supplied = process.env) {
  let local = {};
  const localPath = path.join(root, '.release.local.json');
  if (fs.existsSync(localPath)) {
    try { local = JSON.parse(fs.readFileSync(localPath, 'utf8')); }
    catch { throw new Error('Cannot parse .release.local.json. It must contain valid JSON.'); }
    if (!local || typeof local !== 'object' || Array.isArray(local)) throw new Error('Invalid local release configuration.');
  }
  if (local.credentialsFiles !== undefined && (!Array.isArray(local.credentialsFiles)
    || local.credentialsFiles.some(file => typeof file !== 'string' || !file))) {
    throw new Error('credentialsFiles in .release.local.json must be an array of file paths.');
  }
  const env = { ...supplied };
  const files = ['.env.release.local', ...(local.credentialsFiles ?? []), '.env.desktop', '.env'];
  for (const file of files) {
    const resolved = path.resolve(root, file);
    if (!fs.existsSync(resolved)) continue;
    let parsed;
    try { parsed = parseEnv(fs.readFileSync(resolved, 'utf8')); }
    catch { throw new Error(`Cannot read signing environment file: ${resolved}`); }
    for (const [key, value] of Object.entries(parsed)) {
      if (SIGNING_KEYS.has(key) && !env[key]) env[key] = value;
    }
  }
  env.APPLE_APP_SPECIFIC_PASSWORD ||= env.APPLE_ID_PASSWORD;
  return env;
}

export function selectIdentity(output, requested, team) {
  const identities = [...output.matchAll(/([A-Fa-f0-9]{40}) "([^"]+)"/g)]
    .map(match => ({ hash: match[1], name: match[2], team: match[2].match(/\(([A-Z0-9]+)\)$/)?.[1] }))
    .filter(identity => identity.name.startsWith('Developer ID Application:'));
  const candidates = identities.filter(identity => (!requested || identity.name === requested || identity.name === `Developer ID Application: ${requested}`
    || identity.hash.toLowerCase() === requested.toLowerCase())
    && (!team || identity.team === team));
  if (!candidates.length) throw new Error('No matching valid Developer ID Application identity/private key is available in Keychain.');
  if (candidates.length !== 1) throw new Error('Multiple Developer ID Application identities match. Set CLIPSCREEN_SIGNING_IDENTITY to the intended certificate name or hash.');
  return candidates[0];
}

function commandRunner(env, secrets) {
  return (command, args, options = {}) => {
    const result = spawnSync(command, args, { cwd: options.cwd, env, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
    if ((result.error || result.status !== 0) && !options.allowFailure) {
      const detail = result.error?.message ?? `${result.stderr || result.stdout}`;
      throw new Error(redact(`${path.basename(command)} failed (${result.status ?? 'unavailable'}): ${detail}`, secrets));
    }
    return { status: result.status, stdout: result.stdout ?? '', stderr: result.stderr ?? '' };
  };
}

function requireValue(value, pattern, label) {
  if (!pattern.test(value)) throw new Error(`Invalid ${label} in release configuration.`);
  return value;
}

export function preflight(root, env, run, platform = process.platform) {
  if (platform !== 'darwin') throw new Error('Signed macOS distribution builds require a Mac.');
  const info = path.join(root, 'Resources', 'Info.plist');
  const read = key => run('/usr/bin/plutil', ['-extract', key, 'raw', info]).stdout.trim();
  const version = requireValue(read('CFBundleShortVersionString'), /^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$/, 'version');
  const build = requireValue(read('CFBundleVersion'), /^\d+$/, 'build number');
  const executable = requireValue(read('CFBundleExecutable'), /^[A-Za-z0-9_-]+$/, 'executable name');
  const bundle = requireValue(env.CLIPSCREEN_BUNDLE_ID || read('CFBundleIdentifier'), /^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/, 'bundle identifier');
  const minimum = requireValue(read('LSMinimumSystemVersion'), /^\d+\.\d+(?:\.\d+)?$/, 'deployment target');
  const sdkVersion = run('/usr/bin/xcrun', ['--show-sdk-version']).stdout.trim();
  if (Number.parseInt(sdkVersion, 10) < 26 || !/^\d+/.test(sdkVersion)) throw new Error('Xcode 26 or a newer compatible macOS SDK is required.');
  const sdk = run('/usr/bin/xcrun', ['--show-sdk-path']).stdout.trim();
  const swift = run('/usr/bin/xcrun', ['--find', 'swiftc']).stdout.trim();
  const lipo = run('/usr/bin/xcrun', ['--find', 'lipo']).stdout.trim();
  run('/usr/bin/xcrun', ['--find', 'notarytool']);
  run('/usr/bin/xcrun', ['--find', 'stapler']);
  const identity = selectIdentity(run('/usr/bin/security', ['find-identity', '-v', '-p', 'codesigning']).stdout,
    env.CLIPSCREEN_SIGNING_IDENTITY || env.CSC_NAME, env.APPLE_TEAM_ID);
  const profile = env.CLIPSCREEN_NOTARY_PROFILE || env.APPLE_KEYCHAIN_PROFILE;
  let auth;
  if (profile) auth = ['--keychain-profile', profile];
  else {
    if (!env.APPLE_ID || !env.APPLE_APP_SPECIFIC_PASSWORD) {
      throw new Error('Set APPLE_KEYCHAIN_PROFILE, or APPLE_ID and APPLE_APP_SPECIFIC_PASSWORD (APPLE_ID_PASSWORD is also supported), in .env.release.local or the environment.');
    }
    auth = ['--apple-id', env.APPLE_ID, '--team-id', env.APPLE_TEAM_ID || identity.team,
      '--password', env.APPLE_APP_SPECIFIC_PASSWORD];
  }
  const sources = fs.readdirSync(path.join(root, 'Sources', 'Clipscreen')).filter(file => file.endsWith('.swift')).sort()
    .map(file => path.join(root, 'Sources', 'Clipscreen', file));
  if (!sources.length) throw new Error('No application Swift sources found.');
  for (const required of ['LICENSE', 'Resources/Lucide/LICENSE', 'Resources/Lucide/clipboard.svg', 'Resources/Clipscreen.icns']) {
    if (!fs.existsSync(path.join(root, required))) throw new Error(`Missing distribution resource: ${required}`);
  }
  const revisionResult = run('/usr/bin/git', ['rev-parse', '--short=12', 'HEAD'], { cwd: root, allowFailure: true });
  const revision = revisionResult.status === 0 ? revisionResult.stdout.trim() : 'source-archive';
  const dirtyResult = run('/usr/bin/git', ['status', '--porcelain', '--untracked-files=normal'], { cwd: root, allowFailure: true });
  const modified = dirtyResult.status === 0 && Boolean(dirtyResult.stdout.trim());
  return { version, build, executable, bundle, minimum, sdk, sdkVersion, swift, lipo, identity, auth,
    authMethod: profile ? 'Keychain profile' : 'Apple ID environment', sources,
    revision: revision + (modified ? '+modified' : ''), modified,
    filename: `Clipscreen-${version}-universal.dmg` };
}

export function verifyUniversalBinary(lipo, executable, run) {
  // -verify_arch consumes every following argument as an architecture name.
  // Put the input file first so it cannot be parsed as an architecture name.
  return run(lipo, [executable, '-verify_arch', 'arm64', 'x86_64']);
}

function acquireLock(root) {
  const directory = path.join(root, '.build');
  fs.mkdirSync(directory, { recursive: true });
  const lock = path.join(directory, 'dist.lock');
  try {
    const descriptor = fs.openSync(lock, 'wx', 0o600);
    fs.writeFileSync(descriptor, String(process.pid)); fs.closeSync(descriptor);
  } catch (error) {
    if (error.code !== 'EEXIST') throw error;
    const pid = Number(fs.readFileSync(lock, 'utf8'));
    if (!Number.isInteger(pid) || pid <= 0) throw new Error('Invalid .build/dist.lock; check for an existing release job before removing it.');
    try { process.kill(pid, 0); }
    catch (probe) {
      if (probe.code === 'ESRCH') { fs.unlinkSync(lock); return acquireLock(root); }
      throw new Error('Another release process owns .build/dist.lock.');
    }
    throw new Error('Another release process is already running.');
  }
  return () => {
    if (fs.existsSync(lock) && fs.readFileSync(lock, 'utf8') === String(process.pid)) fs.unlinkSync(lock);
  };
}

export function distribute({ root = PROJECT, suppliedEnv = process.env, run: injectedRun,
  log = console.log, checkOnly = false, platform = process.platform } = {}) {
  const env = loadSigningEnvironment(root, suppliedEnv);
  const secrets = [env.APPLE_APP_SPECIFIC_PASSWORD, env.APPLE_ID_PASSWORD, env.APPLE_ID];
  const rawRun = injectedRun || commandRunner(env, secrets);
  const run = (tool, args, options = {}) => {
    try { return rawRun(tool, args, { cwd: root, ...options }); }
    catch (error) { throw new Error(redact(error.message, secrets)); }
  };
  const config = preflight(root, env, run, platform);
  log(`Clipscreen ${config.version} (${config.build}) · Universal 2 · macOS ${config.minimum}+`);
  log(`Signing: ${config.identity.name}`);
  log(`Notarization: ${config.authMethod} (credential values hidden)`);
  log(`Source: ${config.revision}`);
  if (checkOnly) {
    log('Preflight passed. No app was compiled, signed, packaged or uploaded. Apple credentials have not been validated remotely.');
    return { ...config, auth: undefined };
  }
  const unlock = acquireLock(root);
  let work;
  let completed = false;
  try {
    const runs = path.join(root, '.build', 'dist-runs');
    fs.mkdirSync(runs, { recursive: true });
    work = fs.mkdtempSync(path.join(runs, 'run-'));
    const app = path.join(work, 'Clipscreen.app');
    const macos = path.join(app, 'Contents', 'MacOS');
    const resources = path.join(app, 'Contents', 'Resources');
    fs.mkdirSync(macos, { recursive: true }); fs.mkdirSync(resources, { recursive: true });
    const info = path.join(app, 'Contents', 'Info.plist');
    fs.copyFileSync(path.join(root, 'Resources', 'Info.plist'), info);
    run('/usr/bin/ditto', [path.join(root, 'Resources', 'Lucide'), path.join(resources, 'Lucide')]);
    fs.copyFileSync(path.join(root, 'LICENSE'), path.join(resources, 'LICENSE'));
    fs.copyFileSync(path.join(root, 'Resources/Clipscreen.icns'), path.join(resources, 'Clipscreen.icns'));
    run('/usr/bin/plutil', ['-replace', 'CFBundleIdentifier', '-string', config.bundle, info]);
    for (const [key, value] of Object.entries({ ClipscreenSourceRevision: config.revision,
      ClipscreenBuildDate: new Date().toISOString(), ClipscreenBuildConfiguration: 'Release',
      ClipscreenArchitectures: 'arm64 x86_64' })) {
      run('/usr/bin/plutil', ['-insert', key, '-string', value, info]);
    }
    const slices = [];
    for (const arch of ['arm64', 'x86_64']) {
      log(`Compiling optimized ${arch} executable…`);
      const slice = path.join(work, `Clipscreen-${arch}`);
      run(config.swift, ['-swift-version', '5', '-O', '-whole-module-optimization', '-sdk', config.sdk,
        '-target', `${arch}-apple-macosx${config.minimum}`, '-module-cache-path', path.join(root, '.build', 'release-module-cache'),
        ...config.sources, '-o', slice]);
      slices.push(slice);
    }
    const executable = path.join(macos, config.executable);
    run(config.lipo, ['-create', ...slices, '-output', executable]);
    fs.chmodSync(executable, 0o755);
    verifyUniversalBinary(config.lipo, executable, run);
    run('/usr/bin/plutil', ['-lint', info]);
    log('Signing the app with Developer ID and Hardened Runtime…');
    run('/usr/bin/codesign', ['--force', '--sign', config.identity.hash, '--options', 'runtime', '--timestamp', app]);
    run('/usr/bin/codesign', ['--verify', '--strict', '--verbose=2', app]);
    const layout = path.join(work, 'layout'); fs.mkdirSync(layout);
    run('/usr/bin/ditto', [app, path.join(layout, 'Clipscreen.app')]);
    fs.symlinkSync('/Applications', path.join(layout, 'Applications'));
    const dmg = path.join(work, config.filename);
    log('Creating and signing the installation DMG…');
    run('/usr/bin/hdiutil', ['create', '-volname', 'Clipscreen', '-srcfolder', layout, '-format', 'UDZO', '-fs', 'HFS+', dmg]);
    run('/usr/bin/codesign', ['--force', '--sign', config.identity.hash, '--timestamp', '--identifier', `${config.bundle}.dmg`, dmg]);
    run('/usr/bin/codesign', ['--verify', '--strict', '--verbose=2', dmg]);
    log('Uploading the signed DMG to Apple and waiting for notarization…');
    const submission = run('/usr/bin/xcrun', ['notarytool', 'submit', dmg, ...config.auth,
      '--wait', '--output-format', 'json', '--no-progress']);
    let result;
    try { result = JSON.parse(submission.stdout); }
    catch { throw new Error('Apple notarization returned an unreadable response; inspect this run before submitting again.'); }
    const notary = { id: result.id, status: result.status };
    fs.writeFileSync(path.join(work, 'notarization.json'), redact(JSON.stringify(notary, null, 2), secrets)+'\n');
    if (result.status !== 'Accepted' || typeof result.id !== 'string' || !result.id) {
      throw new Error(`Apple notarization was not Accepted (status: ${result.status || 'unknown'}, submission: ${result.id || 'unknown'}). No release artifact was published.`);
    }
    log('Stapling the ticket and verifying the final DMG…');
    run('/usr/bin/xcrun', ['stapler', 'staple', dmg]);
    run('/usr/bin/xcrun', ['stapler', 'validate', dmg]);
    run('/usr/bin/hdiutil', ['verify', dmg]);
    run('/usr/bin/codesign', ['--verify', '--strict', '--verbose=2', dmg]);
    run('/usr/sbin/spctl', ['--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', dmg]);
    const digest = crypto.createHash('sha256').update(fs.readFileSync(dmg)).digest('hex');
    const manifest = { name: 'Clipscreen', version: config.version, build: config.build,
      bundleIdentifier: config.bundle, architectures: ['arm64', 'x86_64'], minimumMacOS: config.minimum,
      sourceRevision: config.revision, builtAt: new Date().toISOString(), signingIdentity: config.identity.name,
      teamIdentifier: config.identity.team, notarization: notary, sha256: digest, file: config.filename };
    const output = path.join(root, 'release'); fs.mkdirSync(output, { recursive: true });
    const temporary = path.join(output, `.${config.filename}.${path.basename(work)}.tmp`);
    fs.copyFileSync(dmg, temporary);
    fs.renameSync(temporary, path.join(output, config.filename));
    fs.writeFileSync(path.join(output, `${config.filename}.sha256`), `${digest}  ${config.filename}\n`);
    fs.writeFileSync(path.join(output, config.filename.replace(/\.dmg$/, '.release.json')), JSON.stringify(manifest, null, 2)+'\n');
    completed = true;
    log(`Ready: ${path.join(output, config.filename)}`);
    log('Developer ID signature, Apple Accepted status, stapled ticket and Gatekeeper assessment passed.');
    return manifest;
  } catch (error) {
    throw new Error(redact(`${error.message}${work ? `\nDiagnostic workspace retained at: ${work}` : ''}`, secrets));
  } finally {
    unlock();
    if (completed && work) fs.rmSync(work, { recursive: true, force: true });
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const args = process.argv.slice(2);
    if (args.includes('--help')) {
      console.log('Usage: npm run dist [-- --check]\nBuilds, signs and notarizes a Universal 2 DMG in release/.\n--check verifies local prerequisites without building or uploading.');
    } else {
      if (args.some(arg => arg !== '--check')) throw new Error('Unknown option. Use --help.');
      distribute({ checkOnly: args.includes('--check') });
    }
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
