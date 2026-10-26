// Asset conversion only: no application build, signing or Finder control.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.resolve(process.argv[2] || path.join(root, 'Resources/AppIcon.png'));
const output = path.resolve(process.argv[3] || path.join(root, 'Resources/Clipscreen.icns'));
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'clipscreen-icon-'));
const iconset = path.join(temporary, 'Clipscreen.iconset');
function run(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8' });
  if (result.error || result.status !== 0) throw new Error(result.error?.message || result.stderr);
}
try {
  fs.mkdirSync(iconset);
  for (const size of [16, 32, 128, 256, 512]) {
    for (const scale of [1, 2]) {
      const pixels = size * scale;
      run('/usr/bin/sips', ['-z', String(pixels), String(pixels), source, '--out',
        path.join(iconset, `icon_${size}x${size}${scale === 2 ? '@2x' : ''}.png`)]);
    }
  }
  run('/usr/bin/iconutil', ['-c', 'icns', iconset, '-o', output]);
  const bytes = fs.readFileSync(output);
  if (bytes.toString('ascii', 0, 4) !== 'icns' || bytes.readUInt32BE(4) !== bytes.length) {
    throw new Error('Invalid generated ICNS container');
  }
  console.log(`Created ${output}`);
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
