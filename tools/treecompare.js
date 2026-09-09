// Compare an expected .result against swift output as XML trees
const fs = require('fs');
const sax = require('/Users/trasch/Projects/swift-carto/reference/carto/node_modules/sax');
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
const expected = parseXML(fs.readFileSync(process.argv[1]));
const actual = parseXML(fs.readFileSync(process.argv[2]));
console.log('EXPECTED:', JSON.stringify(expected, null, 1));
console.log('ACTUAL:  ', JSON.stringify(actual, null, 1));
