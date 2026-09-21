using Godot;
using System;
using System.Collections.Generic;
using Minecraft.World.Level.Block;
using Minecraft.World.Level.Chunk;
using Minecraft.Core;

namespace Minecraft.World.Level
{
    /// <summary>
    /// Translation of net.minecraft.world.level.Level - central world class
    /// Manages blocks, entities, game rules, time, weather.
    /// </summary>
    public class Level
    {
        public long Seed { get; }
        public string Dimension { get; }
        public long GameTime { get; private set; } = 0;
        public long DayTime { get; private set; } = 0;
        public bool IsRaining { get; private set; } = false;
        public bool IsThundering { get; private set; } = false;
        public int RainTime { get; private set; } = 0;
        public int ThunderTime { get; private set; } = 0;

        public GameRules GameRules { get; } = new GameRules();

        // Entity list
        private List<global::Minecraft.World.Entity.Entity> _entities = new List<global::Minecraft.World.Entity.Entity>(256);
        private List<global::Minecraft.World.Entity.Entity> _toAdd = new List<global::Minecraft.World.Entity.Entity>(32);
        private List<global::Minecraft.World.Entity.Entity> _toRemove = new List<global::Minecraft.World.Entity.Entity>(32);

        public Level(long seed, string dimension)
        {
            Seed = seed;
            Dimension = dimension;
        }

        public void Tick()
        {
            GameTime++;
            DayTime = (DayTime + 1) % 24000; // Minecraft day = 24000 ticks

            // Weather
            if (RainTime > 0) RainTime--;
            else
            {
                if (GD.Randf() < 0.001f) IsRaining = !IsRaining;
                RainTime = GD.RandRange(12000, 24000);
            }

            // Entities
            foreach (var e in _toAdd) _entities.Add(e);
            _toAdd.Clear();
            foreach (var e in _toRemove) _entities.Remove(e);
            _toRemove.Clear();

            foreach (var entity in _entities)
            {
                entity.Tick();
            }

            // Random block ticks - from Level.tickChunk
            // Would tick random blocks in each chunk if randomTickSpeed >0
        }

        public BlockState GetBlockState(Vector3I pos)
        {
            // Delegates to ChunkManager
            return ChunkManager.Instance?.GetBlockState(pos) ?? BlockState.AIR;
        }

        public bool SetBlockState(Vector3I pos, BlockState state, int flags = 3)
        {
            // flags: 1=update neighbors, 2=send to clients, 3=both
            bool result = ChunkManager.Instance?.SetBlockState(pos, state) ?? false;
            if (result && (flags & 1) != 0)
            {
                // Update neighbors - for redstone, etc.
                UpdateNeighbors(pos);
            }
            return result;
        }

        private void UpdateNeighbors(Vector3I pos)
        {
            // Notify 6 neighbors - for redstone, pistons, etc.
            // Simplified
        }

        public void AddEntity(global::Minecraft.World.Entity.Entity entity)
        {
            _toAdd.Add(entity);
        }

        public void RemoveEntity(global::Minecraft.World.Entity.Entity entity)
        {
            _toRemove.Add(entity);
        }

        public IEnumerable<global::Minecraft.World.Entity.Entity> GetEntities() => _entities;

        public bool IsAir(Vector3I pos) => GetBlockState(pos).IsAir;
        public bool IsSolid(Vector3I pos) => GetBlockState(pos).IsSolid;

        // Raycasting - from Level.clip / ClipContext
        public BlockHitResult Clip(ClipContext context)
        {
            // Simplified raycast - walks along ray and checks blocks
            Vector3 from = context.From;
            Vector3 to = context.To;
            Vector3 dir = (to - from).Normalized();
            float maxDist = from.DistanceTo(to);
            float step = 0.1f;
            Vector3 current = from;
            for (float d = 0; d < maxDist; d += step)
            {
                Vector3I blockPos = new Vector3I((int)MathF.Floor(current.X), (int)MathF.Floor(current.Y), (int)MathF.Floor(current.Z));
                BlockState state = GetBlockState(blockPos);
                if (!state.IsAir && state.IsSolid)
                {
                    // Hit
                    return new BlockHitResult(true, blockPos, current, Vector3.Up, state);
                }
                current += dir * step;
            }
            return new BlockHitResult(false, Vector3I.Zero, to, Vector3.Zero, BlockState.AIR);
        }

        public int GetBrightness(Vector3I pos)
        {
            // Simplified light - would use sky + block light
            return 15;
        }
    }

    public class GameRules
    {
        // From net.minecraft.world.level.GameRules
        public bool DoDaylightCycle = true;
        public bool DoWeatherCycle = true;
        public bool DoMobSpawning = true;
        public bool DoFireTick = true;
        public int RandomTickSpeed = 3;
        public bool KeepInventory = false;
        public bool DoMobLoot = true;
        public bool DoTileDrops = true;
        public bool NaturalRegeneration = true;
    }

    public struct ClipContext
    {
        public Vector3 From;
        public Vector3 To;
        public enum BlockMode { Collider, Outline, Visual, FallDamage }
        public enum FluidMode { None, SourceOnly, Any }
        public BlockMode Block;
        public FluidMode Fluid;

        public ClipContext(Vector3 from, Vector3 to, BlockMode block, FluidMode fluid)
        {
            From = from; To = to; Block = block; Fluid = fluid;
        }
    }

    public struct BlockHitResult
    {
        public bool Hit;
        public Vector3I BlockPos;
        public Vector3 Location;
        public Vector3 Normal;
        public BlockState State;

        public BlockHitResult(bool hit, Vector3I blockPos, Vector3 location, Vector3 normal, BlockState state)
        {
            Hit = hit; BlockPos = blockPos; Location = location; Normal = normal; State = state;
        }
    }
}
