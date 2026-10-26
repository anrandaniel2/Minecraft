#!/bin/bash
set -e
JAR="minecraft-client.jar"
OUT="extracted"
DEOBFUSCATED="deobfuscated"

echo "=== Extracting $JAR ==="
rm -rf "$OUT" "$DEOBFUSCATED"
mkdir -p "$OUT"
unzip -q "$JAR" -d "$OUT"
echo "Extracted to $OUT: $(find "$OUT" -type f | wc -l) files"
ls -lh "$OUT" | head -n 20

echo ""
echo "=== Checking obfuscation ==="
if [ -f "$OUT/a.class" ] || [ -f "$OUT/net/minecraft/a.class" ]; then
  echo "Obfuscated (a.class found) - deobfuscation needed"
else
  echo "Not obfuscated - modern 26.1+ jar, classes at net/minecraft/... are readable"
  ls "$OUT/net/minecraft/client/" | head -n 20
fi

echo ""
echo "=== Deobfuscation (26.3 is already deobfuscated since 26.1) ==="
# For 26.3, just copy extracted to deobfuscated (no mapping needed)
# For older versions, would apply Mojang mappings via Vineflower/SpecialSource
mkdir -p "$DEOBFUSCATED"
cp -r "$OUT/net" "$DEOBFUSCATED/" 2>/dev/null || true
cp -r "$OUT/com" "$DEOBFUSCATED/" 2>/dev/null || true
echo "Deobfuscated (copied) to $DEOBFUSCATED: $(find "$DEOBFUSCATED" -type f | wc -l) class files"

echo ""
echo "=== Mappings info ==="
# Try to fetch mappings if needed (for older versions)
if [ -f "version.json" ]; then
  echo "version.json found in jar:"
  cat "$OUT/version.json" 2>/dev/null | head -n 20 || unzip -p "$JAR" version.json | head -n 20
fi
# Check for built-in mappings URL
grep -r "mappings" "$OUT" 2>/dev/null | head -n 5 || echo "No embedded mappings (26.3 uses published client.txt)"

echo ""
echo "=== Decompiler check ==="
if command -v java >/dev/null 2>&1; then
  echo "Java found: $(java -version 2>&1 | head -n1)"
  echo "Attempting to decompile one class with Vineflower/CFR if available..."
  # If vineflower.jar exists, use it
  if [ -f "vineflower.jar" ]; then
    java -jar vineflower.jar "$OUT/net/minecraft/client/Minecraft.class" --help 2>&1 | head -n 5 || true
  else
    echo "No decompiler jar found, using javap as fallback:"
    javap -c -p "$OUT/net/minecraft/client/Minecraft.class" 2>&1 | head -n 100 || echo "javap failed"
  fi
else
  echo "No Java in sandbox - decompilation will be done via GitHub Actions (see .github/workflows/deobfuscate.yml)"
  echo "Example class: net/minecraft/client/Minecraft.class (already readable, not a.class)"
fi

echo ""
echo "Done. Extracted files are in $OUT (not committed to git to avoid 10k file cap)."
echo "Deobfuscated subset is in $DEOBFUSCATED (also not committed)."
echo "See DEOBFUSCATION.md for details and GitHub Actions workflow for full decompilation."
