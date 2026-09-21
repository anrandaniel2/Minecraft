using Godot;
using System;
using Minecraft.World;
using Minecraft.World.Entity;
using Minecraft.Core;

namespace Minecraft.Client
{
    /// <summary>
    /// Translation of net.minecraft.client.Minecraft - central client class
    /// Handles game loop, player, level, renderers, screens, input.
    /// In Godot, lifecycle is delegated to GameManager, but this holds game state.
    /// </summary>
    public class MinecraftClient
    {
        public static MinecraftClient Instance { get; private set; }

        public global::Minecraft.World.Entity.Player Player { get; private set; }
        public global::Minecraft.World.Level.Level Level { get; private set; }
        public GameRenderer GameRenderer { get; private set; }
        public bool IsPaused { get; set; } = false;

        // From Minecraft.java fields
        public int Fps { get; private set; } = 0;
        public long TickCount { get; private set; } = 0;
        public float PartialTick { get; private set; } = 0f;

        // Input
        public bool IsWindowActive { get; set; } = true;

        // Screens - from net.minecraft.client.gui.screens.Screen
        public Gui.Screens.Screen CurrentScreen { get; private set; } = null;

        // Hit result - from Minecraft.hitResult
        public global::Minecraft.World.Level.BlockHitResult HitResult { get; private set; }

        // Options - from net.minecraft.client.Options
        public ClientOptions Options { get; } = new ClientOptions();

        public MinecraftClient()
        {
            Instance = this;
            GameRenderer = new GameRenderer();
            GD.Print($"[MinecraftClient] Created - Version {SharedConstants.VERSION_STRING}");
        }

        public void InitializeLevel(long seed, string worldType)
        {
            WorldManager.Instance.InitializeWorld(seed, worldType);
            Level = WorldManager.Instance.GameLevel;
            Player = new global::Minecraft.World.Entity.Player(Level);
            Player.SetPos(0, 80, 0);
            Level.AddEntity(Player);
            GD.Print($"[MinecraftClient] Level initialized - Seed {seed}, Player at {Player.Position}");
        }

        public void Update(float delta)
        {
            PartialTick = delta / SharedConstants.TICK_SECONDS;
            GameRenderer.Update(delta);

            if (CurrentScreen != null)
            {
                CurrentScreen.Update(delta);
            }
            else
            {
                // Update hit result for block breaking/placing
                UpdateHitResult();
            }
        }

        public void Tick()
        {
            TickCount++;
            if (IsPaused) return;

            Level?.Tick();
            Player?.Tick();

            // Fps calc
            Fps = (int)(1.0f / GameManager.Instance.DeltaTime);
        }

        private void UpdateHitResult()
        {
            if (this.Player == null || Level == null || GameRenderer?.Camera == null) return;

            // Raycast from eye position along view vector - 5 blocks reach (creative 6)
            float reach = this.Player.Mode == global::Minecraft.World.Entity.Player.GameMode.Creative ? 6f : 5f;
            Vector3 from = this.Player.GetEyePosition();
            Vector3 view = this.Player.GetViewVector(PartialTick);
            Vector3 to = from + view * reach;

            var context = new global::Minecraft.World.Level.ClipContext(from, to, global::Minecraft.World.Level.ClipContext.BlockMode.Outline, global::Minecraft.World.Level.ClipContext.FluidMode.None);
            HitResult = Level.Clip(context);
        }

        public void SetScreen(Gui.Screens.Screen screen)
        {
            CurrentScreen?.OnClose();
            CurrentScreen = screen;
            CurrentScreen?.OnOpen();
            GD.Print($"[MinecraftClient] Screen changed to {screen?.GetType().Name ?? "null"}");
        }

        public void HandleBlockBreak()
        {
            if (HitResult.Hit)
            {
                var pos = HitResult.BlockPos;
                var state = Level.GetBlockState(pos);
                if (!state.IsAir)
                {
                    // Check if can break (survival vs creative)
                    if (this.Player.Mode == global::Minecraft.World.Entity.Player.GameMode.Creative || !state.Block.BlockProperties.RequiresCorrectTool)
                    {
                        Level.SetBlockState(pos, global::Minecraft.World.Level.Block.BlockState.AIR);
                        // Spawn particles, play sound
                        GD.Print($"[MinecraftClient] Broke block {state.Block.Name} at {pos}");
                    }
                }
            }
        }

        public void HandleBlockPlace()
        {
            if (HitResult.Hit)
            {
                var selected = this.Player.GetSelectedItem();
                if (selected.IsEmpty || !selected.Item.IsBlockItem) return;

                Vector3I placePos = HitResult.BlockPos + new Vector3I((int)HitResult.Normal.X, (int)HitResult.Normal.Y, (int)HitResult.Normal.Z);
                var current = Level.GetBlockState(placePos);
                if (current.IsAir)
                {
                    var blockState = new global::Minecraft.World.Level.Block.BlockState(selected.Item.Block.Id);
                    Level.SetBlockState(placePos, blockState);
                    if (this.Player.Mode != global::Minecraft.World.Entity.Player.GameMode.Creative)
                    {
                        selected.Shrink(1);
                    }
                    GD.Print($"[MinecraftClient] Placed {selected.Item.Name} at {placePos}");
                }
            }
        }
    }

    public class ClientOptions
    {
        // From net.minecraft.client.Options - ~100 options
        public int RenderDistance = SharedConstants.DEFAULT_RENDER_DISTANCE;
        public int SimulationDistance = 6;
        public int Fov = 70;
        public float Sensitivity = 0.5f;
        public bool InvertYMouse = false;
        public float SoundVolume = 1.0f;
        public float MusicVolume = 0.5f;
        public bool AutoJump = true;
        public bool Touchscreen = true;
        public int GuiScale = 0; // auto
        public bool HideGui = false;
        public bool FancyGraphics = false; // false for mobile perf
        public bool SmoothLighting = true;
        public int Particles = 1; // 0=all,1=decreased,2=minimal - mobile uses 1
        public bool EntityShadows = false; // disabled on mobile
    }

    public class GameRenderer
    {
        public Camera.GameCamera Camera { get; set; }
        public float Fov { get; set; } = 70f;
        public float NearPlane { get; set; } = 0.05f;
        public float FarPlane { get; set; } = 1000f;

        public void Update(float delta)
        {
            // Would handle camera effects, fog, etc.
        }
    }
}
