<#
.SYNOPSIS
    Creates Intune Trusted Certificate profiles from Root and Subordinate CA certificates.

.DESCRIPTION
    Reads certificates (.cer, .crt) from Root CA and Subordinate CA folders,
    extracts the CA name from the certificate subject, and creates Intune
    Trusted Certificate profiles via Microsoft Graph API with a standardized
    naming convention: "{Prefix} - {CA Name from Subject}".

.PARAMETER Prefix
    The naming prefix for all Intune policies (e.g., "ISP").

.PARAMETER RootCACertsPath
    Path to the folder containing Root CA certificates.

.PARAMETER SubordinateCACertsPath
    Path to the folder containing Subordinate CA certificates.

.PARAMETER DryRun
    When specified, shows what would be created without making any changes.

.EXAMPLE
    .\New-IntuneCertificatePolicy.ps1 -Prefix "ISP" -RootCACertsPath ".\RootCAs" -SubordinateCACertsPath ".\SubCAs"

.EXAMPLE
    .\New-IntuneCertificatePolicy.ps1 -Prefix "ISP" -RootCACertsPath ".\RootCAs" -SubordinateCACertsPath ".\SubCAs" -DryRun
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Prefix,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$RootCACertsPath,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$SubordinateCACertsPath,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Helper Functions

function Get-CertificateFromFile {
    <#
    .SYNOPSIS
        Loads an X509 certificate from a .cer or .crt file.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($Path)
        return $cert
    }
    catch {
        Write-Warning "Failed to load certificate from '$Path': $_"
        return $null
    }
}

function Get-CertificateCAName {
    <#
    .SYNOPSIS
        Extracts the Common Name (CN) from the certificate subject.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    $cn = $Certificate.GetNameInfo(
        [System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName,
        $false
    )

    if ([string]::IsNullOrWhiteSpace($cn)) {
        # Fallback: parse CN from Subject string
        if ($Certificate.Subject -match 'CN=([^,]+)') {
            $cn = $Matches[1].Trim()
        }
        else {
            $cn = $Certificate.Subject
        }
    }

    return $cn
}

function Get-CertificateFiles {
    <#
    .SYNOPSIS
        Gets all .cer and .crt files from a folder.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath
    )

    $files = Get-ChildItem -Path $FolderPath -File -Include '*.cer', '*.crt' -Recurse
    if (-not $files) {
        Write-Warning "No .cer or .crt files found in '$FolderPath'"
    }
    return $files
}

function New-IntuneTrustedCertificateProfile {
    <#
    .SYNOPSIS
        Creates an Intune Trusted Certificate profile via Microsoft Graph API.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [Parameter(Mandatory)]
        [ValidateSet('computerCertStoreRoot', 'computerCertStoreIntermediate')]
        [string]$DestinationStore,

        [Parameter(Mandatory)]
        [string]$FileName
    )

    $certBase64 = [Convert]::ToBase64String($Certificate.RawData)

    $body = @{
        '@odata.type'          = '#microsoft.graph.windows81TrustedRootCertificate'
        displayName            = $DisplayName
        description            = $Description
        trustedRootCertificate = $certBase64
        destinationStore       = $DestinationStore
        fileName               = $FileName
    }

    $uri = 'https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations'

    try {
        $response = Invoke-MgGraphRequest -Method POST -Uri $uri -Body ($body | ConvertTo-Json -Depth 10) -ContentType 'application/json'
        return $response
    }
    catch {
        Write-Error "Failed to create profile '$DisplayName': $_"
        return $null
    }
}

function Get-ExistingTrustedCertProfiles {
    <#
    .SYNOPSIS
        Retrieves existing Intune Trusted Certificate profiles to avoid duplicates.
    #>
    $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$filter=isof('microsoft.graph.windows81TrustedRootCertificate')&`$select=id,displayName"

    try {
        $profiles = @()
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri
        $profiles += $response.value

        while ($response.'@odata.nextLink') {
            $response = Invoke-MgGraphRequest -Method GET -Uri $response.'@odata.nextLink'
            $profiles += $response.value
        }

        return $profiles
    }
    catch {
        Write-Warning "Could not retrieve existing profiles: $_"
        return @()
    }
}

#endregion

#region Main

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Intune Certificate Policy Creator" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "[DRY RUN] No changes will be made.`n" -ForegroundColor Yellow
}

# Connect to Microsoft Graph
if (-not $DryRun) {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    try {
        $context = Get-MgContext
        if (-not $context) {
            Connect-MgGraph -Scopes 'DeviceManagementConfiguration.ReadWrite.All' -NoWelcome
        }
        else {
            $requiredScope = 'DeviceManagementConfiguration.ReadWrite.All'
            if ($context.Scopes -notcontains $requiredScope) {
                Write-Host "Reconnecting with required scope..." -ForegroundColor Yellow
                Connect-MgGraph -Scopes $requiredScope -NoWelcome
            }
        }
        Write-Host "Connected as: $(Get-MgContext | Select-Object -ExpandProperty Account)`n" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        exit 1
    }

    # Retrieve existing profiles to detect duplicates
    Write-Host "Checking for existing Trusted Certificate profiles..." -ForegroundColor Cyan
    $existingProfiles = Get-ExistingTrustedCertProfiles
    $existingNames = $existingProfiles | ForEach-Object { $_.displayName }
    Write-Host "Found $($existingProfiles.Count) existing profile(s).`n" -ForegroundColor Gray
}

# Process certificates
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

$certGroups = @(
    @{
        Label            = 'Root CA'
        Path             = $RootCACertsPath
        DestinationStore = 'computerCertStoreRoot'
    },
    @{
        Label            = 'Subordinate CA'
        Path             = $SubordinateCACertsPath
        DestinationStore = 'computerCertStoreIntermediate'
    }
)

foreach ($group in $certGroups) {
    Write-Host "Processing $($group.Label) certificates from: $($group.Path)" -ForegroundColor Cyan
    Write-Host ('-' * 60) -ForegroundColor Gray

    $certFiles = Get-CertificateFiles -FolderPath $group.Path
    if (-not $certFiles) {
        Write-Host "  No certificates found. Skipping.`n" -ForegroundColor Yellow
        continue
    }

    foreach ($file in $certFiles) {
        $cert = Get-CertificateFromFile -Path $file.FullName
        if (-not $cert) {
            $results.Add([PSCustomObject]@{
                Type        = $group.Label
                File        = $file.Name
                PolicyName  = 'N/A'
                Status      = 'FAILED - Could not load certificate'
                Thumbprint  = 'N/A'
            })
            continue
        }

        $caName = Get-CertificateCAName -Certificate $cert
        $policyName = "$Prefix - $caName"
        $description = "$($group.Label) certificate: $caName (Thumbprint: $($cert.Thumbprint))"

        Write-Host "  Certificate : $($file.Name)" -ForegroundColor White
        Write-Host "  CA Name     : $caName" -ForegroundColor White
        Write-Host "  Policy Name : $policyName" -ForegroundColor White
        Write-Host "  Thumbprint  : $($cert.Thumbprint)" -ForegroundColor Gray
        Write-Host "  Valid From  : $($cert.NotBefore.ToString('yyyy-MM-dd')) to $($cert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor Gray
        Write-Host "  Store       : $($group.DestinationStore)" -ForegroundColor Gray

        if ($DryRun) {
            $status = 'DRY RUN - Would create'
            Write-Host "  Status      : $status" -ForegroundColor Yellow
        }
        else {
            # Check for duplicates
            if ($existingNames -contains $policyName) {
                $status = 'SKIPPED - Profile already exists'
                Write-Host "  Status      : $status" -ForegroundColor Yellow
            }
            elseif ($PSCmdlet.ShouldProcess($policyName, 'Create Intune Trusted Certificate Profile')) {
                $response = New-IntuneTrustedCertificateProfile `
                    -DisplayName $policyName `
                    -Description $description `
                    -Certificate $cert `
                    -DestinationStore $group.DestinationStore `
                    -FileName $file.Name

                if ($response) {
                    $status = "CREATED (ID: $($response.id))"
                    Write-Host "  Status      : $status" -ForegroundColor Green
                }
                else {
                    $status = 'FAILED - See error above'
                    Write-Host "  Status      : $status" -ForegroundColor Red
                }
            }
        }

        $results.Add([PSCustomObject]@{
            Type       = $group.Label
            File       = $file.Name
            PolicyName = $policyName
            Status     = $status
            Thumbprint = $cert.Thumbprint
        })

        $cert.Dispose()
        Write-Host ''
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$results | Format-Table -AutoSize -Property Type, File, PolicyName, Status

$created  = @($results | Where-Object { $_.Status -like 'CREATED*' }).Count
$skipped  = @($results | Where-Object { $_.Status -like 'SKIPPED*' }).Count
$failed   = @($results | Where-Object { $_.Status -like 'FAILED*' }).Count
$dryCount = @($results | Where-Object { $_.Status -like 'DRY RUN*' }).Count

if ($DryRun) {
    Write-Host "Dry Run: $dryCount policy/policies would be created.`n" -ForegroundColor Yellow
}
else {
    Write-Host "Created: $created | Skipped: $skipped | Failed: $failed`n" -ForegroundColor Cyan
}

#endregion
