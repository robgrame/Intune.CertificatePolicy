# Intune.CertificatePolicy

PowerShell script to bulk-create **Intune Trusted Certificate profiles** from Root CA and Subordinate CA certificate files via the Microsoft Graph API.

## Scripts

| Script | Purpose |
|---|---|
| `New-IntuneCertificatePolicy.ps1` | Bulk-create Intune Trusted Certificate profiles |
| `Test-IntuneCertificatePolicy.ps1` | Verify if local certificates are already deployed in Intune |

## Features

### New-IntuneCertificatePolicy

- 📂 Reads `.cer` and `.crt` certificates from Root CA and Subordinate CA folders
- 🏷️ Automatic naming convention: `{Prefix} - {CA Name from Subject CN}`
- 🔒 Root CAs → `computerCertStoreRoot`, Subordinate CAs → `computerCertStoreIntermediate`
- 🔍 Duplicate detection — skips profiles that already exist in Intune
- 🧪 **Dry-run mode** to preview changes without creating anything
- 🔑 Interactive authentication via Microsoft Graph (`Connect-MgGraph`)

### Test-IntuneCertificatePolicy

- 🔎 Scans local certificate files and compares against all Intune Trusted Certificate profiles
- 🧬 **Content-based matching** — compares raw certificate bytes (thumbprint + byte-for-byte fallback)
- ✅ Reports which certificates are **deployed** and which are **missing**
- ⏭️ Optionally skips expired certificates (use `-IncludeExpired` to include them)
- 📊 Summary report with actionable output

## Prerequisites

- PowerShell 7+
- [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/installation)

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

## Usage

### Dry Run (preview only)

```powershell
.\New-IntuneCertificatePolicy.ps1 `
    -Prefix "CORP" `
    -RootCACertsPath ".\Certificates\RootCAs" `
    -SubordinateCACertsPath ".\Certificates\SubCAs" `
    -DryRun
```

### Create profiles

```powershell
.\New-IntuneCertificatePolicy.ps1 `
    -Prefix "CORP" `
    -RootCACertsPath ".\Certificates\RootCAs" `
    -SubordinateCACertsPath ".\Certificates\SubCAs"
```

### Example output

```
========================================
 Intune Certificate Policy Creator
========================================

Processing Root CA certificates from: .\Certificates\RootCAs
------------------------------------------------------------
  Certificate : ContosoRootCA.cer
  CA Name     : Contoso Root CA - Root 01
  Policy Name : CORP - Contoso Root CA - Root 01
  Thumbprint  : B532ACDB5BC16795449F3D61F158F89811BB4CF6
  Store       : computerCertStoreRoot
  Status      : CREATED (ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
```

### Verify deployed certificates

```powershell
.\Test-IntuneCertificatePolicy.ps1 -CertificatePaths ".\RootCAs", ".\SubCAs"
```

### Verify including expired certificates

```powershell
.\Test-IntuneCertificatePolicy.ps1 -CertificatePaths ".\RootCAs" -IncludeExpired
```

### Example verification output

```
Scanning certificates in: .\RootCAs
------------------------------------------------------------
  ✅ ContosoRootCA.cer
     CA Name    : Contoso Root CA - Root 01
     Thumbprint : B532ACDB5BC16795449F3D61F158F89811BB4CF6
     Status     : DEPLOYED
     Policy     : CORP - Contoso Root CA - Root 01
     Match      : Thumbprint

  ❌ NewRootCA.cer
     CA Name    : New Root CA
     Status     : MISSING

Total: 2 | Deployed: 1 | Missing: 1 | Errors: 0
```

## Parameters

### New-IntuneCertificatePolicy

| Parameter | Required | Description |
|---|---|---|
| `-Prefix` | ✅ | Naming prefix for all Intune policies |
| `-RootCACertsPath` | ✅ | Folder containing Root CA certificates |
| `-SubordinateCACertsPath` | ✅ | Folder containing Subordinate CA certificates |
| `-DryRun` | ❌ | Preview mode — no changes are made |

### Test-IntuneCertificatePolicy

| Parameter | Required | Description |
|---|---|---|
| `-CertificatePaths` | ✅ | One or more folders containing certificates to verify |
| `-IncludeExpired` | ❌ | Include expired certificates in the check |

## Required Permissions

| Script | Permission |
|---|---|
| `New-IntuneCertificatePolicy.ps1` | `DeviceManagementConfiguration.ReadWrite.All` |
| `Test-IntuneCertificatePolicy.ps1` | `DeviceManagementConfiguration.Read.All` |

The interactive login will prompt for consent if not already granted.

## License

[MIT](LICENSE)
