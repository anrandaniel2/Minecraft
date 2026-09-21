using System;
using System.Collections.Generic;

namespace Minecraft.World.Inventory.Crafting
{
    /// <summary>
    /// Additional recipe types: Smelting, Blasting, Smoking, Campfire, Smithing, Stonecutting
    /// Translation of net.minecraft.world.item.crafting.*
    /// </summary>
    public class SmeltingRecipe : Recipe
    {
        public Item Ingredient { get; }
        public float Experience { get; }
        public int CookingTime { get; }

        public SmeltingRecipe(string id, Item ingredient, ItemStack result, float exp, int time) : base(id, "", result)
        {
            Ingredient = ingredient;
            Experience = exp;
            CookingTime = time;
        }

        public override bool Matches(CraftingContainer container)
        {
            if (container.Size != 1) return false;
            var stack = container.GetItem(0);
            return !stack.IsEmpty && stack.Item.Id == Ingredient.Id;
        }

        public override ItemStack Assemble(CraftingContainer container) => Result.Copy();
    }

    public class RecipeManager
    {
        private List<Recipe> _allRecipes = new List<Recipe>(1000);

        public RecipeManager()
        {
            LoadVanilla();
        }

        private void LoadVanilla()
        {
            // Would load from data/minecraft/recipes/*.json (1000+ files)
            // Example smelting
            _allRecipes.Add(new SmeltingRecipe("iron_ingot", Items.IRON_ORE, new ItemStack(Items.IRON_INGOT, 1), 0.7f, 200));
            _allRecipes.Add(new SmeltingRecipe("gold_ingot", Items.GOLD_ORE, new ItemStack(Items.GOLD_INGOT, 1), 1.0f, 200));
            // ... 1000 more
        }

        public List<Recipe> GetAll() => _allRecipes;
    }
}
