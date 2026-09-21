using Godot;
using System;
using System.Collections.Generic;
using Minecraft.World.Physics;
using Minecraft.World.Entity;
using GameLevel = global::Minecraft.World.Level.Level;
using EntityClass = global::Minecraft.World.Entity.Entity;

namespace Minecraft.World.Level.Block
{
    /// <summary>
    /// Base block class - translation of net.minecraft.world.level.block.Block
    /// Original: ~2000 lines, handles properties, behavior, state definition, etc.
    /// Optimized for mobile: struct-based state storage, flattened arrays.
    /// </summary>
    public class Block
    {
        // Block properties - from BlockBehaviour.Properties
        public sealed class Properties
        {
            public float DestroyTime { get; private set; } = 1.0f;
            public float ExplosionResistance { get; private set; } = 1.0f;
            public bool RequiresCorrectTool { get; private set; } = false;
            public bool NoCollision { get; private set; } = false;
            public bool IsAir { get; private set; } = false;
            public bool IsLiquid { get; private set; } = false;
            public int LightEmission { get; private set; } = 0;
            public SoundType Sound { get; private set; } = SoundType.Stone;
            public bool IsSolid { get; private set; } = true;
            public bool IsTransparent { get; private set; } = false;
            public bool IsRandomlyTicking { get; private set; } = false;

            public static Properties Of() => new Properties();

            public Properties Strength(float destroyTime, float resistance)
            {
                DestroyTime = destroyTime;
                ExplosionResistance = resistance;
                return this;
            }
            public Properties Strength(float strength) => Strength(strength, strength);
            public Properties NoCollission() { NoCollision = true; IsSolid = false; return this; }
            public Properties NoOcclusion() { IsTransparent = true; return this; }
            public Properties Air() { IsAir = true; IsSolid = false; NoCollision = true; return this; }
            public Properties LightLevel(int level) { LightEmission = level; return this; }
            public Properties WithSound(SoundType sound) { Sound = sound; return this; }
            public Properties RequiresTool() { RequiresCorrectTool = true; return this; }
            public Properties RandomTicks() { IsRandomlyTicking = true; return this; }
        }

        public enum SoundType
        {
            Stone, Wood, Gravel, Grass, Metal, Glass, Wool, Sand, Snow, Ladder, Anvil, Slime, Honey, Netherite
        }

        // Block registry ID - flattened for GC optimization
        public int Id { get; }
        public string Name { get; }
        public Properties BlockProperties { get; }
        public BlockState DefaultState { get; private set; }

        // Material properties for rendering/physics
        public bool IsAir => BlockProperties.IsAir;
        public bool IsSolid => BlockProperties.IsSolid;
        public bool IsTransparent => BlockProperties.IsTransparent;
        public bool IsLiquid => BlockProperties.IsLiquid;
        public int LightEmission => BlockProperties.LightEmission;

        // Texture mapping - atlas UVs
        public Vector2[] FaceUVs { get; protected set; } = new Vector2[6]; // -X,+X,-Y,+Y,-Z,+Z
        public string[] TextureNames { get; protected set; } = new string[6];

        public Block(int id, string name, Properties props)
        {
            Id = id;
            Name = name;
            BlockProperties = props;
            // Default UVs - will be replaced by atlas
            for (int i = 0; i < 6; i++) FaceUVs[i] = Vector2.Zero;
        }

        public virtual void SetDefaultState(BlockState state) => DefaultState = state;

        // Block behavior hooks - mirrors net.minecraft.world.level.block.Block methods
        public virtual void OnPlace(GameLevel level, Vector3I pos, BlockState state) { }
        public virtual void OnRemove(GameLevel level, Vector3I pos, BlockState state) { }
        public virtual void RandomTick(GameLevel level, Vector3I pos, BlockState state, Random random) { }
        public virtual void EntityInside(GameLevel level, Vector3I pos, BlockState state, EntityClass entity) { }
        public virtual bool CanSurvive(GameLevel level, Vector3I pos) => true;
        public virtual VoxelShape.Physics.AABB GetCollisionShape(BlockState state) => IsSolid ? new VoxelShape.Physics.AABB(0,0,0,1,1,1) : new VoxelShape.Physics.AABB(0,0,0,0,0,0);
        public virtual VoxelShape.Physics.AABB GetVisualShape(BlockState state) => GetCollisionShape(state);

        // For chunk meshing: should this face be rendered?
        public virtual bool ShouldRenderFace(BlockState self, GameLevel level, Vector3I pos, int face, BlockState neighbor)
        {
            if (IsAir) return false;
            if (neighbor.Block.IsAir) return true;
            if (IsTransparent && neighbor.Block.Id == Id) return false; // same transparent block culls
            if (!neighbor.Block.IsSolid && !neighbor.Block.IsTransparent) return true;
            if (IsTransparent) return neighbor.Block.IsAir || neighbor.Block.IsTransparent && neighbor.Block.Id != Id;
            return neighbor.Block.IsTransparent || !neighbor.Block.IsSolid;
        }

        public override string ToString() => $"Block[{Name}#{Id}]";
    }

    /// <summary>
    /// Struct-based BlockState for GC optimization - flattened, no heap alloc per block.
    /// Original Java uses immutable BlockState with Property map.
    /// Here we use struct with int id + byte data for mobile.
    /// </summary>
    public struct BlockState : IEquatable<BlockState>
    {
        public static readonly BlockState AIR = new BlockState(0);

        // Flattened storage: block id + 16-bit extra data (for variants like facing, waterlogged, etc.)
        public int BlockId;
        public ushort Data; // packs all properties: 4 bits per property max

        public Block Block => Blocks.GetById(BlockId);

        public BlockState(int blockId, ushort data = 0)
        {
            BlockId = blockId;
            Data = data;
        }

        public bool IsAir => BlockId == 0;
        public bool IsSolid => Block?.IsSolid ?? false;
        public bool IsTransparent => Block?.IsTransparent ?? true;

        // Property helpers - mimics BlockStateProperties
        public int GetIntProperty(int shift, int mask) => (Data >> shift) & mask;
        public BlockState WithIntProperty(int shift, int mask, int value)
        {
            ushort newData = (ushort)((Data & ~(mask << shift)) | ((value & mask) << shift));
            return new BlockState(BlockId, newData);
        }

        public bool Equals(BlockState other) => BlockId == other.BlockId && Data == other.Data;
        public override bool Equals(object obj) => obj is BlockState other && Equals(other);
        public override int GetHashCode() => (BlockId * 397) ^ Data;
        public static bool operator ==(BlockState left, BlockState right) => left.Equals(right);
        public static bool operator !=(BlockState left, BlockState right) => !left.Equals(right);
    }
}
