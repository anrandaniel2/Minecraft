#pragma once
#include <string>
#include <vector>
#include <unordered_map>
namespace Eaglercraft26 {
struct FullEntityRegistry {
    struct EntityInfo {
        std::string id;
        float width;
        float height;
        float health;
        bool hostile;
        bool is_animal;
        std::string category;
    };
    static inline std::unordered_map<std::string, EntityInfo> get_all_entities() {
        std::unordered_map<std::string, EntityInfo> map;
        return map;
    }
};
}
