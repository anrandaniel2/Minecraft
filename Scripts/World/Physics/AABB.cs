using Godot;
using System;

namespace Minecraft.World.Physics
{
    /// <summary>
    /// Translation of net.minecraft.world.phys.AABB
    /// Axis-Aligned Bounding Box for collision, rendering, raycasting.
    /// Optimized with struct for mobile GC.
    /// </summary>
    public struct AABB : IEquatable<AABB>
    {
        public double MinX, MinY, MinZ;
        public double MaxX, MaxY, MaxZ;

        public static readonly AABB Zero = new AABB(0,0,0,0,0,0);
        public static readonly AABB Infinite = new AABB(double.NegativeInfinity, double.NegativeInfinity, double.NegativeInfinity, double.PositiveInfinity, double.PositiveInfinity, double.PositiveInfinity);

        public AABB(double minX, double minY, double minZ, double maxX, double maxY, double maxZ)
        {
            MinX = System.Math.Min(minX, maxX);
            MinY = System.Math.Min(minY, maxY);
            MinZ = System.Math.Min(minZ, maxZ);
            MaxX = System.Math.Max(minX, maxX);
            MaxY = System.Math.Max(minY, maxY);
            MaxZ = System.Math.Max(minZ, maxZ);
        }

        public AABB(Vector3 min, Vector3 max) : this(min.X, min.Y, min.Z, max.X, max.Y, max.Z) {}
        public AABB(Vector3I pos) : this(pos.X, pos.Y, pos.Z, pos.X+1, pos.Y+1, pos.Z+1) {}
        public AABB(Vector3 pos, float width, float height) : this(pos.X - width/2, pos.Y, pos.Z - width/2, pos.X + width/2, pos.Y + height, pos.Z + width/2) {}

        public double SizeX => MaxX - MinX;
        public double SizeY => MaxY - MinY;
        public double SizeZ => MaxZ - MinZ;
        public double Volume => SizeX * SizeY * SizeZ;

        public Vector3 Center => new Vector3((float)((MinX+MaxX)*0.5), (float)((MinY+MaxY)*0.5), (float)((MinZ+MaxZ)*0.5));

        public bool Intersects(AABB other) => MinX < other.MaxX && MaxX > other.MinX && MinY < other.MaxY && MaxY > other.MinY && MinZ < other.MaxZ && MaxZ > other.MinZ;

        public bool Contains(double x, double y, double z) => x >= MinX && x < MaxX && y >= MinY && y < MaxY && z >= MinZ && z < MaxZ;
        public bool Contains(Vector3 v) => Contains(v.X, v.Y, v.Z);

        public AABB Move(double dx, double dy, double dz) => new AABB(MinX+dx, MinY+dy, MinZ+dz, MaxX+dx, MaxY+dy, MaxZ+dz);
        public AABB Move(Vector3 v) => Move(v.X, v.Y, v.Z);
        public AABB Inflate(double x, double y, double z) => new AABB(MinX-x, MinY-y, MinZ-z, MaxX+x, MaxY+y, MaxZ+z);
        public AABB Inflate(double v) => Inflate(v,v,v);
        public AABB Deflate(double v) => Inflate(-v);
        public AABB ExpandTowards(Vector3 v) => ExpandTowards(v.X, v.Y, v.Z);
        public AABB ExpandTowards(double x, double y, double z)
        {
            double minX = MinX, minY = MinY, minZ = MinZ, maxX = MaxX, maxY = MaxY, maxZ = MaxZ;
            if (x < 0) minX += x; else if (x > 0) maxX += x;
            if (y < 0) minY += y; else if (y > 0) maxY += y;
            if (z < 0) minZ += z; else if (z > 0) maxZ += z;
            return new AABB(minX, minY, minZ, maxX, maxY, maxZ);
        }

        public AABB MinMax(AABB other) => new AABB(System.Math.Min(MinX, other.MinX), System.Math.Min(MinY, other.MinY), System.Math.Min(MinZ, other.MinZ), System.Math.Max(MaxX, other.MaxX), System.Math.Max(MaxY, other.MaxY), System.Math.Max(MaxZ, other.MaxZ));

        public bool Equals(AABB other) => MinX==other.MinX && MinY==other.MinY && MinZ==other.MinZ && MaxX==other.MaxX && MaxY==other.MaxY && MaxZ==other.MaxZ;
        public override bool Equals(object obj) => obj is AABB other && Equals(other);
        public override int GetHashCode() => HashCode.Combine(MinX, MinY, MinZ, MaxX, MaxY, MaxZ);

        // Raycasting - from AABB.clip
        public Vector3? Clip(Vector3 from, Vector3 to)
        {
            // Liang-Barsky ray-AABB
            double tMin = 0, tMax = 1;
            Vector3 dir = to - from;
            if (!ClipAxis(from.X, dir.X, MinX, MaxX, ref tMin, ref tMax)) return null;
            if (!ClipAxis(from.Y, dir.Y, MinY, MaxY, ref tMin, ref tMax)) return null;
            if (!ClipAxis(from.Z, dir.Z, MinZ, MaxZ, ref tMin, ref tMax)) return null;
            return from + dir * (float)tMin;
        }

        private static bool ClipAxis(double origin, double dir, double min, double max, ref double tMin, ref double tMax)
        {
            if (System.Math.Abs(dir) < 1e-8)
            {
                return origin >= min && origin <= max;
            }
            double t1 = (min - origin) / dir;
            double t2 = (max - origin) / dir;
            if (t1 > t2) (t1, t2) = (t2, t1);
            tMin = System.Math.Max(tMin, t1);
            tMax = System.Math.Min(tMax, t2);
            return tMin <= tMax;
        }

        public Godot.Aabb ToGodotAabb() => new Godot.Aabb(new Vector3((float)MinX, (float)MinY, (float)MinZ), new Vector3((float)SizeX, (float)SizeY, (float)SizeZ));
    }

    public static class VoxelShape
    {
        public static class Physics
        {
            public struct AABB
            {
                public float MinX, MinY, MinZ, MaxX, MaxY, MaxZ;
                public AABB(float minX, float minY, float minZ, float maxX, float maxY, float maxZ)
                {
                    MinX=minX; MinY=minY; MinZ=minZ; MaxX=maxX; MaxY=maxY; MaxZ=maxZ;
                }
                public static AABB Full => new AABB(0,0,0,1,1,1);
                public static AABB Empty => new AABB(0,0,0,0,0,0);
            }
        }
    }
}
