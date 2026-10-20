using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;

namespace OrbitDrop.Native;

internal sealed class UpdateChecker : IDisposable
{
    private const string LatestReleaseUrl = "https://api.github.com/repos/sasukefrontenddev/orbitdrop/releases/latest";
    private readonly Dispatcher _dispatcher;
    private readonly HttpClient _client = new() { Timeout = TimeSpan.FromMinutes(3) };
    private readonly SemaphoreSlim _gate = new(1, 1);
    private Timer? _timer;
    private string? _displayedVersion;

    internal UpdateChecker(Dispatcher dispatcher)
    {
        _dispatcher = dispatcher;
        _client.DefaultRequestHeaders.UserAgent.ParseAdd($"OrbitDrop/{CurrentVersion}");
        _client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
    }

    internal void Start()
    {
        _timer = new Timer(async _ => await CheckAsync(false), null, TimeSpan.FromSeconds(4), TimeSpan.FromHours(6));
    }

    internal void Check(bool showCurrent) => _ = CheckAsync(showCurrent);

    private async Task CheckAsync(bool showCurrent)
    {
        if (!await _gate.WaitAsync(0)) return;
        try
        {
            using var response = await _client.GetAsync(LatestReleaseUrl);
            if (!response.IsSuccessStatusCode) return;
            await using var stream = await response.Content.ReadAsStreamAsync();
            using var document = await JsonDocument.ParseAsync(stream);
            var root = document.RootElement;
            var latestText = root.GetProperty("tag_name").GetString()?.TrimStart('v', 'V');
            if (!Version.TryParse(latestText, out var latest)) return;
            var installed = CurrentVersion;

            if (latest <= installed)
            {
                if (showCurrent)
                    _dispatcher.Invoke(() => MessageBox.Show($"OrbitDrop {installed.ToString(3)} is the newest version.", "OrbitDrop updates", MessageBoxButton.OK, MessageBoxImage.Information));
                return;
            }
            if (_displayedVersion == latest.ToString()) return;
            _displayedVersion = latest.ToString();

            ReleaseAsset? executable = null;
            ReleaseAsset? checksums = null;
            foreach (var asset in root.GetProperty("assets").EnumerateArray())
            {
                var name = asset.GetProperty("name").GetString();
                var url = asset.TryGetProperty("browser_download_url", out var download) ? download.GetString() : null;
                if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(url)) continue;
                if (name.EndsWith("Windows-x64.exe", StringComparison.OrdinalIgnoreCase)) executable = new(name, url);
                if (name.Equals("SHA256SUMS.txt", StringComparison.Ordinal)) checksums = new(name, url);
            }
            if (executable is null || checksums is null) throw new InvalidDataException("This release is missing its Windows app or checksum file.");

            var accepted = _dispatcher.Invoke(() => MessageBox.Show(
                $"OrbitDrop {latest.ToString(3)} is available. You have version {installed.ToString(3)}.\n\nInstall it now? OrbitDrop will securely replace this copy and reopen automatically. No extra download will be left behind.",
                "OrbitDrop update available",
                MessageBoxButton.YesNo,
                MessageBoxImage.Information) == MessageBoxResult.Yes);
            if (!accepted) return;

            await DownloadAndInstallAsync(executable, checksums, latest);
        }
        catch (Exception error)
        {
            if (showCurrent || _displayedVersion is not null)
            {
                _dispatcher.Invoke(() => MessageBox.Show(
                    $"OrbitDrop could not install the update. Your current app has not been changed.\n\n{error.Message}",
                    "OrbitDrop update",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error));
            }
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task DownloadAndInstallAsync(ReleaseAsset executable, ReleaseAsset checksums, Version latest)
    {
        var manifest = await _client.GetStringAsync(checksums.Url);
        var expected = ChecksumFor(executable.Name, manifest)
            ?? throw new InvalidDataException("The release checksum could not be read.");
        var work = Path.Combine(Path.GetTempPath(), $"OrbitDrop-Update-{Guid.NewGuid():N}");
        Directory.CreateDirectory(work);
        try
        {
            var staged = Path.Combine(work, executable.Name);
            await using (var source = await _client.GetStreamAsync(executable.Url))
            await using (var destination = new FileStream(staged, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, true))
                await source.CopyToAsync(destination);

            var actual = await Sha256Async(staged);
            if (!actual.Equals(expected, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("The downloaded update did not pass its security check.");

            var fileVersionText = FileVersionInfo.GetVersionInfo(staged).FileVersion;
            if (!Version.TryParse(fileVersionText, out var fileVersion) || fileVersion.Major != latest.Major || fileVersion.Minor != latest.Minor || fileVersion.Build != latest.Build)
                throw new InvalidDataException("The downloaded app version does not match the release.");

            var target = Environment.ProcessPath ?? throw new InvalidOperationException("OrbitDrop could not locate its installed app.");
            var updater = Path.Combine(work, "Install-OrbitDropUpdate.ps1");
            var backup = target + $".orbitdrop-backup-{Guid.NewGuid():N}";
            await File.WriteAllTextAsync(updater, UpdaterScript, new UTF8Encoding(false));

            var startInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File {QuoteArgument(updater)} -ProcessId {Environment.ProcessId} -Source {QuoteArgument(staged)} -Target {QuoteArgument(target)} -Backup {QuoteArgument(backup)} -WorkDir {QuoteArgument(work)}",
                UseShellExecute = !CanWriteTo(Path.GetDirectoryName(target)!),
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            if (startInfo.UseShellExecute) startInfo.Verb = "runas";
            Process.Start(startInfo) ?? throw new InvalidOperationException("OrbitDrop could not start the updater.");
            _dispatcher.BeginInvoke(() => Application.Current.Shutdown());
        }
        catch
        {
            try { Directory.Delete(work, true); } catch { }
            throw;
        }
    }

    private static string? ChecksumFor(string fileName, string manifest)
    {
        foreach (var line in manifest.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
        {
            var split = line.IndexOfAny(new[] { ' ', '\t' });
            if (split <= 0) continue;
            var hash = line[..split];
            var listedName = line[(split + 1)..].TrimStart(' ', '\t', '*');
            if (hash.Length == 64 && listedName.Equals(fileName, StringComparison.Ordinal)) return hash;
        }
        return null;
    }

    private static async Task<string> Sha256Async(string path)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 81920, true);
        var hash = await SHA256.HashDataAsync(stream);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    private static bool CanWriteTo(string directory)
    {
        var probe = Path.Combine(directory, $".orbitdrop-write-test-{Guid.NewGuid():N}");
        try
        {
            File.WriteAllText(probe, string.Empty);
            File.Delete(probe);
            return true;
        }
        catch { return false; }
    }

    private static string QuoteArgument(string value) => "\"" + value.Replace("\"", "\\\"") + "\"";

    private const string UpdaterScript = """
param(
  [Parameter(Mandatory=$true)][int]$ProcessId,
  [Parameter(Mandatory=$true)][string]$Source,
  [Parameter(Mandatory=$true)][string]$Target,
  [Parameter(Mandatory=$true)][string]$Backup,
  [Parameter(Mandatory=$true)][string]$WorkDir
)
$ErrorActionPreference = 'Stop'
try { Wait-Process -Id $ProcessId -ErrorAction SilentlyContinue } catch {}
$installed = $false
try {
  Copy-Item -LiteralPath $Target -Destination $Backup -Force
  Move-Item -LiteralPath $Source -Destination $Target -Force
  $installed = $true
} catch {
  if (Test-Path -LiteralPath $Backup) { Copy-Item -LiteralPath $Backup -Destination $Target -Force }
}
if (Test-Path -LiteralPath $Target) { Start-Process -FilePath $Target }
if ($installed -and (Test-Path -LiteralPath $Backup)) { Remove-Item -LiteralPath $Backup -Force }
$cleanup = 'ping 127.0.0.1 -n 3 > nul & rmdir /s /q "' + $WorkDir + '"'
Start-Process -WindowStyle Hidden -FilePath $env:ComSpec -ArgumentList '/d','/c',$cleanup
""";

    private sealed record ReleaseAsset(string Name, string Url);

    private static Version CurrentVersion => Assembly.GetExecutingAssembly().GetName().Version ?? new Version(0, 0, 0);

    public void Dispose()
    {
        _timer?.Dispose();
        _client.Dispose();
        _gate.Dispose();
    }
}
