using System;
using System.Drawing;
using System.IO;
using System.Security.Cryptography;

// Independent pixel checks shared by the Windows package validator.
public sealed class CursorPixelInspector
{
    private readonly int size, wheelX, wheelY, wheelSize;
    private readonly int[] pointer;
    private readonly string[] frames = new string[60];
    private string alphaHash;
    public int FrameCount { get; private set; }
    public int UniqueFrames { get; private set; }
    public int MinimumColorPixels { get; private set; }
    public int MinimumX { get; private set; }
    public int MaximumX { get; private set; }
    public int MinimumY { get; private set; }
    public int MaximumY { get; private set; }

    public CursorPixelInspector(int canvasSize, int x, int y, int diameter, byte[] pointerPng)
    {
        size = canvasSize; wheelX = x; wheelY = y; wheelSize = diameter;
        MinimumColorPixels = int.MaxValue;
        MinimumX = MinimumY = size; MaximumX = MaximumY = -1;
        if (pointerPng != null)
        {
            pointer = new int[size * size];
            using (var stream = new MemoryStream(pointerPng))
            using (var bitmap = new Bitmap(stream))
            {
                if (bitmap.Width != size || bitmap.Height != size)
                    throw new ArgumentException("Reference pointer dimensions changed.");
                for (int py = 0; py < size; py++)
                    for (int px = 0; px < size; px++)
                        pointer[py * size + px] = bitmap.GetPixel(px, py).ToArgb();
            }
        }
    }

    private static string Hash(byte[] data)
    {
        using (var sha = SHA256.Create())
            return BitConverter.ToString(sha.ComputeHash(data)).Replace("-", "");
    }

    public void Inspect(byte[] png)
    {
        var alpha = new byte[size * size];
        int colorPixels = 0;
        using (var stream = new MemoryStream(png))
        using (var bitmap = new Bitmap(stream))
        {
            if (bitmap.Width != size || bitmap.Height != size)
                throw new InvalidOperationException("PNG dimensions differ from the cursor resource.");
            for (int y = 0; y < size; y++)
            {
                for (int x = 0; x < size; x++)
                {
                    Color c = bitmap.GetPixel(x, y);
                    bool inside = x >= wheelX && x < wheelX + wheelSize &&
                                  y >= wheelY && y < wheelY + wheelSize;
                    int index = y * size + x;
                    if (pointer != null)
                    {
                        Color reference = Color.FromArgb(pointer[index]);
                        if ((!inside || reference.A == 255) && c.ToArgb() != pointer[index])
                            throw new InvalidOperationException("Work changed a pointer pixel at " + size + "px (" + x + "," + y + ").");
                    }
                    else if (!inside && c.A != 0)
                        throw new InvalidOperationException("Busy extends outside its artwork bounds.");
                    alpha[index] = c.A;
                    int max = Math.Max(c.R, Math.Max(c.G, c.B));
                    int min = Math.Min(c.R, Math.Min(c.G, c.B));
                    if (c.A > 32 && max - min > 45)
                    {
                        if (!inside) throw new InvalidOperationException("Color wheel extends outside its fixed bounds.");
                        colorPixels++;
                        MinimumX = Math.Min(MinimumX, x); MaximumX = Math.Max(MaximumX, x);
                        MinimumY = Math.Min(MinimumY, y); MaximumY = Math.Max(MaximumY, y);
                    }
                }
            }
        }
        string hash = Hash(alpha);
        if (alphaHash != null && hash != alphaHash)
            throw new InvalidOperationException("The animation alpha boundary changes between frames at " + size + "px.");
        alphaHash = hash;
        string frameHash = Hash(png);
        if (Array.IndexOf(frames, frameHash) < 0)
        {
            if (UniqueFrames == frames.Length)
                throw new InvalidOperationException("More than 60 unique frames were provided.");
            frames[UniqueFrames++] = frameHash;
        }
        MinimumColorPixels = Math.Min(MinimumColorPixels, colorPixels);
        FrameCount++;
    }
}
