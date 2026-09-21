using Godot;
using System;

namespace Minecraft.Client.Gui.Components
{
    /// <summary>
    /// Translation of net.minecraft.client.gui.components.* - all GUI widgets
    /// Includes AbstractWidget, Button, Checkbox, Slider, EditBox, etc.
    /// Maps to Godot Control nodes with Minecraft styling.
    /// </summary>
    public abstract partial class AbstractWidget : Control
    {
        public string Message { get; set; }
        public bool IsHovered { get; protected set; }
        public bool IsFocused { get; protected set; }
        public bool Active { get; set; } = true;

        protected AbstractWidget(string message)
        {
            Message = message;
        }

        public abstract void Render();
        public virtual void OnClick() {}
    }

    public partial class Button : AbstractWidget
    {
        public Action OnPress { get; set; }
        public Button(string message, Action onPress) : base(message) { OnPress = onPress; }

        public override void Render()
        {
            // Uses widget/button.png, button_disabled.png, button_highlighted.png
        }

        public override void OnClick() => OnPress?.Invoke();
    }

    public partial class Checkbox : AbstractWidget
    {
        public bool Checked { get; set; }
        public Checkbox(string message, bool initial) : base(message) { Checked = initial; }
        public override void Render() {}
    }

    public partial class Slider : AbstractWidget
    {
        public float Value { get; set; }
        public float Min { get; set; } = 0;
        public float Max { get; set; } = 1;
        public Slider(string message, float min, float max, float value) : base(message) { Min=min; Max=max; Value=value; }
        public override void Render() {}
    }

    public partial class EditBox : AbstractWidget
    {
        public string Value { get; set; } = "";
        public EditBox(string message) : base(message) {}
        public override void Render() {}
    }

    public class BossHealthOverlay
    {
        // From BossHealthOverlay.java - renders boss bars
        public void Render() {}
    }

    public class ChatComponent
    {
        // From ChatComponent.java - handles chat messages, fading, etc.
        private System.Collections.Generic.Queue<string> _messages = new System.Collections.Generic.Queue<string>(100);
        public void AddMessage(string msg) => _messages.Enqueue(msg);
        public void Render() {}
    }

    public class DebugScreenOverlay
    {
        // From DebugScreenOverlay.java - F3 debug screen
        public bool ShowDebug = false;
        public void Render()
        {
            if (!ShowDebug) return;
            // Would render FPS, coords, biome, etc.
        }
    }
}
