using Godot;
using System;
using Minecraft.World.Level.Block;
using Minecraft.Core;

namespace Minecraft.World.Level.Chunk
{
    /// <summary>
    /// Translation of net.minecraft.world.level.chunk.LevelChunk
    /// Holds 24 sections (for -64 to 320 height), block entities, ticks, etc.
    /// Optimized: flattened arrays, no per-block object allocation.
    /// </summary>
    public class LevelChunk
    {
        public ChunkPos Pos { get; }
        public int MinSection { get; } // -4 for -64 y
        public int MaxSection { get; } // 19 for 320 y
        public ChunkSection[] Sections { get; }
        public int MinY => MinSection * ChunkSection.SIZE;
        public int MaxY => (MaxSection + 1) * ChunkSection.SIZE;
        public bool IsLoaded { get; private set; } = false;
        public bool IsDirty { get; set; } = false;
        public long LastAccessTick { get; set; } = 0;

        // Heightmaps - from net.minecraft.world.level.chunk.Heightmap
        public enum HeightmapType { WorldSurface, MotionBlocking, MotionBlockingNoLeaves, OceanFloor }
        private short[] _worldSurfaceHeightmap; // 256 entries (16x16)
        private short[] _motionBlockingHeightmap;

        // For mesh dirty flag
        public bool MeshDirty { get; set; } = true;
        public int MeshVersion { get; set; } = 0;

        public LevelChunk(ChunkPos pos, int minSection = -4, int maxSection = 19)
        {
            Pos = pos;
            MinSection = minSection;
            MaxSection = maxSection;
            int count = maxSection - minSection + 1;
            Sections = new ChunkSection[count];
            for (int i = 0; i < count; i++)
            {
                int yBase = (minSection + i) * ChunkSection.SIZE;
                Sections[i] = new ChunkSection(yBase);
            }
            _worldSurfaceHeightmap = new short[256];
            _motionBlockingHeightmap = new short[256];
            Array.Fill(_worldSurfaceHeightmap, (short)SharedConstants.MIN_Y);
            Array.Fill(_motionBlockingHeightmap, (short)SharedConstants.MIN_Y);
        }

        public ChunkSection GetSection(int sectionY)
        {
            int idx = sectionY - MinSection;
            if (idx < 0 || idx >= Sections.Length) return null;
            return Sections[idx];
        }

        public ChunkSection GetSectionForY(int y)
        {
            int sectionY = y >> 4;
            return GetSection(sectionY);
        }

        public BlockState GetBlockState(Vector3I pos) => GetBlockState(pos.X, pos.Y, pos.Z);

        public BlockState GetBlockState(int x, int y, int z)
        {
            // x,z are world coords
            int localX = x & 15;
            int localZ = z & 15;
            var section = GetSectionForY(y);
            if (section == null) return BlockState.AIR;
            int localY = y & 15;
            return section.GetBlockState(localX, localY, localZ);
        }

        public BlockState SetBlockState(Vector3I pos, BlockState state, bool updateHeightmap = true)
        {
            int x = pos.X, y = pos.Y, z = pos.Z;
            int localX = x & 15;
            int localZ = z & 15;
            var section = GetSectionForY(y);
            if (section == null) return BlockState.AIR;
            int localY = y & 15;
            BlockState old = section.SetBlockState(localX, localY, localZ, state);
            IsDirty = true;
            MeshDirty = true;

            if (updateHeightmap)
            {
                int hmIdx = (localZ << 4) | localX;
                // Update heightmaps if needed
                if (!state.IsAir && y >= _worldSurfaceHeightmap[hmIdx])
                {
                    _worldSurfaceHeightmap[hmIdx] = (short)y;
                }
                else if (state.IsAir && y == _worldSurfaceHeightmap[hmIdx])
                {
                    // Need to recalc downwards - simplified
                    RecalcHeightmapColumn(localX, localZ);
                }
            }

            return old;
        }

        private void RecalcHeightmapColumn(int localX, int localZ)
        {
            int hmIdx = (localZ << 4) | localX;
            for (int y = MaxY - 1; y >= MinY; y--)
            {
                if (!GetBlockState(Pos.MinBlockX + localX, y, Pos.MinBlockZ + localZ).IsAir)
                {
                    _worldSurfaceHeightmap[hmIdx] = (short)y;
                    return;
                }
            }
            _worldSurfaceHeightmap[hmIdx] = (short)MinY;
        }

        public int GetHeight(HeightmapType type, int x, int z)
        {
            int localX = x & 15;
            int localZ = z & 15;
            int idx = (localZ << 4) | localX;
            return type switch
            {
                HeightmapType.WorldSurface => _worldSurfaceHeightmap[idx],
                HeightmapType.MotionBlocking => _motionBlockingHeightmap[idx],
                _ => _worldSurfaceHeightmap[idx]
            };
        }

        public void SetLoaded(bool loaded) => IsLoaded = loaded;

        // For chunk manager: check if chunk has any blocks (for culling empty chunks)
        public bool IsEmptyChunk()
        {
            foreach (var sec in Sections)
                if (!sec.IsEmpty) return false;
            return true;
        }

        // Light - simplified
        public void FillSkyLight()
        {
            foreach (var sec in Sections) sec.FillSkyLight(15);
        }

        // Serialization
        public byte[] Serialize()
        {
            // Simplified - real uses NBT
            using var ms = new System.IO.MemoryStream();
            using var bw = new System.IO.BinaryWriter(ms);
            bw.Write(Pos.X);
            bw.Write(Pos.Z);
            foreach (var sec in Sections)
            {
                var data = sec.Serialize();
                bw.Write(data.Length);
                bw.Write(data);
            }
            return ms.ToArray();
        }
    }
}
