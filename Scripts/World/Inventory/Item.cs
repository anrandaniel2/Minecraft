using System;
using System.Collections.Generic;
using Minecraft.World.Level.Block;
using BlockClass = global::Minecraft.World.Level.Block.Block;

namespace Minecraft.World.Inventory
{
    /// <summary>
    /// Translation of net.minecraft.world.item.Item and Items registry
    /// Original Items.java has 1400+ items.
    /// </summary>
    public class Item
    {
        public int Id { get; }
        public string Name { get; }
        public int MaxStackSize { get; set; } = 64;
        public int MaxDamage { get; set; } = 0;
        public bool IsFood { get; set; } = false;
        public int FoodNutrition { get; set; } = 0;
        public float FoodSaturation { get; set; } = 0;
        public BlockClass Block { get; set; } = null; // for BlockItem

        public Item(int id, string name)
        {
            Id = id;
            Name = name;
        }

        public virtual bool IsBlockItem => Block != null;
        public virtual bool IsDamageable => MaxDamage > 0;

        public class Properties
        {
            public int StacksTo { get; set; } = 64;
            public int Durability { get; set; } = 0;
            public BlockClass Block { get; set; } = null;
            public static Properties Of() => new Properties();
            public Properties Stacks(int size) { StacksTo = size; return this; }
            public Properties DurabilityProp(int d) { Durability = d; return this; }
        }
    }

    public class BlockItem : Item
    {
        public BlockItem(int id, string name, BlockClass block) : base(id, name)
        {
            Block = block;
        }
    }

    public struct ItemStack : IEquatable<ItemStack>
    {
        public static readonly ItemStack Empty = new ItemStack(null, 0);

        public Item Item { get; }
        public int Count { get; private set; }
        public int Damage { get; private set; }
        public Dictionary<string, object> Tag { get; } // NBT

        public ItemStack(Item item, int count = 1, int damage = 0)
        {
            Item = item;
            Count = count;
            Damage = damage;
            Tag = null;
        }

        public bool IsEmpty => Item == null || Count <= 0;
        public bool IsFull => !IsEmpty && Count >= Item.MaxStackSize;

        public void SetCount(int count) => Count = Math.Clamp(count, 0, Item?.MaxStackSize ?? 64);
        public void Grow(int amount) => SetCount(Count + amount);
        public void Shrink(int amount) => SetCount(Count - amount);

        public ItemStack Copy() => new ItemStack(Item, Count, Damage);

        public bool Equals(ItemStack other) => Item?.Id == other.Item?.Id && Count == other.Count && Damage == other.Damage;
        public override bool Equals(object obj) => obj is ItemStack other && Equals(other);
        public override int GetHashCode() => HashCode.Combine(Item?.Id, Count, Damage);
        public static bool operator ==(ItemStack a, ItemStack b) => a.Equals(b);
        public static bool operator !=(ItemStack a, ItemStack b) => !a.Equals(b);

        public override string ToString() => IsEmpty ? "Empty" : $"{Item.Name} x{Count}";
    }

    public static class Items
    {
        private static Dictionary<string, Item> _byName = new Dictionary<string, Item>(1024);
        private static Dictionary<int, Item> _byId = new Dictionary<int, Item>(1024);
        private static List<Item> _all = new List<Item>(1024);
        private static int _nextId = 0;

        // Core items - subset, full would be 1400+
        public static Item AIR { get; private set; }
        public static Item STONE { get; private set; }
        public static Item GRASS_BLOCK { get; private set; }
        public static Item DIRT { get; private set; }
        public static Item COBBLESTONE { get; private set; }
        public static Item OAK_PLANKS { get; private set; }
        public static Item OAK_LOG { get; private set; }
        public static Item OAK_LEAVES { get; private set; }
        public static Item BEDROCK { get; private set; }
        public static Item SAND { get; private set; }
        public static Item GRAVEL { get; private set; }
        public static Item GOLD_ORE { get; private set; }
        public static Item IRON_ORE { get; private set; }
        public static Item COAL_ORE { get; private set; }
        public static Item DIAMOND_ORE { get; private set; }
        public static Item OAK_SAPLING { get; private set; }
        public static Item GLASS { get; private set; }
        public static Item LAPIS_LAZULI { get; private set; }
        public static Item DIAMOND { get; private set; }
        public static Item IRON_INGOT { get; private set; }
        public static Item GOLD_INGOT { get; private set; }
        public static Item STICK { get; private set; }
        public static Item BOWL { get; private set; }
        public static Item MUSHROOM_STEW { get; private set; }
        public static Item STRING { get; private set; }
        public static Item FEATHER { get; private set; }
        public static Item GUNPOWDER { get; private set; }
        public static Item WHEAT_SEEDS { get; private set; }
        public static Item WHEAT { get; private set; }
        public static Item BREAD { get; private set; }
        public static Item FLINT { get; private set; }
        public static Item COAL { get; private set; }
        public static Item IRON_PICKAXE { get; private set; }
        public static Item DIAMOND_PICKAXE { get; private set; }
        public static Item IRON_SWORD { get; private set; }
        public static Item DIAMOND_SWORD { get; private set; }
        public static Item BOW { get; private set; }
        public static Item ARROW { get; private set; }
        public static Item APPLE { get; private set; }
        public static Item GOLDEN_APPLE { get; private set; }
        public static Item BUCKET { get; private set; }
        public static Item WATER_BUCKET { get; private set; }
        public static Item LAVA_BUCKET { get; private set; }
        public static Item CRAFTING_TABLE { get; private set; }
        public static Item FURNACE { get; private set; }
        public static Item CHEST { get; private set; }
        public static Item TORCH { get; private set; }

        static Items()
        {
            RegisterAll();
        }

        private static Item Register(string name, Func<int, string, Item> factory = null)
        {
            int id = _nextId++;
            Item item = factory != null ? factory(id, name) : new Item(id, name);
            _byName[name] = item;
            _byId[id] = item;
            _all.Add(item);
            return item;
        }

        private static Item RegisterBlock(string name, BlockClass block)
        {
            return Register(name, (id, n) => new BlockItem(id, n, block) { });
        }

        private static void RegisterAll()
        {
            AIR = Register("air");
            STONE = RegisterBlock("stone", Blocks.STONE);
            GRASS_BLOCK = RegisterBlock("grass_block", Blocks.GRASS_BLOCK);
            DIRT = RegisterBlock("dirt", Blocks.DIRT);
            COBBLESTONE = RegisterBlock("cobblestone", Blocks.COBBLESTONE);
            OAK_PLANKS = RegisterBlock("oak_planks", Blocks.OAK_PLANKS);
            OAK_LOG = RegisterBlock("oak_log", Blocks.OAK_LOG);
            OAK_LEAVES = RegisterBlock("oak_leaves", Blocks.OAK_LEAVES);
            BEDROCK = RegisterBlock("bedrock", Blocks.BEDROCK);
            SAND = RegisterBlock("sand", Blocks.SAND);
            GRAVEL = RegisterBlock("gravel", Blocks.GRAVEL);
            GOLD_ORE = RegisterBlock("gold_ore", Blocks.GOLD_ORE);
            IRON_ORE = RegisterBlock("iron_ore", Blocks.IRON_ORE);
            COAL_ORE = RegisterBlock("coal_ore", Blocks.COAL_ORE);
            DIAMOND_ORE = RegisterBlock("diamond_ore", Blocks.DIAMOND_ORE);
            OAK_SAPLING = RegisterBlock("oak_sapling", Blocks.OAK_SAPLING);
            GLASS = RegisterBlock("glass", Blocks.GLASS);
            DIAMOND = Register("diamond");
            IRON_INGOT = Register("iron_ingot");
            GOLD_INGOT = Register("gold_ingot");
            STICK = Register("stick");
            STRING = Register("string");
            FEATHER = Register("feather");
            GUNPOWDER = Register("gunpowder");
            WHEAT_SEEDS = Register("wheat_seeds");
            WHEAT = Register("wheat");
            BREAD = Register("bread");
            FLINT = Register("flint");
            COAL = Register("coal");
            APPLE = Register("apple");
            GOLDEN_APPLE = Register("golden_apple");
            BUCKET = Register("bucket", (id, n) => new Item(id, n) { MaxStackSize = 16 });
            WATER_BUCKET = Register("water_bucket", (id, n) => new Item(id, n) { MaxStackSize = 1 });
            LAVA_BUCKET = Register("lava_bucket", (id, n) => new Item(id, n) { MaxStackSize = 1 });
            CRAFTING_TABLE = RegisterBlock("crafting_table", Blocks.CRAFTING_TABLE);
            FURNACE = RegisterBlock("furnace", Blocks.FURNACE);
            CHEST = RegisterBlock("chest", Blocks.CHEST);
            TORCH = RegisterBlock("torch", Blocks.TORCH);

            // Tools with durability
            IRON_PICKAXE = Register("iron_pickaxe", (id, n) => new Item(id, n) { MaxStackSize = 1, MaxDamage = 250 });
            DIAMOND_PICKAXE = Register("diamond_pickaxe", (id, n) => new Item(id, n) { MaxStackSize = 1, MaxDamage = 1561 });
            IRON_SWORD = Register("iron_sword", (id, n) => new Item(id, n) { MaxStackSize = 1, MaxDamage = 250 });
            DIAMOND_SWORD = Register("diamond_sword", (id, n) => new Item(id, n) { MaxStackSize = 1, MaxDamage = 1561 });
            BOW = Register("bow", (id, n) => new Item(id, n) { MaxStackSize = 1, MaxDamage = 384 });
            ARROW = Register("arrow");
            LAPIS_LAZULI = Register("lapis_lazuli");
        }

        public static Item GetByName(string name) => _byName.TryGetValue(name, out var i) ? i : AIR;
        public static Item GetById(int id) => _byId.TryGetValue(id, out var i) ? i : AIR;
        public static IReadOnlyList<Item> All => _all;
    }

    public class Inventory
    {
        private ItemStack[] _items;
        public int Size => _items.Length;

        public Inventory(int size)
        {
            _items = new ItemStack[size];
            for (int i = 0; i < size; i++) _items[i] = ItemStack.Empty;
        }

        public ItemStack GetItem(int slot) => (slot >=0 && slot < Size) ? _items[slot] : ItemStack.Empty;
        public void SetItem(int slot, ItemStack stack)
        {
            if (slot >=0 && slot < Size) _items[slot] = stack;
        }

        public bool AddItem(ItemStack stack)
        {
            if (stack.IsEmpty) return false;
            // Try merge
            for (int i = 0; i < Size; i++)
            {
                if (_items[i].IsEmpty) continue;
                if (_items[i].Item.Id == stack.Item.Id && !_items[i].IsFull)
                {
                    int space = _items[i].Item.MaxStackSize - _items[i].Count;
                    int toMove = Math.Min(space, stack.Count);
                    _items[i].Grow(toMove);
                    stack.Shrink(toMove);
                    if (stack.IsEmpty) return true;
                }
            }
            // Empty slot
            for (int i = 0; i < Size; i++)
            {
                if (_items[i].IsEmpty)
                {
                    _items[i] = stack.Copy();
                    return true;
                }
            }
            return false;
        }

        public void Clear() => Array.Fill(_items, ItemStack.Empty);
        public ItemStack[] GetAll() => _items;
    }
}
