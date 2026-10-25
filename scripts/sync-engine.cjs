// Copies the validated web model without changing its equations or calendar.
// Usage: node scripts/sync-engine.cjs [path/to/TAONIQ]
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const source = path.resolve(process.argv[2] || '../TAONIQ');
const model = path.join(source, 'assets/model');
const destination = path.resolve(__dirname, '../TAONIQ/Resources');
const json = name => JSON.parse(fs.readFileSync(path.join(model, name), 'utf8'));
const data = {atlas: json('atlas-model.json'), drive: json('drive-config.json'), protocol: json('calibration-protocol.json'), examples: json('examples.json')};
const files = ['../vendor/lunar-1.7.7.js', 'encoding.js', 'drive.js', 'experiment.js', 'morphology.js', 'distance.js', 'mapper.js', 'model.js', 'continuous.js'];
const bundle = '(function(){ const module=undefined,define=undefined;\nglobalThis.TAO_DATA=' + JSON.stringify(data) + ';\n' + files.map(f => fs.readFileSync(path.join(model, f), 'utf8')).join('\n;\n') + '\n}).call(globalThis);\n';
fs.mkdirSync(destination, {recursive: true});
fs.writeFileSync(path.join(destination, 'taoniq-engine.js'), bundle);
fs.copyFileSync(path.join(source, 'assets/vendor/lunar-MIT-LICENSE.txt'), path.join(destination, 'lunar-MIT-LICENSE.txt'));
const hash = contents => crypto.createHash('sha256').update(contents).digest('hex');
const manifest = {
    sourceRepository: 'https://github.com/doyoulikelin-wq/TAONIQ',
    sourceCommit: cp.execFileSync('git', ['rev-parse', 'HEAD'], {cwd: source, encoding: 'utf8'}).trim(),
    engineSHA256: hash(bundle),
    files: Object.fromEntries([...files, 'atlas-model.json', 'drive-config.json', 'calibration-protocol.json', 'examples.json']
        .map(f => [f, hash(fs.readFileSync(path.join(model, f)))])),
    modelUnitsPerCivilDay: 8 / 7,
    responseTimeModelUnits: 1,
    note: 'Exact upstream model sources, data embedded. Browser Worker shell omitted. Native JavaScriptCore host supplies timers.'
};
fs.writeFileSync(path.join(destination, 'engine-manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log('Engine bundled:', Buffer.byteLength(bundle), 'bytes', manifest.engineSHA256);
