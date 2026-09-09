#!/bin/bash
# Runs the swift carto binary over carto's rendering test corpus and compares
# against the .result files (XML-tree comparison like the node harness).
cd /Users/trasch/Projects/swift-carto/reference/carto/test/rendering
PASS=0; FAIL=0; SKIPPED=0
for mml in *_api*.mml ; do SKIPPED=$((SKIPPED+1)); done 2>/dev/null
for mml in *.mml; do
  base="${mml%.mml}"
  case "$mml" in *_api*) SKIPPED=$((SKIPPED+1)); continue;; esac
  result="$base.result"
  [ -f "$result" ] || { SKIPPED=$((SKIPPED+1)); continue; }
  # run swift
  OUT=$(/Users/trasch/Projects/swift-carto/.build/debug/carto "$mml" 2>/dev/null)
  if [ -z "$OUT" ]; then
    echo "FAIL(empty) $mml"
    FAIL=$((FAIL+1))
    continue
  fi
  echo "$OUT" > /tmp/opencode/swift-out.xml
  node -e '
  const fs = require("fs");
  const sax = require("/Users/trasch/Projects/swift-carto/reference/carto/node_modules/sax");
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
      if (text.trim()) tree[0].text = (tree[0].text || "") + text;
    };
    parser.write(xml.toString());
    return tree[0];
  }
  function normalize(obj) {
    // strip __order__, sort attribute keys, and normalize absolute paths
    // like the node harness (removeAbsoluteImages / removeAbsoluteDatasources)
    function walk(o) {
      if (Array.isArray(o)) return o.map(walk);
      if (o && typeof o === "object") {
        const r = {};
        for (const k of Object.keys(o).sort()) {
          if (k === "__order__") continue;
          if (k === "file" && typeof o[k] === "string" && o[k].length > 3) { r[k] = "[absolute path]"; continue; }
          r[k] = walk(o[k]);
        }
        if (r.text !== undefined && typeof r.text === "string" && (r.text.startsWith("/") || r.text.startsWith("http"))) r.text = "[absolute path]";
        return r;
      }
      return o;
    }
    return walk(obj);
  }
  const expected = parseXML(fs.readFileSync(process.argv[1]));
  const actual = parseXML(fs.readFileSync(process.argv[2]));
  if (normalize(expected) === normalize(actual)) process.exit(0);
  process.exit(1);
  ' "$result" /tmp/opencode/swift-out.xml
  if [ $? -eq 0 ]; then
    PASS=$((PASS+1))
  else
    echo "FAIL $mml"
    FAIL=$((FAIL+1))
  fi
done
echo "== PASS: $PASS FAIL: $FAIL SKIPPED: $SKIPPED"
