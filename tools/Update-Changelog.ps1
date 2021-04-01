# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#requires -Version 6.0

using module PowerShellForGitHub

<#
.SYNOPSIS
  Updates the CHANGELOG file with PRs merged since the last release.
.DESCRIPTION
  Expects the Git repositories to be checked out correctly as it does not
  change branches or pull. Handles any merge option for PRs, but is a little
  slow as it queries all closed PRs first.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet("vscode-powershell", "PowerShellEditorServices")]
    [string]$RepositoryName,

    [Parameter(Mandatory)]
    [ValidateScript({ $_.StartsWith("v") })]
    [string]$Version
)

# TODO: Refactor into functions to map over these.
$RepoNames = "vscode-powershell", "PowerShellEditorServices"

# NOTE: This a side effect neccesary for Git operations to work.
Set-Location (Resolve-Path "$PSScriptRoot/../../$RepositoryName")

# Get the repo object, latest release, and commits since its tag.
$Repo = Get-GitHubRepository -OwnerName PowerShell -RepositoryName $RepositoryName
$Release = $Repo | Get-GitHubRelease | Select-Object -First 1
$Commits = git rev-list "$($Release.tag_name)..."
# NOTE: This is a slow API as it gets all closed PRs, and then filters.
$PullRequests = $Repo | Get-GitHubPullRequest -State Closed |
    Where-Object { $_.merge_commit_sha -in $Commits } |
    Where-Object { $_.user.UserName -notmatch "\[bot\]$" } |
    Where-Object { $_.labels.LabelName -notcontains "Ignore" }

$SkipThanks = @(
    'andschwa'
    'daxian-dbw'
    'PaulHigin'
    'rjmholt'
    'SteveL-MSFT'
    'TylerLeonhardt'
)

$LabelEmoji = @{
    'Issue-Enhancement'         = '✨'
    'Issue-Bug'                 = '🐛'
    'Issue-Performance'         = '⚡️'
    'Area-Build & Release'      = '👷'
    'Area-Code Formatting'      = '💎'
    'Area-Configuration'        = '🔧'
    'Area-Debugging'            = '🔍'
    'Area-Documentation'        = '📖'
    'Area-Engine'               = '🚂'
    'Area-Folding'              = '📚'
    'Area-Integrated Console'   = '📟'
    'Area-IntelliSense'         = '🧠'
    'Area-Logging'              = '💭'
    'Area-Pester'               = '🐢'
    'Area-Script Analysis'      = '‍🕵️'
    'Area-Snippets'             = '✂️'
    'Area-Startup'              = '🛫'
    'Area-Symbols & References' = '🔗'
    'Area-Tasks'                = '✅'
    'Area-Test'                 = '🚨'
    'Area-Threading'            = '⏱️'
    'Area-UI'                   = '📺'
    'Area-Workspaces'           = '📁'
}

$CloseKeywords = @(
    'close'
    'closes'
    'closed'
    'fix'
    'fixes'
    'fixed'
    'resolve'
    'resolves'
    'resolved'
)

$IssueRegex = "(" + ($CloseKeywords -join "|") + ")\s+(?<issue>\S+)"

$Bullets = $PullRequests | ForEach-Object {
    # Map all the labels to emoji (or use a default).
    # NOTE: Whitespacing here is weird.
    $emoji = if ($_.labels) {
        $LabelEmoji[$_.labels.LabelName] -join ""
    } else { '#️⃣ 🙏' }
    # Get a linked issue number if it exists (or use the PR).
    $link = if ($_.body -match $IssueRegex) {
        $issue = $Matches.issue
        $number = if ($issue -match "(?<number>\d+)$") {
            $Matches.number
        } else { Write-Error "Couldn't find issue number!" }
        # Handle links to issues in both or repos, in both shortcode and URLs.
        $name = $RepoNames | Where-Object { $issue -match $_ } | Select-Object -First 1
        "$name #$number"
    } else { "$RepositoryName #$($_.number)" }
    # Thank the contributor if they are not one of us.
    $thanks = if ($_.user.UserName -notin $SkipThanks) {
        "(Thanks @$($_.user.UserName)!)"
    }
    # Put the bullet point together.
    "-", $emoji, "[$link]($($_.html_url))", "-", "$($_.title).", $thanks -join " "
}

$ChangelogPath = "CHANGELOG.md"
$CurrentChangelog = Get-Content -Path $ChangelogPath
# TODO: Handle vscode-powershell edge case.
$NewChangelog = @(
    "## $Version"
    "### $([datetime]::Now.ToString('dddd, MMMM dd, yyyy'))`n"
    $Bullets
)
@(
    $CurrentChangelog[0..1]
    $NewChangelog
    $CurrentChangelog[1..$CurrentChangelog.Length]
) | Set-Content -Encoding utf8NoBOM -Path $ChangelogPath

if ($PSCmdlet.ShouldProcess("$RepositoryName/$ChangelogPath", "git")) {
    $branch = git branch --show-current
    if ($branch -ne "release/$version") {
        git checkout -b "release/$version"
    }
    git add $ChangelogPath
    git commit -m "Update CHANGELOG for $Version"
    git push
}

# TODO: Do this in a separate function (will require reading from disk).
$ReleaseParams = @{
    Draft      = $true
    Tag        = $Version
    Name       = $Version
    Body       = $NewChangelog
    PreRelease = $Version -match "-preview"
}
$Repo | New-GitHubRelease @ReleaseParams
