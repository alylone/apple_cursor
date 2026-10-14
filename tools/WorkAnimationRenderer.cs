using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;

// Only the foreground wheel is resampled. Pointer pixels are copied verbatim.
public sealed class WorkAnimationRenderer
{
    private readonly Color[,] source;
    private readonly int width;
    private readonly int height;
    private const int Samples = 4;

    public WorkAnimationRenderer(byte[] spinnerPng)
    {
        using (var stream = new MemoryStream(spinnerPng))
        using (var bitmap = new Bitmap(stream))
        {
            width = bitmap.Width;
            height = bitmap.Height;
            if (width != 256 || height != 256)
                throw new ArgumentException("The canonical wheel must be 256x256.");
            source = new Color[width, height];
            for (int y = 0; y < height; y++)
                for (int x = 0; x < width; x++)
                    source[x, y] = bitmap.GetPixel(x, y);
        }
    }

    private void Sample(double x, double y, out double r, out double g, out double b)
    {
        int x0 = (int)Math.Floor(x), y0 = (int)Math.Floor(y);
        double fx = x - x0, fy = y - y0;
        double alpha = 0;
        r = g = b = 0;
        for (int iy = 0; iy < 2; iy++)
        {
            for (int ix = 0; ix < 2; ix++)
            {
                Color c = source[Math.Max(0, Math.Min(width - 1, x0 + ix)),
                                 Math.Max(0, Math.Min(height - 1, y0 + iy))];
                double weight = (ix == 0 ? 1 - fx : fx) *
                                (iy == 0 ? 1 - fy : fy) * c.A;
                alpha += weight;
                r += c.R * weight;
                g += c.G * weight;
                b += c.B * weight;
            }
        }
        if (alpha <= 0)
            throw new InvalidOperationException("The wheel has an empty interior sample.");
        r /= alpha;
        g /= alpha;
        b /= alpha;
    }

    private static int Byte(double value)
    {
        return Math.Max(0, Math.Min(255, (int)Math.Round(value)));
    }

    public byte[] Render(byte[] pointerPng, int wheelX, int wheelY, int wheelSize,
                         double angleDegrees)
    {
        using (var input = new MemoryStream(pointerPng))
        using (var pointer = new Bitmap(input))
        using (var result = new Bitmap(pointer.Width, pointer.Height, PixelFormat.Format32bppArgb))
        {
            if (wheelX < 0 || wheelY < 0 || wheelX + wheelSize > pointer.Width ||
                wheelY + wheelSize > pointer.Height)
                throw new ArgumentException("The wheel extends outside the cursor canvas.");

            double centerX = wheelX + wheelSize / 2.0;
            double centerY = wheelY + wheelSize / 2.0;
            // Preserve the original wait artwork's visible diameter in its 256px canvas.
            double radius = wheelSize * 110.72 / 256.0;
            double angle = angleDegrees * Math.PI / 180.0;
            double cos = Math.Cos(angle), sin = Math.Sin(angle);
            for (int y = 0; y < pointer.Height; y++)
            {
                for (int x = 0; x < pointer.Width; x++)
                {
                    Color background = pointer.GetPixel(x, y);
                    if (x < wheelX || x >= wheelX + wheelSize ||
                        y < wheelY || y >= wheelY + wheelSize)
                    {
                        result.SetPixel(x, y, background);
                        continue;
                    }

                    int covered = 0;
                    double red = 0, green = 0, blue = 0;
                    for (int sy = 0; sy < Samples; sy++)
                    {
                        for (int sx = 0; sx < Samples; sx++)
                        {
                            double dx = x + (sx + 0.5) / Samples - centerX;
                            double dy = y + (sy + 0.5) / Samples - centerY;
                            if (dx * dx + dy * dy >= radius * radius) continue;
                            // Sample just inside the source boundary, avoiding transparent fringes.
                            double scale = 108.0 / radius;
                            double px = 127.57 + (cos * dx + sin * dy) * scale;
                            double py = 127.724 + (-sin * dx + cos * dy) * scale;
                            double r, g, b;
                            Sample(px, py, out r, out g, out b);
                            red += r; green += g; blue += b;
                            covered++;
                        }
                    }
                    if (covered == 0)
                    {
                        result.SetPixel(x, y, background);
                        continue;
                    }
                    if (background.A == 255)
                        throw new InvalidOperationException("The wheel overlaps the opaque pointer.");

                    // Coverage depends only on the circle, never on the rotated source alpha.
                    double foregroundAlpha = covered / (double)(Samples * Samples);
                    double backgroundAlpha = background.A / 255.0;
                    double outputAlpha = foregroundAlpha + backgroundAlpha * (1 - foregroundAlpha);
                    double backgroundWeight = backgroundAlpha * (1 - foregroundAlpha);
                    result.SetPixel(x, y, Color.FromArgb(Byte(outputAlpha * 255),
                        Byte((red / covered * foregroundAlpha + background.R * backgroundWeight) / outputAlpha),
                        Byte((green / covered * foregroundAlpha + background.G * backgroundWeight) / outputAlpha),
                        Byte((blue / covered * foregroundAlpha + background.B * backgroundWeight) / outputAlpha)));
                }
            }
            using (var output = new MemoryStream())
            {
                result.Save(output, ImageFormat.Png);
                return output.ToArray();
            }
        }
    }
}
