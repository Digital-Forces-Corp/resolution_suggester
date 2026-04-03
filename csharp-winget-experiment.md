# Winget & C# Executable (abandoned)

AI is better at writing C# than PowerShell. The C# implementation was replaced with PowerShell so coworkers receive source code they can debug with AI if problems arise.  Running a `.cs` file directly was considered but requires dotnet10.

## Building the Executable

Requires .NET 8 SDK. The PowerShell script needs no build step.

```
dotnet publish src/resolution_suggester.csproj -c Release -o publish
```

Produces `publish\resolution_suggester.exe`.

The test project (`tests/`) does not use a `<ProjectReference>` to the main project. The main project publishes as a self-contained single-file executable, and .NET SDK error NETSDK1151 prohibits a non-self-contained project from referencing a self-contained one. Instead, the test runner locates the built exe by convention at `src/bin/Release/net8.0-windows/win-x64/resolution_suggester.exe`. Build the main project before running tests.

## Winget Install

Winget does not support delivering PowerShell scripts directly, so a new packaging approach is needed before winget installs can resume. The C# implementation has been removed, so the release workflow also needs to be rewritten for PS1-only distribution.

```
winget install DigitalForcesCorp.ResolutionSuggester
```

Self-contained executable install:

```
curl.exe -LO --output-dir c:\dfc\scripts https://github.com/Digital-Forces-Corp/resolution_suggester/releases/latest/download/resolution_suggester.exe
```

## Release Workflow

The old GitHub Actions release workflow has been removed from `.github/workflows` because it now fails on every tagged push: it still expects the deleted `src/resolution_suggester.csproj` project and the old `.exe` publishing flow. The last workflow YAML is preserved here as historical reference.

What it used to do:

1. Validate the tag format (`v*.*.*`).
2. Build the C# project on `windows-latest`.
3. Run the test suite.
4. Publish the self-contained executable and verify it exists.
5. Create a GitHub Release with auto-generated notes and the `.exe` attached.

Archived workflow YAML:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write  # needed for softprops/action-gh-release to create releases

jobs:
  release:
    runs-on: windows-latest
    outputs:
      version: ${{ steps.version.outputs.version }}
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4

      - name: Validate tag format
        id: version
        shell: bash
        run: |
          if [[ ! "$GITHUB_REF_NAME" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "ERROR: Tag '$GITHUB_REF_NAME' does not match expected format v*.*.*"
            exit 1
          fi
          echo "version=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"

      - uses: actions/setup-dotnet@3e891b0cb619bf60e2c25674b222b8940e2c1c25 # v4
        with:
          dotnet-version: '8.0.x'

      - name: Build
        run: dotnet build src/resolution_suggester.csproj -c Release

      - name: Test
        run: dotnet run --project tests/ResolutionSuggesterTests.csproj -c Release

      - name: Publish
        run: dotnet publish src/resolution_suggester.csproj -c Release --no-build -o publish

      - name: Verify published executable
        shell: bash
        run: test -f publish/resolution_suggester.exe || (echo "ERROR: publish/resolution_suggester.exe not found" && exit 1)

      - name: Create GitHub Release
        uses: softprops/action-gh-release@c062e08bd532815e2082a1c180f2aa45f82c0b72 # v2
        with:
          files: publish/resolution_suggester.exe
          generate_release_notes: true
```

The package uses `InstallerType: portable` (bare `.exe`, no installer). Reference packages with the same pattern:

- [7zip.7zr](https://github.com/microsoft/winget-pkgs/tree/master/manifests/7/7zip/7zr)
- [Ahoy.Ahoy](https://github.com/microsoft/winget-pkgs/tree/master/manifests/a/Ahoy/Ahoy)
- [pnpm.pnpm](https://github.com/microsoft/winget-pkgs/tree/master/manifests/p/pnpm/pnpm)

## [PR #348697](https://github.com/microsoft/winget-pkgs/pull/348697) Timeline

| Time (CT) | Duration | Event |
|---|---|---|
| Mar 14 12:20 PM | — | PR submitted |
| Mar 14 12:21 PM | 1 min | Copilot work started |
| Mar 14 12:38 PM | 17 min | msftrubengu comment, wingetbot picked up |
| Mar 14 12:52 PM | 14 min | `New-Package` label applied |
| Mar 15 12:42 AM | 11 h 50 min | `Azure-Pipeline-Passed`, `Validation-Completed` |
| Mar 15 12:43 AM | 1 min | Auto-squash enabled |
| Mar 16 5:36 PM | 40 h 53 min | @stephengillie manual validation and approval |
| Mar 16 5:36 PM | 0 min | `Moderator-Approved`, merged to master |
| Mar 16 5:37 PM | 1 min | Post-merge validation completed |
| Mar 16 6:18 PM | 41 min | Source branch deleted |

Total: ~53 hours submit-to-merge. ~12 hours automated validation, ~41 hours waiting for manual review.

### Observations

`Get-ARPTable` is a custom function in winget-pkgs' [SandboxTest.ps1](https://github.com/microsoft/winget-pkgs/blob/master/Tools/SandboxTest.ps1) (not a built-in cmdlet). It reads the four Windows Uninstall registry paths and returns `DisplayName`, `DisplayVersion`, `Publisher`, `ProductCode`, `Scope`. The automated pipeline uses it to diff ARP entries before/after install.

The moderator ran `resolution_suggester.exe --version` during manual validation. Winget does **not** formally require `--version` — the automated pipeline only checks that the exe exists and that ARP entries register correctly. However, the [ManualValidationPipeline.ps1](https://github.com/microsoft/winget-pkgs/tree/main/Tools/ManualValidation/ManualValidationPipeline.ps1) shows moderators optionally running `--version` as an ad-hoc cross-check. The exe ignored the flag and ran normally, printing monitor suggestions. If the exe had waited for interactive input instead, the validation could have hung indefinitely.

## Winget Validation Timing

Observed wingetbot "run" to "Validation-Completed" label durations (as of March 2026):

- New version PRs: 3 to 4 hours (Wasmtime.Portable `#342512`, `#342914`)
- New package PRs: 8 to 18 hours (`#348596`, `#348292`, `#348215`, `#348209`)

The Installation Verification step reports "InProgress" every ~50 minutes during validation. New version PRs (Wasmtime.Portable) received "Validation-Completed" within the same day; new package PRs took overnight.

```
git tag v1.2.0
git push origin v1.2.0
```
