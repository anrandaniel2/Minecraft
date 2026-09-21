using Godot;
using System;
using System.Collections.Generic;

namespace Minecraft.World.Level.LevelGen.Structure
{
    /// <summary>
    /// Translation of net.minecraft.world.level.levelgen.structure.Structure and StructureManager
    /// Handles villages, temples, mineshafts, etc.
    /// </summary>
    public abstract class Structure
    {
        public string Name { get; }
        public int Spacing { get; }
        public int Separation { get; }
        protected Structure(string name, int spacing, int separation)
        {
            Name = name;
            Spacing = spacing;
            Separation = separation;
        }

        public abstract bool CanGenerateAt(int chunkX, int chunkZ, long seed);
        public abstract void Generate(global::Minecraft.World.Level.Level level, Vector3I chunkPos, Random random);
    }

    public class VillageStructure : Structure
    {
        public VillageStructure() : base("village", 34, 8) {}

        public override bool CanGenerateAt(int chunkX, int chunkZ, long seed)
        {
            // Check spacing
            int spacing = Spacing;
            int chunkXWithSpacing = (int)MathF.Floor((float)chunkX / spacing) * spacing;
            int chunkZWithSpacing = (int)MathF.Floor((float)chunkZ / spacing) * spacing;
            var r = new Random((int)(seed + chunkXWithSpacing * 341873128712L + chunkZWithSpacing * 132897987541L));
            int offsetX = r.Next(spacing - Separation);
            int offsetZ = r.Next(spacing - Separation);
            return chunkX == chunkXWithSpacing + offsetX && chunkZ == chunkZWithSpacing + offsetZ;
        }

        public override void Generate(global::Minecraft.World.Level.Level level, Vector3I chunkPos, Random random)
        {
            // Would place village buildings
            GD.Print($"[Village] Generating at {chunkPos}");
        }
    }

    public class MineshaftStructure : Structure
    {
        public MineshaftStructure() : base("mineshaft", 10, 5) {}
        public override bool CanGenerateAt(int chunkX, int chunkZ, long seed) => new Random((int)(seed + chunkX * 341873128712L + chunkZ * 132897987541L)).NextDouble() < 0.004;
        public override void Generate(global::Minecraft.World.Level.Level level, Vector3I chunkPos, Random random) {}
    }

    public class StructureManager
    {
        private List<Structure> _structures = new List<Structure>()
        {
            new VillageStructure(),
            new MineshaftStructure(),
            // Would add: DesertPyramid, JungleTemple, OceanMonument, WoodlandMansion, etc.
        };

        public void CheckAndGenerate(global::Minecraft.World.Level.Level level, int chunkX, int chunkZ, long seed)
        {
            var random = new Random((int)(seed + chunkX * 341873128712L + chunkZ * 132897987541L));
            foreach (var structure in _structures)
            {
                if (structure.CanGenerateAt(chunkX, chunkZ, seed))
                {
                    structure.Generate(level, new Vector3I(chunkX*16, 0, chunkZ*16), random);
                }
            }
        }
    }
}
