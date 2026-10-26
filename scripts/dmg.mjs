import fs from 'node:fs';
import path from 'node:path';

// Finder owns the actual drag/copy interaction. The image supplies orientation,
// stable icon positions and a native Applications target, not a custom installer.
export function createInstallationDMG({ root, work, app, filename, run }) {
  const layout = path.join(work, 'layout');
  fs.mkdirSync(path.join(layout, '.background'), { recursive: true });
  run('/usr/bin/ditto', [app, path.join(layout, 'Clipscreen.app')]);
  fs.symlinkSync('/Applications', path.join(layout, 'Applications'));
  fs.copyFileSync(path.join(root, 'Resources/Installer/background.tiff'), path.join(layout, '.background/background.tiff'));
  fs.copyFileSync(path.join(root, 'Resources/Clipscreen.icns'), path.join(layout, '.VolumeIcon.icns'));
  const writable = path.join(work, 'installer-writable.dmg');
  const mount = path.join(work, 'installer-volume');
  const dmg = path.join(work, filename);
  fs.mkdirSync(mount);
  run('/usr/bin/hdiutil', ['create', '-volname', 'Clipscreen', '-srcfolder', layout,
    '-format', 'UDRW', '-fs', 'HFS+', writable]);
  run('/usr/bin/hdiutil', ['attach', '-readwrite', '-nobrowse', '-noautoopen', '-mountpoint', mount, writable]);
  let failure;
  try {
    run('/usr/bin/osascript', [path.join(root, 'scripts/dmg-layout.applescript'), mount]);
    if (!fs.existsSync(path.join(mount, '.DS_Store'))) {
      throw new Error('Finder did not save the installer layout (.DS_Store is missing).');
    }
    run('/usr/bin/xcrun', ['SetFile', '-a', 'C', mount]);
    run('/usr/sbin/bless', ['--folder', mount, '--openfolder', mount]);
  } catch (error) {
    failure = new Error(`Cannot configure the DMG window: ${error.message}\nIf automation was denied, allow your terminal to control Finder in System Settings > Privacy & Security > Automation, then retry.`);
  } finally {
    try { run('/usr/bin/hdiutil', ['detach', mount]); }
    catch (error) {
      try { run('/usr/bin/hdiutil', ['detach', '-force', mount]); }
      catch (cleanup) {
        failure = new Error(`${failure ? failure.message + '\n' : ''}Cannot unmount installer volume ${mount}: ${cleanup.message}`);
      }
    }
  }
  if (failure) throw failure;
  run('/usr/bin/hdiutil', ['convert', writable, '-format', 'UDZO', '-o', dmg]);
  return dmg;
}
