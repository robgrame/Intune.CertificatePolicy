# Intune.CertificatePolicy

PowerShell toolkit to **deploy** and **verify** Intune Trusted Certificate profiles for Root and Subordinate CA certificates using the Microsoft Graph API.

> Manage your PKI trust chain in Intune at scale — import certificates with a consistent naming convention and audit what's already deployed.

## Overview

| Script | Description |
|---|---|
| [`New-IntuneCertificatePolicy.ps1`](#new-intunecertificatepolicyps1) | Bulk-create Intune Trusted Certificate profiles from `.cer` / `.crt` files |
| [`Test-IntuneCertificatePolicy.ps1`](#test-intunecertificatepolicyps1) | Audit local certificates against deployed Intune profiles (content-based matching) |

### Typical workflow

```
1. Collect Root & Subordinate CA certificates (.cer / .crt)
2. Run Test-IntuneCertificatePolicy  →  identify what's missing
3. Run New-IntuneCertificatePolicy   →  deploy missing certificates (with -DryRun first)
4. Run Test-IntuneCertificatePolicy  →  confirm everything is deployed ✅
```

## Prerequisites

- **PowerShell 7+**
- [**Microsoft Graph PowerShell SDK**](https://learn.microsoft.com/en-us/powershell/microsoftgraph/installation)

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

## Quick start

```powershell
# 1. Check which certificates are already deployed
.\Test-IntuneCertificatePolicy.ps1 -CertificatePaths ".\RootCAs", ".\SubCAs"

# 2. Preview what would be created
.\New-IntuneCertificatePolicy.ps1 -Prefix "CORP" `
    -RootCACertsPath ".\RootCAs" `
    -SubordinateCACertsPath ".\SubCAs" `
    -DryRun

# 3. Create the profiles
.\New-IntuneCertificatePolicy.ps1 -Prefix "CORP" `
    -RootCACertsPath ".\RootCAs" `
    -SubordinateCACertsPath ".\SubCAs"
```

---

## New-IntuneCertificatePolicy.ps1

Reads certificates from Root CA and Subordinate CA folders, extracts the CA name from the certificate subject (CN), and creates Intune Trusted Certificate profiles with a standardized naming convention.

### Features

- 📂 Reads `.cer` and `.crt` certificate files
- 🏷️ Naming convention: **`{Prefix} - {CA Name from Subject CN}`**
- 🔒 Root CAs → `computerCertStoreRoot` · Subordinate CAs → `computerCertStoreIntermediate`
- 🔍 Automatic duplicate detection — skips profiles that already exist
- 🧪 **Dry-run mode** (`-DryRun`) to preview without changes

### Parameters

| Parameter | Required | Description |
|---|---|---|
| `-Prefix` | ✅ | Naming prefix for all Intune policies (e.g. `CORP`, `ISP`) |
| `-RootCACertsPath` | ✅ | Folder containing Root CA certificate files |
| `-SubordinateCACertsPath` | ✅ | Folder containing Subordinate CA certificate files |
| `-DryRun` | ❌ | Preview mode — no changes are made |

### Example

```powershell
.\New-IntuneCertificatePolicy.ps1 -Prefix "CORP" `
    -RootCACertsPath ".\RootCAs" `
    -SubordinateCACertsPath ".\SubCAs" `
    -DryRun
```

```
========================================
 Intune Certificate Policy Creator
========================================
[DRY RUN] No changes will be made.

Processing Root CA certificates from: .\RootCAs
------------------------------------------------------------
  Certificate : ContosoRootCA.cer
  CA Name     : Contoso Root CA - Root 01
  Policy Name : CORP - Contoso Root CA - Root 01
  Thumbprint  : B532ACDB5BC16795449F3D61F158F89811BB4CF6
  Store       : computerCertStoreRoot
  Status      : DRY RUN - Would create
```

---

## Test-IntuneCertificatePolicy.ps1

Scans local certificate files and verifies whether they are already deployed as Intune Trusted Certificate profiles. Uses **content-based matching** to ensure accuracy regardless of file or policy name.

### Features

- 🔎 Compares local certificates against all Intune Trusted Certificate profiles
- 🧬 **Two-stage matching**: thumbprint match (fast) → byte-for-byte fallback (exact)
- ✅ Clear status per certificate: **DEPLOYED** or **MISSING**
- ⏭️ Skips expired certificates by default (use `-IncludeExpired` to include)
- 📊 Summary report with actionable output

### Parameters

| Parameter | Required | Description |
|---|---|---|
| `-CertificatePaths` | ✅ | One or more folders containing certificates to verify |
| `-IncludeExpired` | ❌ | Include expired certificates in the report |

### Example

```powershell
.\Test-IntuneCertificatePolicy.ps1 -CertificatePaths ".\RootCAs", ".\SubCAs"
```

```
============================================
 Intune Certificate Policy Verification
============================================

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

---

## Required permissions

| Script | Microsoft Graph Permission | Access |
|---|---|---|
| `New-IntuneCertificatePolicy.ps1` | `DeviceManagementConfiguration.ReadWrite.All` | Read + Write |
| `Test-IntuneCertificatePolicy.ps1` | `DeviceManagementConfiguration.Read.All` | Read only |

The interactive login (`Connect-MgGraph`) will prompt for consent if not already granted.

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

## License

This project is licensed under the [MIT License](LICENSE).
