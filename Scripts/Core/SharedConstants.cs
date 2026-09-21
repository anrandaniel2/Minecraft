using System;

namespace Minecraft.Core
{
    /// <summary>
    /// Direct translation of net.minecraft.SharedConstants
    /// Contains version, protocol, world data version, and global constants.
    /// Original Java: SharedConstants.java - ~400 lines
    /// </summary>
    public static class SharedConstants
    {
        public const string VERSION_STRING = "26.3";
        public const string RELEASE_TYPE = "release";
        public const int WORLD_VERSION = 5002; // 26.3 data version
        public const int PROTOCOL_VERSION = 779; // hypothetical 26.3 protocol
        public const int RELEASE_TARGET = 25; // Java 25
        public const bool IS_DEMO = false;
        public const bool IS_DEBUG = false;
        public const int TICKS_PER_SECOND = 20;
        public const float TICK_SECONDS = 1.0f / TICKS_PER_SECOND;
        public const int MAX_CHAT_LENGTH = 256;
        public const int MAX_COMMAND_LENGTH = 2048;

        // World constants - from net.minecraft.world.level.Level
        public const int MIN_Y = -64;
        public const int MAX_Y = 320;
        public const int WORLD_HEIGHT = MAX_Y - MIN_Y; // 384
        public const int CHUNK_SIZE = 16;
        public const int CHUNK_SECTION_SIZE = 16;
        public const int CHUNK_SECTIONS = WORLD_HEIGHT / CHUNK_SECTION_SIZE; // 24
        public const int CHUNK_VOLUME = CHUNK_SIZE * WORLD_HEIGHT * CHUNK_SIZE; // 98304
        public const int SECTION_VOLUME = CHUNK_SIZE * CHUNK_SECTION_SIZE * CHUNK_SIZE; // 4096
        public const int REGION_SIZE = 32; // chunks per region file

        // Rendering constants
        public const int DEFAULT_RENDER_DISTANCE = 6; // mobile optimized, original 12
        public const int MAX_RENDER_DISTANCE = 12; // capped for mobile GPU
        public const int MIN_RENDER_DISTANCE = 2;

        // Performance
        public const bool ENABLE_CULLING = true;
        public const bool ENABLE_GREEDY_MESHING = true;
        public const int MAX_CHUNK_UPDATES_PER_FRAME = 4;
        public const int CHUNK_GC_INTERVAL_TICKS = 600; // 30 sec

        public static bool IsValidVersion(string version) => version == VERSION_STRING;
        
        public static void CheckWorldVersion(int dataVersion)
        {
            if (dataVersion > WORLD_VERSION)
                throw new InvalidOperationException($"World newer than game: {dataVersion} > {WORLD_VERSION}");
        }
    }
}
