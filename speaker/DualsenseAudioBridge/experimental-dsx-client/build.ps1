$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $root "tools\tinycc\tcc\tcc.exe"
$source = Join-Path $PSScriptRoot "DSX_UDPClient_Test.c"
$output = Join-Path $PSScriptRoot "DSX_UDPClient_Test.exe"

& $compiler `
    "-m64" `
    "-Wl,-subsystem=windows" `
    "-o" $output `
    $source `
    "-lshell32"

if ($LASTEXITCODE -ne 0) {
    throw "TinyCC failed with exit code $LASTEXITCODE"
}

Get-Item -LiteralPath $output |
    Select-Object FullName, Length, LastWriteTime
