using Godot;
using Minecraft.World.Level.LevelGen.WorldGen;
using Minecraft.World.Level.LevelGen.Biome;
using Minecraft.Core;

namespace Minecraft.World
{
    /// <summary>
    /// Manages world creation, dimensions, seed, generator selection.
    /// Translation of net.minecraft.world.level.Level / MinecraftServer world loading.
    /// </summary>
    public partial class WorldManager : Node
    {
        public static WorldManager Instance { get; private set; }

        [Export] public long WorldSeed = 12345;
        [Export] public string WorldType = "default"; // default, flat, debug
        [Export] public string Dimension = "overworld";

        public IChunkGenerator WorldGenerator { get; private set; }
        public BiomeSource BiomeSource { get; private set; }
        public global::Minecraft.World.Level.Level GameLevel { get; private set; }

        public override void _Ready()
        {
            Instance = this;
            GD.Print($"[WorldManager] Seed={WorldSeed}, Type={WorldType}, Dimension={Dimension}");
            InitializeWorld();
        }

        public void InitializeWorld(long? seed = null, string worldType = null)
        {
            if (seed.HasValue) WorldSeed = seed.Value;
            if (!string.IsNullOrEmpty(worldType)) WorldType = worldType;

            BiomeSource = new BiomeSource(WorldSeed);

            WorldGenerator = WorldType switch
            {
                "flat" => new FlatLevelSource(),
                "debug" => new DebugLevelSource(),
                _ => new NoiseChunkGenerator(WorldSeed)
            };

            GameLevel = new global::Minecraft.World.Level.Level(WorldSeed, Dimension);
            GD.Print($"[WorldManager] Generator={WorldGenerator.GetType().Name}");
        }

        public void Tick()
        {
            GameLevel?.Tick();
        }

        public void CreateNewWorld(string name, long seed, string type)
        {
            WorldSeed = seed;
            WorldType = type;
            InitializeWorld(seed, type);
            // In real game, would create world folder and level.dat
        }

        // Dimension handling - from net.minecraft.world.level.dimension.DimensionType
        public enum DimensionType { Overworld, Nether, End }

        public DimensionType GetCurrentDimension() => Dimension switch
        {
            "nether" => DimensionType.Nether,
            "end" => DimensionType.End,
            _ => DimensionType.Overworld
        };

        public static class DimensionConstants
        {
            public const int OVERWORLD_MIN_Y = -64;
            public const int OVERWORLD_MAX_Y = 320;
            public const int NETHER_MIN_Y = 0;
            public const int NETHER_MAX_Y = 128;
            public const int END_MIN_Y = 0;
            public const int END_MAX_Y = 256;
        }
    }
}
