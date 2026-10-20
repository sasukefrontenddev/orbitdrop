using System;
using System.Diagnostics;
using System.Net.Http;
using System.Reflection;
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
    private readonly HttpClient _client = new() { Timeout = TimeSpan.FromSeconds(12) };
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
                    _dispatcher.Invoke(() => MessageBox.Show($"OrbitDrop {installed} is the newest version.", "OrbitDrop updates", MessageBoxButton.OK, MessageBoxImage.Information));
                return;
            }
            if (_displayedVersion == latest.ToString()) return;
            _displayedVersion = latest.ToString();

            var releaseUrl = root.GetProperty("html_url").GetString() ?? "https://github.com/sasukefrontenddev/orbitdrop/releases/latest";
            var downloadUrl = releaseUrl;
            foreach (var asset in root.GetProperty("assets").EnumerateArray())
            {
                if (asset.GetProperty("name").GetString()?.Contains("Windows-x64.exe", StringComparison.OrdinalIgnoreCase) != true) continue;
                if (asset.TryGetProperty("browser_download_url", out var downloadProperty))
                    downloadUrl = downloadProperty.GetString() ?? releaseUrl;
                break;
            }

            _dispatcher.Invoke(() =>
            {
                var result = MessageBox.Show(
                    $"OrbitDrop {latest} is available. You have version {installed}.\n\nDownload the update from the official OrbitDrop repository?",
                    "OrbitDrop update available",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Information);
                if (result == MessageBoxResult.Yes)
                    Process.Start(new ProcessStartInfo(downloadUrl) { UseShellExecute = true });
            });
        }
        catch
        {
            // Update checks are best-effort and never interrupt file operations.
        }
        finally
        {
            _gate.Release();
        }
    }

    private static Version CurrentVersion => Assembly.GetExecutingAssembly().GetName().Version ?? new Version(0, 0, 0);

    public void Dispose()
    {
        _timer?.Dispose();
        _client.Dispose();
        _gate.Dispose();
    }
}
