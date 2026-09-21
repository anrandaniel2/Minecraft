using Godot;
using System;
using Minecraft.Core;

namespace Minecraft.World.Level.Dimension
{
    /// <summary>
    /// Translation of net.minecraft.world.level.dimension.DimensionType and Dimension
    /// Handles Overworld, Nether, End with their specific generation and properties.
    /// </summary>
    public class DimensionType
    {
        public string Name { get; }
        public int MinY { get; }
        public int MaxY { get; }
        public int Height => MaxY - MinY;
        public bool HasSkyLight { get; }
        public bool HasCeiling { get; }
        public bool Ultrawarm { get; }
        public bool Natural { get; }
        public double CoordinateScale { get; }
        public bool BedWorks { get; }
        public bool RespawnAnchorWorks { get; }
        public int LogicalHeight { get; }

        public DimensionType(string name, int minY, int maxY, bool hasSkyLight, bool hasCeiling, bool ultrawarm, bool natural, double coordScale, bool bedWorks, bool anchorWorks)
        {
            Name = name;
            MinY = minY;
            MaxY = maxY;
            HasSkyLight = hasSkyLight;
            HasCeiling = hasCeiling;
            Ultrawarm = ultrawarm;
            Natural = natural;
            CoordinateScale = coordScale;
            BedWorks = bedWorks;
            RespawnAnchorWorks = anchorWorks;
            LogicalHeight = maxY - minY;
        }

        public static readonly DimensionType OVERWORLD = new DimensionType("overworld", -64, 320, true, false, false, true, 1.0, true, false);
        public static readonly DimensionType NETHER = new DimensionType("the_nether", 0, 128, false, true, true, false, 8.0, false, true);
        public static readonly DimensionType END = new DimensionType("the_end", 0, 256, false, false, false, false, 1.0, false, false);

        public static DimensionType ByName(string name) => name switch
        {
            "the_nether" => NETHER,
            "the_end" => END,
            _ => OVERWORLD
        };
    }

    public abstract class Dimension
    {
        public DimensionType Type { get; }
        public long Seed { get; }
        protected Dimension(DimensionType type, long seed) { Type = type; Seed = seed; }
        public abstract void FillChunk(global::Minecraft.World.Level.Chunk.LevelChunk chunk);
    }

    public class OverworldDimension : Dimension
    {
        private readonly LevelGen.WorldGen.NoiseChunkGenerator _generator;
        public OverworldDimension(long seed) : base(DimensionType.OVERWORLD, seed)
        {
            _generator = new LevelGen.WorldGen.NoiseChunkGenerator(seed);
        }
        public override void FillChunk(global::Minecraft.World.Level.Chunk.LevelChunk chunk) => _generator.FillChunk(chunk);
    }

    public class NetherDimension : Dimension
    {
        public NetherDimension(long seed) : base(DimensionType.NETHER, seed) {}
        public override void FillChunk(global::Minecraft.World.Level.Chunk.LevelChunk chunk)
        {
            // Nether generation - netherrack, lava, etc.
            for (int x = 0; x < 16; x++)
            {
                for (int z = 0; z < 16; z++)
                {
                    int wx = chunk.Pos.MinBlockX + x;
                    int wz = chunk.Pos.MinBlockZ + z;
                    for (int y = Type.MinY; y < Type.MaxY; y++)
                    {
                        if (y < 5) chunk.SetBlockState(new Vector3I(wx, y, wz), new global::Minecraft.World.Level.Block.BlockState(global::Minecraft.World.Level.Block.Blocks.BEDROCK.Id), false);
                        else if (y < 100) chunk.SetBlockState(new Vector3I(wx, y, wz), new global::Minecraft.World.Level.Block.BlockState(global::Minecraft.World.Level.Block.Blocks.NETHERRACK.Id), false);
                    }
                }
            }
        }
    }

    public class EndDimension : Dimension
    {
        public EndDimension(long seed) : base(DimensionType.END, seed) {}
        public override void FillChunk(global::Minecraft.World.Level.Chunk.LevelChunk chunk)
        {
            // End generation - obsidian platform + end stone island
            for (int x = 0; x < 16; x++)
            {
                for (int z = 0; z < 16; z++)
                {
                    int wx = chunk.Pos.MinBlockX + x;
                    int wz = chunk.Pos.MinBlockZ + z;
                    double dist = Math.Sqrt(wx*wx + wz*wz);
                    if (dist < 100)
                    {
                        chunk.SetBlockState(new Vector3I(wx, 60, wz), new global::Minecraft.World.Level.Block.BlockState(global::Minecraft.World.Level.Block.Blocks.END_STONE.Id), false);
                    }
                }
            }
        }
    }
}
