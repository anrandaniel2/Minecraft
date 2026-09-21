using Godot;
using System;
using System.Collections.Generic;
using System.IO;

namespace Minecraft.Client.Gui.Screens
{
    /// <summary>
    /// Translation of net.minecraft.client.gui.screens.SelectWorldScreen and WorldSelectionList
    /// Shows list of worlds, with icons, version, etc.
    /// </summary>
    public partial class SelectWorldScreen : Screen
    {
        private List<WorldInfo> _worlds = new List<WorldInfo>();

        public SelectWorldScreen() : base("Select World") {}

        protected override void Init()
        {
            RenderDirtBackground();
            CreateLabel("Select World", new Vector2(100, 20));

            // World list - from WorldSelectionList.java
            var scroll = new ScrollContainer();
            scroll.Position = new Vector2(50, 60);
            scroll.Size = new Vector2(500, 300);
            AddChild(scroll);

            var vbox = new VBoxContainer();
            scroll.AddChild(vbox);

            LoadWorlds();
            foreach (var world in _worlds)
            {
                var btn = new Button();
                btn.Text = $"{world.Name} - {world.Version} - {world.LastPlayed}";
                btn.CustomMinimumSize = new Vector2(480, 40);
                btn.Pressed += () => OnWorldSelected(world);
                vbox.AddChild(btn);
            }

            float centerX = GetViewportRect().Size.X / 2 - 100;
            CreateButton("Play Selected World", new Vector2(centerX, 380), new Vector2(200, 30), () => OnPlay());
            CreateButton("Create New World", new Vector2(centerX, 420), new Vector2(200, 30), () => OnCreateNew());
            CreateButton("Cancel", new Vector2(centerX, 460), new Vector2(200, 30), () => GetTree().ChangeSceneToFile("res://Scenes/UI/MainMenu.tscn"));
        }

        private void LoadWorlds()
        {
            // Would load from saves/ folder, reading level.dat via NBT
            _worlds.Add(new WorldInfo("New World", "26.3", DateTime.Now, 12345));
            _worlds.Add(new WorldInfo("Flat World", "26.3", DateTime.Now.AddDays(-1), 0, "flat"));
            _worlds.Add(new WorldInfo("Debug World", "26.3", DateTime.Now.AddDays(-2), 0, "debug"));
        }

        private void OnWorldSelected(WorldInfo world)
        {
            GD.Print($"[SelectWorld] Selected {world.Name}");
        }

        private void OnPlay()
        {
            if (_worlds.Count > 0)
            {
                var world = _worlds[0];
                MinecraftClient.Instance?.InitializeLevel(world.Seed, world.Type);
                GetTree().ChangeSceneToFile("res://Scenes/World/World.tscn");
            }
        }

        private void OnCreateNew()
        {
            var create = new CreateWorldScreen();
            GetTree().Root.AddChild(create);
            QueueFree();
        }

        private class WorldInfo
        {
            public string Name;
            public string Version;
            public DateTime LastPlayed;
            public long Seed;
            public string Type;
            public WorldInfo(string name, string version, DateTime last, long seed, string type="default")
            {
                Name=name; Version=version; LastPlayed=last; Seed=seed; Type=type;
            }
        }
    }
}
