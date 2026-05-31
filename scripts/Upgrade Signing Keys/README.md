# Upgrade-SigningKey.ps1

Guided 7-step PowerShell script that upgrades a Microsoft Entra Verified ID authority's signing key from **P-256K (secp256k1)** to **P-256 (NIST)** to achieve FIPS compliance.

Reference: [Upgrading the signing key](https://learn.microsoft.com/en-us/entra/verified-id/signing-key-upgrade#upgrading-the-signing-key)

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **PowerShell** | PowerShell 7+ required (`pwsh`). Windows PowerShell 5.1 is **not supported** — its UTF-8 encoding includes a BOM that corrupts DID documents. Install from https://aka.ms/install-powershell |
| **MSAL.PS module** | Installed automatically if missing |
| **App registration** | Must have `Verifiable Credentials Service Admin` API permission (`6a8b4b39-c021-437c-b060-5a14a3fd65f3/full_access`). Under **Authentication → Advanced settings**, set **Allow public client flows** to **Yes** (required for interactive and device-code login). |
| **Key Vault access** | The signing-in user must have permission to create keys in the authority's Key Vault |
| **Web server access** | Ability to deploy files to `https://<your-domain>/.well-known/` |

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-TenantId` | No* | Entra tenant ID or domain (e.g. `contoso.onmicrosoft.com`). Prompted if omitted. |
| `-ClientId` | No* | App registration client ID. Prompted if omitted. |
| `-AuthorityId` | No | Authority ID (GUID) to upgrade. If omitted, the script lists all authorities and lets you choose. Can use `-Did` instead. |
| `-Did` | No | DID string (e.g. `did:web:example.com`) of the authority to upgrade. The script resolves this to the authority ID automatically. |
| `-OutputDir` | No | Directory to save output files. Defaults to current directory. |
| `-StartFromStep` | No | Resume from a specific step (1-7). Defaults to 1. |
| `-UseDeviceCode` | No | Use device-code flow instead of interactive browser login. |

\* You will be prompted interactively if not provided.

## Usage

### Interactive (recommended)

```powershell
.\Upgrade-SigningKey.ps1
```

The script will prompt for tenant ID, client ID, and let you select an authority.
After authentication it presents an **interactive step menu**:

```
  Select which step(s) to run:

    [A] Run ALL steps (from step 1 onward)

    [1] Create a new P-256 signing key in Key Vault
    [2] Generate a new DID document (did.json)
    [3] [Manual] Deploy did.json to web servers
    [4] Synchronize with DID document (start using new key)
    [5] Generate well-known DID configuration (did-configuration.json)
    [6] [Manual] Deploy did-configuration.json to web servers
    [7] Validate well-known DID configuration (linked domain verified)
```

- Choose **A** to run all steps sequentially from the starting step.
- Choose **1–7** to start from a specific step. After each step completes, you are prompted to **continue to the next step or exit**. This makes it easy to resume from any intermediate point.

### With parameters

```powershell
.\Upgrade-SigningKey.ps1 -TenantId "contoso.onmicrosoft.com" -ClientId "00001111-aaaa-2222-bbbb-3333cccc4444"
```

### Fully automated (no authority selection prompt)

```powershell
.\Upgrade-SigningKey.ps1 `
  -TenantId "contoso.onmicrosoft.com" `
  -ClientId "00001111-aaaa-2222-bbbb-3333cccc4444" `
  -AuthorityId "00aa00aa-bb11-cc22-dd33-44ee44ee44ee" `
  -OutputDir "C:\deploy"
```

### Using a DID instead of authority ID

```powershell
.\Upgrade-SigningKey.ps1 `
  -TenantId "contoso.onmicrosoft.com" `
  -ClientId "00001111-aaaa-2222-bbbb-3333cccc4444" `
  -Did "did:web:example.com"
```

### Device-code flow (headless/remote sessions)

```powershell
.\Upgrade-SigningKey.ps1 -UseDeviceCode
```

## The 7 Steps

### Step 1 — Create a new P-256 signing key

**API call**: `POST /v1.0/verifiableCredentials/authorities/{id}/didInfo/signingKeys`

Creates a new P-256 key in the authority's Azure Key Vault. After this step the authority's `didDocumentStatus` becomes `outOfSync` because the new key exists in Key Vault but is not yet in the published DID document.

**Automatic fallbacks:**
- If the create endpoint returns **HTTP 404** (older API), the script falls back to the `/signingKeys/rotate` endpoint.
- If the create endpoint returns **HTTP 400 "Maximum number of signing keys has been reached"** (e.g. a P-256 key already exists from a previous incomplete run), the script also falls back to `/signingKeys/rotate`.

### Step 2 — Generate a new DID document

**API call**: `POST /v1.0/verifiableCredentials/authorities/{id}/generateDidDocument`

Generates a new `did.json` containing **both** the new P-256 key and the old P-256K key. The file is saved to the output directory.

### Step 3 — Deploy did.json *(manual)*

You must deploy the generated `did.json` to your web server at:

```
https://<your-domain>/.well-known/did.json
```

The script prompts whether you have uploaded the file:
- **Yes** — the script sends an HTTP GET to `<domain>/.well-known/did.json` and checks for a 200 OK response. It then asks you to browse to that URL and confirm the new key appears in the `assertionMethod` section.
- **No** — the script waits for you to deploy the file before continuing.

### Step 4 — Synchronize with DID document

**API call**: `POST /v1.0/verifiableCredentials/authorities/{id}/didInfo/synchronizeWithDidDocument`

The service validates that the Key Vault keys and the publicly deployed `did.json` match, then activates the new P-256 key. The `didDocumentStatus` returns to `published`. From this point, new issuance and presentation requests use the P-256 key.

### Step 5 — Generate well-known DID configuration

**API call**: `POST /v1.0/verifiableCredentials/authorities/{id}/generateWellknownDidConfiguration`

Generates a new `did-configuration.json` signed with the P-256 key. This file proves ownership of the linked domain. Saved to the output directory.

### Step 6 — Deploy did-configuration.json *(manual)*

Deploy the generated `did-configuration.json` to:

```
https://<your-domain>/.well-known/did-configuration.json
```

The script prompts whether you have uploaded the file:
- **Yes** — the script sends an HTTP GET to `<domain>/.well-known/did-configuration.json` and checks for a 200 OK response. It then asks you to browse to that URL and confirm the new configuration file is correct.
- **No** — the script waits for you to deploy the file before continuing.

### Step 7 — Validate well-known DID configuration

**API call**: `POST /v1.0/verifiableCredentials/authorities/{id}/validateWellKnownDidConfiguration`

The service downloads and validates the deployed configuration. On success, the linked domain status becomes `verified`.

## Output Files

| File | Location | Purpose |
|------|----------|---------|
| `did.json` | `<OutputDir>/did.json` | DID document with both P-256 and P-256K keys |
| `did-configuration.json` | `<OutputDir>/did-configuration.json` | Linked domain proof signed with P-256 |
| `upgrade-signingkey.log` | `<OutputDir>/upgrade-signingkey.log` | Timestamped log of all actions and outcomes |

## Error Handling & Logging

- **All API calls** (Steps 1, 2, 4, 5, 7) are wrapped in try/catch blocks. On failure, the script displays the error, logs it, and prints a resume command so you can pick up from the failed step.
- **Authentication failures** (MSAL.PS install, token acquisition) are caught with actionable error messages.
- **HTTP verification** in Steps 3 and 6 catches network errors and reports the status without aborting the script.
- **Every action** is written to `upgrade-signingkey.log` with timestamps — including step start/completion, HTTP verification results, user menu choices, and continue/exit decisions.

## Resuming from an Intermediate Step

When you select a specific step (1–7) from the menu, the script runs that step and then prompts:

```
  Step N complete. Continue to Step N+1? [Y/N]
```

- **Y** — proceeds to the next step (with full error handling and logging).
- **N** — exits gracefully. You can resume later with the `-StartFromStep` parameter or by selecting the next step from the menu.

## Rollback

> **Step 4 (Synchronize) is the point of no return.** Before Step 4, the old P-256K key is still the active signing key and no rollback is needed — just stop the script. After Step 4, there is no API-supported way to revert.

| Stopped at | Rollback possible? | What to do |
|------------|-------------------|------------|
| **Before Step 4** | Yes — nothing changed operationally | Stop the script. The new P-256 key exists in Key Vault but is not active. Optionally disable or delete the unused P-256 key version from Key Vault manually (see *Testing Rollback* below). |
| **After Step 4** | No — the service is now signing with P-256 | The Verified ID Admin API has no "revert signing key" endpoint. The `/signingKeys/rotate` endpoint rotates forward, not backward. Contact Microsoft support if you need to revert post-synchronization. |

Previously issued credentials (signed with P-256K) continue to verify after Step 4 because the old key remains in the DID document. Only **new** issuance and presentation operations use the P-256 key.

### Testing Rollback (Before Step 4)

If you want to verify that rollback works before committing to the upgrade, run Steps 1–2 and then follow this procedure:

1. **Note the `didDocumentStatus`** — after Step 1 it should be `outOfSync` (the service knows a new key exists in Key Vault but the DID document hasn't been updated).

2. **Inspect the generated `did.json`** (after Step 2) — confirm it lists both the new P-256 key and the old P-256K key in the `verificationMethod` / `assertionMethod` arrays. This file was only saved locally; nothing was deployed.

3. **Disable (or delete) the new P-256 key version in Key Vault**:
   - Azure Portal → Key Vault used by your authority → Keys
   - Click into the signing key (e.g. `vcSigningKey-<guid>`) → **Versions**
   - The Verified ID service creates the P-256 key as a **new version** of the existing signing key (not a separate key). Identify the current version (most recent creation date) and click into it.
   - Confirm the version shows **Elliptic curve name: P-256** to ensure you have the right one.
   - Set **Enabled** to **No** (or right-click → Disable) and **Save**.
   - Alternatively, if the P-256 key was created as a separate key object, use the **Delete** button in the top navigation bar to remove the entire key.

4. **Re-synchronize to restore `published` status** — re-run the script, select your authority, and choose **Step 4** from the menu. Since the web server still hosts the original `did.json` (P-256K only) and the P-256 key version is disabled/removed, synchronization should bring `didDocumentStatus` back to `published` with only the P-256K key active.

5. **Verify** — confirm `didDocumentStatus` is `published` and test that issuance/presentation still works with P-256K.

6. **Clean up** — delete the local `did.json` generated in Step 2 (it's no longer valid).

> **Tip:** If you only completed Step 1 (never ran Step 2), you can simply disable the Key Vault key version and skip re-synchronizing. The old `did.json` on your server is still valid, and the `outOfSync` status just means Key Vault has keys not reflected in the published DID document — disabling the extra key version resolves the mismatch.

## Post-Upgrade Notes

- New issuance and presentation requests use the P-256 key immediately after Step 4.
- Previously issued credentials (signed with P-256K) continue to verify because the old key remains in the DID document.
- Once all old credentials expire or are reissued, you can remove the old P-256K keys from Key Vault and regenerate `did.json`.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `MSAL.PS` installation fails | Run `Install-Module -Name MSAL.PS -Scope CurrentUser -Force` manually |
| Authentication fails | Verify the app registration has `Verifiable Credentials Service Admin` API permission with admin consent granted |
| Step 3 HTTP check fails | Verify did.json is publicly accessible at the expected URL; check DNS and firewall rules |
| Step 4 fails (`didDocumentStatus` not `published`) | Ensure `did.json` is deployed correctly and publicly accessible at the expected URL |
| Step 6 HTTP check fails | Verify did-configuration.json is publicly accessible at the expected URL |
| Step 7 validation fails | Ensure `did-configuration.json` is accessible at `https://<domain>/.well-known/did-configuration.json` |
| Step 1 fails with "Maximum number of signing keys" | A P-256 key likely already exists from a previous run. The script handles this automatically by falling back to key rotation. If rotation also fails, check the authority's keys in Key Vault. |
| Key Vault access denied | The signed-in user needs Key create/get permissions on the authority's Key Vault |
