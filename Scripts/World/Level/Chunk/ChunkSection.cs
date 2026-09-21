using System;
using Minecraft.World.Level.Block;
using Minecraft.Core;

namespace Minecraft.World.Level.Chunk
{
    /// <summary>
    /// Translation of net.minecraft.world.level.chunk.LevelChunkSection
    /// Stores 16x16x16 blocks using palette + flattened array for GC optimization.
    /// Mobile optimized: uses ushort[] instead of BlockState[] object array to avoid 4096 heap objects per section.
    /// Original uses PalettedContainer - we implement simplified version with global palette (block id) + local palette compression.
    /// </summary>
    public class ChunkSection
    {
        public const int SIZE = 16;
        public const int VOLUME = SIZE * SIZE * SIZE; // 4096
        public const int BIOME_SIZE = 4; // 4x4x4 biomes per section
        public const int BIOME_VOLUME = BIOME_SIZE * BIOME_SIZE * BIOME_SIZE; // 64

        // Flattened block storage - ushort block id for GC efficiency (no BlockState objects)
        // For full data we store separate ushort data array
        private ushort[] _blockIds; // 4096 * 2 bytes = 8KB per section
        private ushort[] _blockData; // 8KB extra for state
        private byte[] _blockLight; // 2048 bytes (nibble)
        private byte[] _skyLight; // 2048 bytes

        public int YBase { get; }
        public bool IsEmpty { get; private set; } = true;
        public int NonEmptyBlockCount { get; private set; } = 0;
        public int TickingBlockCount { get; private set; } = 0;
        public int TickingFluidCount { get; private set; } = 0;

        // Biome palette - simplified
        private byte[] _biomes; // 64 bytes

        public ChunkSection(int yBase)
        {
            YBase = yBase;
            _blockIds = new ushort[VOLUME];
            _blockData = new ushort[VOLUME];
            _blockLight = new byte[VOLUME / 2];
            _skyLight = new byte[VOLUME / 2];
            _biomes = new byte[BIOME_VOLUME];
            // Initialize to air (0)
            IsEmpty = true;
        }

        // Index calculation: x + z*16 + y*256  (y major for cache)
        public static int GetIndex(int x, int y, int z) => (y << 8) | (z << 4) | x;
        // Original Minecraft uses y << 8 | z << 4 | x

        public BlockState GetBlockState(int x, int y, int z)
        {
            if (x < 0 || x >= SIZE || y < 0 || y >= SIZE || z < 0 || z >= SIZE) return BlockState.AIR;
            int idx = GetIndex(x, y, z);
            return new BlockState(_blockIds[idx], _blockData[idx]);
        }

        public BlockState SetBlockState(int x, int y, int z, BlockState state)
        {
            int idx = GetIndex(x, y, z);
            BlockState old = new BlockState(_blockIds[idx], _blockData[idx]);
            
            _blockIds[idx] = (ushort)state.BlockId;
            _blockData[idx] = state.Data;

            // Update counters
            bool wasAir = old.BlockId == 0;
            bool isAir = state.BlockId == 0;
            if (wasAir && !isAir)
            {
                NonEmptyBlockCount++;
                IsEmpty = false;
                if (state.Block?.BlockProperties.IsRandomlyTicking ?? false) TickingBlockCount++;
            }
            else if (!wasAir && isAir)
            {
                NonEmptyBlockCount--;
                if (NonEmptyBlockCount == 0) IsEmpty = true;
                if (old.Block?.BlockProperties.IsRandomlyTicking ?? false) TickingBlockCount--;
            }

            return old;
        }

        // Light
        public int GetBlockLight(int x, int y, int z)
        {
            int idx = GetIndex(x, y, z);
            int byteIdx = idx >> 1;
            return (idx & 1) == 0 ? _blockLight[byteIdx] & 0xF : (_blockLight[byteIdx] >> 4) & 0xF;
        }

        public void SetBlockLight(int x, int y, int z, int light)
        {
            int idx = GetIndex(x, y, z);
            int byteIdx = idx >> 1;
            if ((idx & 1) == 0)
                _blockLight[byteIdx] = (byte)((_blockLight[byteIdx] & 0xF0) | (light & 0xF));
            else
                _blockLight[byteIdx] = (byte)((_blockLight[byteIdx] & 0x0F) | ((light & 0xF) << 4));
        }

        public int GetSkyLight(int x, int y, int z)
        {
            int idx = GetIndex(x, y, z);
            int byteIdx = idx >> 1;
            return (idx & 1) == 0 ? _skyLight[byteIdx] & 0xF : (_skyLight[byteIdx] >> 4) & 0xF;
        }

        public void SetSkyLight(int x, int y, int z, int light)
        {
            int idx = GetIndex(x, y, z);
            int byteIdx = idx >> 1;
            if ((idx & 1) == 0)
                _skyLight[byteIdx] = (byte)((_skyLight[byteIdx] & 0xF0) | (light & 0xF));
            else
                _skyLight[byteIdx] = (byte)((_skyLight[byteIdx] & 0x0F) | ((light & 0xF) << 4));
        }

        // For meshing - direct array access (no alloc)
        public Span<ushort> GetBlockIdsSpan() => _blockIds.AsSpan();
        public bool HasOnlyAir() => IsEmpty;

        public void FillSkyLight(int value)
        {
            byte b = (byte)((value & 0xF) | ((value & 0xF) << 4));
            Array.Fill(_skyLight, b);
        }

        // Serialization - for saving/loading
        public byte[] Serialize()
        {
            // Simplified NBT-like serialization
            // Real Minecraft uses PalettedContainer serialization
            byte[] data = new byte[VOLUME * 4 + 8];
            Buffer.BlockCopy(_blockIds, 0, data, 0, VOLUME*2);
            Buffer.BlockCopy(_blockData, 0, data, VOLUME*2, VOLUME*2);
            return data;
        }

        public void Deserialize(byte[] data)
        {
            Buffer.BlockCopy(data, 0, _blockIds, 0, VOLUME*2);
            Buffer.BlockCopy(data, VOLUME*2, _blockData, 0, VOLUME*2);
            // Recalc counts
            NonEmptyBlockCount = 0;
            IsEmpty = true;
            for (int i = 0; i < VOLUME; i++)
            {
                if (_blockIds[i] != 0)
                {
                    NonEmptyBlockCount++;
                    IsEmpty = false;
                }
            }
        }
    }
}
