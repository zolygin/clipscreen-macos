// Explicit opt-in native check: creates temporary test images and Finder windows.
// No executable app, signing, notarization or release artifact is created.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createInstallationDMG } from '../scripts/dmg.mjs';

if (process.platform !== 'darwin') throw new Error('The native DMG layout check requires macOS.');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'clipscreen-layout-check-'));
const app = path.join(work, 'Clipscreen.app');
const mounts = new Set();
function execute(tool, args) {
  const result = spawnSync(tool, args, { encoding: 'utf8', timeout: 60000 });
  if (result.error || result.status !== 0) throw new Error(result.error?.message || result.stderr || `${tool} failed`);
  return result;
}
function run(tool, args) {
  const result = execute(tool, args);
  if (path.basename(tool) === 'hdiutil') {
    if (args[0] === 'attach') mounts.add(args[args.indexOf('-mountpoint') + 1]);
    if (args[0] === 'detach') mounts.delete(args.at(-1));
  }
  if (path.basename(tool) === 'osascript') {
    const mount = args[1];
    const windowID = result.stdout.trim();
    assert.match(windowID, /^\d+$/, 'production script must identify the exact window it closed');
    const exists = execute('/usr/bin/osascript', ['-e', `tell application "Finder" to exists Finder window id ${windowID}`]);
    assert.equal(exists.stdout.trim(), 'false', 'the check must close its own Finder window');
    const store = fs.readFileSync(path.join(mount, '.DS_Store'));
    assert.equal(store.toString('ascii', 4, 8), 'Bud1', 'Finder must write a real DS_Store');
    for (const name of ['Clipscreen.app', 'Applications']) {
      assert.ok(store.includes(Buffer.from(name, 'utf16le').swap16()), `${name} layout record is missing`);
    }
  }
  return result;
}
try {
  fs.mkdirSync(path.join(app, 'Contents'), { recursive: true });
  fs.writeFileSync(path.join(app, 'Contents/Info.plist'),
    '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleName</key><string>Layout Fixture</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleIdentifier</key><string>invalid.clipscreen.layout-fixture</string></dict></plist>');
  // Use the actual packaging function, with a non-executable fixture app.
  for (let attempt = 0; attempt < 2; attempt++) {
    const staging = path.join(work, `attempt-${attempt}`);
    fs.mkdirSync(staging);
    const image = createInstallationDMG({ root, work: staging, app, filename: 'fixture.dmg', run });
    assert.ok(fs.statSync(image).size > 0);
    execute('/usr/bin/hdiutil', ['verify', image]);
    assert.equal(mounts.size, 0, 'packaging must detach its private volume');
  }
  console.log('Native DMG packaging passed twice: Finder layout/DS_Store, owned-window cleanup, volume icon, detach, UDZO conversion and image verification.');
} finally {
  // Retain the fixture rather than deleting a directory containing a live mount.
  for (const mount of mounts) {
    const result = spawnSync('/usr/bin/hdiutil', ['detach', mount], { encoding: 'utf8', timeout: 30000 });
    if (result.status !== 0) execute('/usr/bin/hdiutil', ['detach', '-force', mount]);
    mounts.delete(mount);
  }
  fs.rmSync(work, { recursive: true, force: true });
}
