using System;
using System.Collections.Generic;
using System.IO;
using Godot;

namespace Minecraft.Util.Nbt
{
    /// <summary>
    /// Translation of net.minecraft.nbt - NBT tag system for saving worlds, entities, etc.
    /// Original has 12 tag types, CompoundTag, ListTag, etc.
    /// </summary>
    public enum TagType : byte { End=0, Byte=1, Short=2, Int=3, Long=4, Float=5, Double=6, ByteArray=7, String=8, List=9, Compound=10, IntArray=11, LongArray=12 }

    public abstract class Tag
    {
        public abstract TagType Type { get; }
        public abstract void Write(BinaryWriter writer);
        public abstract void Read(BinaryReader reader);
    }

    public class ByteTag : Tag
    {
        public override TagType Type => TagType.Byte;
        public sbyte Value;
        public ByteTag(sbyte v=0) => Value=v;
        public override void Write(BinaryWriter w) => w.Write(Value);
        public override void Read(BinaryReader r) => Value = r.ReadSByte();
    }

    public class IntTag : Tag
    {
        public override TagType Type => TagType.Int;
        public int Value;
        public IntTag(int v=0) => Value=v;
        public override void Write(BinaryWriter w) => w.Write(Value);
        public override void Read(BinaryReader r) => Value = r.ReadInt32();
    }

    public class StringTag : Tag
    {
        public override TagType Type => TagType.String;
        public string Value;
        public StringTag(string v="") => Value=v;
        public override void Write(BinaryWriter w) { w.Write((short)Value.Length); w.Write(System.Text.Encoding.UTF8.GetBytes(Value)); }
        public override void Read(BinaryReader r) { short len=r.ReadInt16(); Value=System.Text.Encoding.UTF8.GetString(r.ReadBytes(len)); }
    }

    public class CompoundTag : Tag
    {
        public override TagType Type => TagType.Compound;
        private Dictionary<string, Tag> _tags = new Dictionary<string, Tag>();

        public void Put(string key, Tag tag) => _tags[key]=tag;
        public void PutByte(string key, sbyte v) => Put(key, new ByteTag(v));
        public void PutInt(string key, int v) => Put(key, new IntTag(v));
        public void PutString(string key, string v) => Put(key, new StringTag(v));
        public Tag Get(string key) => _tags.TryGetValue(key, out var t) ? t : null;
        public bool Contains(string key) => _tags.ContainsKey(key);
        public int GetInt(string key) => Get(key) is IntTag it ? it.Value : 0;
        public string GetString(string key) => Get(key) is StringTag st ? st.Value : "";

        public override void Write(BinaryWriter w)
        {
            foreach (var kvp in _tags)
            {
                w.Write((byte)kvp.Value.Type);
                w.Write((short)kvp.Key.Length);
                w.Write(System.Text.Encoding.UTF8.GetBytes(kvp.Key));
                kvp.Value.Write(w);
            }
            w.Write((byte)TagType.End);
        }

        public override void Read(BinaryReader r)
        {
            _tags.Clear();
            while (true)
            {
                TagType type = (TagType)r.ReadByte();
                if (type == TagType.End) break;
                short len = r.ReadInt16();
                string key = System.Text.Encoding.UTF8.GetString(r.ReadBytes(len));
                Tag tag = CreateTag(type);
                tag.Read(r);
                _tags[key]=tag;
            }
        }

        private static Tag CreateTag(TagType type) => type switch
        {
            TagType.Byte => new ByteTag(),
            TagType.Int => new IntTag(),
            TagType.String => new StringTag(),
            TagType.Compound => new CompoundTag(),
            _ => new ByteTag()
        };

        public byte[] ToBytes()
        {
            using var ms = new MemoryStream();
            using var bw = new BinaryWriter(ms);
            Write(bw);
            return ms.ToArray();
        }

        public static CompoundTag FromBytes(byte[] data)
        {
            using var ms = new MemoryStream(data);
            using var br = new BinaryReader(ms);
            var tag = new CompoundTag();
            tag.Read(br);
            return tag;
        }
    }

    public static class NbtIo
    {
        public static void Write(CompoundTag tag, string path)
        {
            var bytes = tag.ToBytes();
            File.WriteAllBytes(path, bytes);
        }

        public static CompoundTag Read(string path)
        {
            if (!File.Exists(path)) return new CompoundTag();
            var bytes = File.ReadAllBytes(path);
            return CompoundTag.FromBytes(bytes);
        }
    }
}
