using Godot;
using System;
using Minecraft.World.Entity;
using Minecraft.Util.Math;

namespace Minecraft.Client.Camera
{
    /// <summary>
    /// Translation of net.minecraft.client.Camera / GameRenderer camera handling
    /// Handles first-person camera, bobbing, FOV effects, and touch look.
    /// </summary>
    public partial class GameCamera : Camera3D
    {
        [Export] public float MouseSensitivity = 0.3f;
        [Export] public float TouchSensitivity = 0.5f;
        [Export] public bool InvertY = false;
        [Export] public float BobbingAmount = 0.05f;

        private global::Minecraft.World.Entity.Player _player;
        private float _yaw = 0f;
        private float _pitch = 0f;
        private float _bobbingPhase = 0f;
        private Vector3 _basePosition = Vector3.Zero;

        // Touch look handling - right side drag
        private bool _isTouchLooking = false;
        private Vector2 _lastTouchPos = Vector2.Zero;
        private int _lookTouchIndex = -1;

        public override void _Ready()
        {
            // Minecraft uses 70 FOV default, 110 for quake pro
            Fov = 70f;
            Near = 0.05f;
            Far = 1000f;
            // Keep aspect
        }

        public void SetPlayer(global::Minecraft.World.Entity.Player player)
        {
            _player = player;
            if (player != null)
            {
                _yaw = player.YRot;
                _pitch = player.XRot;
            }
        }

        public override void _Process(double delta)
        {
            if (_player == null) return;

            // Follow player eye position
            Vector3 eyePos = _player.GetEyePosition();
            // Apply bobbing if moving
            if (_player.Velocity.Length() > 0.1f && _player.OnGround)
            {
                _bobbingPhase += (float)delta * 10f;
                float bobX = MathF.Sin(_bobbingPhase) * BobbingAmount;
                float bobY = MathF.Abs(MathF.Cos(_bobbingPhase)) * BobbingAmount * 0.5f;
                eyePos += new Vector3(bobX, bobY, 0);
            }

            GlobalPosition = eyePos;
            RotationDegrees = new Vector3(_pitch, _yaw, 0);

            // Update player rotation to match camera
            _player.YRot = _yaw;
            _player.XRot = _pitch;
        }

        public override void _Input(InputEvent @event)
        {
            // Mouse look for desktop testing
            if (@event is InputEventMouseMotion mouseMotion && Godot.Input.MouseMode == Godot.Input.MouseModeEnum.Captured)
            {
                float sens = MouseSensitivity * (MinecraftClient.Instance?.Options.Sensitivity ?? 0.5f) * 2f;
                _yaw -= mouseMotion.Relative.X * sens * 0.1f;
                _pitch -= mouseMotion.Relative.Y * sens * 0.1f * (InvertY ? -1 : 1);
                _pitch = Mathf.Clamp(_pitch, -89.9f, 89.9f);
            }

            // Touch look - right side of screen drag (per requirements: avoid dual joystick)
            if (@event is InputEventScreenTouch touch)
            {
                Vector2 screenSize = GetViewport().GetVisibleRect().Size;
                bool isRightSide = touch.Position.X > screenSize.X * 0.5f; // right half for look

                if (touch.Pressed && isRightSide && _lookTouchIndex == -1)
                {
                    // Start looking
                    _isTouchLooking = true;
                    _lookTouchIndex = touch.Index;
                    _lastTouchPos = touch.Position;
                }
                else if (!touch.Pressed && touch.Index == _lookTouchIndex)
                {
                    _isTouchLooking = false;
                    _lookTouchIndex = -1;
                }
            }

            if (@event is InputEventScreenDrag drag)
            {
                if (drag.Index == _lookTouchIndex && _isTouchLooking)
                {
                    Vector2 delta = drag.Position - _lastTouchPos;
                    _lastTouchPos = drag.Position;

                    float sens = TouchSensitivity * 0.5f;
                    _yaw -= delta.X * sens * 0.1f;
                    _pitch -= delta.Y * sens * 0.1f * (InvertY ? -1 : 1);
                    _pitch = Mathf.Clamp(_pitch, -89.9f, 89.9f);
                }
            }
        }

        public void SetRotation(float yaw, float pitch)
        {
            _yaw = yaw;
            _pitch = Mathf.Clamp(pitch, -89.9f, 89.9f);
        }

        public Vector3 GetLookVector() => -GlobalTransform.Basis.Z;
    }
}
