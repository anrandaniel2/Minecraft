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
        map["allay"] = {"allay", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["armadillo"] = {"armadillo", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["axolotl"] = {"axolotl", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["bat"] = {"bat", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["bee"] = {"bee", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["blaze"] = {"blaze", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["bogged"] = {"bogged", 0.6f, 1.8f, 20f, true, false, "monster"};
        map["breeze"] = {"breeze", 0.6f, 1.8f, 20f, true, false, "monster"};
        map["camel"] = {"camel", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["cat"] = {"cat", 0.6f, 1.8f, 20f, false, true, "animal"};
        map["cave_spider"] = {"cave_spider", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["chicken"] = {"chicken", 0.6f, 1.8f, 20f, false, true, "animal"};
        map["cod"] = {"cod", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["cow"] = {"cow", 0.6f, 1.8f, 20f, false, true, "animal"};
        map["creaking"] = {"creaking", 0.6f, 1.8f, 20f, true, false, "monster"};
        map["creeper"] = {"creeper", 0.6f, 1.8f, 20f, true, false, "monster"};
        map["dolphin"] = {"dolphin", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["donkey"] = {"donkey", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["drowned"] = {"drowned", 0.6f, 1.8f, 20f, true, false, "monster"};
        map["elder_guardian"] = {"elder_guardian", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["ender_dragon"] = {"ender_dragon", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["enderman"] = {"enderman", 0.6f, 1.8f, 20f, true, false, "monster"};
        map["endermite"] = {"endermite", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["evoker"] = {"evoker", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["fox"] = {"fox", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["frog"] = {"frog", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["ghast"] = {"ghast", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["glow_squid"] = {"glow_squid", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["goat"] = {"goat", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["guardian"] = {"guardian", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["hoglin"] = {"hoglin", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["horse"] = {"horse", 0.6f, 1.8f, 20f, false, true, "animal"};
        map["husk"] = {"husk", 0.6f, 1.8f, 20f, true, false, "monster"};
        map["illusioner"] = {"illusioner", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["iron_golem"] = {"iron_golem", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["llama"] = {"llama", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["magma_cube"] = {"magma_cube", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["mooshroom"] = {"mooshroom", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["mule"] = {"mule", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["ocelot"] = {"ocelot", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["panda"] = {"panda", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["parrot"] = {"parrot", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["phantom"] = {"phantom", 0.6f, 1.8f, 20f, true, false, "monster"};
        map["pig"] = {"pig", 0.6f, 1.8f, 20f, false, true, "animal"};
        map["piglin"] = {"piglin", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["piglin_brute"] = {"piglin_brute", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["pillager"] = {"pillager", 0.6f, 1.8f, 20f, true, false, "monster"};
        map["polar_bear"] = {"polar_bear", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["pufferfish"] = {"pufferfish", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["rabbit"] = {"rabbit", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["ravager"] = {"ravager", 0.6f, 1.8f, 20f, true, false, "monster"};
        map["salmon"] = {"salmon", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["sheep"] = {"sheep", 0.6f, 1.8f, 20f, false, true, "animal"};
        map["shulker"] = {"shulker", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["silverfish"] = {"silverfish", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["skeleton"] = {"skeleton", 0.6f, 1.8f, 20f, true, false, "monster"};
        map["skeleton_horse"] = {"skeleton_horse", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["slime"] = {"slime", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["sniffer"] = {"sniffer", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["snow_golem"] = {"snow_golem", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["spider"] = {"spider", 0.6f, 1.8f, 20f, true, false, "monster"};
        map["squid"] = {"squid", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["stray"] = {"stray", 0.6f, 1.8f, 20f, true, false, "monster"};
        map["strider"] = {"strider", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["tadpole"] = {"tadpole", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["trader_llama"] = {"trader_llama", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["tropical_fish"] = {"tropical_fish", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["turtle"] = {"turtle", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["vex"] = {"vex", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["villager"] = {"villager", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["vindicator"] = {"vindicator", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["wandering_trader"] = {"wandering_trader", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["warden"] = {"warden", 0.6f, 1.8f, 20f, true, false, "monster"};
        map["witch"] = {"witch", 0.6f, 1.8f, 20f, true, false, "monster"};
        map["wither"] = {"wither", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["wither_skeleton"] = {"wither_skeleton", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["wolf"] = {"wolf", 0.6f, 1.8f, 20f, false, true, "animal"};
        map["zoglin"] = {"zoglin", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["zombie"] = {"zombie", 0.6f, 1.8f, 20f, true, false, "monster"};
        map["zombie_horse"] = {"zombie_horse", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["zombie_villager"] = {"zombie_villager", 0.6f, 1.8f, 20f, false, false, "creature"};
        map["zombified_piglin"] = {"zombified_piglin", 0.6f, 1.8f, 20f, false, false, "creature"};
        return map;
    }
};
}
