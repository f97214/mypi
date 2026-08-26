## ADDED Requirements

### Requirement: Dual-mode invocation

The installer script at scripts/install.ps1 SHALL support two invocation modes: parameter mode and interactive mode. When any of -Version or -LocalPath is supplied, the installer SHALL run in parameter mode and MUST NOT display the interactive menu. When neither is supplied, the installer SHALL display an interactive source-selection menu. Supplying both -Version and -LocalPath SHALL terminate with a mutually-exclusive-parameters error before performing any download, copy, or PATH change.

#### Scenario: Parameter mode runs without the menu

- **WHEN** the user runs install.ps1 with -LocalPath pointing at a valid zip
- **THEN** the installer installs directly without displaying the interactive menu

#### Scenario: No parameters opens the interactive menu

- **WHEN** the user runs install.ps1 with no arguments in an interactive console
- **THEN** a numbered menu is displayed offering: latest GitHub Release, specific GitHub Release version, local zip file, and local directory

#### Scenario: Mutually exclusive parameters are rejected

- **GIVEN** both -Version "0.84.3" and -LocalPath "C:\pi\pi-windows-x64.zip" are supplied
- **WHEN** the installer starts
- **THEN** it exits with an error naming the conflicting parameters and performs no filesystem changes

### Requirement: Interactive menu flow

In interactive mode the installer SHALL prompt for all required decisions with a visible default that is accepted by pressing Enter. For local-source choices it SHALL prompt for a path, re-prompting on invalid input instead of terminating. For remote-source choices it SHALL resolve the version (latest release by default, or the entered version string). It SHALL then show the resolved install directory (default %LOCALAPPDATA%\Programs\pi) and accept Enter to confirm.

#### Scenario: Menu selection with default answer

- **WHEN** the user presses Enter at the source menu
- **THEN** the latest GitHub Release option is selected

##### Example: default menu choice

- **GIVEN** the menu prompt "[1] Latest release  [2] Specific version  [3] Local zip  [4] Local directory" and the user types nothing but Enter
- **WHEN** the installer reads the selection
- **THEN** it proceeds with option 1 and resolves the version via the GitHub latest-release API

#### Scenario: Invalid local path re-prompts

- **GIVEN** the user selected the local-zip option
- **WHEN** the user enters a path where no file exists
- **THEN** the installer prints an error describing the expected input and prompts again rather than exiting

#### Scenario: Install directory confirmation

- **WHEN** the installer shows the install-directory prompt
- **THEN** the default value %LOCALAPPDATA%\Programs\pi is shown and pressing Enter accepts it

##### Example: install directory prompt

| Input | Resulting InstallDir | Notes |
| ----- | -------------------- | ----- |
| Enter (empty) | %LOCALAPPDATA%\Programs\pi | default accepted |
| C:\tools\pi | C:\tools\pi | custom path used as-is |
| (empty, with -InstallDir C:\tools\pi supplied) | C:\tools\pi | parameter value becomes the shown default |

### Requirement: Remote installation from GitHub Releases

Remote mode SHALL detect the CPU architecture (x64 or arm64), download pi-windows-<arch>.zip and the release's SHA256SUMS from the fork's GitHub Releases for the resolved version, verify the zip's SHA256 against SHA256SUMS, and extract the archive root contents into the install directory. If the requested release or its Windows asset does not exist, the installer SHALL fail with a message explaining that no release assets are available yet and pointing to npm or local installation as alternatives.

#### Scenario: Latest release install succeeds

- **WHEN** the user selects latest-release install and the fork has published a release containing pi-windows-x64.zip and SHA256SUMS
- **THEN** the zip is downloaded, its hash matches SHA256SUMS, and its contents are extracted into the install directory

#### Scenario: Hash mismatch aborts install

- **GIVEN** a downloaded zip whose SHA256 does not match the SHA256SUMS entry
- **WHEN** verification runs
- **THEN** the installer deletes the downloaded file, exits with a checksum-mismatch error, and writes nothing into the install directory

#### Scenario: No published release assets

- **WHEN** the fork has no releases matching the requested version or lacks Windows assets
- **THEN** the installer exits with an error stating that release assets are unavailable and suggesting npm or local installation

##### Example: missing release cases

| Requested version | Release state | Expected outcome |
| ----------------- | ------------- | ---------------- |
| (none, latest) | repo has zero releases | error: no release assets available yet; suggests npm or local install; exit code non-zero |
| v0.84.3 | release exists but has no pi-windows-x64.zip asset | error: Windows asset missing for v0.84.3; suggests npm or local install; exit code non-zero |
| v0.99.0 | no such release tag | error: release v0.99.0 not found; suggests npm or local install; exit code non-zero |

### Requirement: Local installation from build output

The installer SHALL accept -LocalPath with either of the two artifacts produced by scripts/build-binaries.sh --platform windows-x64: the zip archive pi-windows-x64.zip, or the extracted directory windows-x64/. For a zip, the installer SHALL extract the archive root into the install directory. For a directory, the installer SHALL copy its contents recursively into the install directory. Both paths MUST first verify that the content contains pi.exe; if not, the installer SHALL exit with an error that names the build command to produce valid output. Local mode MUST NOT perform hash verification because build-binaries.sh generates no checksum file.

#### Scenario: Install from local zip

- **GIVEN** packages/coding-agent/binaries/pi-windows-x64.zip exists and contains pi.exe at the archive root
- **WHEN** the user runs install.ps1 -LocalPath <zip path>
- **THEN** the archive contents are extracted into the install directory and pi.exe is present there afterwards

#### Scenario: Install from extracted directory

- **GIVEN** packages/coding-agent/binaries/windows-x64/ contains pi.exe plus runtime assets
- **WHEN** the user runs install.ps1 -LocalPath <directory path>
- **THEN** the directory contents are copied recursively into the install directory

#### Scenario: Content without pi.exe is rejected

- **GIVEN** the -LocalPath target contains no pi.exe (for example an empty folder)
- **WHEN** validation runs
- **THEN** the installer exits with an error that includes the build command scripts/build-binaries.sh --platform windows-x64

### Requirement: User PATH registration

After a successful install, unless -NoPath is supplied, the installer SHALL add the install directory to the user-scope PATH environment variable when it is not already present, leaving existing PATH entries unchanged, and print how to make the change effective in open shells. When the directory is already on the user PATH, the installer MUST NOT modify the PATH value.

#### Scenario: PATH updated after install

- **GIVEN** the install directory is not on the user PATH
- **WHEN** installation completes without -NoPath
- **THEN** the user-scope PATH gains exactly one new entry pointing at the install directory and pre-existing entries are preserved

#### Scenario: PATH already contains install directory

- **GIVEN** the install directory already appears on the user PATH
- **WHEN** installation completes
- **THEN** the user PATH value is left byte-for-byte unchanged

#### Scenario: -NoPath skips PATH changes

- **WHEN** the user supplies -NoPath
- **THEN** the installer completes the file installation but never reads or writes the PATH environment variable

##### Example: PATH untouched with -NoPath

- **GIVEN** the user-scope PATH is "C:\Windows\system32;C:\tools" and the install directory is %LOCALAPPDATA%\Programs\pi
- **WHEN** the user runs install.ps1 -LocalPath <zip> -NoPath and installation completes
- **THEN** the user-scope PATH is still exactly "C:\Windows\system32;C:\tools" and pi.exe exists in the install directory

### Requirement: Build from source

The interactive menu SHALL offer a build-from-source choice (option 5) that builds pi from a local repository checkout and installs the result. When selected, the installer SHALL resolve the repository root — defaulting to the installer's parent directory when it contains package.json and packages/coding-agent, otherwise prompting and re-prompting until a valid root is given — verify that node, npm, and bun are available (terminating with an install hint naming the missing tool when not), build via npm ci --ignore-scripts (only when node_modules is absent), npm run build:offline, and bun build --compile for the detected architecture into packages/coding-agent/binaries/windows-<arch>/, stage the runtime assets into that directory with the same layout as the scripts/build-binaries.sh windows output, and then install the staged directory through the existing directory-install path.

#### Scenario: Menu option 5 with repository auto-detected

- **GIVEN** install.ps1 is executed from a repository checkout (scripts/ inside the repo)
- **WHEN** the user selects option 5 and presses Enter at the repository-path prompt
- **THEN** the repository root is resolved from the script location and the build starts without further path input

##### Example: repository path resolution

| Script location | Repo layout check | Resulting repo root |
| --------------- | ----------------- | ------------------- |
| D:\repo\scripts\install.ps1 | D:\repo has package.json and packages\coding-agent | D:\repo (default, Enter accepts) |
| (piped via irm \| iex, no script location) | n/a | prompt until a valid root is entered |

#### Scenario: Missing build tool is reported with a hint

- **GIVEN** bun is not on PATH
- **WHEN** the user selects option 5
- **THEN** the installer exits non-zero with an error naming bun and pointing to its install source, and no build or install step runs

#### Scenario: Build output is installed automatically

- **GIVEN** the build completes and produced packages/coding-agent/binaries/windows-<arch>/pi.exe plus staged assets
- **WHEN** the build step finishes
- **THEN** the staged directory is installed into the install directory (pi.exe present afterwards) without re-prompting for the source path

### Requirement: Context menu integration

The installer SHALL be able to register an "Open with MYPI" (用 MYPI 開啟) Explorer context-menu entry for the current user by writing registry keys under HKCU\Software\Classes\Directory\shell\mypi (right-click on a folder, target %1) and HKCU\Software\Classes\Directory\Background\shell\mypi (right-click on empty space inside a folder, target %V), each with the display name, an Icon pointing at the installed pi.exe, and a command that launches the newest installed PowerShell (pwsh 7 preferred, Windows PowerShell as fallback, path baked in at registration time) with a Set-Location to the target directory followed by pi.exe. Registration SHALL be triggered by the -ContextMenu switch in parameter mode, or by an interactive confirmation prompt (defaulting to yes) after a successful install in interactive mode. The -RemoveContextMenu switch SHALL delete both keys; -ContextMenu and -RemoveContextMenu together SHALL be rejected as mutually exclusive. Registration SHALL be idempotent: re-registering overwrites the same keys. The entry appears in the classic context menu (on Windows 11 under "Show more options"); the installer output SHALL note this when registering.

#### Scenario: Register context menu with -ContextMenu

- **WHEN** the user runs install.ps1 -ContextMenu (with an install source) and installation succeeds
- **THEN** both HKCU\Software\Classes\Directory\shell\mypi and HKCU\Software\Classes\Directory\Background\shell\mypi exist with the display name, pi.exe icon, and a command containing the detected PowerShell path, the target placeholder, and pi.exe

##### Example: command shape per key

| Key | Command contains |
| --- | ---------------- |
| Directory\shell\mypi\command | Set-Location -LiteralPath '%1' and the pi.exe path |
| Directory\Background\shell\mypi\command | Set-Location -LiteralPath '%V' and the pi.exe path |

#### Scenario: PowerShell detection prefers pwsh 7

- **GIVEN** the machine has both pwsh 7 and Windows PowerShell installed
- **WHEN** context-menu registration resolves the shell
- **THEN** the baked command uses the pwsh.exe path

#### Scenario: Windows PowerShell fallback

- **GIVEN** pwsh 7 is not installed
- **WHEN** context-menu registration resolves the shell
- **THEN** the baked command uses the Windows PowerShell powershell.exe path

#### Scenario: Interactive prompt after install

- **GIVEN** an interactive-mode install completed
- **WHEN** the installer asks about context-menu registration
- **THEN** pressing Enter (default) registers the entry and answering no skips it without errors

#### Scenario: Remove context menu

- **WHEN** the user runs install.ps1 -RemoveContextMenu
- **THEN** both registry keys are deleted (a missing key is not an error), the installer exits 0, and the output confirms removal

#### Scenario: Mutually exclusive context-menu switches

- **WHEN** the user supplies both -ContextMenu and -RemoveContextMenu
- **THEN** the installer exits non-zero naming the conflicting switches and changes nothing

##### Example: conflicting context-menu switches

- **GIVEN** the user runs install.ps1 -LocalPath C:\pi\pi-windows-x64.zip -ContextMenu -RemoveContextMenu
- **WHEN** parameter validation runs
- **THEN** the installer exits non-zero, reports both -ContextMenu and -RemoveContextMenu, and does not change files or registry keys

### Requirement: Post-install guidance

On successful completion the installer SHALL print next-step instructions covering starting pi in a project directory and authenticating via /login or an API key environment variable.

#### Scenario: Success summary printed

- **WHEN** installation finishes successfully
- **THEN** the output includes how to start pi and how to authenticate (/login or API key)

##### Example: success output

- **GIVEN** pi 0.84.3 was installed to %LOCALAPPDATA%\Programs\pi
- **WHEN** the installer finishes
- **THEN** the output contains the install path, a start hint equivalent to "cd to your project directory and run pi", and an auth hint equivalent to "run /login or set an API key environment variable such as ANTHROPIC_API_KEY"
