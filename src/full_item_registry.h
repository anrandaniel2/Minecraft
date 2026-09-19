#pragma once
#include <string>
#include <vector>
#include <unordered_map>
namespace Eaglercraft26 {
struct FullItemRegistry {
    struct ItemInfo {
        std::string id;
        int max_stack;
        int durability;
        bool is_food;
        int food_value;
        float saturation;
        std::string type;
    };
    static inline std::unordered_map<std::string, ItemInfo> get_all_items() {
        std::unordered_map<std::string, ItemInfo> map;
        return map;
    }
};
}
