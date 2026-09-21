using Godot;
using System;
using System.Collections.Generic;
using Minecraft.World.Level.Chunk;
using Minecraft.World.Level.Block;
using Minecraft.Core;

namespace Minecraft.Client.Renderer
{
    /// <summary>
    /// Translation of net.minecraft.client.renderer.LevelRenderer / ChunkRenderer
    /// Manages chunk meshes, frustum culling, and rendering.
    /// Optimized for mobile: GridMap-like approach but custom MeshInstance3D with greedy meshing.
    /// </summary>
    public partial class WorldRenderer : Node3D
    {
        [Export] public Material OverrideMaterial;
        [Export] public bool EnableFrustumCulling = true;
        [Export] public int MaxMeshUpdatesPerFrame = 2;

        private Dictionary<long, ChunkMeshInstance> _chunkMeshes = new Dictionary<long, ChunkMeshInstance>(256);
        private Queue<LevelChunk> _meshUpdateQueue = new Queue<LevelChunk>(64);
        private Camera3D _camera;

        private StandardMaterial3D _opaqueMaterial;
        private StandardMaterial3D _transparentMaterial;

        public override void _Ready()
        {
            GD.Print("[WorldRenderer] Initialized - custom MeshInstance3D surface generation");
            // Create materials with Nearest filtering for pixel art
            _opaqueMaterial = new StandardMaterial3D();
            _opaqueMaterial.TextureFilter = BaseMaterial3D.TextureFilterEnum.Nearest;
            _opaqueMaterial.CullMode = BaseMaterial3D.CullModeEnum.Back;
            _opaqueMaterial.VertexColorUseAsAlbedo = true;

            _transparentMaterial = new StandardMaterial3D();
            _transparentMaterial.TextureFilter = BaseMaterial3D.TextureFilterEnum.Nearest;
            _transparentMaterial.Transparency = BaseMaterial3D.TransparencyEnum.AlphaScissor;
            _transparentMaterial.AlphaScissorThreshold = 0.5f;

            // Subscribe to chunk manager
            var chunkMgr = ChunkManager.Instance;
            if (chunkMgr != null)
            {
                chunkMgr.ChunkLoaded += OnChunkLoaded;
                chunkMgr.ChunkUnloaded += OnChunkUnloaded;
                chunkMgr.ChunkMeshDirty += OnChunkMeshDirty;
            }
        }

        public void SetCamera(Camera3D cam) => _camera = cam;

        public override void _Process(double delta)
        {
            // Process mesh updates - limited per frame for mobile
            int updates = 0;
            while (_meshUpdateQueue.Count > 0 && updates < MaxMeshUpdatesPerFrame)
            {
                var chunk = _meshUpdateQueue.Dequeue();
                if (chunk.MeshDirty)
                {
                    UpdateChunkMesh(chunk);
                    chunk.MeshDirty = false;
                    chunk.MeshVersion++;
                }
                updates++;
            }

            // Frustum culling
            if (EnableFrustumCulling && _camera != null)
            {
                // Would cull meshes outside frustum
            }
        }

        private void OnChunkLoaded(LevelChunk chunk)
        {
            // Queue for meshing
            _meshUpdateQueue.Enqueue(chunk);
        }

        private void OnChunkUnloaded(ChunkPos pos)
        {
            long key = pos.LongKey;
            if (_chunkMeshes.TryGetValue(key, out var meshInst))
            {
                meshInst.QueueFree();
                _chunkMeshes.Remove(key);
            }
        }

        private void OnChunkMeshDirty(LevelChunk chunk)
        {
            if (!_meshUpdateQueue.Contains(chunk))
                _meshUpdateQueue.Enqueue(chunk);
        }

        private void UpdateChunkMesh(LevelChunk chunk)
        {
            long key = chunk.Pos.LongKey;
            if (!_chunkMeshes.TryGetValue(key, out var meshInst))
            {
                meshInst = new ChunkMeshInstance();
                meshInst.Name = $"Chunk_{chunk.Pos.X}_{chunk.Pos.Z}";
                meshInst.Position = new Vector3(chunk.Pos.MinBlockX, 0, chunk.Pos.MinBlockZ);
                AddChild(meshInst);
                _chunkMeshes[key] = meshInst;
            }

            // Generate mesh for all sections in chunk
            // For mobile, we combine sections into one mesh per chunk to reduce draw calls
            var combinedVertices = new List<Vector3>(8192);
            var combinedNormals = new List<Vector3>(8192);
            var combinedUVs = new List<Vector2>(8192);
            var combinedColors = new List<Color>(8192);
            var combinedIndices = new List<int>(12288);
            int vertexOffset = 0;

            foreach (var section in chunk.Sections)
            {
                if (section.IsEmpty) continue;

                var meshData = ChunkMesher.GenerateMesh(chunk, section, worldPos =>
                {
                    // World lookup for face culling - checks neighboring chunks
                    return ChunkManager.Instance?.GetBlockState(worldPos) ?? BlockState.AIR;
                });

                if (meshData.IsEmpty) continue;

                // Offset vertices by section Y
                for (int i = 0; i < meshData.Vertices.Count; i++)
                {
                    Vector3 v = meshData.Vertices[i];
                    v.Y += section.YBase;
                    combinedVertices.Add(v);
                }
                combinedNormals.AddRange(meshData.Normals);
                combinedUVs.AddRange(meshData.UVs);
                combinedColors.AddRange(meshData.Colors);
                foreach (var idx in meshData.Indices)
                {
                    combinedIndices.Add(idx + vertexOffset);
                }
                vertexOffset += meshData.Vertices.Count;
            }

            if (combinedVertices.Count == 0)
            {
                meshInst.Visible = false;
                return;
            }

            meshInst.Visible = true;
            // Build Godot mesh
            var arrays = new Godot.Collections.Array();
            arrays.Resize((int)Mesh.ArrayType.Max);
            arrays[(int)Mesh.ArrayType.Vertex] = combinedVertices.ToArray();
            arrays[(int)Mesh.ArrayType.Normal] = combinedNormals.ToArray();
            arrays[(int)Mesh.ArrayType.TexUV] = combinedUVs.ToArray();
            arrays[(int)Mesh.ArrayType.Color] = combinedColors.ToArray();
            arrays[(int)Mesh.ArrayType.Index] = combinedIndices.ToArray();

            var arrayMesh = new ArrayMesh();
            arrayMesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arrays);
            // Set material
            arrayMesh.SurfaceSetMaterial(0, _opaqueMaterial);

            meshInst.Mesh = arrayMesh;
            // For collision, would also generate StaticBody3D with concave shape
        }

        public partial class ChunkMeshInstance : MeshInstance3D
        {
            public ChunkPos ChunkPos { get; set; }
            public int Version { get; set; } = 0;
        }
    }
}
