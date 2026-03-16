# Winget & C# Executable (abandoned)

The C# implementation was replaced with PowerShell so coworkers receive source code they can debug with AI if problems arise. AI is also better at writing PowerShell than C#. Running a `.cs` file directly was considered but cannot be deployed via winget either.

## Building the Executable

Requires .NET 8 SDK. The PowerShell script needs no build step.

```
dotnet publish src/resolution_suggester.csproj -c Release -o publish
```

Produces `publish\resolution_suggester.exe` (pass `-o publish` as shown above).

The test project (`tests/`) does not use a `<ProjectReference>` to the main project. The main project publishes as a self-contained single-file executable, and .NET SDK error NETSDK1151 prohibits a non-self-contained project from referencing a self-contained one. Instead, the test runner locates the built exe by convention at `src/bin/Release/net8.0-windows/win-x64/resolution_suggester.exe`. Build the main project before running tests.

## Winget Install

Winget does not support delivering PowerShell scripts directly, so a new packaging approach is needed before winget installs can resume. The C# implementation has been removed, so the release workflow also needs to be rewritten for PS1-only distribution.

```
winget install DigitalForcesCorp.ResolutionSuggester
```

Submission status: [PR #348697](https://github.com/microsoft/winget-pkgs/pull/348697#issuecomment-4061030437), [validation build](https://dev.azure.com/shine-oss/winget-pkgs/_build/results?buildId=280104&view=results).

Self-contained executable install:

```
curl.exe -Lo c:\dfc\scripts\resolution_suggester.exe https://github.com/Digital-Forces-Corp/resolution_suggester/releases/latest/download/resolution_suggester.exe
```

## Release Workflow

Pushing a `v*` tag triggers the [release workflow](.github/workflows/release.yml), which:

1. Validates the tag format (`v*.*.*`)
2. Builds the project on `windows-latest`
3. Runs the test suite
4. Publishes the self-contained executable and verifies it exists
5. Creates a GitHub Release with auto-generated release notes and the `.exe` attached
6. Submits the new version to winget via `winget-releaser` (requires `WINGET_TOKEN` GitHub repository secret)

The package uses `InstallerType: portable` (bare `.exe`, no installer). Reference packages with the same pattern:

- [7zip.7zr](https://github.com/microsoft/winget-pkgs/tree/master/manifests/7/7zip/7zr)
- [Ahoy.Ahoy](https://github.com/microsoft/winget-pkgs/tree/master/manifests/a/Ahoy/Ahoy)
- [pnpm.pnpm](https://github.com/microsoft/winget-pkgs/tree/master/manifests/p/pnpm/pnpm)

## Winget Validation Timing

Observed wingetbot "run" to "Validation-Completed" label durations (March 2026):

- New version PRs: 3\-4 hours (Wasmtime.Portable #342512, #342914)
- New package PRs: 8\-18 hours (#348596, #348292, #348215, #348209)

The Installation Verification step reports "InProgress" every ~50 minutes during validation. New version PRs (Wasmtime.Portable) received "Validation-Completed" within the same day; new package PRs took overnight.

```
git tag v1.2.0
git push origin v1.2.0
```
