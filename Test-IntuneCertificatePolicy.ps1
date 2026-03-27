<#
.SYNOPSIS
    Verifies whether local CA certificates are already deployed as Intune Trusted Certificate profiles.

.DESCRIPTION
    Reads certificate files (.cer, .crt) from one or more folders and compares their
    content against all existing Intune Trusted Certificate profiles retrieved via
    Microsoft Graph API. Matching is done by comparing the raw certificate bytes,
    ensuring an exact content-based match regardless of file name or policy name.

.PARAMETER CertificatePaths
    One or more paths to folders containing certificate files to verify.

.PARAMETER IncludeExpired
    When specified, also reports certificates that are expired.

.EXAMPLE
    .\Test-IntuneCertificatePolicy.ps1 -CertificatePaths ".\RootCAs", ".\SubCAs"

.EXAMPLE
    .\Test-IntuneCertificatePolicy.ps1 -CertificatePaths ".\RootCAs" -IncludeExpired
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({
        foreach ($p in $_) {
            if (-not (Test-Path $p -PathType Container)) {
                throw "Path '$p' does not exist or is not a directory."
            }
        }
        $true
    })]
    [string[]]$CertificatePaths,

    [switch]$IncludeExpired
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Helper Functions

function Get-CertificateFromFile {
    param([Parameter(Mandatory)][string]$Path)
    try {
        return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($Path)
    }
    catch {
        Write-Warning "Failed to load certificate from '$Path': $_"
        return $null
    }
}

function Get-CertificateCAName {
    param([Parameter(Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    $cn = $Certificate.GetNameInfo(
        [System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false
    )
    if ([string]::IsNullOrWhiteSpace($cn)) {
        if ($Certificate.Subject -match 'CN=([^,]+)') { $cn = $Matches[1].Trim() }
        else { $cn = $Certificate.Subject }
    }
    return $cn
}

function Get-AllTrustedCertificateProfiles {
    <#
    .SYNOPSIS
        Retrieves all Intune Trusted Certificate profiles with their certificate content.
    #>
    Write-Host "  Fetching profile list..." -ForegroundColor Gray
    $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$filter=isof('microsoft.graph.windows81TrustedRootCertificate')&`$select=id,displayName,destinationStore"

    $profiles = [System.Collections.Generic.List[PSCustomObject]]::new()
    $response = Invoke-MgGraphRequest -Method GET -Uri $uri

    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $response.value) { $ids.Add($item.id) }
    while ($response.'@odata.nextLink') {
        $response = Invoke-MgGraphRequest -Method GET -Uri $response.'@odata.nextLink'
        foreach ($item in $response.value) { $ids.Add($item.id) }
    }

    Write-Host "  Found $($ids.Count) profile(s). Downloading certificate content..." -ForegroundColor Gray
    $counter = 0

    foreach ($id in $ids) {
        $counter++
        Write-Progress -Activity "Downloading profiles" -Status "$counter of $($ids.Count)" -PercentComplete (($counter / $ids.Count) * 100)

        try {
            $detail = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$id"

            $certBytes = $null
            if ($detail.trustedRootCertificate) {
                $certBytes = [Convert]::FromBase64String($detail.trustedRootCertificate)
            }

            $profiles.Add([PSCustomObject]@{
                Id               = $detail.id
                DisplayName      = $detail.displayName
                DestinationStore = $detail.destinationStore
                CertificateBytes = $certBytes
                Thumbprint       = if ($certBytes) {
                    try {
                        $c = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certBytes)
                        $tp = $c.Thumbprint
                        $c.Dispose()
                        $tp
                    } catch { $null }
                } else { $null }
            })
        }
        catch {
            Write-Warning "Failed to retrieve profile '$id': $_"
        }
    }

    Write-Progress -Activity "Downloading profiles" -Completed
    return $profiles
}

#endregion

#region Main

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host " Intune Certificate Policy Verification" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
try {
    $context = Get-MgContext
    if (-not $context) {
        Connect-MgGraph -Scopes 'DeviceManagementConfiguration.Read.All' -NoWelcome
    }
    Write-Host "Connected as: $(Get-MgContext | Select-Object -ExpandProperty Account)`n" -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $_"
    exit 1
}

# Retrieve all Intune trusted certificate profiles
Write-Host "Retrieving Intune Trusted Certificate profiles..." -ForegroundColor Cyan
$intuneProfiles = Get-AllTrustedCertificateProfiles
Write-Host "  Loaded $($intuneProfiles.Count) profile(s) with certificate content.`n" -ForegroundColor Green

# Build a lookup by thumbprint for fast matching
$profilesByThumbprint = @{}
foreach ($profile in $intuneProfiles) {
    if ($profile.Thumbprint) {
        if (-not $profilesByThumbprint.ContainsKey($profile.Thumbprint)) {
            $profilesByThumbprint[$profile.Thumbprint] = [System.Collections.Generic.List[PSCustomObject]]::new()
        }
        $profilesByThumbprint[$profile.Thumbprint].Add($profile)
    }
}

# Load and verify local certificates
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($folder in $CertificatePaths) {
    $resolvedPath = Resolve-Path $folder
    Write-Host "Scanning certificates in: $resolvedPath" -ForegroundColor Cyan
    Write-Host ('-' * 60) -ForegroundColor Gray

    $files = Get-ChildItem -Path $resolvedPath -File -Include '*.cer', '*.crt' -Recurse
    if (-not $files) {
        Write-Host "  No .cer or .crt files found. Skipping.`n" -ForegroundColor Yellow
        continue
    }

    foreach ($file in $files) {
        $cert = Get-CertificateFromFile -Path $file.FullName
        if (-not $cert) {
            $results.Add([PSCustomObject]@{
                File          = $file.Name
                Folder        = $resolvedPath
                CAName        = 'N/A'
                Thumbprint    = 'N/A'
                Expired       = $false
                Status        = 'ERROR'
                MatchedPolicy = 'N/A'
                MatchType     = 'N/A'
            })
            continue
        }

        $caName = Get-CertificateCAName -Certificate $cert
        $isExpired = $cert.NotAfter -lt (Get-Date)

        if ($isExpired -and -not $IncludeExpired) {
            Write-Host "  ⏭ $($file.Name) — EXPIRED ($($cert.NotAfter.ToString('yyyy-MM-dd'))), skipping." -ForegroundColor DarkGray
            $cert.Dispose()
            continue
        }

        # Match by thumbprint (derived from raw certificate bytes)
        $matchedProfiles = @()
        if ($profilesByThumbprint.ContainsKey($cert.Thumbprint)) {
            $matchedProfiles = $profilesByThumbprint[$cert.Thumbprint]
        }

        # Secondary match: byte-for-byte comparison for profiles without thumbprint
        if ($matchedProfiles.Count -eq 0) {
            $localBytes = $cert.RawData
            foreach ($profile in $intuneProfiles) {
                if ($profile.CertificateBytes -and $profile.CertificateBytes.Length -eq $localBytes.Length) {
                    if ([System.Linq.Enumerable]::SequenceEqual([byte[]]$localBytes, [byte[]]$profile.CertificateBytes)) {
                        $matchedProfiles += $profile
                    }
                }
            }
        }

        $matchType = if ($matchedProfiles.Count -gt 0 -and $profilesByThumbprint.ContainsKey($cert.Thumbprint)) {
            'Thumbprint'
        }
        elseif ($matchedProfiles.Count -gt 0) {
            'ByteContent'
        }
        else {
            'None'
        }

        if ($matchedProfiles.Count -gt 0) {
            $policyNames = ($matchedProfiles | ForEach-Object { $_.DisplayName }) -join ', '
            $statusText = 'DEPLOYED'
            $statusColor = 'Green'
        }
        else {
            $policyNames = '-'
            $statusText = 'MISSING'
            $statusColor = 'Red'
        }

        if ($isExpired) {
            $statusText = "$statusText (EXPIRED)"
            $statusColor = 'Yellow'
        }

        $statusIcon = if ($statusText -like 'DEPLOYED*') { '✅' } else { '❌' }

        Write-Host "  $statusIcon $($file.Name)" -ForegroundColor $statusColor
        Write-Host "     CA Name    : $caName" -ForegroundColor White
        Write-Host "     Thumbprint : $($cert.Thumbprint)" -ForegroundColor Gray
        Write-Host "     Valid      : $($cert.NotBefore.ToString('yyyy-MM-dd')) → $($cert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor Gray
        Write-Host "     Status     : $statusText" -ForegroundColor $statusColor
        if ($matchedProfiles.Count -gt 0) {
            Write-Host "     Policy     : $policyNames" -ForegroundColor Gray
            Write-Host "     Match      : $matchType" -ForegroundColor Gray
        }
        Write-Host ''

        $results.Add([PSCustomObject]@{
            File          = $file.Name
            Folder        = [string]$resolvedPath
            CAName        = $caName
            Thumbprint    = $cert.Thumbprint
            Expired       = $isExpired
            Status        = $statusText
            MatchedPolicy = $policyNames
            MatchType     = $matchType
        })

        $cert.Dispose()
    }
}

# Summary
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host " Summary" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$results | Format-Table -AutoSize -Property File, CAName, Status, MatchedPolicy, MatchType

$deployed = @($results | Where-Object { $_.Status -like 'DEPLOYED*' }).Count
$missing  = @($results | Where-Object { $_.Status -like 'MISSING*' }).Count
$errors   = @($results | Where-Object { $_.Status -eq 'ERROR' }).Count
$total    = $results.Count

Write-Host "Total: $total | Deployed: $deployed | Missing: $missing | Errors: $errors" -ForegroundColor Cyan

if ($missing -gt 0) {
    Write-Host "`nMissing certificates that need to be imported:" -ForegroundColor Yellow
    $results | Where-Object { $_.Status -like 'MISSING*' } | ForEach-Object {
        Write-Host "  ❌ $($_.CAName) ($($_.File))" -ForegroundColor Yellow
    }
}

if ($deployed -eq $total -and $total -gt 0) {
    Write-Host "`n✅ All certificates are deployed in Intune.`n" -ForegroundColor Green
}

Write-Host ''

#endregion
