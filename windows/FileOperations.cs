using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Media.Imaging;
using System.Windows.Media;
using System.Xml.Linq;
using Forms = System.Windows.Forms;

namespace OrbitDrop.Native;

internal static class FileOperations
{
    private static readonly HashSet<string> Images = new(StringComparer.OrdinalIgnoreCase) { ".png", ".jpg", ".jpeg", ".bmp", ".gif", ".tif", ".tiff", ".ico", ".heic" };

    internal static void Perform(
        OrbitAction action,
        IReadOnlyList<string> sources,
        Action<string, string, Forms.ToolTipIcon> notify,
        Action<bool, string> completed)
    {
        Task.Run(() => Execute(action, sources)).ContinueWith(task =>
        {
            System.Windows.Application.Current.Dispatcher.Invoke(() =>
            {
                if (task.IsFaulted)
                {
                    var message = task.Exception?.GetBaseException().Message ?? "The file operation failed.";
                    notify("OrbitDrop couldn’t finish", message, Forms.ToolTipIcon.Error);
                    completed(false, message);
                    return;
                }
                var outputs = task.Result;
                if (outputs.Count > 0) Reveal(outputs[0]);
                var successMessage = outputs.Count == 1 ? Path.GetFileName(outputs[0]) : $"Created {outputs.Count} files";
                notify("OrbitDrop finished", successMessage, Forms.ToolTipIcon.Info);
                completed(true, successMessage);
            });
        });
    }

    internal static IReadOnlyList<string> Execute(OrbitAction action, IReadOnlyList<string> sources)
    {
        if (sources.Count == 0) return Array.Empty<string>();
        if (action == OrbitAction.Zip && sources.Count > 1) return new[] { ZipTogether(sources) };
        return sources.Select(source => action switch
        {
            OrbitAction.Pdf => ConvertToPdf(source),
            OrbitAction.Png => ConvertImage(source, ImageFormat.Png, 100),
            OrbitAction.Jpg => ConvertImage(source, ImageFormat.Jpg, 86),
            OrbitAction.Tiff => ConvertImage(source, ImageFormat.Tiff, 100),
            OrbitAction.Bmp => ConvertImage(source, ImageFormat.Bmp, 100),
            OrbitAction.Zip => ZipSingle(source, ""),
            OrbitAction.Shrink => Images.Contains(Path.GetExtension(source)) ? CompressImage(source) : ZipSingle(source, " compressed"),
            OrbitAction.Resize => EditImage(source, ImageEdit.Resize),
            OrbitAction.Rotate => EditImage(source, ImageEdit.Rotate),
            OrbitAction.Flip => EditImage(source, ImageEdit.Flip),
            OrbitAction.Grayscale => EditImage(source, ImageEdit.Grayscale),
            OrbitAction.Copy => Copy(source),
            _ => throw new NotSupportedException()
        }).ToArray();
    }

    private static string ConvertToPdf(string source)
    {
        var output = UniquePath(Path.GetDirectoryName(source)!, Path.GetFileNameWithoutExtension(source), ".pdf");
        if (Images.Contains(Path.GetExtension(source)))
        {
            PdfWriter.WriteImage(source, output);
            return output;
        }
        if (Path.GetExtension(source).Equals(".docx", StringComparison.OrdinalIgnoreCase) && TryWordPdf(source, output)) return output;
        PdfWriter.WriteText(ExtractText(source), output);
        return output;
    }

    private static bool TryWordPdf(string source, string output)
    {
        object? word = null;
        object? document = null;
        try
        {
            var type = Type.GetTypeFromProgID("Word.Application");
            if (type is null) return false;
            word = Activator.CreateInstance(type);
            dynamic app = word!;
            app.Visible = false;
            document = app.Documents.Open(source, ReadOnly: true, Visible: false);
            ((dynamic)document).ExportAsFixedFormat(output, 17);
            ((dynamic)document).Close(false);
            document = null;
            app.Quit(false);
            word = null;
            return File.Exists(output);
        }
        catch { return false; }
        finally
        {
            if (document is not null && Marshal.IsComObject(document)) Marshal.FinalReleaseComObject(document);
            if (word is not null)
            {
                try { ((dynamic)word).Quit(false); } catch { }
                if (Marshal.IsComObject(word)) Marshal.FinalReleaseComObject(word);
            }
        }
    }

    private static string ExtractText(string source)
    {
        var extension = Path.GetExtension(source).ToLowerInvariant();
        if (extension == ".docx")
        {
            using var archive = ZipFile.OpenRead(source);
            var entry = archive.GetEntry("word/document.xml") ?? throw new InvalidDataException("The DOCX document is missing its contents.");
            using var stream = entry.Open();
            var xml = XDocument.Load(stream);
            XNamespace word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
            return string.Join(Environment.NewLine, xml.Descendants(word + "p").Select(paragraph => string.Concat(paragraph.Descendants(word + "t").Select(node => node.Value))));
        }

        var text = File.ReadAllText(source);
        if (extension is ".html" or ".htm") return WebUtility.HtmlDecode(Regex.Replace(text, "<[^>]+>", " "));
        if (extension == ".rtf")
        {
            text = Regex.Replace(text, @"\\'[0-9a-fA-F]{2}", "?");
            text = Regex.Replace(text, @"\\[a-zA-Z]+-?\d* ?", "");
            text = text.Replace("{", "").Replace("}", "");
        }
        return text;
    }

    private enum ImageFormat { Png, Jpg, Tiff, Bmp }
    private enum ImageEdit { Resize, Rotate, Flip, Grayscale }

    private static string ConvertImage(string source, ImageFormat format, int quality, string suffix = "")
    {
        using var input = File.OpenRead(source);
        var decoder = BitmapDecoder.Create(input, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        BitmapEncoder encoder = format switch
        {
            ImageFormat.Png => new PngBitmapEncoder(),
            ImageFormat.Tiff => new TiffBitmapEncoder { Compression = TiffCompressOption.Zip },
            ImageFormat.Bmp => new BmpBitmapEncoder(),
            _ => new JpegBitmapEncoder { QualityLevel = quality }
        };
        encoder.Frames.Add(decoder.Frames[0]);
        var extension = format switch
        {
            ImageFormat.Png => ".png",
            ImageFormat.Tiff => ".tiff",
            ImageFormat.Bmp => ".bmp",
            _ => ".jpg"
        };
        var output = UniquePath(Path.GetDirectoryName(source)!, Path.GetFileNameWithoutExtension(source) + suffix, extension);
        using var stream = File.Create(output);
        encoder.Save(stream);
        return output;
    }

    private static string CompressImage(string source)
    {
        using var input = File.OpenRead(source);
        var frame = BitmapDecoder.Create(input, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad).Frames[0];
        var originalBytes = new FileInfo(source).Length;
        var firstScale = Math.Min(1.0, 1920.0 / Math.Max(frame.PixelWidth, frame.PixelHeight));
        var targetBytes = Math.Max(18_000L, (long)(originalBytes * 0.55));
        var attempts = new (double Scale, int Quality)[]
        {
            (1.00, 58), (0.86, 52), (0.72, 46), (0.60, 40), (0.48, 36)
        };
        byte[]? best = null;

        foreach (var attempt in attempts)
        {
            var scale = firstScale * attempt.Scale;
            BitmapSource candidate = scale < 0.995
                ? new TransformedBitmap(frame, new ScaleTransform(scale, scale))
                : frame;
            var encoder = new JpegBitmapEncoder { QualityLevel = attempt.Quality };
            encoder.Frames.Add(BitmapFrame.Create(candidate));
            using var memory = new MemoryStream();
            encoder.Save(memory);
            best = memory.ToArray();
            if (best.LongLength <= targetBytes) break;
        }

        if (best is null) throw new InvalidDataException("The image could not be compressed.");
        var output = UniquePath(Path.GetDirectoryName(source)!, Path.GetFileNameWithoutExtension(source) + " compressed", ".jpg");
        File.WriteAllBytes(output, best);
        return output;
    }

    private static string EditImage(string source, ImageEdit edit)
    {
        using var input = File.OpenRead(source);
        var frame = BitmapDecoder.Create(input, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad).Frames[0];
        BitmapSource result = edit switch
        {
            ImageEdit.Resize => new TransformedBitmap(frame, new ScaleTransform(0.5, 0.5)),
            ImageEdit.Rotate => new TransformedBitmap(frame, new RotateTransform(90)),
            ImageEdit.Flip => new TransformedBitmap(frame, new ScaleTransform(-1, 1)),
            ImageEdit.Grayscale => new FormatConvertedBitmap(frame, PixelFormats.Gray8, null, 0),
            _ => frame
        };
        var suffix = edit switch
        {
            ImageEdit.Resize => " resized",
            ImageEdit.Rotate => " rotated",
            ImageEdit.Flip => " flipped",
            _ => " grayscale"
        };
        var output = UniquePath(Path.GetDirectoryName(source)!, Path.GetFileNameWithoutExtension(source) + suffix, ".png");
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(result));
        using var stream = File.Create(output);
        encoder.Save(stream);
        return output;
    }

    private static string ZipSingle(string source, string suffix)
    {
        var stem = Path.GetFileNameWithoutExtension(source) + suffix;
        var output = UniquePath(Path.GetDirectoryName(source)!, stem, ".zip");
        using var archive = ZipFile.Open(output, ZipArchiveMode.Create);
        AddToArchive(archive, source, Path.GetFileName(source));
        return output;
    }

    private static string ZipTogether(IReadOnlyList<string> sources)
    {
        var output = UniquePath(Path.GetDirectoryName(sources[0])!, "OrbitDrop Archive", ".zip");
        using var archive = ZipFile.Open(output, ZipArchiveMode.Create);
        foreach (var source in sources) AddToArchive(archive, source, Path.GetFileName(source));
        return output;
    }

    private static void AddToArchive(ZipArchive archive, string source, string entryRoot)
    {
        if (File.Exists(source))
        {
            archive.CreateEntryFromFile(source, entryRoot, CompressionLevel.SmallestSize);
            return;
        }
        foreach (var file in Directory.EnumerateFiles(source, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(source, file);
            archive.CreateEntryFromFile(file, Path.Combine(entryRoot, relative).Replace('\\', '/'), CompressionLevel.SmallestSize);
        }
    }

    private static string Copy(string source)
    {
        var output = UniquePath(Path.GetDirectoryName(source)!, Path.GetFileNameWithoutExtension(source) + " copy", Path.GetExtension(source));
        if (File.Exists(source)) File.Copy(source, output);
        else CopyDirectory(source, output);
        return output;
    }

    private static void CopyDirectory(string source, string destination)
    {
        Directory.CreateDirectory(destination);
        foreach (var directory in Directory.EnumerateDirectories(source, "*", SearchOption.AllDirectories))
            Directory.CreateDirectory(Path.Combine(destination, Path.GetRelativePath(source, directory)));
        foreach (var file in Directory.EnumerateFiles(source, "*", SearchOption.AllDirectories))
            File.Copy(file, Path.Combine(destination, Path.GetRelativePath(source, file)));
    }

    private static string UniquePath(string directory, string stem, string extension)
    {
        var candidate = Path.Combine(directory, stem + extension);
        var counter = 2;
        while (File.Exists(candidate) || Directory.Exists(candidate)) candidate = Path.Combine(directory, $"{stem} {counter++}{extension}");
        return candidate;
    }

    private static void Reveal(string path)
    {
        Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });
    }
}

internal static class PdfWriter
{
    internal static void WriteText(string text, string output)
    {
        var lines = Wrap(text, 82).ToList();
        if (lines.Count == 0) lines.Add("");
        var pages = lines.Chunk(49).ToList();
        var fontId = 3 + pages.Count * 2;
        var objects = new List<byte[]>();
        objects.Add(Ascii("<< /Type /Catalog /Pages 2 0 R >>"));
        var kids = string.Join(" ", Enumerable.Range(0, pages.Count).Select(index => $"{3 + index * 2} 0 R"));
        objects.Add(Ascii($"<< /Type /Pages /Kids [{kids}] /Count {pages.Count} >>"));
        for (var index = 0; index < pages.Count; index++)
        {
            var pageId = 3 + index * 2;
            var contentId = pageId + 1;
            objects.Add(Ascii($"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 {fontId} 0 R >> >> /Contents {contentId} 0 R >>"));
            var commands = new StringBuilder("BT /F1 11 Tf 48 744 Td 14 TL\n");
            foreach (var line in pages[index]) commands.Append('(').Append(Escape(line)).Append(") Tj T*\n");
            commands.Append("ET");
            var content = Ascii(commands.ToString());
            objects.Add(StreamObject($"<< /Length {content.Length} >>", content));
        }
        objects.Add(Ascii("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"));
        WriteObjects(objects, output);
    }

    internal static void WriteImage(string source, string output)
    {
        byte[] jpeg;
        int width;
        int height;
        using (var input = File.OpenRead(source))
        {
            var frame = BitmapDecoder.Create(input, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad).Frames[0];
            width = frame.PixelWidth;
            height = frame.PixelHeight;
            var encoder = new JpegBitmapEncoder { QualityLevel = 92 };
            encoder.Frames.Add(frame);
            using var memory = new MemoryStream();
            encoder.Save(memory);
            jpeg = memory.ToArray();
        }

        var scale = Math.Min(540.0 / width, 720.0 / height);
        scale = Math.Min(scale, 1);
        var drawWidth = width * scale;
        var drawHeight = height * scale;
        var x = (612 - drawWidth) / 2;
        var y = (792 - drawHeight) / 2;
        var commands = Ascii($"q {drawWidth:0.###} 0 0 {drawHeight:0.###} {x:0.###} {y:0.###} cm /Im0 Do Q");
        var objects = new List<byte[]>
        {
            Ascii("<< /Type /Catalog /Pages 2 0 R >>"),
            Ascii("<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
            Ascii("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>"),
            StreamObject($"<< /Type /XObject /Subtype /Image /Width {width} /Height {height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length {jpeg.Length} >>", jpeg),
            StreamObject($"<< /Length {commands.Length} >>", commands)
        };
        WriteObjects(objects, output);
    }

    private static IEnumerable<string> Wrap(string text, int width)
    {
        foreach (var raw in text.Replace("\r", "").Split('\n'))
        {
            var remaining = raw.TrimEnd();
            if (remaining.Length == 0) { yield return ""; continue; }
            while (remaining.Length > width)
            {
                var split = remaining.LastIndexOf(' ', width);
                if (split < width / 2) split = width;
                yield return remaining[..split];
                remaining = remaining[split..].TrimStart();
            }
            yield return remaining;
        }
    }

    private static string Escape(string value)
    {
        var ascii = new string(value.Select(character => character is >= ' ' and <= '~' ? character : '?').ToArray());
        return ascii.Replace("\\", "\\\\").Replace("(", "\\(").Replace(")", "\\)");
    }

    private static byte[] StreamObject(string dictionary, byte[] content)
    {
        using var memory = new MemoryStream();
        memory.Write(Ascii(dictionary + "\nstream\n"));
        memory.Write(content);
        memory.Write(Ascii("\nendstream"));
        return memory.ToArray();
    }

    private static void WriteObjects(IReadOnlyList<byte[]> objects, string output)
    {
        using var stream = File.Create(output);
        stream.Write(Ascii("%PDF-1.4\n%ORBT\n"));
        var offsets = new List<long> { 0 };
        for (var index = 0; index < objects.Count; index++)
        {
            offsets.Add(stream.Position);
            stream.Write(Ascii($"{index + 1} 0 obj\n"));
            stream.Write(objects[index]);
            stream.Write(Ascii("\nendobj\n"));
        }
        var xref = stream.Position;
        stream.Write(Ascii($"xref\n0 {objects.Count + 1}\n0000000000 65535 f \n"));
        for (var index = 1; index < offsets.Count; index++) stream.Write(Ascii($"{offsets[index]:0000000000} 00000 n \n"));
        stream.Write(Ascii($"trailer\n<< /Size {objects.Count + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n"));
    }

    private static byte[] Ascii(string value) => Encoding.ASCII.GetBytes(value);
}
