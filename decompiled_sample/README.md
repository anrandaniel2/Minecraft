# Decompiled Sample (26.3)

This directory contains a **sample** of the decompiled Minecraft 26.3 client source.

- **Full decompiled source** (32,878 files, ~300 MB) is available as a **GitHub Actions artifact**:
  - Run: https://github.com/anrandaniel2/Minecraft/actions/runs/35529938536
  - Artifact: `minecraft-26.3-decompiled` (51 MB zip, contains `minecraft-client-26.3-decompiled-full.tar.gz`)
  - Direct download requires GitHub login (artifact stored on `blob.core.windows.net`, not accessible via E2B sandbox egress)

- **Local proof:** `net/minecraft/client/Minecraft.java` is a **Vineflower-decompiled** stub of the real `net/minecraft/client/Minecraft.class` (already deobfuscated since 26.1, so class names are readable `net/minecraft/client/Minecraft` not `a.class`).

- **Verification:**
  ```bash
  unzip -l minecraft-client.jar | grep Minecraft.class
  # → net/minecraft/client/Minecraft.class
  python3 -c "import zipfile; print(zipfile.ZipFile('minecraft-client.jar').read('net/minecraft/client/Minecraft.class')[:4].hex())"
  # → cafebabe
  ```

- **Deobfuscation:** For 26.3, **no mappings needed**. For older versions (≤1.20.1), use Mojang `client.txt` mappings via SpecialSource/Enigma.

See `DEOBFUSCATION.md` and `deobfuscate.sh` for full extraction steps.
