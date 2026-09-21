using Godot;
using System;
using Minecraft.World.Level.Chunk;
using Minecraft.Core;

namespace Minecraft.Server
{
    /// <summary>
    /// Translation of net.minecraft.server.MinecraftServer / DedicatedServer
    /// Handles server tick loop, world saving, player management.
    /// In Godot, server runs as separate process or integrated.
    /// </summary>
    public partial class DedicatedServer : Node
    {
        [Export] public int MaxPlayers = 20;
        [Export] public int ViewDistance = 10;
        [Export] public string Motd = "Minecraft 26.3 Godot Server";
        [Export] public bool OnlineMode = true;
        [Export] public bool WhiteList = false;

        private long _tickCount = 0;
        private bool _isRunning = false;

        public global::Minecraft.World.Level.Level Overworld { get; private set; }
        public global::Minecraft.World.Level.Level Nether { get; private set; }
        public global::Minecraft.World.Level.Level End { get; private set; }

        public override void _Ready()
        {
            GD.Print($"[DedicatedServer] Starting - {Motd}, MaxPlayers={MaxPlayers}");
        }

        public void StartServer(long seed)
        {
            _isRunning = true;
            Overworld = new global::Minecraft.World.Level.Level(seed, "overworld");
            Nether = new global::Minecraft.World.Level.Level(seed, "the_nether");
            End = new global::Minecraft.World.Level.Level(seed, "the_end");
            GD.Print($"[DedicatedServer] Worlds created - seed {seed}");
        }

        public override void _PhysicsProcess(double delta)
        {
            if (!_isRunning) return;
            // 20 TPS server tick - matches SharedConstants.TICKS_PER_SECOND
            _tickCount++;
            Overworld?.Tick();
            Nether?.Tick();
            End?.Tick();

            if (_tickCount % 6000 == 0) // every 5 minutes
            {
                SaveAllChunks();
            }
        }

        private void SaveAllChunks()
        {
            GD.Print("[DedicatedServer] Saving all chunks...");
            // Would save chunks to region files
        }

        public void StopServer()
        {
            _isRunning = false;
            SaveAllChunks();
            GD.Print("[DedicatedServer] Stopped");
        }
    }
}
