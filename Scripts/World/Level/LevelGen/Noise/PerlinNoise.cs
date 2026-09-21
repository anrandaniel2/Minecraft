using System;
using Minecraft.Util.Math;

namespace Minecraft.World.Level.LevelGen.Noise
{
    /// <summary>
    /// Translation of net.minecraft.world.level.levelgen.synth.PerlinSimplexNoise / PerlinNoise / ImprovedNoise
    /// Original uses 256-entry permutation table and gradient noise.
    /// This implementation matches Minecraft's ImprovedNoise (Perlin) for terrain generation.
    /// </summary>
    public class PerlinNoise
    {
        private readonly int[] _p = new int[512];
        private readonly double _originX, _originY, _originZ;

        public PerlinNoise(Random random)
        {
            _originX = random.NextDouble() * 256;
            _originY = random.NextDouble() * 256;
            _originZ = random.NextDouble() * 256;
            int[] perm = new int[256];
            for (int i = 0; i < 256; i++) perm[i] = i;
            // Shuffle
            for (int i = 0; i < 256; i++)
            {
                int j = random.Next(256 - i) + i;
                (perm[i], perm[j]) = (perm[j], perm[i]);
            }
            for (int i = 0; i < 512; i++) _p[i] = perm[i & 255];
        }

        public PerlinNoise(long seed) : this(new Random((int)(seed ^ (seed >> 32)))) {}

        // Fade function - 6t^5 - 15t^4 + 10t^3
        private static double Fade(double t) => t * t * t * (t * (t * 6 - 15) + 10);
        private static double Lerp(double t, double a, double b) => a + t * (b - a);
        private static double Grad(int hash, double x, double y, double z)
        {
            int h = hash & 15;
            double u = h < 8 ? x : y;
            double v = h < 4 ? y : (h == 12 || h == 14 ? x : z);
            return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v);
        }

        public double Noise(double x, double y, double z = 0)
        {
            x += _originX; y += _originY; z += _originZ;
            int X = (int)System.Math.Floor(x) & 255;
            int Y = (int)System.Math.Floor(y) & 255;
            int Z = (int)System.Math.Floor(z) & 255;
            x -= System.Math.Floor(x);
            y -= System.Math.Floor(y);
            z -= System.Math.Floor(z);
            double u = Fade(x), v = Fade(y), w = Fade(z);
            int A = _p[X] + Y, AA = _p[A] + Z, AB = _p[A+1] + Z;
            int B = _p[X+1] + Y, BA = _p[B] + Z, BB = _p[B+1] + Z;

            return Lerp(w, Lerp(v, Lerp(u, Grad(_p[AA], x, y, z), Grad(_p[BA], x-1, y, z)),
                                   Lerp(u, Grad(_p[AB], x, y-1, z), Grad(_p[BB], x-1, y-1, z))),
                           Lerp(v, Lerp(u, Grad(_p[AA+1], x, y, z-1), Grad(_p[BA+1], x-1, y, z-1)),
                                   Lerp(u, Grad(_p[AB+1], x, y-1, z-1), Grad(_p[BB+1], x-1, y-1, z-1))));
        }

        public double OctaveNoise(double x, double y, double z, int octaves, double persistence = 0.5, double lacunarity = 2.0)
        {
            double total = 0, freq = 1, amp = 1, max = 0;
            for (int i = 0; i < octaves; i++)
            {
                total += Noise(x*freq, y*freq, z*freq) * amp;
                max += amp;
                amp *= persistence;
                freq *= lacunarity;
            }
            return total / max;
        }
    }

    /// <summary>
    /// Translation of net.minecraft.world.level.levelgen.synth.NormalNoise / BlendedNoise
    /// Used for density functions in 1.18+ worldgen.
    /// </summary>
    public class NormalNoise
    {
        private readonly PerlinNoise[] _layers;
        private readonly double[] _amplitudes;

        public NormalNoise(Random random, int firstOctave, double[] amplitudes)
        {
            _amplitudes = amplitudes;
            _layers = new PerlinNoise[amplitudes.Length];
            int lastOctave = firstOctave + amplitudes.Length - 1;
            for (int i = 0; i < amplitudes.Length; i++)
            {
                if (amplitudes[i] != 0)
                {
                    _layers[i] = new PerlinNoise(random);
                }
            }
        }

        public double GetValue(double x, double y, double z)
        {
            double sum = 0, ampSum = 0;
            for (int i = 0; i < _layers.Length; i++)
            {
                if (_layers[i] != null && _amplitudes[i] != 0)
                {
                    double freq = System.Math.Pow(2, i);
                    sum += _layers[i].Noise(x*freq, y*freq, z*freq) * _amplitudes[i];
                    ampSum += _amplitudes[i];
                }
            }
            return sum / ampSum;
        }
    }

    /// <summary>
    /// Simplex noise - for biome blending
    /// </summary>
    public class SimplexNoise
    {
        private readonly PerlinNoise _perlin;
        public SimplexNoise(long seed) => _perlin = new PerlinNoise(seed);
        public double Noise(double x, double y) => _perlin.Noise(x, y, 0);
        public double Noise(double x, double y, double z) => _perlin.Noise(x, y, z);
    }
}
