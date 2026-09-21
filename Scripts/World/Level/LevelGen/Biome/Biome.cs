using System;
using System.Collections.Generic;
using Minecraft.World.Level.Block;
using BlockClass = global::Minecraft.World.Level.Block.Block;

namespace Minecraft.World.Level.LevelGen.Biome
{
    /// <summary>
    /// Translation of net.minecraft.world.level.biome.Biome
    /// Holds temperature, humidity, precipitation, foliage colors, etc.
    /// </summary>
    public class Biome
    {
        public enum Precipitation { None, Rain, Snow }
        public enum TemperatureModifier { None, Frozen }

        public string Name { get; }
        public float Temperature { get; }
        public float Downfall { get; }
        public Precipitation HasPrecipitation { get; }
        public TemperatureModifier TempModifier { get; }
        public int SkyColor { get; }
        public int FoliageColor { get; }
        public int GrassColor { get; }
        public int WaterColor { get; }
        public int WaterFogColor { get; }

        // Surface blocks
        public BlockClass TopBlock { get; }
        public BlockClass MiddleBlock { get; }
        public BlockClass UnderwaterBlock { get; }

        // Features
        public List<string> Features { get; } = new List<string>();

        public Biome(string name, float temp, float downfall, Precipitation precip, int skyColor, int foliage, int grass, BlockClass top, BlockClass middle, BlockClass underwater = null)
        {
            Name = name;
            Temperature = temp;
            Downfall = downfall;
            HasPrecipitation = precip;
            SkyColor = skyColor;
            FoliageColor = foliage;
            GrassColor = grass;
            WaterColor = 0x3F76E4;
            WaterFogColor = 0x50533;
            TopBlock = top;
            MiddleBlock = middle;
            UnderwaterBlock = underwater ?? Blocks.SAND;
        }

        public static Biome CreatePlains() => new Biome("plains", 0.8f, 0.4f, Biome.Precipitation.Rain, 0x78A7FF, 0x77AB2F, 0x91BD59, Blocks.GRASS_BLOCK, Blocks.DIRT);
        public static Biome CreateDesert() => new Biome("desert", 2.0f, 0.0f, Biome.Precipitation.None, 0x78A7FF, 0xA0A0A0, 0xC2B280, Blocks.SAND, Blocks.SANDSTONE);
        public static Biome CreateForest() => new Biome("forest", 0.7f, 0.8f, Biome.Precipitation.Rain, 0x78A7FF, 0x79C05A, 0x79C05A, Blocks.GRASS_BLOCK, Blocks.DIRT);
        public static Biome CreateSnowyPlains() => new Biome("snowy_plains", 0.0f, 0.5f, Biome.Precipitation.Snow, 0x78A7FF, 0xFFFFFF, 0xFFFFFF, Blocks.SNOW_BLOCK, Blocks.DIRT, Blocks.GRAVEL);
        public static Biome CreateSwamp() => new Biome("swamp", 0.8f, 0.9f, Biome.Precipitation.Rain, 0x78A7FF, 0x6A7039, 0x6A7039, Blocks.GRASS_BLOCK, Blocks.DIRT);
        public static Biome CreateOcean() => new Biome("ocean", 0.5f, 0.5f, Biome.Precipitation.Rain, 0x78A7FF, 0x77AB2F, 0x91BD59, Blocks.GRAVEL, Blocks.GRAVEL, Blocks.GRAVEL);
    }

    public static class Biomes
    {
        public static readonly Biome PLAINS = Biome.CreatePlains();
        public static readonly Biome DESERT = Biome.CreateDesert();
        public static readonly Biome FOREST = Biome.CreateForest();
        public static readonly Biome SNOWY_PLAINS = Biome.CreateSnowyPlains();
        public static readonly Biome SWAMP = Biome.CreateSwamp();
        public static readonly Biome OCEAN = Biome.CreateOcean();
        public static readonly Biome MOUNTAINS = new Biome("windswept_hills", 0.2f, 0.3f, Biome.Precipitation.Rain, 0x78A7FF, 0x77AB2F, 0x91BD59, Blocks.GRASS_BLOCK, Blocks.DIRT);
        public static readonly Biome JUNGLE = new Biome("jungle", 0.95f, 0.9f, Biome.Precipitation.Rain, 0x78A7FF, 0x30BB0B, 0x59C93C, Blocks.GRASS_BLOCK, Blocks.DIRT);
        public static readonly Biome SAVANNA = new Biome("savanna", 1.2f, 0.0f, Biome.Precipitation.None, 0x78A7FF, 0xA0A0A0, 0xBFA76F, Blocks.GRASS_BLOCK, Blocks.DIRT);
        public static readonly Biome BADLANDS = new Biome("badlands", 2.0f, 0.0f, Biome.Precipitation.None, 0x78A7FF, 0x9E814D, 0x9E814D, Blocks.RED_SAND, Blocks.TERRACOTTA);
        public static readonly Biome TAIGA = new Biome("taiga", 0.25f, 0.8f, Biome.Precipitation.Rain, 0x78A7FF, 0x24852A, 0x24852A, Blocks.GRASS_BLOCK, Blocks.DIRT);
        public static readonly Biome DARK_FOREST = new Biome("dark_forest", 0.7f, 0.8f, Biome.Precipitation.Rain, 0x78A7FF, 0x79C05A, 0x79C05A, Blocks.GRASS_BLOCK, Blocks.DIRT);

        private static readonly Dictionary<string, Biome> _byName = new Dictionary<string, Biome>()
        {
            { "plains", PLAINS }, { "desert", DESERT }, { "forest", FOREST }, { "snowy_plains", SNOWY_PLAINS },
            { "swamp", SWAMP }, { "ocean", OCEAN }, { "mountains", MOUNTAINS }, { "jungle", JUNGLE },
            { "savanna", SAVANNA }, { "badlands", BADLANDS }, { "taiga", TAIGA }, { "dark_forest", DARK_FOREST }
        };

        public static Biome GetByName(string name) => _byName.TryGetValue(name, out var b) ? b : PLAINS;
        public static IEnumerable<Biome> All => _byName.Values;
    }

    /// <summary>
    /// Biome source - determines biome at position using noise (from net.minecraft.world.level.biome.BiomeSource / MultiNoiseBiomeSource)
    /// </summary>
    public class BiomeSource
    {
        private readonly Noise.PerlinNoise _biomeNoise;
        private readonly Noise.PerlinNoise _temperatureNoise;
        private readonly long _seed;

        public BiomeSource(long seed)
        {
            _seed = seed;
            var r = new Random((int)seed);
            _biomeNoise = new Noise.PerlinNoise(new Random(r.Next()));
            _temperatureNoise = new Noise.PerlinNoise(new Random(r.Next()));
        }

        public Biome GetBiome(int x, int y, int z)
        {
            double temp = _temperatureNoise.OctaveNoise(x * 0.001, z * 0.001, 0, 2);
            double biomeVal = _biomeNoise.OctaveNoise(x * 0.0005, 0, z * 0.0005, 3);

            // Simple biome selection - original uses multi-noise with 6 parameters
            if (biomeVal < -0.5) return Biomes.OCEAN;
            if (biomeVal < -0.3) return Biomes.SWAMP;
            if (temp < -0.4) return Biomes.SNOWY_PLAINS;
            if (temp > 0.6)
            {
                if (biomeVal > 0.4) return Biomes.DESERT;
                if (biomeVal > 0.1) return Biomes.SAVANNA;
                return Biomes.BADLANDS;
            }
            if (biomeVal > 0.5) return Biomes.MOUNTAINS;
            if (biomeVal > 0.3) return Biomes.FOREST;
            if (biomeVal > 0.15) return Biomes.TAIGA;
            return Biomes.PLAINS;
        }
    }
}
