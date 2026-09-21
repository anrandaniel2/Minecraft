using System;
using Godot;

namespace Minecraft.Util.Math
{
    /// <summary>
    /// Translation of net.minecraft.util.Mth - Minecraft's math utility class
    /// Used everywhere: worldgen, entity movement, rendering.
    /// Contains fast sin/cos LUT, lerp, clamp, etc.
    /// </summary>
    public static class Mth
    {
        public const float PI = MathF.PI;
        public const float PI2 = MathF.PI * 2f;
        public const float PIO2 = MathF.PI * 0.5f;
        public const float DEG_TO_RAD = PI / 180f;
        public const float RAD_TO_DEG = 180f / PI;
        public const float SQRT_OF_TWO = 1.4142135f;
        public const float EPSILON = 1.0E-5f;

        // Fast sin table - original Mth uses 65536 entries
        private const int SIN_BITS = 12;
        private const int SIN_MASK = 4095;
        private const int SIN_SIZE = SIN_MASK + 1;
        private const float RAD_TO_INDEX = SIN_SIZE / PI2;
        private static readonly float[] SinTable = new float[SIN_SIZE];

        static Mth()
        {
            for (int i = 0; i < SIN_SIZE; i++)
            {
                SinTable[i] = MathF.Sin((i + 0.5f) / SIN_SIZE * PI2);
            }
            // Correct cardinal directions like original
            for (int i = 0; i < 360; i += 90)
            {
                int idx = (int)(i * SIN_SIZE / 360f) & SIN_MASK;
                SinTable[idx] = MathF.Sin(i * DEG_TO_RAD);
            }
        }

        public static float Sin(float f) => SinTable[(int)(f * RAD_TO_INDEX) & SIN_MASK];
        public static float Cos(float f) => SinTable[(int)((f + PIO2) * RAD_TO_INDEX) & SIN_MASK];

        public static float Sqrt(float f) => MathF.Sqrt(f);
        public static int Floor(float f) => (int)MathF.Floor(f);
        public static int Floor(double d) => (int)System.Math.Floor(d);
        public static int Ceil(float f) => (int)MathF.Ceiling(f);
        public static long Lfloor(double d) => (long)System.Math.Floor(d);

        public static float Clamp(float v, float min, float max) => v < min ? min : v > max ? max : v;
        public static int Clamp(int v, int min, int max) => v < min ? min : v > max ? max : v;
        public static double Clamp(double v, double min, double max) => v < min ? min : v > max ? max : v;

        public static float Lerp(float delta, float start, float end) => start + delta * (end - start);
        public static double Lerp(double delta, double start, double end) => start + delta * (end - start);
        public static float Lerp2(float dx, float dy, float x0, float x1, float y0, float y1) => Lerp(dy, Lerp(dx, x0, x1), Lerp(dx, y0, y1));
        public static float Lerp3(float dx, float dy, float dz, float x0, float x1, float y0, float y1, float z0, float z1, float z2, float z3) => Lerp(dz, Lerp2(dx, dy, x0, x1, y0, y1), Lerp2(dx, dy, z0, z1, z2, z3));

        public static float InverseLerp(float v, float min, float max) => (v - min) / (max - min);
        public static double InverseLerp(double v, double min, double max) => (v - min) / (max - min);

        public static float WrapDegrees(float f)
        {
            f %= 360f;
            if (f >= 180f) f -= 360f;
            if (f < -180f) f += 360f;
            return f;
        }

        public static float DegreesDifference(float a, float b) => WrapDegrees(b - a);
        public static float Approach(float current, float target, float step) => step > 0 ? MathF.Min(current + step, target) : MathF.Max(current + step, target);
        public static float ApproachDegrees(float current, float target, float step)
        {
            float diff = DegreesDifference(current, target);
            return Approach(current, current + diff, step);
        }

        public static int PositiveModulo(int x, int m) => (x % m + m) % m;
        public static float PositiveModulo(float x, float m) => (x % m + m) % m;

        public static int FastFloor(double d) => (int)(d + 1024.0) - 1024;

        public static int BinarySearch(int min, int max, Func<int, bool> predicate)
        {
            int i = max - min;
            while (i > 0)
            {
                int j = i / 2;
                int k = min + j;
                if (predicate(k))
                {
                    i = j;
                }
                else
                {
                    min = k + 1;
                    i -= j + 1;
                }
            }
            return min;
        }

        public static float RotLerp(float delta, float start, float end) => start + delta * WrapDegrees(end - start);

        // Godot interop
        public static Vector3 Clamp(Vector3 v, Vector3 min, Vector3 max) => new Vector3(Clamp(v.X, min.X, max.X), Clamp(v.Y, min.Y, max.Y), Clamp(v.Z, min.Z, max.Z));
        public static int FloorDiv(int a, int b) => (int)System.Math.Floor((double)a / b);
        public static int PosFloorMod(int x, int y) => ((x % y) + y) % y;
    }
}
