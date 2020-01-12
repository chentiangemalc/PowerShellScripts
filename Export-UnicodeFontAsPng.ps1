$code = @'
using System;
using System.Drawing;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace FontRoutines
{
    public static class NativeMethods
    {
        [DllImport("gdi32.dll")]
        public static extern uint GetFontUnicodeRanges(IntPtr hdc, IntPtr lpgs);

        [DllImport("gdi32.dll")]
        public extern static IntPtr SelectObject(IntPtr hDC, IntPtr hObject);

        public struct FontRange
        {
            public UInt16 Low;
            public UInt16 High;
        }

        public static List<FontRange> GetFontUnicodeRanges(Font font)
        {
            Graphics g = Graphics.FromHwnd(IntPtr.Zero);
            IntPtr hdc = g.GetHdc();
            IntPtr hFont = font.ToHfont();
            IntPtr old = SelectObject(hdc, hFont);
            uint size = GetFontUnicodeRanges(hdc, IntPtr.Zero);
            IntPtr glyphSet = Marshal.AllocHGlobal((int)size);
            GetFontUnicodeRanges(hdc, glyphSet);
            List<FontRange> fontRanges = new List<FontRange>();
            int count = Marshal.ReadInt32(glyphSet, 12);
            for (int i = 0; i < count; i++)
            {
                FontRange range = new FontRange();
                range.Low = (UInt16)Marshal.ReadInt16(glyphSet, 16 + i * 4);
                range.High = (UInt16)(range.Low + Marshal.ReadInt16(glyphSet, 18 + i * 4) - 1);
                fontRanges.Add(range);
            }
            SelectObject(hdc, old);
            Marshal.FreeHGlobal(glyphSet);
            g.ReleaseHdc(hdc);
            g.Dispose();
            return fontRanges;
        }
    }
}
'@


Add-Type -TypeDefinition $code -ReferencedAssemblies @("System.Windows.Forms","System.Drawing")
 
$fontDialog = New-Object System.Windows.Forms.FontDialog

if ($fontDialog.ShowDialog() -eq ([System.Windows.Forms.DialogResult]::OK))
{
    # currently outputs to C:\BitmapFonts\fontname folder
    $outputFolder = [System.IO.Path]::Combine(`
        "C:\",`
        "BitmapFonts",`
        "$($fontDialog.Font.Name) $($fontDialog.Font.Size)pt $($fontDialog.Font.Style)")

    if (!(Test-Path $outputFolder))
    {
        New-Item -Path $outputFolder -ItemType Directory 
    }

    # retrieve unicode range for font
    $unicodeRange = [FontRoutines.NativeMethods]::GetFontUnicodeRanges($fontDialog.Font)

    # string formatting
    $stringFormat = New-Object System.Drawing.StringFormat
    $stringFormat.Alignment = [System.Drawing.StringAlignment]::Center
    $stringFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
            
    $totalRange = 0
    ForEach ($range in $unicodeRange)
    {
        $totalRange += ($range.High - $range.Low)+1
    }

    $current = 0
    ForEach ($range in $unicodeRange)
    {
        for ($c = $range.Low; $c -le $range.High; $c++)
        {
            $current++
            Write-Progress "Generating bitmap" -Status "Unicode character $c" -PercentComplete (($current*100)/$totalRange)
            $string = [char]$c
            $bmp = New-Object System.Drawing.Bitmap(1,1)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $size = $g.MeasureString($string, $fontDialog.Font)
            $bmp = New-Object System.Drawing.Bitmap([int]$size.Width,[int]$size.Height)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            
            $rectF = New-Object System.Drawing.RectangleF(0, 0, $bmp.Width, $bmp.Height)

            # ------------------------------------------
            # Ensure the best possible quality rendering
            # ------------------------------------------
            # The smoothing mode specifies whether lines, curves, and the edges of filled areas use smoothing (also called antialiasing). 
            # One exception is that path gradient brushes do not obey the smoothing mode. 
            # Areas filled using a PathGradientBrush are rendered the same way (aliased) regardless of the SmoothingMode property.
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

            # The interpolation mode determines how intermediate values between two endpoints are calculated.
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

            # Use this property to specify either higher quality, slower rendering, or lower quality, faster rendering of the contents of this Graphics object.
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

            # Each character is drawn using its antialiased glyph bitmap with hinting. Much better quality due to antialiasing, but at a higher performance cost
            $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

            # Draw the text onto the image
            $g.DrawString($string, $fontDialog.Font, [System.Drawing.Brushes]::Black, $rectF, $stringFormat);

            # Flush all graphics changes to the bitmap
            $g.Flush()

            # Now save or use the bitmap
            $bmp.Save([System.IO.Path]::Combine($outputFolder,"$c.png"))
        }
    }
    
}