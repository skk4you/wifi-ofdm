param(
    [string]$MeldPath = 'C:\Users\skk4y\AppData\Local\Programs\Meld\meld.exe',
    [string]$GitPath = 'C:\Program Files\Git\cmd\git.exe'
)

# Run once in PowerShell, e.g.:
# .\setup_meld.ps1
# Configures Git's graphical diff viewer; git diff remains a text diff.
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $GitPath -PathType Leaf)) {
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCommand) { throw 'Git was not found. Supply -GitPath.' }
    $GitPath = $gitCommand.Source
}
if (-not $MeldPath) {
    $meldCommand = Get-Command meld,Meld.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($meldCommand) { $MeldPath = $meldCommand.Source }
    foreach ($candidate in @('C:\Program Files\Meld\Meld.exe','C:\Program Files (x86)\Meld\Meld.exe')) {
        if (-not $MeldPath -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $MeldPath = $candidate
        }
    }
}
if (-not $MeldPath -or -not (Test-Path -LiteralPath $MeldPath -PathType Leaf)) {
    throw 'Meld was not found. Install Meld, then supply its executable with -MeldPath.'
}
$MeldPath = (Resolve-Path -LiteralPath $MeldPath).Path.Replace('\','/')
$settings = @(
    @('diff.tool','meld'),
    @('difftool.meld.path',$MeldPath),
    @('difftool.prompt','false'),
    @('alias.meld','difftool --tool=meld --no-prompt')
)
foreach ($setting in $settings) {
    & $GitPath config --global $setting[0] $setting[1]
    if ($LASTEXITCODE -ne 0) { throw "Git configuration failed for $($setting[0])." }
}
Write-Output 'Git graphical diff is configured for Meld:'
& $GitPath config --global --get-regexp '^(diff\.tool|difftool\.|alias\.meld)'
Write-Output 'Inside a Git working tree, use: git meld'
Write-Output 'For staged changes, use: git meld --staged'
Write-Output 'To compare commits, use: git meld HEAD~1 HEAD'
