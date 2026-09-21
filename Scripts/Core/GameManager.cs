using Godot;
using Minecraft.Client;
using Minecraft.World;

namespace Minecraft.Core
{
    /// <summary>
    /// Root singleton managing Godot lifecycle.
    /// Translates net.minecraft.client.Minecraft.java main loop (Runnable) into Godot _Ready/_Process/_PhysicsProcess.
    /// Original Minecraft.java: ~3000 lines, handles window, gameRenderer, level, player, particleEngine, soundEngine, etc.
    /// Here we map to Godot's Engine loop.
    /// </summary>
    public partial class GameManager : Node
    {
        public static GameManager Instance { get; private set; }

        [Export] public int TargetFps = 60;
        [Export] public bool IsMobile = true;

        public MinecraftClient Client { get; private set; }
        public WorldManager WorldManager { get; private set; }
        public bool IsPaused { get; private set; }
        public float DeltaTime { get; private set; }

        private long _tickCounter = 0;
        private float _tickAccumulator = 0f;

        public override void _Ready()
        {
            Instance = this;
            GD.Print($"[Minecraft] Starting {SharedConstants.VERSION_STRING} - {WorldVersion.CURRENT.Name}");
            GD.Print($"[Minecraft] Protocol {SharedConstants.PROTOCOL_VERSION}, Data {SharedConstants.WORLD_VERSION}");
            
            // Mobile optimizations
            if (OS.GetName() == "Android" || IsMobile)
            {
                OS.LowProcessorUsageMode = false;
                Engine.MaxFps = TargetFps;
                // Conservative GC for Android
                // Use struct-based arrays to minimize heap allocs
            }

            Client = new MinecraftClient();
            WorldManager = GetNode<WorldManager>("/root/WorldManager");
            
            // Initialize asset manager
            var assetMgr = GetNode<Assets.AssetManager>("/root/AssetManager");
            assetMgr.Initialize();

            // Load main menu
            CallDeferred(MethodName.SwitchToMainMenu);
        }

        public override void _Process(double delta)
        {
            DeltaTime = (float)delta;
            if (IsPaused) return;

            _tickAccumulator += (float)delta;
            Client?.Update((float)delta);
        }

        public override void _PhysicsProcess(double delta)
        {
            // Minecraft runs at 20 TPS - fixed physics tick
            _tickAccumulator += (float)delta;
            while (_tickAccumulator >= SharedConstants.TICK_SECONDS)
            {
                _tickAccumulator -= SharedConstants.TICK_SECONDS;
                _tickCounter++;
                Tick();
            }
        }

        private void Tick()
        {
            // Original Minecraft.runTick() -> this is the 20 TPS game logic tick
            Client?.Tick();
            WorldManager?.Tick();
        }

        public void SwitchToMainMenu()
        {
            GetTree().ChangeSceneToFile("res://Scenes/UI/MainMenu.tscn");
        }

        public void SwitchToWorld()
        {
            GetTree().ChangeSceneToFile("res://Scenes/World/World.tscn");
        }

        public void SetPaused(bool paused)
        {
            IsPaused = paused;
            GetTree().Paused = paused;
        }

        public long GetTickCounter() => _tickCounter;

        // Translation of Minecraft.getInstance() singleton pattern
        public static GameManager GetInstance() => Instance;

        // Translation of CrashReport handling
        public void Crash(string message, System.Exception ex)
        {
            GD.PrintErr($"[CRASH] {message}: {ex}");
            var report = new System.Text.StringBuilder();
            report.AppendLine($"---- Minecraft Crash Report ----");
            report.AppendLine($"Time: {System.DateTime.Now}");
            report.AppendLine($"Version: {SharedConstants.VERSION_STRING}");
            report.AppendLine($"Description: {message}");
            report.AppendLine(ex.ToString());
            // In real game, would write to crash-reports/ and show screen
            OS.Alert($"Game crashed: {message}\n{ex.Message}", "Minecraft Crash");
        }
    }
}
