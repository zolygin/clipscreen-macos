import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { distribute, loadSigningEnvironment, selectIdentity, verifyUniversalBinary } from '../scripts/dist.mjs';

const HASH = 'A'.repeat(40);
const TEAM = 'ABCDE12345';
const PASSWORD = 'fixture-password-do-not-log';
const IDENTITIES = `1) ${HASH} "Developer ID Application: Test Developer (${TEAM})"\n2) ${'B'.repeat(40)} "Apple Development: Test Developer (${TEAM})"\n2 valid identities found`;

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'clipscreen dist test-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const files = {
    'Resources/Info.plist': '<plist><dict><key>CFBundleIdentifier</key><string>local.kirill.clip</string></dict></plist>',
    'Resources/Clipscreen.icns': 'fixture icon',
    'Resources/Installer/background.tiff': 'fixture background', 'scripts/dmg-layout.applescript': '-- fixture Finder script',
    'Resources/Lucide/LICENSE': 'fixture Lucide license', 'Resources/Lucide/clipboard.svg': '<svg/>',
    'LICENSE': 'fixture MIT license', 'Sources/Clipscreen/App.swift': '// Never compiled: commands are intercepted.\n',
    '.env.release.local': `APPLE_ID=developer@example.invalid\nAPPLE_TEAM_ID=${TEAM}\nAPPLE_APP_SPECIFIC_PASSWORD=${PASSWORD}\n`,
  };
  for (const [file, value] of Object.entries(files)) {
    const dest = path.join(root, file); fs.mkdirSync(path.dirname(dest), { recursive: true }); fs.writeFileSync(dest, value);
  }
  return root;
}

function host(options = {}) {
  const calls = [];
  const run = (command, args) => {
    calls.push({ command, args: [...args] });
    const binary = path.basename(command);
    const ok = stdout => ({ status: 0, stdout: stdout ?? '', stderr: '' });
    if (binary === 'plutil') {
      if (args[0] === '-extract') return ok({ CFBundleShortVersionString: '0.5.0', CFBundleVersion: '7',
        CFBundleExecutable: 'Clipscreen', CFBundleIdentifier: 'local.kirill.clip', LSMinimumSystemVersion: '13.0' }[args[1]]);
      return ok();
    }
    if (binary === 'security') return ok(options.identities ?? IDENTITIES);
    if (binary === 'git') return ok(args[0] === 'rev-parse' ? '123456789abc\n' : '');
    if (binary === 'xcrun') {
      if (args[0] === '--show-sdk-version') return ok(options.sdk ?? '26.5');
      if (args[0] === '--show-sdk-path') return ok('/fixture SDK');
      if (args[0] === '--find') return ok(`/fixture tools/${args[1]}`);
      if (args[0] === 'notarytool') {
        if (options.notaryError) throw new Error(`notarytool failed: ${PASSWORD}`);
        return ok(options.notaryRaw ?? JSON.stringify({ status: options.status ?? 'Accepted', id: 'fixture-submission-id' }));
      }
      if (args[0] === 'SetFile') return ok();
      if (args[0] === 'stapler') {
        if (options.stapleError) throw new Error('Ticket stapling failed');
        if (args[1] === 'staple') fs.appendFileSync(args[2], '\nstapled ticket');
        return ok();
      }
    }
    if (binary === 'swiftc') { fs.writeFileSync(args[args.indexOf('-o') + 1], 'FAKE object, not a Mach-O executable'); return ok(); }
    if (binary === 'lipo') {
      if (args[0] === '-create') fs.writeFileSync(args[args.indexOf('-output') + 1], 'FAKE universal executable');
      else {
        assert.equal(args[1], '-verify_arch');
        assert.deepEqual(args.slice(2), ['arm64', 'x86_64']);
        assert.ok(fs.existsSync(args[0]), 'lipo input file must precede -verify_arch');
      }
      return ok();
    }
    if (binary === 'ditto') { fs.cpSync(args[0], args[1], { recursive: true }); return ok(); }
    if (binary === 'hdiutil') {
      if (args[0] === 'create') {
        const layout = args[args.indexOf('-srcfolder') + 1];
        assert.equal(fs.readlinkSync(path.join(layout, 'Applications')), '/Applications');
        assert.ok(fs.existsSync(path.join(layout, 'Clipscreen.app/Contents/Resources/Lucide/LICENSE')));
        assert.ok(fs.existsSync(path.join(layout, 'Clipscreen.app/Contents/Resources/LICENSE')));
        assert.equal(fs.readFileSync(path.join(layout, '.VolumeIcon.icns'), 'utf8'), 'fixture icon');
        assert.equal(fs.readFileSync(path.join(layout, 'Clipscreen.app/Contents/Resources/Clipscreen.icns'), 'utf8'), 'fixture icon');
        fs.writeFileSync(args.at(-1), 'FAKE writable disk image fixture');
      } else if (args[0] === 'attach') {
        const mount = args[args.indexOf('-mountpoint') + 1];
        const layout = path.join(path.dirname(mount), 'layout');
        fs.cpSync(layout, mount, { recursive: true, verbatimSymlinks: true });
      } else if (args[0] === 'detach') {
        if (options.detachError && !args.includes('-force')) throw new Error('Volume busy');
        if (options.forceDetachError) throw new Error('Unmount failed');
      } else if (args[0] === 'convert') {
        fs.writeFileSync(args[args.indexOf('-o') + 1], 'FAKE compressed disk image fixture');
      }
      return ok();
    }
    if (binary === 'osascript') {
      if (options.layoutError) throw new Error(typeof options.layoutError === 'string' ? options.layoutError : 'Finder automation denied');
      const mount = args[1];
      assert.ok(fs.existsSync(path.join(mount, '.background/background.tiff')));
      assert.equal(fs.readlinkSync(path.join(mount, 'Applications')), '/Applications');
      if (!options.missingLayout) fs.writeFileSync(path.join(mount, '.DS_Store'), 'FAKE Finder metadata');
      return ok();
    }
    if (binary === 'bless') return ok();
    if (binary === 'codesign') return ok();
    if (binary === 'spctl') { if (options.gatekeeperError) throw new Error('Gatekeeper rejected the disk image'); return ok(); }
    throw new Error(`Unexpected external command: ${binary}`);
  };
  return { calls, run };
}

function invoke(root, mocked, extra = {}) {
  const messages = [];
  const result = distribute({ root, suppliedEnv: {}, platform: 'darwin', run: mocked.run,
    log: value => messages.push(value), ...extra });
  return { result, messages };
}

function filesUnder(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => entry.isDirectory()
    ? filesUnder(path.join(dir, entry.name)) : entry.isFile() ? [path.join(dir, entry.name)] : []);
}

test('Signing environment honors precedence/Dictata alias without executing dotenv content or importing unrelated secrets', t => {
  const root = fixture(t);
  fs.writeFileSync(path.join(root, '.env.release.local'), 'APPLE_ID=local@example.invalid\n');
  const external = path.join(root, 'existing-signing.env');
  fs.writeFileSync(external, `APPLE_ID=external@example.invalid\nAPPLE_TEAM_ID=${TEAM}\nAPPLE_ID_PASSWORD='${PASSWORD}'\nAWS_SECRET_ACCESS_KEY=unrelated-provider-secret\n`);
  fs.writeFileSync(path.join(root, '.release.local.json'), JSON.stringify({ credentialsFiles: [external] }));
  const env = loadSigningEnvironment(root, { APPLE_ID: 'shell@example.invalid' });
  assert.equal(env.APPLE_ID, 'shell@example.invalid');
  assert.equal(env.APPLE_APP_SPECIFIC_PASSWORD, PASSWORD);
  assert.equal(env.AWS_SECRET_ACCESS_KEY, undefined);
  const marker = path.join(root, 'must-not-exist');
  fs.writeFileSync(external, `APPLE_ID="$(touch '${marker}')"\n`);
  fs.rmSync(path.join(root, '.env.release.local'));
  assert.match(loadSigningEnvironment(root, {}).APPLE_ID, /^\$\(touch/);
  assert.equal(fs.existsSync(marker), false);
});

test('Only a matching valid Developer ID Application identity may sign; ambiguity is explicit', () => {
  assert.equal(selectIdentity(IDENTITIES, undefined, TEAM).hash, HASH);
  assert.equal(selectIdentity(IDENTITIES, HASH).team, TEAM);
  assert.equal(selectIdentity(IDENTITIES, HASH.toLowerCase()).team, TEAM);
  assert.equal(selectIdentity(IDENTITIES, `Test Developer (${TEAM})`).hash, HASH);
  assert.throws(() => selectIdentity('0 valid identities found'), /No matching/);
  assert.throws(() => selectIdentity(IDENTITIES, '-', TEAM), /No matching/);
  assert.throws(() => selectIdentity(IDENTITIES, undefined, 'OTHERTEAM'), /No matching/);
  assert.throws(() => selectIdentity(IDENTITIES + `\n${'C'.repeat(40)} "Developer ID Application: Another Developer (OTHERTEAM)"`), /Multiple/);
});

test('Read-only preflight performs no compile, signature, container creation, upload or output-directory creation', t => {
  const root = fixture(t); const mocked = host();
  const { result, messages } = invoke(root, mocked, { checkOnly: true });
  assert.equal(result.filename, 'Clipscreen-0.5.0-universal.dmg');
  assert.equal(result.auth, undefined);
  assert.equal(fs.existsSync(path.join(root, 'release')), false);
  assert.equal(fs.existsSync(path.join(root, '.build')), false);
  assert.ok(mocked.calls.every(call => !['swiftc', 'lipo', 'codesign', 'hdiutil', 'spctl'].includes(path.basename(call.command))));
  assert.ok(mocked.calls.every(call => call.args[0] !== 'notarytool'));
  assert.ok(!JSON.stringify(result).includes(PASSWORD));
  assert.ok(!messages.join('\n').includes(PASSWORD));
});

test('Keychain profile auth does not require an Apple ID password; unsupported SDK/host fail before building', t => {
  const root = fixture(t); fs.rmSync(path.join(root, '.env.release.local'));
  const mocked = host();
  const result = invoke(root, mocked, { suppliedEnv: { APPLE_KEYCHAIN_PROFILE: 'Existing Profile' }, checkOnly: true }).result;
  assert.equal(result.authMethod, 'Keychain profile');
  assert.throws(() => invoke(root, host({ sdk: '25.0' }), { checkOnly: true }), /Xcode 26/);
  assert.throws(() => invoke(root, host(), { platform: 'linux', checkOnly: true }), /require a Mac/);
  assert.throws(() => invoke(root, host(), { checkOnly: true }), /APPLE_KEYCHAIN_PROFILE/);
});

test('Mocked full pipeline signs only merged Universal 2 app, notarizes final DMG, staples and verifies before publishing', t => {
  const root = fixture(t); const mocked = host();
  fs.mkdirSync(path.join(root, '.build/Clipscreen.app'), { recursive: true });
  fs.writeFileSync(path.join(root, '.build/Clipscreen.app/keep.txt'), 'existing development app');
  const { result, messages } = invoke(root, mocked);
  const compiles = mocked.calls.filter(call => path.basename(call.command) === 'swiftc');
  assert.equal(compiles.length, 2);
  assert.deepEqual(compiles.map(call => call.args[call.args.indexOf('-target') + 1]), ['arm64-apple-macosx13.0', 'x86_64-apple-macosx13.0']);
  assert.ok(compiles.every(call => call.args.includes('-O') && call.args.includes('-whole-module-optimization') && !call.args.includes('-g')));
  const sign = mocked.calls.filter(call => path.basename(call.command) === 'codesign' && call.args.includes('--sign'));
  assert.equal(sign.length, 2);
  assert.ok(sign[0].args.includes('runtime') && sign[0].args.includes('--timestamp'));
  assert.ok(sign[1].args.includes('--timestamp'));
  assert.ok(sign.every(call => call.args[call.args.indexOf('--sign') + 1] === HASH && !call.args.some(arg => arg.startsWith('-r='))));
  const submitIndex = mocked.calls.findIndex(call => call.args[0] === 'notarytool');
  const submit = mocked.calls[submitIndex];
  assert.equal(submit.args[1], 'submit');
  assert.ok(submit.args[2].endsWith('.dmg'));
  assert.equal(mocked.calls.filter(call => call.args[0] === 'notarytool').length, 1);
  assert.ok(mocked.calls.slice(submitIndex + 1).some(call => call.args[0] === 'stapler' && call.args[1] === 'validate'));
  assert.equal(path.basename(mocked.calls.at(-1).command), 'spctl');
  const output = path.join(root, 'release', result.file);
  assert.equal(result.sha256, crypto.createHash('sha256').update(fs.readFileSync(output)).digest('hex'));
  assert.ok(fs.readFileSync(output, 'utf8').endsWith('stapled ticket'));
  assert.match(fs.readFileSync(output + '.sha256', 'utf8'), new RegExp('^'+result.sha256+'  '));
  assert.equal(JSON.parse(fs.readFileSync(output.replace(/\.dmg$/, '.release.json'))).notarization.status, 'Accepted');
  assert.equal(fs.readFileSync(path.join(root, '.build/Clipscreen.app/keep.txt'), 'utf8'), 'existing development app');
  assert.equal(fs.existsSync(path.join(root, '.build/dist.lock')), false);
  assert.equal(fs.readdirSync(path.join(root, '.build/dist-runs')).length, 0);
  assert.ok(!messages.join('\n').includes(PASSWORD));
  for (const file of filesUnder(path.join(root, 'release'))) assert.ok(!fs.readFileSync(file, 'utf8').includes(PASSWORD));
  assert.ok(mocked.calls.every(call => !call.args.includes('push') && !call.args.includes('tag')));
});

for (const [label, options] of [
  ['Rejected notarization', { status: 'Invalid' }], ['Unreadable notarization response', { notaryRaw: 'not-json' }],
  ['Stapling failure', { stapleError: true }], ['Gatekeeper rejection', { gatekeeperError: true }],
]) {
  test(`${label} preserves existing artifacts and never reports success`, t => {
    const root = fixture(t); const mocked = host(options); const messages = [];
    fs.mkdirSync(path.join(root, 'release')); const old = path.join(root, 'release/Clipscreen-0.5.0-universal.dmg');
    fs.writeFileSync(old, 'previous verified image');
    assert.throws(() => invoke(root, mocked, { log: value => messages.push(value) }));
    assert.equal(fs.readFileSync(old, 'utf8'), 'previous verified image');
    assert.ok(!messages.some(line => line.startsWith('Ready:')));
    assert.equal(fs.existsSync(path.join(root, '.build/dist.lock')), false);
    assert.equal(fs.readdirSync(path.join(root, '.build/dist-runs')).length, 1);
    if (options.status || options.notaryRaw) assert.ok(mocked.calls.every(call => call.args[0] !== 'stapler'));
  });
}

test('Credential failures redact secrets and keep diagnostic files free of credentials', t => {
  const root = fixture(t); const mocked = host({ notaryError: true });
  assert.throws(() => invoke(root, mocked), error => !error.message.includes(PASSWORD) && error.message.includes('[redacted]'));
  assert.equal(fs.existsSync(path.join(root, 'release')), false);
  for (const file of filesUnder(path.join(root, '.build/dist-runs'))) assert.ok(!fs.readFileSync(file, 'utf8').includes(PASSWORD));
});

test('An active distribution lock rejects a second build before compilation', t => {
  const root = fixture(t); const mocked = host();
  fs.mkdirSync(path.join(root, '.build')); fs.writeFileSync(path.join(root, '.build/dist.lock'), String(process.pid));
  assert.throws(() => invoke(root, mocked), /already running/);
  assert.ok(mocked.calls.every(call => path.basename(call.command) !== 'swiftc'));
  assert.equal(fs.readFileSync(path.join(root, '.build/dist.lock'), 'utf8'), String(process.pid));
});

// Real CLI smoke test on header-only Mach-O object fixtures. No Swift compiler,
// executable app, signing tool or Apple network request is involved.
test('Real lipo accepts production Universal 2 verification arguments and rejects a missing slice',
  { skip: process.platform !== 'darwin' }, t => {
    const root = fixture(t);
    const location = spawnSync('/usr/bin/xcrun', ['--find', 'lipo'], { encoding: 'utf8' });
    assert.equal(location.status, 0, location.stderr);
    const lipo = location.stdout.trim();
    const architectures = [{ cpu: 0x0100000c, subtype: 0 }, { cpu: 0x01000007, subtype: 3 }];
    function header(cpu, subtype) {
      const bytes = Buffer.alloc(32);
      [0xfeedfacf, cpu, subtype, 1, 0, 0, 0, 0].forEach((value, index) => bytes.writeUInt32LE(value, index * 4));
      return bytes;
    }
    const fat = Buffer.alloc(8192 + 32);
    fat.writeUInt32BE(0xcafebabe, 0); fat.writeUInt32BE(2, 4);
    architectures.forEach((arch, index) => {
      const offset = 4096 * (index + 1);
      [arch.cpu, arch.subtype, offset, 32, 12].forEach((value, field) => fat.writeUInt32BE(value, 8 + index * 20 + field * 4));
      header(arch.cpu, arch.subtype).copy(fat, offset);
    });
    const universal = path.join(root, 'universal fixture.o');
    fs.writeFileSync(universal, fat);
    const actualRun = (tool, args) => {
      const result = spawnSync(tool, args, { encoding: 'utf8' });
      if (result.status !== 0) {
        const error = new Error(result.stderr || 'lipo verification failed');
        error.exitCode = result.status;
        throw error;
      }
      return result;
    };
    assert.doesNotThrow(() => verifyUniversalBinary(lipo, universal, actualRun));
    const thin = path.join(root, 'arm64 only fixture.o');
    fs.writeFileSync(thin, header(architectures[0].cpu, architectures[0].subtype));
    assert.equal(actualRun(lipo, [thin, '-archs']).stdout.trim(), 'arm64');
    assert.throws(() => verifyUniversalBinary(lipo, thin, actualRun), error => Number.isInteger(error.exitCode) && error.exitCode !== 0);
  });


test('Installer layout is saved and unmounted before compression, signing and upload', t => {
  const root = fixture(t); const mocked = host({ detachError: true });
  invoke(root, mocked);
  const step = (binary, arg) => mocked.calls.findIndex(c => path.basename(c.command) === binary && (!arg || c.args[0] === arg));
  assert.ok(step('hdiutil', 'create') < step('hdiutil', 'attach'));
  assert.ok(step('hdiutil', 'attach') < step('osascript'));
  assert.ok(step('osascript') < step('bless'));
  assert.ok(step('bless') < step('hdiutil', 'detach'));
  assert.ok(step('hdiutil', 'detach') < step('hdiutil', 'convert'));
  const force = mocked.calls.findIndex(c => c.args[0] === 'detach' && c.args.includes('-force'));
  assert.ok(force > step('hdiutil', 'detach') && force < step('hdiutil', 'convert'));
  const dmgSign = mocked.calls.findIndex(c => path.basename(c.command) === 'codesign' && c.args.includes('--sign') && c.args.at(-1).endsWith('.dmg'));
  assert.ok(step('hdiutil', 'convert') < dmgSign);
  assert.ok(dmgSign < step('xcrun', 'notarytool'));
  assert.ok(mocked.calls[step('hdiutil', 'attach')].args.includes('-noautoopen'));
});

for (const options of [{ layoutError: true }, { missingLayout: true }, { forceDetachError: true }]) {
  test(`Installer failure ${Object.keys(options)[0]} prevents compression/signing/upload and attempts unmount`, t => {
    const root = fixture(t); const mocked = host(options);
    assert.throws(() => invoke(root, mocked), /Cannot configure|Cannot unmount/);
    assert.ok(mocked.calls.some(c => c.args[0] === 'detach'));
    assert.ok(!mocked.calls.some(c => c.args[0] === 'convert' || c.args[0] === 'notarytool'));
    assert.equal(fs.existsSync(path.join(root, 'release')), false);
    assert.equal(fs.existsSync(path.join(root, '.build/dist.lock')), false);
  });
}


for (const [label, message, expectedHint] of [
  ['Finder object lookup error', 'Can’t get container window of alias "Clipscreen:". (-1728)', false],
  ['Apple-event permission denied', 'Not authorized to send Apple events to Finder. (-1743)', true],
  ['Unrelated layout error', 'Cannot save icon positions. (-10000)', false],
]) {
  test(`${label} preserves the actual error and shows an Automation hint only for permission failures`, t => {
    const root = fixture(t); const mocked = host({ layoutError: message });
    assert.throws(() => invoke(root, mocked), error => {
      assert.ok(error.message.includes(message));
      assert.equal(error.message.includes('Privacy & Security > Automation'), expectedHint);
      return true;
    });
    assert.ok(mocked.calls.some(c => c.args[0] === 'detach'));
    assert.ok(!mocked.calls.some(c => c.args[0] === 'notarytool'));
  });
}
