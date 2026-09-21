using System;
using System.Collections.Generic;
using Minecraft.World.Level.Block;

namespace Minecraft.World.Inventory.Crafting
{
    /// <summary>
    /// Translation of net.minecraft.world.item.crafting.Recipe, CraftingRecipe, RecipeManager
    /// Handles shaped, shapeless, smelting, etc.
    /// </summary>
    public abstract class Recipe
    {
        public string Id { get; }
        public string Group { get; }
        public ItemStack Result { get; }

        protected Recipe(string id, string group, ItemStack result)
        {
            Id = id;
            Group = group;
            Result = result;
        }

        public abstract bool Matches(CraftingContainer container);
        public abstract ItemStack Assemble(CraftingContainer container);
    }

    public class ShapedRecipe : Recipe
    {
        public int Width { get; }
        public int Height { get; }
        public Item[] Ingredients { get; } // flattened width*height, null for empty

        public ShapedRecipe(string id, string group, int width, int height, Item[] ingredients, ItemStack result) : base(id, group, result)
        {
            Width = width;
            Height = height;
            Ingredients = ingredients;
        }

        public override bool Matches(CraftingContainer container)
        {
            // Try all offsets in 3x3 grid
            for (int offsetX = 0; offsetX <= container.Width - Width; offsetX++)
            {
                for (int offsetY = 0; offsetY <= container.Height - Height; offsetY++)
                {
                    if (MatchesAt(container, offsetX, offsetY, false)) return true;
                    if (MatchesAt(container, offsetX, offsetY, true)) return true; // mirrored
                }
            }
            return false;
        }

        private bool MatchesAt(CraftingContainer container, int offsetX, int offsetY, bool mirrored)
        {
            for (int y = 0; y < container.Height; y++)
            {
                for (int x = 0; x < container.Width; x++)
                {
                    int recipeX = x - offsetX;
                    int recipeY = y - offsetY;
                    Item expected = null;
                    if (recipeX >=0 && recipeY >=0 && recipeX < Width && recipeY < Height)
                    {
                        int idx = mirrored ? (Width - recipeX -1) + recipeY * Width : recipeX + recipeY * Width;
                        expected = Ingredients[idx];
                    }
                    var actual = container.GetItem(x + y * container.Width);
                    if (expected == null)
                    {
                        if (!actual.IsEmpty) return false;
                    }
                    else
                    {
                        if (actual.IsEmpty || actual.Item.Id != expected.Id) return false;
                    }
                }
            }
            return true;
        }

        public override ItemStack Assemble(CraftingContainer container) => Result.Copy();
    }

    public class ShapelessRecipe : Recipe
    {
        public List<Item> Ingredients { get; }

        public ShapelessRecipe(string id, string group, List<Item> ingredients, ItemStack result) : base(id, group, result)
        {
            Ingredients = ingredients;
        }

        public override bool Matches(CraftingContainer container)
        {
            List<Item> needed = new List<Item>(Ingredients);
            for (int i = 0; i < container.Size; i++)
            {
                var stack = container.GetItem(i);
                if (stack.IsEmpty) continue;
                bool found = false;
                for (int j = 0; j < needed.Count; j++)
                {
                    if (needed[j].Id == stack.Item.Id)
                    {
                        needed.RemoveAt(j);
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
            }
            return needed.Count == 0;
        }

        public override ItemStack Assemble(CraftingContainer container) => Result.Copy();
    }

    public class CraftingContainer
    {
        public int Width { get; }
        public int Height { get; }
        public int Size => Width * Height;
        private ItemStack[] _items;

        public CraftingContainer(int width, int height)
        {
            Width = width;
            Height = height;
            _items = new ItemStack[width*height];
            for (int i=0;i<_items.Length;i++) _items[i]=ItemStack.Empty;
        }

        public ItemStack GetItem(int idx) => (idx>=0 && idx<Size) ? _items[idx] : ItemStack.Empty;
        public void SetItem(int idx, ItemStack stack) { if (idx>=0 && idx<Size) _items[idx]=stack; }
    }

    public class CraftingManager
    {
        private List<Recipe> _recipes = new List<Recipe>(500);

        public CraftingManager()
        {
            RegisterVanillaRecipes();
        }

        private void RegisterVanillaRecipes()
        {
            // Planks from logs - shapeless
            _recipes.Add(new ShapelessRecipe("oak_planks", "", new List<Item>{ Items.OAK_LOG }, new ItemStack(Items.OAK_PLANKS, 4)));

            // Sticks - shaped: planks over planks
            _recipes.Add(new ShapedRecipe("stick", "", 1, 2, new Item[]{ Items.OAK_PLANKS, Items.OAK_PLANKS }, new ItemStack(Items.STICK, 4)));

            // Crafting table - 2x2 planks
            _recipes.Add(new ShapedRecipe("crafting_table", "", 2, 2, new Item[]{ Items.OAK_PLANKS, Items.OAK_PLANKS, Items.OAK_PLANKS, Items.OAK_PLANKS }, new ItemStack(Items.CRAFTING_TABLE, 1)));

            // Torch - coal + stick
            _recipes.Add(new ShapedRecipe("torch", "", 1, 2, new Item[]{ Items.COAL, Items.STICK }, new ItemStack(Items.TORCH, 4)));

            // Pickaxe - shaped 3x3
            // Would add all tool recipes, etc. Full implementation has 1000+ recipes from data/minecraft/recipes/
            // For brevity we have core set
        }

        public Recipe FindMatching(CraftingContainer container)
        {
            foreach (var recipe in _recipes)
            {
                if (recipe.Matches(container)) return recipe;
            }
            return null;
        }

        public List<Recipe> GetAll() => _recipes;
    }
}
