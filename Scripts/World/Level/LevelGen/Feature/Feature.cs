using Godot;
using System;
using Minecraft.World.Level.Block;
using Minecraft.World.Level.Chunk;
using BlockClass = global::Minecraft.World.Level.Block.Block;

namespace Minecraft.World.Level.LevelGen.Feature
{
    /// <summary>
    /// Translation of net.minecraft.world.level.levelgen.feature.Feature
    /// Base for all world features: trees, ores, lakes, etc.
    /// </summary>
    public abstract class Feature
    {
        public string Name { get; }
        protected Feature(string name) => Name = name;
        public abstract bool Place(global::Minecraft.World.Level.Level level, Vector3I pos, Random random);
    }

    public class TreeFeature : Feature
    {
        private readonly BlockClass _log;
        private readonly BlockClass _leaves;
        private readonly int _minHeight;

        public TreeFeature(string name, BlockClass log, BlockClass leaves, int minHeight = 5) : base(name)
        {
            _log = log;
            _leaves = leaves;
            _minHeight = minHeight;
        }

        public override bool Place(global::Minecraft.World.Level.Level level, Vector3I pos, Random random)
        {
            int height = _minHeight + random.Next(3);
            // Check space
            for (int y = 0; y < height + 3; y++)
            {
                var checkPos = pos + new Vector3I(0, y, 0);
                var state = level.GetBlockState(checkPos);
                if (!state.IsAir && state.BlockId != Blocks.OAK_LEAVES.Id) return false;
            }

            // Trunk
            for (int y = 0; y < height; y++)
            {
                level.SetBlockState(pos + new Vector3I(0, y, 0), new BlockState(_log.Id));
            }

            // Leaves - simple blob
            for (int dx = -2; dx <= 2; dx++)
            {
                for (int dz = -2; dz <= 2; dz++)
                {
                    for (int dy = -1; dy <= 1; dy++)
                    {
                        if (Math.Abs(dx) == 2 && Math.Abs(dz) == 2 && dy != 0) continue;
                        var leafPos = pos + new Vector3I(dx, height + dy, dz);
                        var existing = level.GetBlockState(leafPos);
                        if (existing.IsAir)
                        {
                            level.SetBlockState(leafPos, new BlockState(_leaves.Id));
                        }
                    }
                }
            }

            // Top
            level.SetBlockState(pos + new Vector3I(0, height, 0), new BlockState(_leaves.Id));
            level.SetBlockState(pos + new Vector3I(0, height+1, 0), new BlockState(_leaves.Id));

            return true;
        }

        public static readonly TreeFeature OAK = new TreeFeature("oak", Blocks.OAK_LOG, Blocks.OAK_LEAVES, 5);
        public static readonly TreeFeature SPRUCE = new TreeFeature("spruce", Blocks.SPRUCE_LOG, Blocks.SPRUCE_LEAVES, 7);
        public static readonly TreeFeature BIRCH = new TreeFeature("birch", Blocks.BIRCH_LOG, Blocks.BIRCH_LEAVES, 5);
    }

    public class OreFeature : Feature
    {
        private readonly BlockClass _ore;
        private readonly int _veinSize;
        private readonly int _minY;
        private readonly int _maxY;

        public OreFeature(string name, BlockClass ore, int veinSize, int minY, int maxY) : base(name)
        {
            _ore = ore;
            _veinSize = veinSize;
            _minY = minY;
            _maxY = maxY;
        }

        public override bool Place(global::Minecraft.World.Level.Level level, Vector3I pos, Random random)
        {
            int count = _veinSize;
            Vector3I current = pos;
            for (int i = 0; i < count; i++)
            {
                current += new Vector3I(random.Next(3)-1, random.Next(3)-1, random.Next(3)-1);
                if (current.Y < _minY || current.Y > _maxY) continue;
                var state = level.GetBlockState(current);
                if (state.BlockId == Blocks.STONE.Id || state.BlockId == Blocks.DEEPSLATE.Id)
                {
                    level.SetBlockState(current, new BlockState(_ore.Id));
                }
            }
            return true;
        }

        public static readonly OreFeature COAL = new OreFeature("coal", Blocks.COAL_ORE, 17, -64, 320);
        public static readonly OreFeature IRON = new OreFeature("iron", Blocks.IRON_ORE, 9, -64, 320);
        public static readonly OreFeature GOLD = new OreFeature("gold", Blocks.GOLD_ORE, 9, -64, 32);
        public static readonly OreFeature DIAMOND = new OreFeature("diamond", Blocks.DIAMOND_ORE, 8, -64, 16);
    }

    public class LakeFeature : Feature
    {
        private readonly BlockClass _liquid;
        public LakeFeature(string name, BlockClass liquid) : base(name) => _liquid = liquid;

        public override bool Place(global::Minecraft.World.Level.Level level, Vector3I pos, Random random)
        {
            // Simple lake - 5x5x2 water
            for (int dx = -2; dx <= 2; dx++)
            {
                for (int dz = -2; dz <= 2; dz++)
                {
                    for (int dy = 0; dy < 2; dy++)
                    {
                        if (dx*dx + dz*dz <= 4)
                        {
                            level.SetBlockState(pos + new Vector3I(dx, dy, dz), new BlockState(_liquid.Id));
                        }
                    }
                }
            }
            return true;
        }
    }

    public static class Features
    {
        public static readonly TreeFeature[] TREES = new TreeFeature[] { TreeFeature.OAK, TreeFeature.SPRUCE, TreeFeature.BIRCH };
        public static readonly OreFeature[] ORES = new OreFeature[] { OreFeature.COAL, OreFeature.IRON, OreFeature.GOLD, OreFeature.DIAMOND };
    }
}
