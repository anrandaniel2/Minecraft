using Godot;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading.Tasks;
using Minecraft.Core;
using Minecraft.World.Level.Block;

namespace Minecraft.World.Level.Chunk
{
    /// <summary>
    /// Translation of net.minecraft.server.level.ChunkMap / ServerChunkCache / ClientChunkCache
    /// Manages loaded chunks, loading/unloading, render distance, and mesh updates.
    /// Optimized for Android: conservative render distance, async loading, GC-friendly.
    /// </summary>
    public partial class ChunkManager : Node
    {
        public static ChunkManager Instance { get; private set; }

        [Export] public int RenderDistance = SharedConstants.DEFAULT_RENDER_DISTANCE;
        [Export] public int SimulationDistance = 6;
        [Export] public int MaxChunksPerFrame = SharedConstants.MAX_CHUNK_UPDATES_PER_FRAME;
        [Export] public bool EnableFrustumCulling = true;

        private ConcurrentDictionary<long, LevelChunk> _chunks = new ConcurrentDictionary<long, LevelChunk>();
        private Queue<ChunkPos> _loadQueue = new Queue<ChunkPos>();
        private Queue<long> _unloadQueue = new Queue<long>();
        private HashSet<long> _loadingSet = new HashSet<long>();

        private Vector3I _lastPlayerChunkPos = new Vector3I(int.MaxValue, 0, int.MaxValue);
        private long _tickCounter = 0;

        public event Action<LevelChunk> ChunkLoaded;
        public event Action<ChunkPos> ChunkUnloaded;
        public event Action<LevelChunk> ChunkMeshDirty;

        public override void _Ready()
        {
            Instance = this;
            // Mobile: lower render distance
            if (OS.GetName() == "Android")
            {
                RenderDistance = Math.Min(RenderDistance, SharedConstants.MAX_RENDER_DISTANCE);
            }
            GD.Print($"[ChunkManager] RenderDistance={RenderDistance}, SimDistance={SimulationDistance}");
        }

        public override void _Process(double delta)
        {
            ProcessQueues();
        }

        public void SetPlayerPosition(Vector3 worldPos)
        {
            Vector3I chunkPos = new Vector3I((int)MathF.Floor(worldPos.X) >> 4, 0, (int)MathF.Floor(worldPos.Z) >> 4);
            if (chunkPos != _lastPlayerChunkPos)
            {
                _lastPlayerChunkPos = chunkPos;
                UpdateChunkQueues(chunkPos);
            }
        }

        private void UpdateChunkQueues(Vector3I centerChunk)
        {
            // Determine chunks to load within render distance
            int r = RenderDistance;
            HashSet<long> needed = new HashSet<long>();

            for (int dx = -r; dx <= r; dx++)
            {
                for (int dz = -r; dz <= r; dz++)
                {
                    // Circular distance check for better performance (original uses square)
                    if (dx*dx + dz*dz > (r+1)*(r+1)) continue;
                    int cx = centerChunk.X + dx;
                    int cz = centerChunk.Z + dz;
                    long key = ChunkPos.AsLong(cx, cz);
                    needed.Add(key);
                    if (!_chunks.ContainsKey(key) && !_loadingSet.Contains(key))
                    {
                        _loadQueue.Enqueue(new ChunkPos(cx, cz));
                    }
                }
            }

            // Unload distant chunks
            foreach (var kvp in _chunks)
            {
                if (!needed.Contains(kvp.Key))
                {
                    _unloadQueue.Enqueue(kvp.Key);
                }
            }
        }

        private void ProcessQueues()
        {
            // Load up to MaxChunksPerFrame per frame to avoid stutter on mobile
            // Simplified synchronous version to avoid Task/CallDeferred Variant issues on Godot Mono Android
            int loads = 0;
            while (_loadQueue.Count > 0 && loads < MaxChunksPerFrame)
            {
                var pos = _loadQueue.Dequeue();
                long key = pos.LongKey;
                if (_chunks.ContainsKey(key)) continue;
                if (_loadingSet.Contains(key)) continue;

                _loadingSet.Add(key);
                try
                {
                    var chunk = GenerateChunk(pos);
                    if (chunk != null)
                    {
                        OnChunkGenerated(chunk);
                    }
                }
                finally
                {
                    _loadingSet.Remove(key);
                }
                loads++;
            }

            int unloads = 0;
            while (_unloadQueue.Count > 0 && unloads < MaxChunksPerFrame)
            {
                long key = _unloadQueue.Dequeue();
                if (_chunks.TryRemove(key, out var chunk))
                {
                    ChunkUnloaded?.Invoke(chunk.Pos);
                    // In real game, save to disk if dirty
                    if (chunk.IsDirty)
                    {
                        // SaveChunk(chunk);
                    }
                }
                unloads++;
            }
        }

        private void OnChunkGenerated(LevelChunk chunk)
        {
            _chunks[chunk.Pos.LongKey] = chunk;
            chunk.SetLoaded(true);
            ChunkLoaded?.Invoke(chunk);
            // Mark neighbors dirty for mesh updates (AO, etc.)
            MarkNeighborsDirty(chunk.Pos);
        }

        private LevelChunk GenerateChunk(ChunkPos pos)
        {
            // Delegates to world generator - simplified flat + noise
            var chunk = new LevelChunk(pos);
            // Use NoiseChunkGenerator (see WorldGen folder)
            var generator = WorldManager.Instance?.WorldGenerator;
            if (generator != null)
            {
                generator.FillChunk(chunk);
            }
            else
            {
                // Fallback: flat world for testing
                FillFlatChunk(chunk);
            }
            chunk.FillSkyLight();
            return chunk;
        }

        private void FillFlatChunk(LevelChunk chunk)
        {
            // Flat world: bedrock, dirt, grass
            for (int x = 0; x < 16; x++)
            {
                for (int z = 0; z < 16; z++)
                {
                    int worldX = chunk.Pos.MinBlockX + x;
                    int worldZ = chunk.Pos.MinBlockZ + z;
                    chunk.SetBlockState(new Vector3I(worldX, -64, worldZ), new BlockState(Blocks.BEDROCK.Id), false);
                    for (int y = -63; y < 0; y++)
                    {
                        chunk.SetBlockState(new Vector3I(worldX, y, worldZ), new BlockState(Blocks.STONE.Id), false);
                    }
                    for (int y = 0; y < 3; y++)
                    {
                        chunk.SetBlockState(new Vector3I(worldX, y, worldZ), new BlockState(Blocks.DIRT.Id), false);
                    }
                    chunk.SetBlockState(new Vector3I(worldX, 3, worldZ), new BlockState(Blocks.GRASS_BLOCK.Id), false);
                }
            }
        }

        private void MarkNeighborsDirty(ChunkPos pos)
        {
            for (int dx = -1; dx <= 1; dx++)
            {
                for (int dz = -1; dz <= 1; dz++)
                {
                    if (dx == 0 && dz == 0) continue;
                    long key = ChunkPos.AsLong(pos.X + dx, pos.Z + dz);
                    if (_chunks.TryGetValue(key, out var neighbor))
                    {
                        neighbor.MeshDirty = true;
                        ChunkMeshDirty?.Invoke(neighbor);
                    }
                }
            }
        }

        public LevelChunk GetChunk(int chunkX, int chunkZ)
        {
            long key = ChunkPos.AsLong(chunkX, chunkZ);
            _chunks.TryGetValue(key, out var chunk);
            return chunk;
        }

        public LevelChunk GetChunk(ChunkPos pos) => GetChunk(pos.X, pos.Z);

        public BlockState GetBlockState(Vector3I worldPos)
        {
            int chunkX = worldPos.X >> 4;
            int chunkZ = worldPos.Z >> 4;
            var chunk = GetChunk(chunkX, chunkZ);
            return chunk?.GetBlockState(worldPos) ?? BlockState.AIR;
        }

        public bool SetBlockState(Vector3I worldPos, BlockState state)
        {
            int chunkX = worldPos.X >> 4;
            int chunkZ = worldPos.Z >> 4;
            var chunk = GetChunk(chunkX, chunkZ);
            if (chunk == null) return false;
            chunk.SetBlockState(worldPos, state);
            ChunkMeshDirty?.Invoke(chunk);
            // Also dirty neighbors if on edge
            if ((worldPos.X & 15) == 0) GetChunk(chunkX-1, chunkZ)?.Let(c => { c.MeshDirty = true; ChunkMeshDirty?.Invoke(c); });
            if ((worldPos.X & 15) == 15) GetChunk(chunkX+1, chunkZ)?.Let(c => { c.MeshDirty = true; ChunkMeshDirty?.Invoke(c); });
            if ((worldPos.Z & 15) == 0) GetChunk(chunkX, chunkZ-1)?.Let(c => { c.MeshDirty = true; ChunkMeshDirty?.Invoke(c); });
            if ((worldPos.Z & 15) == 15) GetChunk(chunkX, chunkZ+1)?.Let(c => { c.MeshDirty = true; ChunkMeshDirty?.Invoke(c); });
            return true;
        }

        public void Tick()
        {
            _tickCounter++;
            // Unload old chunks every 600 ticks
            if (_tickCounter % SharedConstants.CHUNK_GC_INTERVAL_TICKS == 0)
            {
                // GC pass - could unload more aggressively on low memory
                if (OS.GetStaticMemoryUsage() > 200_000_000) // 200MB
                {
                    // Force unload distant chunks
                    GD.Print("[ChunkManager] Low memory, forcing chunk GC");
                }
            }
        }

        public int LoadedChunkCount => _chunks.Count;
        public IEnumerable<LevelChunk> GetLoadedChunks() => _chunks.Values;
    }

    public static class ChunkExtensions
    {
        public static void Let(this LevelChunk chunk, Action<LevelChunk> action) => action(chunk);
    }
}
