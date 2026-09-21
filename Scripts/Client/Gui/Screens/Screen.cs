using Godot;
using System;

namespace Minecraft.Client.Gui.Screens
{
    /// <summary>
    /// Base screen - translation of net.minecraft.client.gui.screens.Screen
    /// Original handles rendering, mouse, keyboard, children widgets.
    /// In Godot we use Control nodes but preserve logic.
    /// </summary>
    public abstract partial class Screen : Control
    {
        public string Title { get; protected set; }
        protected MinecraftClient _minecraft;
        protected bool _isInitialized = false;

        public Screen(string title)
        {
            Title = title;
        }

        public override void _Ready()
        {
            _minecraft = MinecraftClient.Instance;
            SetAnchorsPreset(LayoutPreset.FullRect);
            Init();
            _isInitialized = true;
        }

        protected virtual void Init() {}

        public virtual void OnOpen()
        {
            GD.Print($"[Screen] Opened {GetType().Name}: {Title}");
            Godot.Input.MouseMode = Godot.Input.MouseModeEnum.Visible;
        }

        public virtual void OnClose()
        {
            GD.Print($"[Screen] Closed {GetType().Name}");
        }

        public virtual void Update(float delta) {}

        protected Button CreateButton(string text, Vector2 pos, Vector2 size, Action onPress)
        {
            var btn = new Button();
            btn.Text = text;
            btn.Position = pos;
            btn.Size = size;
            btn.Pressed += onPress;
            // Style to match Minecraft button texture - from gui/sprites/widget/button.png
            var styleNormal = new StyleBoxFlat();
            styleNormal.BgColor = new Color(0.5f, 0.5f, 0.5f, 1f);
            styleNormal.BorderColor = new Color(0,0,0,1);
            styleNormal.SetBorderWidthAll(2);
            styleNormal.CornerRadiusTopLeft = 2;
            styleNormal.CornerRadiusTopRight = 2;
            styleNormal.CornerRadiusBottomLeft = 2;
            styleNormal.CornerRadiusBottomRight = 2;

            var styleHover = new StyleBoxFlat();
            styleHover.BgColor = new Color(0.6f, 0.6f, 0.8f, 1f);
            styleHover.BorderColor = new Color(1,1,1,1);
            styleHover.SetBorderWidthAll(2);

            btn.AddThemeStyleboxOverride("normal", styleNormal);
            btn.AddThemeStyleboxOverride("hover", styleHover);
            btn.AddThemeStyleboxOverride("pressed", styleHover);

            AddChild(btn);
            return btn;
        }

        protected Label CreateLabel(string text, Vector2 pos)
        {
            var label = new Label();
            label.Text = text;
            label.Position = pos;
            // Minecraft font - would use custom font from assets/minecraft/font/
            label.AddThemeFontSizeOverride("font_size", 16);
            AddChild(label);
            return label;
        }

        // Background rendering - from Screen.renderBackground
        protected void RenderDirtBackground()
        {
            // Would draw menu_background.png tiled
            // For Godot we use ColorRect
            var bg = new ColorRect();
            bg.Color = new Color(0.2f, 0.2f, 0.2f, 1f);
            bg.SetAnchorsPreset(LayoutPreset.FullRect);
            bg.ZIndex = -100;
            AddChild(bg);
        }

        protected void RenderMenuBackground()
        {
            // Panorama or dirt - from TitleScreen
            var bg = new ColorRect();
            bg.Color = new Color(0.1f, 0.1f, 0.15f, 1f);
            bg.SetAnchorsPreset(LayoutPreset.FullRect);
            bg.ZIndex = -100;
            AddChild(bg);
        }
    }
}
