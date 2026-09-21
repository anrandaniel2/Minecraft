using System;
using Minecraft.World.Level.Chunk;

namespace Minecraft.World.Level.LevelGen.WorldGen
{
    /// <summary>
    /// Translation of net.minecraft.world.level.levelgen.Aquifer
    /// Handles water/lava placement in noise caves.
    /// </summary>
    public class Aquifer
    {
        public enum FluidStatus { Air, Water, Lava }

        private readonly long _seed;
        private readonly int _seaLevel;

        public Aquifer(long seed, int seaLevel = 62)
        {
            _seed = seed;
            _seaLevel = seaLevel;
        }

        public FluidStatus GetFluidStatus(int x, int y, int z)
        {
            if (y > _seaLevel) return FluidStatus.Air;
            if (y < -54) return FluidStatus.Lava; // lava level in 1.18+
            return FluidStatus.Water;
        }

        public class NoiseBasedAquifer : Aquifer
        {
            private readonly Noise.PerlinNoise _barrierNoise;
            private readonly Noise.PerlinNoise _fluidLevelNoise;

            public NoiseBasedAquifer(long seed, int seaLevel) : base(seed, seaLevel)
            {
                var r = new Random((int)seed);
                _barrierNoise = new Noise.PerlinNoise(new Random(r.Next()));
                _fluidLevelNoise = new Noise.PerlinNoise(new Random(r.Next()));
            }

            public bool ShouldPlaceBarrier(int x, int y, int z)
            {
                double noise = _barrierNoise.Noise(x * 0.01, y * 0.01, z * 0.01);
                return noise > 0.5;
            }
        }
    }

    /// <summary>
    /// Translation of Beardifier - for structure beard (villages, etc. carve terrain)
    /// </summary>
    public class Beardifier
    {
        public struct Rigid
        {
            public int MinY;
            public int MaxY;
            public double Factor;
        }

        public static double GetBeardContribution(int x, int y, int z)
        {
            // Would sample structure boxes and apply smoothing
            return 0;
        }
    }

    /// <summary>
    /// Translation of DensityFunctions - new 1.18+ density function system
    /// </summary>
    public static class DensityFunctions
    {
        public static double FinalDensity(double continent, double erosion, double depth, double ridge)
        {
            // Spline + density combination from data/minecraft/worldgen/density_function/
            return continent + erosion * 0.5 + depth;
        }

        public static double Depth(int y, int minY, int maxY)
        {
            return (y - minY) / (double)(maxY - minY) * 2 - 1;
        }
    }
}
