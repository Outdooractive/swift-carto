// Differential test: node carto vs swift carto over all TilemillProjects.
// Compares parsed XML trees (semantic equivalence).
const fs = require('fs');
const path = require('path');
const sax = require('/Users/trasch/Projects/swift-carto/reference/carto/node_modules/sax');
const { execFileSync } = require('child_process');
const carto = require('/Users/trasch/Projects/swift-carto/reference/carto/lib/carto');

const dir = '/Users/trasch/Projects/Backup/TilemillProjects';
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
  parser.write(xml.toString());
  return tree[0];
}
function walk(o) {
  if (Array.isArray(o)) return o.map(walk);
  if (o && typeof o === 'object') {
    const r = {};
    for (const k of Object.keys(o).sort()) {
      if (k === '__order__') continue;
      r[k] = walk(o[k]);
    }
    return r;
  }
  return o;
}

let pass = 0, fail = 0, skip = 0;
const failures = [];
for (const project of fs.readdirSync(dir).sort()) {
  const mmlPath = path.join(dir, project, 'project.mml');
  if (!fs.existsSync(mmlPath)) { skip++; continue; }

  // node carto (via the MML loader, like CartoTool does)
  let nodeXML = null, nodeErr = false;
  try {
    const data = fs.readFileSync(mmlPath, 'utf8');
    const mml = new carto.MML({});
    // synchronous emulation of MML.load
    const doc = JSON.parse(data);
    doc.Stylesheet = (doc.Stylesheet || []).map(s => {
      if (typeof s === 'string') {
        return { id: s, data: fs.readFileSync(path.join(path.dirname(mmlPath), s), 'utf8') };
      }
      return s;
    });
    const out = new carto.Renderer({ filename: mmlPath }).render(doc);
    if (out.data) nodeXML = out.data; else nodeErr = true;
  } catch (e) { nodeErr = true; }

  // swift carto
  let swiftXML = null, swiftErr = false;
  try {
    swiftXML = execFileSync(bin, [mmlPath], { encoding: 'utf8', maxBuffer: 512 * 1024 * 1024, stdio: ['pipe', 'pipe', 'pipe'] });
  } catch (e) { swiftXML = e.stdout || ''; swiftErr = !swiftXML; }

  if (nodeErr && swiftErr) { pass++; continue; }  // both fail → same behavior
  if (nodeErr !== swiftErr) { fail++; failures.push([project, 'error mismatch']); continue; }

  const equal = JSON.stringify(walk(parseXML(nodeXML))) === JSON.stringify(walk(parseXML(swiftXML)));
  if (process.env.DEBUG_PROJECT === project) console.log('DEBUG equal:', equal, 'nodeLen:', nodeXML.length, 'swiftLen:', swiftXML.length);
  if (equal) {
    pass++;
  } else {
    fail++;
    failures.push([project, 'xml differs']);
  }
}
console.log(`PASS: ${pass}  FAIL: ${fail}  SKIP: ${skip}`);
for (const f of failures) console.log('FAIL', f[0], '-', f[1]);
