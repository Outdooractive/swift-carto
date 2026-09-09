// Compare one project: node vs swift, print first difference
const fs = require('fs');
const path = require('path');
const sax = require('/Users/trasch/Projects/swift-carto/reference/carto/node_modules/sax');
const { execFileSync } = require('child_process');
const carto = require('/Users/trasch/Projects/swift-carto/reference/carto/lib/carto');

const project = process.argv[2];
const mmlPath = path.join('/Users/trasch/Projects/Backup/TilemillProjects', project, 'project.mml');
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
const doc = JSON.parse(fs.readFileSync(mmlPath, 'utf8'));
doc.Stylesheet = (doc.Stylesheet || []).map(s => typeof s === 'string' ? { id: s, data: fs.readFileSync(path.join(path.dirname(mmlPath), s), 'utf8') } : s);
const nodeOut = new carto.Renderer({}).render(doc);
const swiftOut = execFileSync('/Users/trasch/Projects/swift-carto/.build/debug/carto', [mmlPath], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, stdio: ['pipe','pipe','pipe'] });
const es = JSON.stringify(walk(parseXML(nodeOut.data))), as = JSON.stringify(walk(parseXML(swiftOut)));
console.log('equal:', es === as);
if (es !== as) {
  // find structural difference: walk and compare recursively, print first
  function findDiff(e, a, p) {
    if (typeof e !== typeof a) return p + ' type ' + typeof e + ' vs ' + typeof a;
    if (Array.isArray(e)) {
      if (e.length !== a.length) return p + ' len ' + e.length + ' vs ' + a.length;
      for (let i = 0; i < e.length; i++) {
        const d = findDiff(e[i], a[i], p + '[' + i + ']');
        if (d) return d;
      }
      return null;
    }
    if (e && typeof e === 'object') {
      const keys = new Set([...Object.keys(e), ...Object.keys(a)]);
      for (const k of keys) {
        if (!(k in e)) return p + '.' + k + ' only in swift: ' + JSON.stringify(a[k]).slice(0, 120);
        if (!(k in a)) return p + '.' + k + ' only in node: ' + JSON.stringify(e[k]).slice(0, 120);
        const d = findDiff(e[k], a[k], p + '.' + k);
        if (d) return d;
      }
      return null;
    }
    if (e !== a) return p + ': ' + JSON.stringify(e) + ' vs ' + JSON.stringify(a);
    return null;
  }
  const diff = findDiff(walk(parseXML(nodeOut.data)), walk(parseXML(swiftOut)), '');
  console.log('DIFF:', diff);
}
