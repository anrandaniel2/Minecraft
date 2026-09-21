using System;
using Minecraft.Core;

namespace Minecraft.World.Level
{
    /// <summary>
    /// Translation of net.minecraft.world.level.LevelSettings, WorldOptions, WorldData
    /// </summary>
    public class LevelSettings
    {
        public string LevelName { get; set; } = "World";
        public GameModeType SelectedGameMode { get; set; } = GameModeType.Survival;
        public bool Hardcore { get; set; } = false;
        public DifficultyType SelectedDifficulty { get; set; } = DifficultyType.Normal;
        public bool AllowCommands { get; set; } = false;
        public GameRules GameRules { get; set; } = new GameRules();

        public enum GameModeType { Survival, Creative, Adventure, Spectator }
        public enum DifficultyType { Peaceful, Easy, Normal, Hard }
        // Legacy aliases for compatibility
        public GameModeType GameMode { get => SelectedGameMode; set => SelectedGameMode = value; }
        public DifficultyType Difficulty { get => SelectedDifficulty; set => SelectedDifficulty = value; }
    }

    public class WorldOptions
    {
        public long Seed { get; set; }
        public bool GenerateFeatures { get; set; } = true;
        public bool BonusChest { get; set; } = false;
        public string LegacyCustomOptions { get; set; } = "";

        public WorldOptions(long seed, bool features = true, bool bonusChest = false)
        {
            Seed = seed;
            GenerateFeatures = features;
            BonusChest = bonusChest;
        }

        public static WorldOptions Default => new WorldOptions(new Random().NextInt64());
        public static WorldOptions Debug => new WorldOptions(0) { GenerateFeatures = false };
        public static WorldOptions Flat => new WorldOptions(0) { GenerateFeatures = false };
    }

    public class LevelData
    {
        public LevelSettings Settings { get; set; }
        public WorldOptions Options { get; set; }
        public long GameTime { get; set; } = 0;
        public long DayTime { get; set; } = 0;
        public int Version { get; set; } = SharedConstants.WORLD_VERSION;
        public bool IsRaining { get; set; } = false;
        public int RainTime { get; set; } = 0;

        public LevelData(LevelSettings settings, WorldOptions options)
        {
            Settings = settings;
            Options = options;
        }
    }
}
