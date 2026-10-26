// Explicit opt-in native check: creates a temporary test volume and Finder window.
// No executable app, signing, notarization or release artifact is created.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

if (process.platform !== 'darwin') throw new Error('The native DMG layout check requires macOS.');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'clipscreen-layout-check-'));
const source = path.join(work, 'fixture');
const mount = path.join(work, 'private-mount');
const image = path.join(work, 'fixture.dmg');
let mounted = false;
function run(tool, args) {
  const result = spawnSync(tool, args, { encoding: 'utf8', timeout: 60000 });
  if (result.error || result.status !== 0) throw new Error(result.error?.message || result.stderr || `${tool} failed`);
  return result.stdout.trim();
}
try {
  fs.mkdirSync(path.join(source, 'Clipscreen.app/Contents'), { recursive: true });
  fs.writeFileSync(path.join(source, 'Clipscreen.app/Contents/Info.plist'),
    '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleName</key><string>Layout Fixture</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleIdentifier</key><string>invalid.clipscreen.layout-fixture</string></dict></plist>');
  fs.mkdirSync(path.join(source, '.background'));
  fs.copyFileSync(path.join(root, 'Resources/Installer/background.tiff'), path.join(source, '.background/background.tiff'));
  fs.symlinkSync('/Applications', path.join(source, 'Applications'));
  fs.mkdirSync(mount);
  run('/usr/bin/hdiutil', ['create', '-size', '16m', '-fs', 'HFS+', '-volname', 'Clipscreen',
    '-srcfolder', source, '-format', 'UDRW', image]);
  run('/usr/bin/hdiutil', ['attach', '-readwrite', '-nobrowse', '-noautoopen', '-mountpoint', mount, image]);
  mounted = true;
  // Exercise the actual production script twice, including its saved-layout path.
  for (let attempt = 0; attempt < 2; attempt++) {
    const windowID = run('/usr/bin/osascript', [path.join(root, 'scripts/dmg-layout.applescript'), mount]);
    assert.match(windowID, /^\d+$/, 'production script must identify the exact window it closed');
    const exists = run('/usr/bin/osascript', ['-e', `tell application "Finder" to exists Finder window id ${windowID}`]);
    assert.equal(exists, 'false', 'the check must close its own Finder window');
    const store = fs.readFileSync(path.join(mount, '.DS_Store'));
    assert.equal(store.toString('ascii', 4, 8), 'Bud1', 'Finder must write a real DS_Store');
    for (const name of ['Clipscreen.app', 'Applications']) {
      assert.ok(store.includes(Buffer.from(name, 'utf16le').swap16()), `${name} layout record is missing`);
    }
  }
  console.log('Native Finder layout passed twice: private mount alias, saved DS_Store, both item records and owned-window cleanup.');
} finally {
  if (mounted) {
    const result = spawnSync('/usr/bin/hdiutil', ['detach', mount], { encoding: 'utf8', timeout: 30000 });
    if (result.status !== 0) run('/usr/bin/hdiutil', ['detach', '-force', mount]);
  }
  fs.rmSync(work, { recursive: true, force: true });
}
