// Differential test: node carto vs swift carto on arbitrary MSS snippets.
// Usage: node difftest.js "mss data"
const carto = require('/Users/trasch/Projects/swift-carto/reference/carto/lib/carto');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const data = process.argv[2];
const tmp = '/tmp/opencode/difftest-' + process.pid;
fs.mkdirSync(tmp, { recursive: true });

const mml = { Stylesheet: [ { id: 't.mss', data } ], Layer: [ { id: 'layer', Datasource: { type: 'shape', file: 'x.shp' } } ] };

// node carto
const r = new carto.Renderer({});
const nodeOut = r.render(mml);
const nodeXML = nodeOut.data || null;

// swift carto
fs.writeFileSync(path.join(tmp, 'project.mml'), JSON.stringify(mml));
let swiftXML = null;
try {
  swiftXML = execSync('/Users/trasch/Projects/swift-carto/.build/debug/carto ' + path.join(tmp, 'project.mml'), { encoding: 'utf8', stdio: ['pipe','pipe','pipe'] });
} catch (e) {
  swiftXML = null;
}

// Compare as XML trees
const sax = require('/Users/trasch/Projects/swift-carto/reference/carto/node_modules/sax');

function parseXML(xml) {
  if (!xml) return null;
  const parser = sax.parser(true);
  const tree = [{}];
  let i = 0;
  parser.onopentag = function(node) {
    if (!(node.name in tree[0])) tree[0][node.name] = [];
    node.attributes.__order__ = i++;
    tree[0][node.name].push(node.attributes);
    tree.unshift(node.attributes);
  };
  parser.onclosetag = function() {
    tree.shift();
  };
  parser.ontext = parser.oncdata = function(text) {
    if (text.trim()) tree[0].text = (tree[0].text || '') + text;
  };
  parser.write(xml.toString());
  return tree[0];
}

const equal = JSON.stringify(parseXML(nodeXML)) === JSON.stringify(parseXML(swiftXML));
console.log('--- MSS:', JSON.stringify(data));
if (!equal) {
  console.log('NODE:', nodeXML);
  console.log('SWIFT:', swiftXML);
  if (!nodeXML) console.log('NODE MSG:', JSON.stringify(nodeOut.msg));
  process.exitCode = 1;
} else {
  console.log('OK');
}
