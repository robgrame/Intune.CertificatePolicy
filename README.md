# Intune.CertificatePolicy

PowerShell script to bulk-create **Intune Trusted Certificate profiles** from Root CA and Subordinate CA certificate files via the Microsoft Graph API.

## Features

- 📂 Reads `.cer` and `.crt` certificates from Root CA and Subordinate CA folders
- 🏷️ Automatic naming convention: `{Prefix} - {CA Name from Subject CN}`
- 🔒 Root CAs → `computerCertStoreRoot`, Subordinate CAs → `computerCertStoreIntermediate`
- 🔍 Duplicate detection — skips profiles that already exist in Intune
- 🧪 **Dry-run mode** to preview changes without creating anything
- 🔑 Interactive authentication via Microsoft Graph (`Connect-MgGraph`)

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

## Parameters

| Parameter | Required | Description |
|---|---|---|
| `-Prefix` | ✅ | Naming prefix for all Intune policies |
| `-RootCACertsPath` | ✅ | Folder containing Root CA certificates |
| `-SubordinateCACertsPath` | ✅ | Folder containing Subordinate CA certificates |
| `-DryRun` | ❌ | Preview mode — no changes are made |

## Required Permissions

The script requires the following Microsoft Graph permission:

- `DeviceManagementConfiguration.ReadWrite.All`

The interactive login will prompt for consent if not already granted.

## License

[MIT](LICENSE)
