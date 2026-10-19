$ErrorActionPreference = "Stop"
$Project = Join-Path $PSScriptRoot "OrbitDrop.Native.csproj"
$Output = Join-Path $PSScriptRoot "build\win-x64"
dotnet publish $Project -c Release -r win-x64 --self-contained true -o $Output
Write-Output (Join-Path $Output "OrbitDrop.exe")
