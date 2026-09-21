namespace Minecraft.Core
{
    /// <summary>
    /// Translation of net.minecraft.WorldVersion
    /// </summary>
    public interface IWorldVersion
    {
        int DataVersion { get; }
        string Id { get; }
        string Name { get; }
        bool IsStable { get; }
    }

    public sealed class WorldVersion : IWorldVersion
    {
        public static readonly WorldVersion CURRENT = new WorldVersion(
            SharedConstants.WORLD_VERSION,
            SharedConstants.VERSION_STRING,
            "26.3 - Wilderness Bound",
            true
        );

        public int DataVersion { get; }
        public string Id { get; }
        public string Name { get; }
        public bool IsStable { get; }
        public int ProtocolVersion { get; }
        public int ResourcePackVersion { get; }
        public int DataPackVersion { get; }

        public WorldVersion(int dataVersion, string id, string name, bool stable, int protocol = SharedConstants.PROTOCOL_VERSION)
        {
            DataVersion = dataVersion;
            Id = id;
            Name = name;
            IsStable = stable;
            ProtocolVersion = protocol;
            ResourcePackVersion = 55; // 26.3 pack format
            DataPackVersion = 80;
        }

        public static WorldVersion Simple(int dataVersion, string id) => new WorldVersion(dataVersion, id, id, true);
    }
}
