using Godot;
using System;

namespace Minecraft.World.Level.Chunk
{
    /// <summary>
    /// Translation of net.minecraft.world.level.ChunkPos
    /// </summary>
    public struct ChunkPos : IEquatable<ChunkPos>
    {
        public int X;
        public int Z;
        public long LongKey => ((long)X & 0xFFFFFFFFL) | (((long)Z & 0xFFFFFFFFL) << 32);

        public ChunkPos(int x, int z) { X = x; Z = z; }
        public ChunkPos(Vector3I blockPos) : this(blockPos.X >> 4, blockPos.Z >> 4) {}
        public ChunkPos(Vector3 worldPos) : this((int)MathF.Floor(worldPos.X) >> 4, (int)MathF.Floor(worldPos.Z) >> 4) {}
        public ChunkPos(long packed) { X = (int)packed; Z = (int)(packed >> 32); }

        public int MinBlockX => X << 4;
        public int MinBlockZ => Z << 4;
        public int MaxBlockX => (X << 4) + 15;
        public int MaxBlockZ => (Z << 4) + 15;
        public Vector3I WorldPosition => new Vector3I(MinBlockX, 0, MinBlockZ);

        public int GetChessboardDistance(ChunkPos other) => Math.Max(Math.Abs(X - other.X), Math.Abs(Z - other.Z));
        public int GetSquaredDistance(ChunkPos other)
        {
            int dx = X - other.X;
            int dz = Z - other.Z;
            return dx*dx + dz*dz;
        }

        public static long AsLong(int x, int z) => ((long)x & 0xFFFFFFFFL) | (((long)z & 0xFFFFFFFFL) << 32);
        public static long AsLong(Vector3I blockPos) => AsLong(blockPos.X >> 4, blockPos.Z >> 4);

        public bool Equals(ChunkPos other) => X==other.X && Z==other.Z;
        public override bool Equals(object obj) => obj is ChunkPos other && Equals(other);
        public override int GetHashCode() => HashCode.Combine(X, Z);
        public override string ToString() => $"[{X}, {Z}]";
        public static bool operator ==(ChunkPos a, ChunkPos b) => a.Equals(b);
        public static bool operator !=(ChunkPos a, ChunkPos b) => !a.Equals(b);
    }
}
