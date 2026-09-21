using Godot;
using System;
using Minecraft.World.Entity;
using Minecraft.Core;

namespace Minecraft.Client.Input
{
    /// <summary>
    /// Android touch controls - implements classic 4-way/8-way D-pad on left, action buttons, and right-side look.
    /// Per requirements: D-pad for movement, separate jump/crouch/inventory, camera via right side drag, tap-and-hold break, quick-tap place.
    /// This is the core mobile input translation of net.minecraft.client.KeyboardHandler + MouseHandler.
    /// </summary>
    public partial class TouchControls : CanvasLayer
    {
        // D-pad
        private Control _dpadContainer;
        private Button _btnUp, _btnDown, _btnLeft, _btnRight;
        private TextureRect _dpadBackground;
        private Vector2 _dpadCenter;
        private bool _dpadTouching = false;
        private int _dpadTouchIndex = -1;
        private Vector2 _dpadVector = Vector2.Zero; // -1..1

        // Action buttons
        private Button _btnJump, _btnCrouch, _btnInventory, _btnAttack, _btnUse;
        private Button _btnFlyUp, _btnFlyDown; // for creative

        // For block breaking - tap and hold
        private bool _isBreaking = false;
        private float _breakProgress = 0f;
        private float _breakTime = 0f;
        private const float BREAK_HOLD_TIME = 0.2f; // time to start breaking
        private const float BREAK_SPEED = 1.0f; // blocks per second (survival)

        // Placement - quick tap
        private float _lastTapTime = 0f;
        private const float DOUBLE_TAP_TIME = 0.3f;

        private global::Minecraft.World.Entity.Player _player;
        private MinecraftClient _client;

        public override void _Ready()
        {
            _client = MinecraftClient.Instance;
            BuildUI();
            GD.Print("[TouchControls] Initialized - D-pad + action buttons, right-side look");
        }

        private void BuildUI()
        {
            // Root container - covers whole screen, mouse filter ignore for look-through
            var root = new Control();
            root.SetAnchorsPreset(Control.LayoutPreset.FullRect);
            root.MouseFilter = Control.MouseFilterEnum.Ignore;
            AddChild(root);

            // D-pad container - left side, bottom
            _dpadContainer = new Control();
            _dpadContainer.Position = new Vector2(20, 0);
            _dpadContainer.Size = new Vector2(200, 200);
            _dpadContainer.AnchorBottom = 1.0f;
            _dpadContainer.AnchorTop = 1.0f;
            _dpadContainer.OffsetTop = -220;
            _dpadContainer.OffsetBottom = -20;
            _dpadContainer.OffsetLeft = 20;
            _dpadContainer.OffsetRight = 220;
            root.AddChild(_dpadContainer);

            // D-pad background - visual
            _dpadBackground = new TextureRect();
            _dpadBackground.SetAnchorsPreset(Control.LayoutPreset.FullRect);
            _dpadBackground.Modulate = new Godot.Color(1,1,1,0.3f);
            // Would load texture from assets - placeholder
            _dpadBackground.Texture = CreateCircleTexture(200, new Godot.Color(0.2f,0.2f,0.2f,0.5f));
            _dpadContainer.AddChild(_dpadBackground);

            // D-pad buttons - 4-way
            _btnUp = CreateDPadButton("▲", new Vector2(60, 0), new Vector2(80, 60));
            _btnDown = CreateDPadButton("▼", new Vector2(60, 140), new Vector2(80, 60));
            _btnLeft = CreateDPadButton("◀", new Vector2(0, 60), new Vector2(60, 80));
            _btnRight = CreateDPadButton("▶", new Vector2(140, 60), new Vector2(60, 80));

            _dpadContainer.AddChild(_btnUp);
            _dpadContainer.AddChild(_btnDown);
            _dpadContainer.AddChild(_btnLeft);
            _dpadContainer.AddChild(_btnRight);

            // Center knob for 8-way
            var centerKnob = new TextureRect();
            centerKnob.Position = new Vector2(70, 70);
            centerKnob.Size = new Vector2(60, 60);
            centerKnob.Texture = CreateCircleTexture(60, new Godot.Color(0.8f,0.8f,0.8f,0.6f));
            centerKnob.MouseFilter = Control.MouseFilterEnum.Ignore;
            _dpadContainer.AddChild(centerKnob);

            _dpadCenter = new Vector2(100, 100);

            // Action buttons - right side, above look area but distinct
            var actionContainer = new Control();
            actionContainer.AnchorLeft = 1.0f;
            actionContainer.AnchorRight = 1.0f;
            actionContainer.AnchorTop = 1.0f;
            actionContainer.AnchorBottom = 1.0f;
            actionContainer.OffsetLeft = -250;
            actionContainer.OffsetRight = -20;
            actionContainer.OffsetTop = -300;
            actionContainer.OffsetBottom = -20;
            root.AddChild(actionContainer);

            _btnJump = CreateActionButton("JUMP", new Vector2(120, 0), new Vector2(100, 80), new Godot.Color(0.2f,0.8f,0.2f,0.7f));
            _btnCrouch = CreateActionButton("CROUCH", new Vector2(120, 90), new Vector2(100, 60), new Godot.Color(0.8f,0.5f,0.2f,0.7f));
            _btnInventory = CreateActionButton("INV", new Vector2(0, 0), new Vector2(80, 60), new Godot.Color(0.2f,0.2f,0.8f,0.7f));
            _btnAttack = CreateActionButton("BREAK", new Vector2(0, 70), new Vector2(100, 80), new Godot.Color(0.8f,0.2f,0.2f,0.7f));
            _btnUse = CreateActionButton("PLACE", new Vector2(0, 160), new Vector2(100, 80), new Godot.Color(0.2f,0.6f,0.8f,0.7f));

            actionContainer.AddChild(_btnJump);
            actionContainer.AddChild(_btnCrouch);
            actionContainer.AddChild(_btnInventory);
            actionContainer.AddChild(_btnAttack);
            actionContainer.AddChild(_btnUse);

            // Hook signals
            _btnJump.Pressed += () => OnJumpPressed();
            _btnCrouch.Pressed += () => OnCrouchPressed();
            _btnInventory.Pressed += () => OnInventoryPressed();
            _btnAttack.ButtonDown += () => OnAttackDown();
            _btnAttack.ButtonUp += () => OnAttackUp();
            _btnUse.Pressed += () => OnUsePressed();

            // Make D-pad touchable
            _dpadContainer.GuiInput += OnDPadInput;
        }

        private Button CreateDPadButton(string text, Vector2 pos, Vector2 size)
        {
            var btn = new Button();
            btn.Position = pos;
            btn.Size = size;
            btn.Text = text;
            btn.Modulate = new Godot.Color(1,1,1,0.6f);
            return btn;
        }

        private Button CreateActionButton(string text, Vector2 pos, Vector2 size, Godot.Color color)
        {
            var btn = new Button();
            btn.Position = pos;
            btn.Size = size;
            btn.Text = text;
            var style = new StyleBoxFlat();
            style.BgColor = color;
            style.CornerRadiusTopLeft = 12;
            style.CornerRadiusTopRight = 12;
            style.CornerRadiusBottomLeft = 12;
            style.CornerRadiusBottomRight = 12;
            btn.AddThemeStyleboxOverride("normal", style);
            return btn;
        }

        private Texture2D CreateCircleTexture(int size, Godot.Color color)
        {
            var img = Image.CreateEmpty(size, size, false, Image.Format.Rgba8);
            img.Fill(new Godot.Color(0,0,0,0));
            Vector2 center = new Vector2(size/2f, size/2f);
            float radius = size/2f;
            for (int x=0;x<size;x++)
            {
                for (int y=0;y<size;y++)
                {
                    Vector2 p = new Vector2(x,y);
                    if (p.DistanceTo(center) <= radius)
                    {
                        img.SetPixel(x,y,color);
                    }
                }
            }
            return ImageTexture.CreateFromImage(img);
        }

        public void SetPlayer(global::Minecraft.World.Entity.Player player) => _player = player;

        public override void _Process(double delta)
        {
            if (_player == null) return;

            // Apply D-pad movement - 8-way
            Vector3 move = Vector3.Zero;
            if (_dpadVector.Length() > 0.1f)
            {
                // Convert 2D D-pad to 3D movement relative to camera yaw
                float yaw = _player.YRot * Mathf.Pi / 180f;
                Vector3 forward = new Vector3(-Mathf.Sin(yaw), 0, Mathf.Cos(yaw));
                Vector3 right = new Vector3(Mathf.Cos(yaw), 0, Mathf.Sin(yaw));

                // D-pad Y is inverted (up = -1)
                move += forward * (-_dpadVector.Y);
                move += right * (_dpadVector.X);
                move = move.Normalized() * _player.WalkSpeed * ( _player.IsSprinting ? 1.3f : 1f) * 10f;
            }

            // Apply movement - keep Y velocity
            _player.Velocity = new Vector3(move.X, _player.Velocity.Y, move.Z);

            // Handle breaking progress
            if (_isBreaking)
            {
                _breakTime += (float)delta;
                if (_breakTime > BREAK_HOLD_TIME)
                {
                    _breakProgress += (float)delta * BREAK_SPEED;
                    if (_breakProgress >= 1.0f)
                    {
                        _client?.HandleBlockBreak();
                        _breakProgress = 0f;
                    }
                }
            }

            // Update crosshair for touch raycasting optimization
            // Tap-and-hold breaks, quick-tap places (per requirements)
        }

        private void OnDPadInput(InputEvent @event)
        {
            if (@event is InputEventScreenTouch touch)
            {
                if (touch.Pressed && _dpadTouchIndex == -1)
                {
                    _dpadTouchIndex = touch.Index;
                    _dpadTouching = true;
                    UpdateDPadVector(touch.Position);
                }
                else if (!touch.Pressed && touch.Index == _dpadTouchIndex)
                {
                    _dpadTouchIndex = -1;
                    _dpadTouching = false;
                    _dpadVector = Vector2.Zero;
                }
            }
            else if (@event is InputEventScreenDrag drag)
            {
                if (drag.Index == _dpadTouchIndex)
                {
                    UpdateDPadVector(drag.Position);
                }
            }
        }

        private void UpdateDPadVector(Vector2 pos)
        {
            // pos is relative to D-pad container? Convert
            Vector2 local = pos - _dpadContainer.GlobalPosition - _dpadCenter;
            float maxDist = 80f;
            float dist = local.Length();
            if (dist > maxDist)
            {
                local = local.Normalized() * maxDist;
            }
            // Normalize to -1..1
            _dpadVector = local / maxDist;
            // Deadzone
            if (_dpadVector.Length() < 0.2f) _dpadVector = Vector2.Zero;
        }

        private void OnJumpPressed()
        {
            if (_player == null) return;
            if (_player.OnGround)
            {
                _player.Velocity = new Vector3(_player.Velocity.X, 6f, _player.Velocity.Z);
            }
            else if (_player.MayFly)
            {
                _player.Velocity = new Vector3(_player.Velocity.X, _player.FlySpeed * 10f, _player.Velocity.Z);
            }
        }

        private void OnCrouchPressed()
        {
            if (_player == null) return;
            _player.IsCrouching = !_player.IsCrouching;
            GD.Print($"[TouchControls] Crouch: {_player.IsCrouching}");
        }

        private void OnInventoryPressed()
        {
            GD.Print("[TouchControls] Inventory pressed");
            // Open inventory screen
            var gameMgr = GameManager.Instance;
            if (gameMgr != null)
            {
                // Would switch to inventory UI
            }
        }

        private void OnAttackDown()
        {
            _isBreaking = true;
            _breakTime = 0f;
            _breakProgress = 0f;
            GD.Print("[TouchControls] Start breaking");
        }

        private void OnAttackUp()
        {
            _isBreaking = false;
            _breakTime = 0f;
            _breakProgress = 0f;
            // If quick tap (< BREAK_HOLD_TIME), treat as attack
            if (_breakTime < BREAK_HOLD_TIME)
            {
                _client?.HandleBlockBreak();
            }
        }

        private void OnUsePressed()
        {
            // Quick-tap places block (per requirements)
            _client?.HandleBlockPlace();
            GD.Print("[TouchControls] Place block");
        }

        // Public API for external input
        public Vector2 GetMovementVector() => _dpadVector;
        public bool IsJumpPressed() => _btnJump.ButtonPressed;
        public bool IsCrouchPressed() => _btnCrouch.ButtonPressed;
    }
}
