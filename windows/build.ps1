param(
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"
$Project = Join-Path $PSScriptRoot "OrbitDrop.Native.csproj"
$Output = Join-Path $PSScriptRoot "build\win-x64"
$VersionArgs = @()
if ($Version) {
    $VersionArgs = @("-p:Version=$Version", "-p:AssemblyVersion=$Version.0", "-p:FileVersion=$Version.0")
}
dotnet publish $Project -c Release -r win-x64 --self-contained true -o $Output @VersionArgs
Write-Output (Join-Path $Output "OrbitDrop.exe")
