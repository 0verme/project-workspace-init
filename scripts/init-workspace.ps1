#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Repository,

    [Parameter(Mandatory = $false)]
    [string]$Root
)

$ErrorActionPreference = 'Stop'

# This command is bootstrap-only. The Skill must not invoke it for daily
# Worktree operations after an initialized base has been discovered.

function Stop-NeedsInput {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Missing = @(),
        [string]$Reason
    )

    Write-Output 'STATUS: NEEDS_INPUT'
    if ($Reason) {
        Write-Output "Reason: $Reason"
    }
    Write-Output 'Missing:'
    foreach ($item in $Missing) {
        Write-Output "- $item"
    }
    Write-Output 'No Git or filesystem mutations were made.'
    exit 2
}

function Stop-Attention {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Headline,
        [string[]]$Reasons = @()
    )

    Write-Output 'STATUS: NEEDS_ATTENTION'
    Write-Output $Headline
    foreach ($reason in $Reasons) {
        if ($reason) {
            Write-Output "Reason: $reason"
        }
    }
    Write-Output 'No destructive Git or filesystem mutations were made.'
    exit 2
}

function Test-WindowsAbsolutePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -ne $Value.Trim()) {
        return $false
    }

    $isDrivePath = $Value -match '^[A-Za-z]:[\\/]'
    $isUncPath = $Value -match '^\\\\[^\\/]+[\\/][^\\/]+'
    if (-not ($isDrivePath -or $isUncPath)) {
        return $false
    }

    if ($Value -match '(^|[\\/])\.{1,2}([\\/]|$)') {
        return $false
    }

    if ($Value.IndexOfAny([char[]]'*?') -ge 0) {
        return $false
    }

    try {
        [System.IO.Path]::GetFullPath($Value) | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Get-RepositorySpec {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $candidate = $Value.Trim()
    while ($candidate.EndsWith('/')) {
        $candidate = $candidate.Substring(0, $candidate.Length - 1)
    }
    if ($candidate.EndsWith('.git')) {
        $candidate = $candidate.Substring(0, $candidate.Length - 4)
    }

    $owner = $null
    $name = $null
    if ($candidate -match '^https://github\.com/([^/]+)/([^/]+)$') {
        $owner = $Matches[1]
        $name = $Matches[2]
    }
    elseif ($candidate -match '^([^/]+)/([^/]+)$') {
        $owner = $Matches[1]
        $name = $Matches[2]
    }
    else {
        return $null
    }

    if ($owner -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
        $name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        return $null
    }

    return [pscustomobject]@{
        Owner = $owner
        Name = $name
        Identity = "$owner/$name"
        CloneUrl = "https://github.com/$owner/$name.git"
    }
}

function Invoke-GitCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [string]$WorkingDirectory
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($WorkingDirectory) {
            $rawOutput = & git -C $WorkingDirectory @Arguments 2>&1
        }
        else {
            $rawOutput = & git @Arguments 2>&1
        }
        $exitCode = $LASTEXITCODE
        $text = (($rawOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
        return [pscustomobject]@{
            ExitCode = $exitCode
            Output = $text
        }
    }
    catch {
        return [pscustomobject]@{
            ExitCode = 127
            Output = $_.Exception.Message
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function Get-DefaultBranch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRef,
        [string]$WorkingDirectory
    )

    $result = Invoke-GitCommand -WorkingDirectory $WorkingDirectory -Arguments @('ls-remote', '--symref', $RepositoryRef, 'HEAD')
    if ($result.ExitCode -ne 0) {
        return [pscustomobject]@{
            Valid = $false
            Branch = $null
            Error = "Unable to read remote default branch: $($result.Output.Trim())"
        }
    }

    foreach ($line in @($result.Output -split "`r?`n")) {
        if ($line -match '^ref:\s+refs/heads/([^\s]+)\s+HEAD$') {
            return [pscustomobject]@{
                Valid = $true
                Branch = $Matches[1]
                Error = $null
            }
        }
    }

    return [pscustomobject]@{
        Valid = $false
        Branch = $null
        Error = 'The remote did not advertise a default branch.'
    }
}

function Get-RemoteState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRef
    )

    # A successful --heads probe with no refs is the reliable empty-repository
    # signal. A failed probe means the repository cannot be confirmed safely.
    $headsResult = Invoke-GitCommand -Arguments @('ls-remote', '--heads', $RepositoryRef)
    if ($headsResult.ExitCode -ne 0) {
        return [pscustomobject]@{
            State = 'REPOSITORY_NOT_FOUND'
            BranchCount = 0
            DefaultBranch = $null
            Error = "Unable to confirm the remote repository: $($headsResult.Output.Trim())"
        }
    }

    $branchCount = @(
        $headsResult.Output -split "`r?`n" |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    ).Count
    if ($branchCount -eq 0) {
        # Confirm that HEAD is also not advertised before accepting the empty
        # repository state. A successful HEAD probe with a branch ref wins.
        $emptyDefaultInfo = Get-DefaultBranch -RepositoryRef $RepositoryRef
        if ($emptyDefaultInfo.Valid) {
            return [pscustomobject]@{
                State = 'EXISTING_REPOSITORY'
                BranchCount = 0
                DefaultBranch = $emptyDefaultInfo.Branch
                Error = $null
            }
        }
        if ($emptyDefaultInfo.Error -ne 'The remote did not advertise a default branch.') {
            return [pscustomobject]@{
                State = 'REPOSITORY_NOT_FOUND'
                BranchCount = 0
                DefaultBranch = $null
                Error = "Unable to confirm the remote repository: $($emptyDefaultInfo.Error)"
            }
        }
        return [pscustomobject]@{
            State = 'EMPTY_REPOSITORY'
            BranchCount = 0
            DefaultBranch = $null
            Error = $null
        }
    }

    $defaultInfo = Get-DefaultBranch -RepositoryRef $RepositoryRef
    return [pscustomobject]@{
        State = 'EXISTING_REPOSITORY'
        BranchCount = $branchCount
        DefaultBranch = if ($defaultInfo.Valid) { $defaultInfo.Branch } else { $null }
        Error = if ($defaultInfo.Valid) { $null } else { $defaultInfo.Error }
    }
}

function Get-RemoteIdentity {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Remote
    )

    $candidate = $Remote.Trim().TrimEnd('/')
    if ($candidate.EndsWith('.git')) {
        $candidate = $candidate.Substring(0, $candidate.Length - 4)
    }

    $owner = $null
    $name = $null
    if ($candidate -match '^https://github\.com/([^/]+)/([^/]+)$') {
        $owner = $Matches[1]
        $name = $Matches[2]
    }
    elseif ($candidate -match '^git@github\.com:([^/]+)/([^/]+)$') {
        $owner = $Matches[1]
        $name = $Matches[2]
    }
    elseif ($candidate -match '^ssh://git@github\.com/([^/]+)/([^/]+)$') {
        $owner = $Matches[1]
        $name = $Matches[2]
    }
    else {
        return $null
    }

    if ($owner -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
        $name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        return $null
    }

    return "$owner/$name"
}

function Get-ComparablePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    try {
        return ([System.IO.Path]::GetFullPath($Value)).TrimEnd([char[]]'\\/').ToLowerInvariant()
    }
    catch {
        return $Value.TrimEnd([char[]]'\\/').ToLowerInvariant()
    }
}

function Inspect-MainWorkspace {
    param(
        [Parameter(Mandatory = $true)]
        [string]$MainPath,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedIdentity,
        [string]$RemoteState = 'EXISTING_REPOSITORY'
    )

    $reasons = New-Object System.Collections.Generic.List[string]
    $expectedPath = Get-ComparablePath -Value $MainPath

    $topResult = Invoke-GitCommand -WorkingDirectory $MainPath -Arguments @('rev-parse', '--show-toplevel')
    if ($topResult.ExitCode -ne 0) {
        $reasons.Add('Main Workspace is not a Git repository.')
        return [pscustomobject]@{
            Valid = $false
            Dirty = $false
            CurrentBranch = $null
            DefaultBranch = $null
            Origin = $null
            Reasons = @($reasons)
        }
    }

    if ((Get-ComparablePath -Value $topResult.Output.Trim()) -ne $expectedPath) {
        $reasons.Add('Main Workspace Git top level does not match the requested path.')
        return [pscustomobject]@{
            Valid = $false
            Dirty = $false
            CurrentBranch = $null
            DefaultBranch = $null
            Origin = $null
            Reasons = @($reasons)
        }
    }

    $worktreeResult = Invoke-GitCommand -WorkingDirectory $MainPath -Arguments @('rev-parse', '--is-inside-work-tree')
    if ($worktreeResult.ExitCode -ne 0 -or $worktreeResult.Output.Trim() -ne 'true') {
        $reasons.Add('Main Workspace is not a non-bare Git working tree.')
    }

    $originResult = Invoke-GitCommand -WorkingDirectory $MainPath -Arguments @('config', '--get', 'remote.origin.url')
    $origin = $originResult.Output.Trim()
    if ($originResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($origin)) {
        $reasons.Add('origin is missing.')
    }
    else {
        $originIdentity = Get-RemoteIdentity -Remote $origin
        if ([string]::IsNullOrWhiteSpace($originIdentity) -or
            $originIdentity.ToLowerInvariant() -ne $ExpectedIdentity.ToLowerInvariant()) {
            $reasons.Add("origin '$origin' does not match the requested Repository '$ExpectedIdentity'.")
        }
    }

    if ($RemoteState -eq 'EMPTY_REPOSITORY') {
        $defaultInfo = $null
    }
    else {
        $defaultInfo = Get-DefaultBranch -RepositoryRef 'origin' -WorkingDirectory $MainPath
        if (-not $defaultInfo.Valid) {
            $reasons.Add($defaultInfo.Error)
        }
    }

    $branchResult = Invoke-GitCommand -WorkingDirectory $MainPath -Arguments @('symbolic-ref', '--quiet', '--short', 'HEAD')
    $currentBranch = $branchResult.Output.Trim()
    if ($branchResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($currentBranch)) {
        $reasons.Add('Main Workspace is detached or its current branch cannot be read.')
    }
    elseif ($RemoteState -eq 'EMPTY_REPOSITORY' -and $currentBranch -ne 'main') {
        $reasons.Add("Current branch '$currentBranch' must be 'main' for an empty remote repository.")
    }
    elseif ($null -ne $defaultInfo -and $defaultInfo.Valid -and $currentBranch -ne $defaultInfo.Branch) {
        $reasons.Add("Current branch '$currentBranch' is not remote default branch '$($defaultInfo.Branch)'.")
    }

    $statusResult = Invoke-GitCommand -WorkingDirectory $MainPath -Arguments @('status', '--porcelain=v1', '--untracked-files=all')
    $dirty = $statusResult.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($statusResult.Output.Trim())
    if ($statusResult.ExitCode -ne 0) {
        $reasons.Add('Unable to read Main Workspace working tree status.')
    }
    elseif ($dirty) {
        $reasons.Add('Main Workspace: DIRTY')
    }

    return [pscustomobject]@{
        Valid = $reasons.Count -eq 0
        Dirty = $dirty
        CurrentBranch = $currentBranch
        DefaultBranch = if ($null -ne $defaultInfo -and $defaultInfo.Valid) { $defaultInfo.Branch } else { $null }
        Origin = $origin
        Reasons = @($reasons)
    }
}

$missing = New-Object System.Collections.Generic.List[string]
if ([string]::IsNullOrWhiteSpace($Repository)) {
    $missing.Add('Repository')
}
if ([string]::IsNullOrWhiteSpace($Root)) {
    $missing.Add('Workspace Root')
}
if ($missing.Count -gt 0) {
    Stop-NeedsInput -Missing @($missing)
}

if (-not (Test-WindowsAbsolutePath -Value $Root)) {
    Stop-NeedsInput -Missing @() -Reason 'Workspace Root must be an explicit Windows absolute path.'
}

$repositorySpec = Get-RepositorySpec -Value $Repository
if ($null -eq $repositorySpec) {
    Stop-NeedsInput -Missing @() -Reason 'Repository must be a GitHub URL or an explicit owner/repo value.'
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Stop-Attention -Headline 'Git is unavailable.' -Reasons @('Put git in PATH and retry.')
}

try {
    $rootPath = [System.IO.Path]::GetFullPath($Root)
}
catch {
    Stop-NeedsInput -Missing @() -Reason 'Workspace Root could not be parsed as an absolute path.'
}

if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
    Stop-Attention -Headline 'Workspace Root is unavailable.' -Reasons @("Root does not exist as a directory: $rootPath")
}

$mainPath = Join-Path -Path $rootPath -ChildPath $repositorySpec.Name
$basePath = Join-Path -Path $rootPath -ChildPath ("{0}_base" -f $repositorySpec.Name)
$templateRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..\templates'))
$agentsTemplate = Join-Path -Path $templateRoot -ChildPath 'AGENTS.md'
$statusTemplate = Join-Path -Path $templateRoot -ChildPath 'STATUS.md'

if (-not (Test-Path -LiteralPath $agentsTemplate -PathType Leaf) -or
    -not (Test-Path -LiteralPath $statusTemplate -PathType Leaf)) {
    Stop-Attention -Headline 'Skill templates are unavailable.' -Reasons @("Expected templates under: $templateRoot")
}

$preflightReasons = New-Object System.Collections.Generic.List[string]
$mainExists = Test-Path -LiteralPath $mainPath
$baseExists = Test-Path -LiteralPath $basePath

if ($mainExists -and -not (Test-Path -LiteralPath $mainPath -PathType Container)) {
    $preflightReasons.Add("Main Workspace path is not a directory: $mainPath")
}

if ($baseExists) {
    if (-not (Test-Path -LiteralPath $basePath -PathType Container)) {
        $preflightReasons.Add("Base Workspace path is not a directory: $basePath")
    }
    else {
        $baseGitResult = Invoke-GitCommand -WorkingDirectory $basePath -Arguments @('rev-parse', '--show-toplevel')
        if ($baseGitResult.ExitCode -eq 0) {
            $preflightReasons.Add('Base Workspace is inside an existing Git repository; Base must remain non-Git.')
        }

        foreach ($directoryName in @('status', 'integration', 'worktrees')) {
            $directoryPath = Join-Path -Path $basePath -ChildPath $directoryName
            if ((Test-Path -LiteralPath $directoryPath) -and
                -not (Test-Path -LiteralPath $directoryPath -PathType Container)) {
                $preflightReasons.Add("Base entry is not a directory: $directoryPath")
            }
        }

        foreach ($fileName in @('AGENTS.md', 'STATUS.md')) {
            $filePath = Join-Path -Path $basePath -ChildPath $fileName
            if ((Test-Path -LiteralPath $filePath) -and
                -not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
                $preflightReasons.Add("Base template target is not a file: $filePath")
            }
        }
    }
}

if ($preflightReasons.Count -gt 0) {
    Stop-Attention -Headline 'Workspace preflight failed.' -Reasons @($preflightReasons)
}

$remoteStateInfo = Get-RemoteState -RepositoryRef $repositorySpec.CloneUrl
if ($remoteStateInfo.State -eq 'REPOSITORY_NOT_FOUND') {
    Stop-Attention -Headline 'Remote repository validation failed.' -Reasons @(
        "Remote State: $($remoteStateInfo.State)",
        $remoteStateInfo.Error
    )
}
if ($remoteStateInfo.State -eq 'EXISTING_REPOSITORY' -and
    [string]::IsNullOrWhiteSpace($remoteStateInfo.DefaultBranch)) {
    Stop-Attention -Headline 'Remote repository default branch cannot be determined safely.' -Reasons @(
        "Remote State: $($remoteStateInfo.State)",
        $remoteStateInfo.Error
    )
}

$mainStatus = $null
$inspection = $null
if ($mainExists) {
    $inspection = Inspect-MainWorkspace -MainPath $mainPath -ExpectedIdentity $repositorySpec.Identity -RemoteState $remoteStateInfo.State
    if ($inspection.Dirty) {
        $remainingReasons = @($inspection.Reasons | Where-Object { $_ -ne 'Main Workspace: DIRTY' })
        Stop-Attention -Headline 'Main Workspace: DIRTY' -Reasons $remainingReasons
    }
    if (-not $inspection.Valid) {
        Stop-Attention -Headline 'Main Workspace: NEEDS_ATTENTION' -Reasons @($inspection.Reasons)
    }
    $mainStatus = 'EXISTS'
}
else {
    if ($remoteStateInfo.State -eq 'EMPTY_REPOSITORY') {
        $initResult = Invoke-GitCommand -WorkingDirectory $rootPath -Arguments @('init', '-b', 'main', $mainPath)
        if ($initResult.ExitCode -ne 0) {
            $initMessage = $initResult.Output.Trim()
            if ([string]::IsNullOrWhiteSpace($initMessage)) {
                $initMessage = 'git init returned a non-zero exit code.'
            }
            Stop-Attention -Headline 'Empty Repository Bootstrap failed.' -Reasons @($initMessage)
        }

        $remoteResult = Invoke-GitCommand -WorkingDirectory $mainPath -Arguments @('remote', 'add', 'origin', $repositorySpec.CloneUrl)
        if ($remoteResult.ExitCode -ne 0) {
            $remoteMessage = $remoteResult.Output.Trim()
            if ([string]::IsNullOrWhiteSpace($remoteMessage)) {
                $remoteMessage = 'git remote add returned a non-zero exit code.'
            }
            Stop-Attention -Headline 'Empty Repository Bootstrap failed.' -Reasons @($remoteMessage)
        }

        $inspection = Inspect-MainWorkspace -MainPath $mainPath -ExpectedIdentity $repositorySpec.Identity -RemoteState 'EMPTY_REPOSITORY'
        if ($inspection.Dirty) {
            $remainingReasons = @($inspection.Reasons | Where-Object { $_ -ne 'Main Workspace: DIRTY' })
            Stop-Attention -Headline 'Main Workspace: DIRTY' -Reasons $remainingReasons
        }
        if (-not $inspection.Valid) {
            Stop-Attention -Headline 'Empty Repository Bootstrap verification failed.' -Reasons @($inspection.Reasons)
        }
        $mainStatus = 'CREATED'
    }
    else {
        $cloneResult = Invoke-GitCommand -WorkingDirectory $rootPath -Arguments @(
            'clone',
            '--origin', 'origin',
            '--branch', $remoteStateInfo.DefaultBranch,
            $repositorySpec.CloneUrl,
            $mainPath
        )
        if ($cloneResult.ExitCode -ne 0) {
            $cloneMessage = $cloneResult.Output.Trim()
            if ([string]::IsNullOrWhiteSpace($cloneMessage)) {
                $cloneMessage = 'git clone returned a non-zero exit code.'
            }
            Stop-Attention -Headline 'Main Workspace clone failed.' -Reasons @($cloneMessage)
        }

        $inspection = Inspect-MainWorkspace -MainPath $mainPath -ExpectedIdentity $repositorySpec.Identity -RemoteState 'EXISTING_REPOSITORY'
        if ($inspection.Dirty) {
            $remainingReasons = @($inspection.Reasons | Where-Object { $_ -ne 'Main Workspace: DIRTY' })
            Stop-Attention -Headline 'Main Workspace: DIRTY' -Reasons $remainingReasons
        }
        if (-not $inspection.Valid) {
            Stop-Attention -Headline 'Cloned Main Workspace verification failed.' -Reasons @($inspection.Reasons)
        }
        $mainStatus = 'CREATED'
    }
}

$legacyCandidates = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
try {
    foreach ($child in @(Get-ChildItem -LiteralPath $rootPath -Directory -Force)) {
        if ($child.Name.StartsWith(($repositorySpec.Name + '-'), [System.StringComparison]::OrdinalIgnoreCase)) {
            $legacyCandidates.Add($child.FullName)
        }
    }
}
catch {
    $warnings.Add("Unable to inspect flat legacy Worktree candidates: $($_.Exception.Message)")
}

$worktreeListResult = Invoke-GitCommand -WorkingDirectory $mainPath -Arguments @('worktree', 'list')
if ($worktreeListResult.ExitCode -ne 0) {
    $warnings.Add("git worktree list failed: $($worktreeListResult.Output.Trim())")
}

$baseStatus = $null
$directoryStatuses = New-Object System.Collections.Generic.List[object]
$templateStatuses = New-Object System.Collections.Generic.List[object]
try {
    if (-not (Test-Path -LiteralPath $basePath)) {
        [System.IO.Directory]::CreateDirectory($basePath) | Out-Null
        $baseStatus = 'CREATED'
    }
    else {
        $baseStatus = 'EXISTS'
    }

    foreach ($directoryName in @('status', 'integration', 'worktrees')) {
        $directoryPath = Join-Path -Path $basePath -ChildPath $directoryName
        if (-not (Test-Path -LiteralPath $directoryPath)) {
            [System.IO.Directory]::CreateDirectory($directoryPath) | Out-Null
            $directoryStatuses.Add([pscustomobject]@{ Name = $directoryName; State = 'CREATED' })
        }
        else {
            $directoryStatuses.Add([pscustomobject]@{ Name = $directoryName; State = 'EXISTS' })
        }
    }

    foreach ($template in @(
        [pscustomobject]@{ Name = 'AGENTS.md'; Source = $agentsTemplate },
        [pscustomobject]@{ Name = 'STATUS.md'; Source = $statusTemplate }
    )) {
        $targetPath = Join-Path -Path $basePath -ChildPath $template.Name
        if (-not (Test-Path -LiteralPath $targetPath)) {
            Copy-Item -LiteralPath $template.Source -Destination $targetPath
            $templateStatuses.Add([pscustomobject]@{ Name = $template.Name; State = 'CREATED' })
        }
        else {
            $templateStatuses.Add([pscustomobject]@{ Name = $template.Name; State = 'KEEP' })
        }
    }
}
catch {
    Stop-Attention -Headline 'Base Workspace initialization failed.' -Reasons @($_.Exception.Message)
}

Write-Output 'STATUS: SUCCESS'
Write-Output "Repository: $($repositorySpec.Identity)"
Write-Output "Workspace Root: $rootPath"
Write-Output "Main Workspace: $mainPath ($mainStatus)"
Write-Output "Remote State: $($remoteStateInfo.State)"
Write-Output "Current Branch: $($inspection.CurrentBranch)"
$displayDefaultBranch = if ([string]::IsNullOrWhiteSpace($inspection.DefaultBranch)) { 'none' } else { $inspection.DefaultBranch }
Write-Output "Default Branch: $displayDefaultBranch"
if ($remoteStateInfo.State -eq 'EMPTY_REPOSITORY') {
    Write-Output 'Origin: CONFIGURED'
    Write-Output 'Remote main: not created yet'
}
else {
    Write-Output 'Origin: VERIFIED'
}
Write-Output 'Working Tree: CLEAN'
Write-Output "Base Workspace: $basePath ($baseStatus)"
foreach ($item in $directoryStatuses) {
    Write-Output "Base/$($item.Name): $($item.State)"
}
foreach ($item in $templateStatuses) {
    Write-Output "Base/$($item.Name): $($item.State)"
}

if ($legacyCandidates.Count -gt 0) {
    Write-Output 'LEGACY WORKTREES DETECTED'
    foreach ($candidate in $legacyCandidates) {
        Write-Output "- $candidate"
    }
}
foreach ($warning in $warnings) {
    Write-Output "WARNING: $warning"
}
