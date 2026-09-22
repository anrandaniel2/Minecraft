using Godot;
using System;
using System.Collections.Generic;
using Minecraft.World.Physics;
using Minecraft.World.Inventory;
using Minecraft.Core;

namespace Minecraft.World.Entity
{
    /// <summary>
    /// Base entity - translation of net.minecraft.world.entity.Entity
    /// Original: ~3000 lines, handles position, motion, collision, NBT, etc.
    /// </summary>
    public abstract class Entity
    {
        private static int _nextId = 1;

        public int Id { get; }
        public Guid Uuid { get; } = Guid.NewGuid();
        public string TypeName { get; protected set; }

        public Vector3 Position { get; set; }
        public Vector3 PreviousPosition { get; set; }
        public Vector3 Velocity { get; set; }
        public float YRot { get; set; } // yaw
        public float XRot { get; set; } // pitch
        public float YRotPrev { get; set; }
        public float XRotPrev { get; set; }

        public AABB BoundingBox { get; protected set; }
        public bool OnGround { get; set; } = false;
        public bool IsRemoved { get; private set; } = false;
        public bool NoPhysics { get; set; } = false;
        public bool NoGravity { get; set; } = false;
        public float FallDistance { get; set; } = 0;
        public int TickCount { get; set; } = 0;

        public global::Minecraft.World.Level.Level Level { get; set; }

        // Dimensions - from EntityDimensions
        public float Width { get; set; } = 0.6f;
        public float Height { get; set; } = 1.8f;
        public float EyeHeight { get; set; } = 1.62f;

        protected Entity(string typeName, global::Minecraft.World.Level.Level level)
        {
            Id = _nextId++;
            TypeName = typeName;
            Level = level;
            Position = Vector3.Zero;
            PreviousPosition = Vector3.Zero;
            BoundingBox = new AABB(0,0,0,0,0,0);
        }

        public virtual void SetPos(double x, double y, double z)
        {
            Position = new Vector3((float)x, (float)y, (float)z);
            UpdateBoundingBox();
        }

        public virtual void SetPos(Vector3 pos) => SetPos(pos.X, pos.Y, pos.Z);

        protected void UpdateBoundingBox()
        {
            BoundingBox = new AABB(Position.X - Width/2, Position.Y, Position.Z - Width/2, Position.X + Width/2, Position.Y + Height, Position.Z + Width/2);
        }

        public virtual void Tick()
        {
            PreviousPosition = Position;
            YRotPrev = YRot;
            XRotPrev = XRot;
            TickCount++;

            if (!NoPhysics)
            {
                // Apply gravity - from Entity.move()
                if (!NoGravity)
                {
                    Velocity += new Vector3(0, -0.08f, 0); // gravity
                    Velocity *= 0.98f; // drag
                }

                Move(MoverType.Self, Velocity);
            }

            // Fall distance
            if (OnGround) FallDistance = 0;
            else FallDistance += (float)(PreviousPosition.Y - Position.Y);
        }

        public enum MoverType { Self, Player, Piston, ShulkerBox, Shulker }

        public virtual void Move(MoverType mover, Vector3 motion)
        {
            if (NoPhysics)
            {
                SetPos(Position + motion);
                return;
            }

            // Collision - simplified from Entity.collide()
            // Original does per-axis collision with voxel shapes
            Vector3 originalMotion = motion;
            AABB box = BoundingBox;

            // X
            if (motion.X != 0)
            {
                AABB moved = box.Move(motion.X, 0, 0);
                if (!Collides(moved))
                {
                    box = moved;
                }
                else
                {
                    motion.X = 0;
                    Velocity = new Vector3(0, Velocity.Y, Velocity.Z);
                }
            }
            // Y
            if (motion.Y != 0)
            {
                AABB moved = box.Move(0, motion.Y, 0);
                if (!Collides(moved))
                {
                    box = moved;
                }
                else
                {
                    if (motion.Y < 0) OnGround = true;
                    motion.Y = 0;
                    Velocity = new Vector3(Velocity.X, 0, Velocity.Z);
                }
            }
            else
            {
                // Check ground
                AABB below = box.Move(0, -0.1, 0);
                OnGround = Collides(below);
            }
            // Z
            if (motion.Z != 0)
            {
                AABB moved = box.Move(0, 0, motion.Z);
                if (!Collides(moved))
                {
                    box = moved;
                }
                else
                {
                    motion.Z = 0;
                    Velocity = new Vector3(Velocity.X, Velocity.Y, 0);
                }
            }

            // Update position from box center
            Vector3 center = box.Center;
            Position = new Vector3(center.X, (float)box.MinY, center.Z);
            BoundingBox = box;
        }

        private bool Collides(AABB box)
        {
            if (Level == null) return false;
            // Check blocks in AABB
            int minX = (int)MathF.Floor((float)box.MinX);
            int minY = (int)MathF.Floor((float)box.MinY);
            int minZ = (int)MathF.Floor((float)box.MinZ);
            int maxX = (int)MathF.Floor((float)box.MaxX);
            int maxY = (int)MathF.Floor((float)box.MaxY);
            int maxZ = (int)MathF.Floor((float)box.MaxZ);

            for (int x = minX; x <= maxX; x++)
            {
                for (int y = minY; y <= maxY; y++)
                {
                    for (int z = minZ; z <= maxZ; z++)
                    {
                        var state = Level.GetBlockState(new Vector3I(x, y, z));
                        if (state.IsSolid)
                        {
                            AABB blockBox = new AABB(x, y, z, x+1, y+1, z+1);
                            if (box.Intersects(blockBox)) return true;
                        }
                    }
                }
            }
            return false;
        }

        public virtual void Remove() => IsRemoved = true;

        public Vector3 GetEyePosition() => Position + new Vector3(0, EyeHeight, 0);
        public Vector3 GetViewVector(float partialTicks = 1.0f)
        {
            float yaw = YRotPrev + (YRot - YRotPrev) * partialTicks;
            float pitch = XRotPrev + (XRot - XRotPrev) * partialTicks;
            float yawRad = yaw * Util.Math.Mth.DEG_TO_RAD;
            float pitchRad = pitch * Util.Math.Mth.DEG_TO_RAD;
            float cosPitch = MathF.Cos(pitchRad);
            return new Vector3(-MathF.Sin(yawRad) * cosPitch, -MathF.Sin(pitchRad), MathF.Cos(yawRad) * cosPitch).Normalized();
        }

        public virtual bool Hurt(float damage) => false;
        public virtual void Push(Vector3 vec) => Velocity += vec;
    }

    public abstract class LivingEntity : Entity
    {
        public float Health { get; set; } = 20f;
        public float MaxHealth { get; set; } = 20f;
        public float Absorption { get; set; } = 0;
        public int HurtTime { get; set; } = 0;
        public int DeathTime { get; set; } = 0;
        public bool IsDead => Health <= 0;

        public global::Minecraft.World.Inventory.InventoryContainer Inventory { get; } = new global::Minecraft.World.Inventory.InventoryContainer(36);

        protected LivingEntity(string type, global::Minecraft.World.Level.Level level) : base(type, level) {}

        public override bool Hurt(float damage)
        {
            if (IsDead) return false;
            Health -= damage;
            HurtTime = 10;
            if (Health <= 0)
            {
                Die();
            }
            return true;
        }

        protected virtual void Die()
        {
            DeathTime = 20;
            // Drop loot, etc.
        }

        public void Heal(float amount)
        {
            Health = MathF.Min(Health + amount, MaxHealth);
        }

        public override void Tick()
        {
            base.Tick();
            if (HurtTime > 0) HurtTime--;
            if (IsDead && DeathTime > 0) DeathTime--;
        }
    }

    public class Player : LivingEntity
    {
        public enum GameMode { Survival, Creative, Adventure, Spectator }

        public GameMode Mode { get; set; } = GameMode.Survival;
        public float Experience { get; set; } = 0;
        public int ExperienceLevel { get; set; } = 0;
        public int SelectedSlot { get; set; } = 0;
        public bool IsCrouching { get; set; } = false;
        public bool IsSprinting { get; set; } = false;
        public bool IsFlying { get; set; } = false;
        public float FlySpeed { get; set; } = 0.05f;
        public float WalkSpeed { get; set; } = 0.1f;

        // Abilities - from net.minecraft.world.entity.player.Abilities
        public bool MayFly { get; set; } = false;
        public bool Instabuild { get; set; } = false;
        public bool Invulnerable { get; set; } = false;

        public Player(global::Minecraft.World.Level.Level level) : base("player", level)
        {
            Width = 0.6f;
            Height = 1.8f;
            EyeHeight = 1.62f;
            MaxHealth = 20f;
            Health = 20f;
            MayFly = Mode == GameMode.Creative || Mode == GameMode.Spectator;
            Instabuild = Mode == GameMode.Creative;
        }

        public void SetGameMode(GameMode mode)
        {
            Mode = mode;
            MayFly = mode == GameMode.Creative || mode == GameMode.Spectator;
            Instabuild = mode == GameMode.Creative;
            Invulnerable = mode == GameMode.Creative || mode == GameMode.Spectator;
            NoPhysics = mode == GameMode.Spectator;
        }

        public ItemStack GetSelectedItem() => Inventory.GetItem(SelectedSlot);

        public void DropSelected()
        {
            var stack = GetSelectedItem();
            if (!stack.IsEmpty)
            {
                // Spawn item entity
                Inventory.SetItem(SelectedSlot, ItemStack.Empty);
            }
        }

        public override void Tick()
        {
            base.Tick();
            // Hunger, etc. would go here
        }
    }

    // Mob base - from net.minecraft.world.entity.Mob
    public abstract class Mob : LivingEntity
    {
        public enum MobType { Hostile, Passive, Neutral, Boss }

        public MobType Type { get; protected set; } = MobType.Passive;
        public float FollowRange { get; set; } = 32f;
        public List<AI.Goal> Goals { get; } = new List<AI.Goal>();

        protected Mob(string type, global::Minecraft.World.Level.Level level) : base(type, level) {}

        public void AddGoal(AI.Goal goal) => Goals.Add(goal);

        public override void Tick()
        {
            base.Tick();
            // AI tick
            foreach (var goal in Goals)
            {
                if (goal.CanUse()) goal.Tick();
            }
        }
    }

    // Example mobs - would have 100+ in full implementation
    public class Zombie : Mob
    {
        public Zombie(global::Minecraft.World.Level.Level level) : base("zombie", level) { Type = MobType.Hostile; MaxHealth = 20; Health = 20; }
    }
    public class Creeper : Mob
    {
        public float Swell { get; set; } = 0;
        public Creeper(global::Minecraft.World.Level.Level level) : base("creeper", level) { Type = MobType.Hostile; MaxHealth = 20; Health = 20; }
    }
    public class Skeleton : Mob
    {
        public Skeleton(global::Minecraft.World.Level.Level level) : base("skeleton", level) { Type = MobType.Hostile; MaxHealth = 20; Health = 20; }
    }
}
