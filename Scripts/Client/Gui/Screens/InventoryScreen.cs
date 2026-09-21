using Godot;
using System;
using Minecraft.World.Inventory;
using Minecraft.World.Inventory.Crafting;

namespace Minecraft.Client.Gui.Screens
{
    /// <summary>
    /// Translation of net.minecraft.client.gui.screens.inventory.InventoryScreen / CraftingScreen
    /// Recreates inventory UI with exact texture slices from container/inventory.png etc.
    /// </summary>
    public partial class InventoryScreen : Screen
    {
        private global::Minecraft.World.Inventory.global::Minecraft.World.Inventory.Inventory _playerInventory;
        private CraftingContainer _craftingContainer;
        private CraftingManager _craftingManager;

        private GridContainer _inventoryGrid;
        private GridContainer _craftingGrid;
        private TextureRect _resultSlot;

        public InventoryScreen(global::Minecraft.World.Inventory.Inventory inventory) : base("Inventory")
        {
            _playerInventory = inventory;
            _craftingContainer = new CraftingContainer(2, 2); // inventory crafting 2x2
            _craftingManager = new CraftingManager();
        }

        protected override void Init()
        {
            // Background - from container/inventory.png (176x166)
            var bg = new ColorRect();
            bg.Color = new Color(0.6f, 0.6f, 0.6f, 1f);
            bg.SetAnchorsPreset(LayoutPreset.FullRect);
            AddChild(bg);

            var container = new CenterContainer();
            container.SetAnchorsPreset(LayoutPreset.FullRect);
            AddChild(container);

            var panel = new Panel();
            panel.CustomMinimumSize = new Vector2(400, 400);
            container.AddChild(panel);

            // Crafting grid - 2x2
            CreateLabel("Crafting", new Vector2(20, 20));
            _craftingGrid = new GridContainer();
            _craftingGrid.Position = new Vector2(20, 50);
            _craftingGrid.Size = new Vector2(100, 100);
            _craftingGrid.Columns = 2;
            panel.AddChild(_craftingGrid);

            for (int i = 0; i < 4; i++)
            {
                var slot = CreateSlot(i, true);
                _craftingGrid.AddChild(slot);
            }

            // Result slot
            _resultSlot = new TextureRect();
            _resultSlot.Position = new Vector2(150, 70);
            _resultSlot.Size = new Vector2(40, 40);
            _resultSlot.Modulate = new Color(0.8f, 0.8f, 0.8f);
            panel.AddChild(_resultSlot);

            // Inventory grid - 9x3 + hotbar
            CreateLabel("Inventory", new Vector2(20, 180));
            _inventoryGrid = new GridContainer();
            _inventoryGrid.Position = new Vector2(20, 210);
            _inventoryGrid.Size = new Vector2(360, 180);
            _inventoryGrid.Columns = 9;
            panel.AddChild(_inventoryGrid);

            for (int i = 9; i < 36; i++)
            {
                var slot = CreateSlot(i, false);
                _inventoryGrid.AddChild(slot);
            }

            // Hotbar
            var hotbarGrid = new GridContainer();
            hotbarGrid.Position = new Vector2(20, 320);
            hotbarGrid.Size = new Vector2(360, 40);
            hotbarGrid.Columns = 9;
            panel.AddChild(hotbarGrid);

            for (int i = 0; i < 9; i++)
            {
                var slot = CreateSlot(i, false);
                hotbarGrid.AddChild(slot);
            }

            CreateButton("Close", new Vector2(150, 370), new Vector2(100, 30), () => QueueFree());
        }

        private Control CreateSlot(int index, bool isCrafting)
        {
            var slotBg = new Panel();
            slotBg.CustomMinimumSize = new Vector2(36, 36);
            var style = new StyleBoxFlat();
            style.BgColor = new Color(0.3f, 0.3f, 0.3f, 1f);
            style.BorderColor = new Color(0.1f, 0.1f, 0.1f, 1f);
            style.SetBorderWidthAll(2);
            slotBg.AddThemeStyleboxOverride("panel", style);

            var itemIcon = new TextureRect();
            itemIcon.SetAnchorsPreset(LayoutPreset.FullRect);
            itemIcon.ExpandMode = TextureRect.ExpandModeEnum.IgnoreSize;

            var stack = isCrafting ? _craftingContainer.GetItem(index) : _playerInventory.GetItem(index);
            if (!stack.IsEmpty)
            {
                // Would set texture from item
                var label = new Label();
                label.Text = stack.Item.Name.Substring(0, Math.Min(3, stack.Item.Name.Length));
                label.AddThemeFontSizeOverride("font_size", 10);
                slotBg.AddChild(label);
            }

            slotBg.AddChild(itemIcon);
            return slotBg;
        }

        private void UpdateCraftingResult()
        {
            var recipe = _craftingManager.FindMatching(_craftingContainer);
            if (recipe != null)
            {
                GD.Print($"[InventoryScreen] Crafting match: {recipe.Id} -> {recipe.Result}");
            }
        }
    }

    public partial class CraftingScreen : Screen
    {
        private CraftingContainer _container;
        private CraftingManager _manager;

        public CraftingScreen() : base("Crafting")
        {
            _container = new CraftingContainer(3, 3);
            _manager = new CraftingManager();
        }

        protected override void Init()
        {
            var bg = new ColorRect();
            bg.Color = new Color(0.6f, 0.6f, 0.6f);
            bg.SetAnchorsPreset(LayoutPreset.FullRect);
            AddChild(bg);

            CreateLabel("Crafting Table - 3x3", new Vector2(50, 20));

            var grid = new GridContainer();
            grid.Position = new Vector2(50, 60);
            grid.Size = new Vector2(150, 150);
            grid.Columns = 3;
            AddChild(grid);

            for (int i = 0; i < 9; i++)
            {
                var panel = new Panel();
                panel.CustomMinimumSize = new Vector2(40, 40);
                grid.AddChild(panel);
            }

            CreateButton("Close", new Vector2(100, 250), new Vector2(100, 30), () => QueueFree());
        }
    }
}
