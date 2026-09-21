using Godot;
using System;
using Minecraft.World.Entity;
using Minecraft.Client;

namespace Minecraft.Client.Gui.Hud
{
    /// <summary>
    /// Translation of net.minecraft.client.gui.Gui / Hud
    /// Renders hotbar, health, armor, food, experience, crosshair, boss bar, chat, etc.
    /// Uses exact UI texture slices from assets/minecraft/textures/gui/sprites/hud/
    /// </summary>
    public partial class Hud : CanvasLayer
    {
        private global::Minecraft.World.Entity.Player _player;
        private MinecraftClient _client;

        // HUD elements
        private Control _hotbarContainer;
        private TextureRect[] _hotbarSlots = new TextureRect[9];
        private TextureRect _hotbarSelection;
        private TextureRect _crosshair;
        private Control _healthContainer;
        private TextureRect[] _hearts = new TextureRect[10];
        private Control _armorContainer;
        private Control _foodContainer;
        private ProgressBar _expBar;
        private Label _expLevelLabel;
        private Control _bossBarContainer;

        // Crosshair attack indicator
        private TextureRect _attackIndicator;

        public override void _Ready()
        {
            _client = MinecraftClient.Instance;
            BuildHud();
            GD.Print("[Hud] Initialized - hotbar, hearts, crosshair, boss bar");
        }

        public void SetPlayer(global::Minecraft.World.Entity.Player player) => _player = player;

        private void BuildHud()
        {
            // Hotbar - bottom center, from hud/hotbar.png (182x22)
            _hotbarContainer = new Control();
            _hotbarContainer.AnchorLeft = 0.5f;
            _hotbarContainer.AnchorRight = 0.5f;
            _hotbarContainer.AnchorTop = 1.0f;
            _hotbarContainer.AnchorBottom = 1.0f;
            _hotbarContainer.OffsetLeft = -91;
            _hotbarContainer.OffsetRight = 91;
            _hotbarContainer.OffsetTop = -50;
            _hotbarContainer.OffsetBottom = -10;
            AddChild(_hotbarContainer);

            var hotbarBg = new TextureRect();
            hotbarBg.SetAnchorsPreset(Control.LayoutPreset.FullRect);
            hotbarBg.Texture = LoadHudTexture("hotbar");
            hotbarBg.ExpandMode = TextureRect.ExpandModeEnum.IgnoreSize;
            hotbarBg.StretchMode = TextureRect.StretchModeEnum.Scale;
            _hotbarContainer.AddChild(hotbarBg);

            // 9 slots
            for (int i = 0; i < 9; i++)
            {
                var slot = new TextureRect();
                slot.Position = new Vector2(3 + i*20, 3);
                slot.Size = new Vector2(16, 16);
                slot.ExpandMode = TextureRect.ExpandModeEnum.IgnoreSize;
                // Would show item icon
                _hotbarSlots[i] = slot;
                _hotbarContainer.AddChild(slot);
            }

            // Selection - from hud/hotbar_selection.png (24x23)
            _hotbarSelection = new TextureRect();
            _hotbarSelection.Size = new Vector2(24, 24);
            _hotbarSelection.Position = new Vector2(0, -1);
            _hotbarSelection.Texture = LoadHudTexture("hotbar_selection");
            _hotbarContainer.AddChild(_hotbarSelection);

            // Health - above hotbar left, 10 hearts (from hud/heart/full.png etc)
            _healthContainer = new Control();
            _healthContainer.AnchorLeft = 0.5f;
            _healthContainer.AnchorRight = 0.5f;
            _healthContainer.AnchorTop = 1.0f;
            _healthContainer.AnchorBottom = 1.0f;
            _healthContainer.OffsetLeft = -91;
            _healthContainer.OffsetRight = 0;
            _healthContainer.OffsetTop = -70;
            _healthContainer.OffsetBottom = -50;
            AddChild(_healthContainer);

            for (int i = 0; i < 10; i++)
            {
                var heart = new TextureRect();
                heart.Position = new Vector2(i*8, 0);
                heart.Size = new Vector2(9, 9);
                heart.Texture = LoadHudTexture("heart/full");
                _hearts[i] = heart;
                _healthContainer.AddChild(heart);
            }

            // Crosshair - center screen, from hud/crosshair.png
            _crosshair = new TextureRect();
            _crosshair.AnchorLeft = 0.5f;
            _crosshair.AnchorRight = 0.5f;
            _crosshair.AnchorTop = 0.5f;
            _crosshair.AnchorBottom = 0.5f;
            _crosshair.OffsetLeft = -8;
            _crosshair.OffsetRight = 8;
            _crosshair.OffsetTop = -8;
            _crosshair.OffsetBottom = 8;
            _crosshair.Texture = LoadHudTexture("crosshair");
            _crosshair.Modulate = new Color(1,1,1,0.8f);
            AddChild(_crosshair);

            // Attack indicator - near crosshair or hotbar
            _attackIndicator = new TextureRect();
            _attackIndicator.Size = new Vector2(16, 16);
            _attackIndicator.Position = new Vector2(10, 10);
            _attackIndicator.Texture = LoadHudTexture("crosshair_attack_indicator_full");
            _crosshair.AddChild(_attackIndicator);

            // Experience bar - above hotbar, from hud/experience_bar_background.png
            _expBar = new ProgressBar();
            _expBar.AnchorLeft = 0.5f;
            _expBar.AnchorRight = 0.5f;
            _expBar.AnchorTop = 1.0f;
            _expBar.AnchorBottom = 1.0f;
            _expBar.OffsetLeft = -91;
            _expBar.OffsetRight = 91;
            _expBar.OffsetTop = -80;
            _expBar.OffsetBottom = -75;
            _expBar.MaxValue = 1.0;
            _expBar.Value = 0.5;
            _expBar.ShowPercentage = false;
            AddChild(_expBar);

            _expLevelLabel = new Label();
            _expLevelLabel.AnchorLeft = 0.5f;
            _expLevelLabel.AnchorRight = 0.5f;
            _expLevelLabel.AnchorTop = 1.0f;
            _expLevelLabel.AnchorBottom = 1.0f;
            _expLevelLabel.OffsetLeft = -20;
            _expLevelLabel.OffsetRight = 20;
            _expLevelLabel.OffsetTop = -95;
            _expLevelLabel.OffsetBottom = -80;
            _expLevelLabel.HorizontalAlignment = HorizontalAlignment.Center;
            _expLevelLabel.Text = "0";
            AddChild(_expLevelLabel);

            // Boss bar container - top center
            _bossBarContainer = new Control();
            _bossBarContainer.AnchorLeft = 0.5f;
            _bossBarContainer.AnchorRight = 0.5f;
            _bossBarContainer.AnchorTop = 0f;
            _bossBarContainer.AnchorBottom = 0f;
            _bossBarContainer.OffsetLeft = -91;
            _bossBarContainer.OffsetRight = 91;
            _bossBarContainer.OffsetTop = 10;
            _bossBarContainer.OffsetBottom = 20;
            AddChild(_bossBarContainer);
        }

        private Texture2D LoadHudTexture(string name)
        {
            // Would load from res://Assets/Textures/gui/sprites/hud/{name}.png
            // For now return placeholder
            return null;
        }

        public override void _Process(double delta)
        {
            if (_player == null) return;

            // Update hotbar selection
            if (_hotbarSelection != null)
            {
                _hotbarSelection.Position = new Vector2(_player.SelectedSlot * 20 - 1, -1);
            }

            // Update health - 20 health = 10 hearts, each heart 2 health
            float health = _player.Health;
            for (int i = 0; i < 10; i++)
            {
                float heartHealth = health - i*2;
                if (_hearts[i] == null) continue;
                if (heartHealth >= 2) _hearts[i].Modulate = Colors.White;
                else if (heartHealth >= 1) _hearts[i].Modulate = new Color(1,1,1,0.5f); // half
                else _hearts[i].Modulate = new Color(1,1,1,0.1f); // empty
            }

            // Update exp
            if (_expBar != null)
            {
                _expBar.Value = _player.Experience;
                _expLevelLabel.Text = _player.ExperienceLevel.ToString();
            }

            // Crosshair visibility - hide when in inventory etc.
            _crosshair.Visible = _client?.CurrentScreen == null;
        }

        public void ShowBossBar(string name, float progress, string color = "red")
        {
            // Would create boss bar from gui/sprites/boss_bar/
            GD.Print($"[Hud] BossBar: {name} {progress*100}%");
        }
    }
}
