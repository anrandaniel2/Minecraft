using Godot;
using System;
using Minecraft.Core;

namespace Minecraft.Client.Gui.Screens
{
    /// <summary>
    /// Translation of net.minecraft.client.gui.screens.TitleScreen
    /// Original: panorama, logo, buttons (Singleplayer, Multiplayer, Options, Quit), splash text.
    /// Recreates layout precisely using Godot Control nodes.
    /// </summary>
    public partial class TitleScreen : Screen
    {
        private Label _splashLabel;
        private string[] _splashes = new string[]
        {
            "Wilderness Bound!", "26.3!", "Godot 4 Mono!", "Android Edition!", "100% Java-Free!",
            "Now with D-pad!", "Touch to break!", "Greedy meshing!", "Flattened arrays!",
            "No GC allocs!", "Nearest filtering!", "CanvasItems stretch!", "Mobile optimized!"
        };

        public TitleScreen() : base("Title Screen") {}

        protected override void Init()
        {
            RenderMenuBackground();

            // Logo - from assets/minecraft/textures/gui/title/minecraft.png
            var logoContainer = new CenterContainer();
            logoContainer.AnchorLeft = 0.5f;
            logoContainer.AnchorRight = 0.5f;
            logoContainer.AnchorTop = 0.2f;
            logoContainer.AnchorBottom = 0.4f;
            logoContainer.OffsetLeft = -200;
            logoContainer.OffsetRight = 200;
            logoContainer.OffsetTop = -50;
            logoContainer.OffsetBottom = 50;
            AddChild(logoContainer);

            var logoLabel = new Label();
            logoLabel.Text = $"MINECRAFT {SharedConstants.VERSION_STRING}";
            logoLabel.HorizontalAlignment = HorizontalAlignment.Center;
            logoLabel.AddThemeFontSizeOverride("font_size", 48);
            logoLabel.AddThemeColorOverride("font_color", new Color(1,1,1));
            logoContainer.AddChild(logoLabel);

            // Splash - yellow text rotated, from TitleScreen splash
            var splash = _splashes[new Random().Next(_splashes.Length)];
            _splashLabel = new Label();
            _splashLabel.Text = splash;
            _splashLabel.Position = new Vector2(logoContainer.OffsetLeft + 250, 100);
            _splashLabel.Rotation = Mathf.DegToRad(-15);
            _splashLabel.AddThemeFontSizeOverride("font_size", 18);
            _splashLabel.AddThemeColorOverride("font_color", new Color(1,1,0));
            AddChild(_splashLabel);

            // Buttons - layout from TitleScreen.java: 3 main + options + quit
            // Original positions: centered, 24px height, 200px width, 24px gap
            float centerX = GetViewportRect().Size.X / 2 - 100;
            float startY = GetViewportRect().Size.Y * 0.5f;

            CreateButton("Singleplayer", new Vector2(centerX, startY), new Vector2(200, 40), () => OnSingleplayer());
            CreateButton("Multiplayer", new Vector2(centerX, startY+50), new Vector2(200, 40), () => OnMultiplayer());
            CreateButton("Create World", new Vector2(centerX, startY+100), new Vector2(200, 40), () => OnCreateWorld());

            CreateButton("Options...", new Vector2(centerX-105, startY+160), new Vector2(95, 40), () => OnOptions());
            CreateButton("Quit Game", new Vector2(centerX+10, startY+160), new Vector2(95, 40), () => OnQuit());

            // Version label bottom left
            var versionLabel = new Label();
            versionLabel.Text = $"{SharedConstants.VERSION_STRING} - Wilderness Bound / Godot 4 Mono Android";
            versionLabel.Position = new Vector2(10, GetViewportRect().Size.Y - 30);
            versionLabel.AddThemeFontSizeOverride("font_size", 12);
            AddChild(versionLabel);

            // Copyright Mojang
            var copyLabel = new Label();
            copyLabel.Text = "Copyright Mojang AB. Do not distribute!";
            copyLabel.Position = new Vector2(GetViewportRect().Size.X - 250, GetViewportRect().Size.Y - 30);
            copyLabel.AddThemeFontSizeOverride("font_size", 10);
            AddChild(copyLabel);
        }

        private void OnSingleplayer()
        {
            GD.Print("[TitleScreen] Singleplayer");
            // Would open SelectWorldScreen
            // For now directly start game with default world
            _minecraft?.InitializeLevel(12345, "default");
            GetTree().ChangeSceneToFile("res://Scenes/World/World.tscn");
        }

        private void OnMultiplayer()
        {
            GD.Print("[TitleScreen] Multiplayer - not implemented in clone, would show server list");
        }

        private void OnCreateWorld()
        {
            GD.Print("[TitleScreen] Create World");
            var createScreen = new CreateWorldScreen();
            _minecraft?.SetScreen(createScreen);
            GetTree().Root.AddChild(createScreen);
            QueueFree();
        }

        private void OnOptions()
        {
            var options = new OptionsScreen();
            _minecraft?.SetScreen(options);
            GetTree().Root.AddChild(options);
            QueueFree();
        }

        private void OnQuit()
        {
            GetTree().Quit();
        }

        public override void _Process(double delta)
        {
            // Animate splash - pulsing scale like original
            if (_splashLabel != null)
            {
                float pulse = 1.0f + Mathf.Sin((float)Time.GetTicksMsec() / 300f) * 0.1f;
                _splashLabel.Scale = new Vector2(pulse, pulse);
            }
        }
    }

    public partial class OptionsScreen : Screen
    {
        public OptionsScreen() : base("Options") {}

        protected override void Init()
        {
            RenderDirtBackground();
            CreateLabel("Options", new Vector2(100, 20));

            float centerX = GetViewportRect().Size.X / 2 - 100;
            CreateButton($"FOV: {MinecraftClient.Instance?.Options.Fov}", new Vector2(centerX, 80), new Vector2(200, 30), () => {});
            CreateButton($"Render Distance: {MinecraftClient.Instance?.Options.RenderDistance}", new Vector2(centerX, 120), new Vector2(200, 30), () => {});
            CreateButton($"Sensitivity: {MinecraftClient.Instance?.Options.Sensitivity}", new Vector2(centerX, 160), new Vector2(200, 30), () => {});
            CreateButton("Done", new Vector2(centerX, 250), new Vector2(200, 30), () => { GetTree().ChangeSceneToFile("res://Scenes/UI/MainMenu.tscn"); });
        }
    }

    public partial class CreateWorldScreen : Screen
    {
        private LineEdit _seedEdit;
        private OptionButton _typeOption;

        public CreateWorldScreen() : base("Create World") {}

        protected override void Init()
        {
            RenderDirtBackground();
            CreateLabel("Create New World", new Vector2(100, 20));

            CreateLabel("World Name:", new Vector2(50, 80));
            var nameEdit = new LineEdit();
            nameEdit.Position = new Vector2(200, 80);
            nameEdit.Size = new Vector2(300, 30);
            nameEdit.Text = "New World";
            AddChild(nameEdit);

            CreateLabel("Seed:", new Vector2(50, 120));
            _seedEdit = new LineEdit();
            _seedEdit.Position = new Vector2(200, 120);
            _seedEdit.Size = new Vector2(300, 30);
            _seedEdit.PlaceholderText = "Random";
            AddChild(_seedEdit);

            CreateLabel("World Type:", new Vector2(50, 160));
            _typeOption = new OptionButton();
            _typeOption.Position = new Vector2(200, 160);
            _typeOption.Size = new Vector2(200, 30);
            _typeOption.AddItem("Default");
            _typeOption.AddItem("Flat");
            _typeOption.AddItem("Debug");
            AddChild(_typeOption);

            float centerX = GetViewportRect().Size.X / 2 - 100;
            CreateButton("Create World", new Vector2(centerX, 250), new Vector2(200, 40), () => OnCreate(nameEdit.Text));
            CreateButton("Cancel", new Vector2(centerX, 300), new Vector2(200, 40), () => GetTree().ChangeSceneToFile("res://Scenes/UI/MainMenu.tscn"));
        }

        private void OnCreate(string name)
        {
            long seed = 0;
            if (!string.IsNullOrEmpty(_seedEdit.Text))
            {
                if (!long.TryParse(_seedEdit.Text, out seed))
                {
                    seed = _seedEdit.Text.GetHashCode();
                }
            }
            else
            {
                seed = new Random().NextInt64();
            }

            string type = _typeOption.GetItemText(_typeOption.Selected);
            GD.Print($"[CreateWorld] Creating {name} seed={seed} type={type}");

            MinecraftClient.Instance?.InitializeLevel(seed, type.ToLower());
            GetTree().ChangeSceneToFile("res://Scenes/World/World.tscn");
        }
    }

    public partial class PauseScreen : Screen
    {
        public PauseScreen() : base("Game Menu") {}

        protected override void Init()
        {
            // Semi-transparent background - inworld_menu_background.png
            var bg = new ColorRect();
            bg.Color = new Color(0,0,0,0.5f);
            bg.SetAnchorsPreset(LayoutPreset.FullRect);
            AddChild(bg);

            float centerX = GetViewportRect().Size.X / 2 - 100;
            float centerY = GetViewportRect().Size.Y / 2 - 100;

            CreateLabel("Game Menu", new Vector2(centerX+50, centerY-50));
            CreateButton("Back to Game", new Vector2(centerX, centerY), new Vector2(200, 40), () => { QueueFree(); GetTree().Paused = false; });
            CreateButton("Options...", new Vector2(centerX, centerY+50), new Vector2(200, 40), () => {});
            CreateButton("Save and Quit to Title", new Vector2(centerX, centerY+100), new Vector2(200, 40), () => GetTree().ChangeSceneToFile("res://Scenes/UI/MainMenu.tscn"));
        }
    }
}
