# Minecraft 26.3 – Extraction & Deobfuscation

> **TL;DR:** `minecraft-client.jar` (26.3, 41,483,720 bytes, SHA1 `e877b6a07acd633fb3bb475002175cec036e7b87`) is **already deobfuscated** since `26.1` (snapshot `26.1` – Mojang stopped obfuscating client JARs). Extraction = deobfuscation. For older versions, mappings are required.

## 1. Extraction (done locally)

```bash
unzip -q minecraft-client.jar -d extracted
# or
python3 -m zipfile --extract minecraft-client.jar extracted
```

Result (26.3, Sept 15 2026):
```
extracted/
├── META-INF/                 (MANIFEST.MF, MOJANGCS.RSA, LICENSE)
├── assets/                   (vanilla resources – blockstates, textures, texts)
├── data/                     (datapacks)
├── com/mojang/               (Blaze3D, authlib, etc.)
├── net/minecraft/            (11,383 class files, NOT obfuscated)
│   └── client/Minecraft.class, TitleScreen.class, GameRenderer.class, ...
├── version.json
├── pack.png
└── flightrecorder-config.jfc

Total: 32,878 files
```

**Check obfuscation:**
```bash
ls extracted/a.class 2>&1 | head   # no such file → not obfuscated
ls extracted/net/minecraft/client/ | head -n 20
# AttackIndicatorStatus.class
# Camera.class
# Minecraft.class   ← readable, not a.class
```

**Sandbox run:**
```
=== Extracting minecraft-client.jar ===
Extracted to extracted: 32878 files
Not obfuscated - modern 26.1+ jar, classes at net/minecraft/... are readable
Deobfuscated (copied) to deobfuscated: 11383 class files
```

The `deobfuscate.sh` script in this repo automates this check:
```bash
./deobfuscate.sh
```

*Note:* `extracted/` and `deobfuscated/` are **not committed** to Git (32k files > 10k file cap, ~300 MB uncompressed). They are created locally via the script and ignored via `.gitignore`. See workflow for CI decompilation.

## 2. Why no deobfuscation needed for 26.3?

From `minecraft.wiki/w/Client_software` and `mcreference.com`:

> **26.1:** snap1 · The Java class files in client.jar are no longer obfuscated, and are no longer located in the root directory of client.jar.  
> **26.1:** snap1 · All files inside of client.jar (except for those inside the META-INF folder) now always have a last modified date of February 1, 1980.

For 26.3:
- Classes are at `net/minecraft/client/Minecraft.class` (not `a.class`)
- No `client.txt` mapping needed (but Mojang still publishes it: `https://piston-data.mojang.com/v1/objects/bdeb624c3aefba11d9d40f34bc96176350b549b6/client.txt` for reference)
- Reproducible builds via Gradle

For **older versions** (≤ 1.20.1) you *do* need mappings:
```bash
# Example for 1.20.1:
# Via Mojang official mappings (Mojang → Parchment/Yarn)
curl -L https://piston-data.mojang.com/v1/objects/bdeb624c.../client.txt -o mappings.txt
# Then use SpecialSource, Vineflower, or Enigma:
# java -jar SpecialSource.jar --in-jar minecraft-client-1.20.1.jar --out-jar deobf.jar --srg mappings.txt
```

For 26.3 you can skip this and directly decompile.

## 3. Decompilation to Java source (full)

**Locally** (requires Java 21+):
```bash
# Install Java 21
sudo apt install openjdk-21-jdk -y

# Download Vineflower (FOSS FernFlower fork)
curl -L -o vineflower.jar https://github.com/Vineflower/vineflower/releases/download/1.10.1/vineflower-1.10.1.jar

# Decompile entire jar (may take 5-10 min, ~300 MB source)
java -jar vineflower.jar -dgs=1 minecraft-client.jar decompiled_src/

# Or single file
java -jar vineflower.jar net/minecraft/client/Minecraft.class decompiled_src/
javap -c -p extracted/net/minecraft/client/Minecraft.class | head -n 100
```

**Via GitHub Actions** (no local Java needed):
- Workflow: `.github/workflows/deobfuscate.yml` (runs on `ubuntu-latest` with `temurin 21` and `Vineflower 1.10.1`)
- Trigger:
  ```bash
  gh workflow run "Deobfuscate Minecraft JAR" --ref arena/01a0c00d-minecraft
  # or push to that workflow file
  ```
- The workflow:
  1. Checks out `arena/01a0c00d-minecraft`
  2. Installs JDK 21, downloads Vineflower
  3. `unzip -q minecraft-client.jar -d extracted` → verifies not obfuscated
  4. `java -jar vineflower.jar minecraft-client.jar decompiled/` (full decompilation)
  5. Creates `minecraft-client-26.3-decompiled.tar.gz` and `minecraft-client-26.3-deobfuscated.jar` (if mappings applied)
  6. Uploads as workflow artifact (not committed to Git to avoid cap) and optionally commits a `decompiled_sample/` with one file (`net/minecraft/client/Minecraft.java`) as proof.

Check the latest run:
```
https://github.com/anrandaniel2/Minecraft/actions/workflows/deobfuscate.yml
```

## 4. Artifacts

- **Local:** `extracted/` (32,878 files, not in Git) and `deobfuscated/` (11,383 class files) – created by `./deobfuscate.sh`
- **CI:** `decompiled_src.tar.gz` (workflow artifact) – full Java source, download from Actions tab
- **Repo:** Only `minecraft-client.jar` (binary), `deobfuscate.sh`, `DEOBFUSCATION.md`, and `.github/workflows/deobfuscate.yml` are committed (keeps repo <128 MB, <10k files)

## 5. Verification (26.3)

```bash
# SHA1 matches Mojang
sha1sum minecraft-client.jar
# e877b6a07acd633fb3bb475002175cec036e7b87

# Valid JAR
python3 -m zipfile --list minecraft-client.jar | head -n 20
# META-INF/MANIFEST.MF, net/minecraft/client/Minecraft.class, ...

# Class magic
python3 -c "import zipfile; print(zipfile.ZipFile('minecraft-client.jar').read('net/minecraft/client/Minecraft.class')[:4].hex())"
# cafebabe

# Deobfuscated name check
unzip -l minecraft-client.jar | grep -E "a\.class|net/minecraft/client/Minecraft.class"
# → net/minecraft/client/Minecraft.class (not a.class)
```

## 6. References

- Mojang version manifest: `https://piston-meta.mojang.com/mc/game/version_manifest_v2.json`
- Skyrising mirror: `https://raw.githubusercontent.com/skyrising/mc-versions/master/data/version/26.3.json`
- mcreference: `https://mcreference.com/minecraft-versions/26.3` (client 39.6 MB, server 59.4 MB)
- Wiki: `https://minecraft.wiki/w/Client_software` (26.1 deobfuscation)
- Mappings for older: `https://piston-data.mojang.com/v1/objects/.../client.txt`

---
*Extracted: 2026-09-20 | JAR: 26.3 (Wilderness Bound) | Method: local unzip + GitHub Actions Vineflower | Branch: arena/01a0c00d-minecraft*
