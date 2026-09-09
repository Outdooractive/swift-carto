// Corpus runner: compare swift carto output against carto's .result fixtures.
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const sax = require('/Users/trasch/Projects/swift-carto/reference/carto/node_modules/sax');

const dir = '/Users/trasch/Projects/swift-carto/reference/carto/test/rendering';
const bin = '/Users/trasch/Projects/swift-carto/.build/debug/carto';

function parseXML(xml) {
  const parser = sax.parser(true);
  const tree = [{}];
  let i = 0;
  parser.onopentag = function(node) {
    if (!(node.name in tree[0])) tree[0][node.name] = [];
    node.attributes.__order__ = i++;
    tree[0][node.name].push(node.attributes);
    tree.unshift(node.attributes);
  };
  parser.onclosetag = function() { tree.shift(); };
  parser.ontext = parser.oncdata = function(text) {
    if (text.trim()) tree[0].text = (tree[0].text || '') + text;
  };
  try { parser.write(xml.toString()); } catch (e) { return { __parse_error: true }; }
  return tree[0];
}

function walk(o) {
  if (Array.isArray(o)) return o.map(walk);
  if (o && typeof o === 'object') {
    const r = {};
    for (const k of Object.keys(o).sort()) {
      if (k === '__order__') continue;
      if (k === 'file' && typeof o[k] === 'string' && o[k].length > 3) { r[k] = '[absolute path]'; continue; }
      r[k] = walk(o[k]);
    }
    if (r.text !== undefined && typeof r.text === 'string' &&
        (r.text.startsWith('/') || r.text.startsWith('http'))) r.text = '[absolute path]';
    return r;
  }
  return o;
}

const files = fs.readdirSync(dir).filter(f => f.endsWith('.mml') && !f.includes('_api'));
let pass = 0, fail = 0, skipped = 0;
const failures = [];
for (const file of files) {
  const base = file.slice(0, -4);
  const resultFile = path.join(dir, base + '.result');
  if (!fs.existsSync(resultFile)) { skipped++; continue; }
  let out;
  try {
    out = execFileSync(bin, [path.join(dir, file)], { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
  } catch (e) {
    out = e.stdout || '';
  }
  if (!out.trim()) {
    fail++;
    failures.push([base, '(empty output)']);
    continue;
  }
  const expected = parseXML(fs.readFileSync(resultFile));
  const actual = parseXML(out);
  const equal = JSON.stringify(walk(expected)) === JSON.stringify(walk(actual));
  if (equal) {
    pass++;
  } else {
    fail++;
    failures.push([base, '']);
  }
}
console.log(`PASS: ${pass}  FAIL: ${fail}  SKIPPED: ${skipped}`);
if (process.argv[2] === '-v') {
  for (const f of failures) console.log('FAIL', f[0]);
}
