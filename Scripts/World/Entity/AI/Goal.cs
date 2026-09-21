using System;
using Godot;

namespace Minecraft.World.Entity.AI
{
    /// <summary>
    /// Translation of net.minecraft.world.entity.ai.goal.Goal
    /// Base AI goal system.
    /// </summary>
    public abstract class Goal
    {
        [Flags]
        public enum Flag { Move=1, Look=2, Jump=4, Target=8 }

        public Flag Flags { get; protected set; } = Flag.Move;
        public bool IsRunning { get; protected set; } = false;

        public abstract bool CanUse();
        public virtual bool CanContinueToUse() => CanUse();
        public virtual void Start() => IsRunning = true;
        public virtual void Stop() => IsRunning = false;
        public virtual void Tick() {}
        public virtual bool RequiresUpdateEveryTick() => false;
    }

    public class RandomStrollGoal : Goal
    {
        private readonly Mob _mob;
        private Vector3 _targetPos;
        private int _cooldown = 0;

        public RandomStrollGoal(Mob mob, double speed = 1.0)
        {
            _mob = mob;
            Flags = Flag.Move;
        }

        public override bool CanUse()
        {
            if (_cooldown > 0) { _cooldown--; return false; }
            return GD.Randf() < 0.02f;
        }

        public override void Start()
        {
            base.Start();
            float dx = (GD.Randf() - 0.5f) * 20f;
            float dz = (GD.Randf() - 0.5f) * 20f;
            _targetPos = _mob.Position + new Vector3(dx, 0, dz);
            _cooldown = GD.RandRange(100, 300);
        }

        public override void Tick()
        {
            Vector3 dir = (_targetPos - _mob.Position);
            dir.Y = 0;
            if (dir.Length() < 1f)
            {
                Stop();
                return;
            }
            dir = dir.Normalized() * 0.1f;
            _mob.Velocity = new Vector3(dir.X, _mob.Velocity.Y, dir.Z);
            // Look at target
            _mob.YRot = Mathf.RadToDeg(Mathf.Atan2(-dir.X, dir.Z));
        }
    }

    public class LookAtPlayerGoal : Goal
    {
        private readonly Mob _mob;
        private readonly float _lookDistance;

        public LookAtPlayerGoal(Mob mob, float distance = 8f)
        {
            _mob = mob;
            _lookDistance = distance;
            Flags = Flag.Look;
        }

        public override bool CanUse()
        {
            // Check if player nearby - simplified
            return true;
        }

        public override void Tick()
        {
            // Look logic
        }
    }

    public class MeleeAttackGoal : Goal
    {
        private readonly Mob _mob;
        private readonly double _speed;
        private int _attackCooldown = 0;

        public MeleeAttackGoal(Mob mob, double speed = 1.2)
        {
            _mob = mob;
            _speed = speed;
            Flags = Flag.Move | Flag.Look;
        }

        public override bool CanUse() => true; // simplified - would check target
        public override void Tick()
        {
            if (_attackCooldown > 0) _attackCooldown--;
            // Move towards target and attack
        }
    }
}
