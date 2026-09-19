#pragma once
#include <string>
#include <vector>
#include <unordered_map>
namespace Eaglercraft26 {
struct FullBiomeRegistry {
    struct BiomeInfo {
        std::string id;
        float temperature;
        float downfall;
        std::string precipitation;
        std::string category;
        int water_color;
        int sky_color;
    };
    static inline std::unordered_map<std::string, BiomeInfo> get_all_biomes() {
        std::unordered_map<std::string, BiomeInfo> map;
        map["badlands"] = {"badlands", 2.0f, 0.0f, "none", "desert", 4159204, 7907327};
        map["bamboo_jungle"] = {"bamboo_jungle", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["basalt_deltas"] = {"basalt_deltas", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["beach"] = {"beach", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["birch_forest"] = {"birch_forest", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["cherry_grove"] = {"cherry_grove", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["cold_ocean"] = {"cold_ocean", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["crimson_forest"] = {"crimson_forest", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["dark_forest"] = {"dark_forest", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["deep_cold_ocean"] = {"deep_cold_ocean", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["deep_dark"] = {"deep_dark", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["deep_frozen_ocean"] = {"deep_frozen_ocean", 0.0f, 0.5f, "snow", "icy", 4159204, 7907327};
        map["deep_lukewarm_ocean"] = {"deep_lukewarm_ocean", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["deep_ocean"] = {"deep_ocean", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["desert"] = {"desert", 2.0f, 0.0f, "none", "desert", 4159204, 7907327};
        map["dripstone_caves"] = {"dripstone_caves", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["end_barrens"] = {"end_barrens", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["end_highlands"] = {"end_highlands", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["end_midlands"] = {"end_midlands", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["eroded_badlands"] = {"eroded_badlands", 2.0f, 0.0f, "none", "desert", 4159204, 7907327};
        map["flower_forest"] = {"flower_forest", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["forest"] = {"forest", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["frozen_ocean"] = {"frozen_ocean", 0.0f, 0.5f, "snow", "icy", 4159204, 7907327};
        map["frozen_peaks"] = {"frozen_peaks", 0.0f, 0.5f, "snow", "icy", 4159204, 7907327};
        map["frozen_river"] = {"frozen_river", 0.0f, 0.5f, "snow", "icy", 4159204, 7907327};
        map["grove"] = {"grove", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["ice_spikes"] = {"ice_spikes", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["jagged_peaks"] = {"jagged_peaks", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["jungle"] = {"jungle", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["lukewarm_ocean"] = {"lukewarm_ocean", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["lush_caves"] = {"lush_caves", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["mangrove_swamp"] = {"mangrove_swamp", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["meadow"] = {"meadow", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["mushroom_fields"] = {"mushroom_fields", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["nether_wastes"] = {"nether_wastes", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["ocean"] = {"ocean", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["old_growth_birch_forest"] = {"old_growth_birch_forest", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["old_growth_pine_taiga"] = {"old_growth_pine_taiga", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["old_growth_spruce_taiga"] = {"old_growth_spruce_taiga", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["pale_garden"] = {"pale_garden", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["plains"] = {"plains", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["river"] = {"river", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["savanna"] = {"savanna", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["savanna_plateau"] = {"savanna_plateau", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["small_end_islands"] = {"small_end_islands", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["snowy_beach"] = {"snowy_beach", 0.0f, 0.5f, "snow", "icy", 4159204, 7907327};
        map["snowy_plains"] = {"snowy_plains", 0.0f, 0.5f, "snow", "icy", 4159204, 7907327};
        map["snowy_slopes"] = {"snowy_slopes", 0.0f, 0.5f, "snow", "icy", 4159204, 7907327};
        map["snowy_taiga"] = {"snowy_taiga", 0.0f, 0.5f, "snow", "icy", 4159204, 7907327};
        map["soul_sand_valley"] = {"soul_sand_valley", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["sparse_jungle"] = {"sparse_jungle", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["stony_peaks"] = {"stony_peaks", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["stony_shore"] = {"stony_shore", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["sunflower_plains"] = {"sunflower_plains", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["swamp"] = {"swamp", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["taiga"] = {"taiga", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["the_end"] = {"the_end", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["the_void"] = {"the_void", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["warm_ocean"] = {"warm_ocean", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["warped_forest"] = {"warped_forest", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["windswept_forest"] = {"windswept_forest", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["windswept_gravelly_hills"] = {"windswept_gravelly_hills", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["windswept_hills"] = {"windswept_hills", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["windswept_savanna"] = {"windswept_savanna", 0.5f, 0.5f, "rain", "plains", 4159204, 7907327};
        map["wooded_badlands"] = {"wooded_badlands", 2.0f, 0.0f, "none", "desert", 4159204, 7907327};
        return map;
    }
};
}
