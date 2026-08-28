[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Owner,

    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [Parameter(Mandatory = $true)]
    [string]$Branch,

    [Parameter(Mandatory = $true)]
    [string]$GithubToken,

    [Parameter(Mandatory = $true)]
    [string]$KeystorePath,

    [Parameter(Mandatory = $true)]
    [string]$KeystorePassword,

    [Parameter(Mandatory = $true)]
    [string]$KeyAlias,

    [Parameter(Mandatory = $true)]
    [string]$KeyPassword,

    [Parameter(Mandatory = $true)]
    [string]$MsixPfxPath,

    [Parameter(Mandatory = $true)]
    [string]$MsixPfxPassword,

    [Parameter(Mandatory = $true)]
    [string]$ArtifactDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BuildRoot = "C:\ToastyBuild"
$RepositoryRoot = Join-Path $BuildRoot "repositories\$Owner\$Repository"

Write-Host ""
Write-Host "========================================"
Write-Host "Toasty Windows Build"
Write-Host "========================================"
Write-Host "Repository: $Owner/$Repository"
Write-Host "Branch:     $Branch"
Write-Host "========================================"
Write-Host ""

# Prepare directories

New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $RepositoryRoot) | Out-Null
New-Item -ItemType Directory -Force -Path $ArtifactDirectory | Out-Null

# Git authentication

Write-Host "Configuring temporary GitHub authentication..."

$CredentialHelper = Join-Path $BuildRoot "git-credentials"

"https://x-access-token:$GithubToken@github.com" |
        Set-Content -Path $CredentialHelper -Encoding UTF8

git config --global credential.helper `
    "store --file=$CredentialHelper"

# Clone or update repository

if (Test-Path (Join-Path $RepositoryRoot ".git")) {

    Write-Host "Repository already exists."
    Write-Host "Updating repository..."

    Push-Location $RepositoryRoot

    try {
        git fetch origin $Branch

        if ($LASTEXITCODE -ne 0) {
            throw "git fetch failed."
        }

        git checkout $Branch

        if ($LASTEXITCODE -ne 0) {
            throw "git checkout failed."
        }

        git reset --hard "origin/$Branch"

        if ($LASTEXITCODE -ne 0) {
            throw "git reset failed."
        }

        git clean -fd

        if ($LASTEXITCODE -ne 0) {
            throw "git clean failed."
        }
    }
    finally {
        Pop-Location
    }

}
else {

    Write-Host "Repository does not exist."
    Write-Host "Cloning repository..."

    git clone `
        --branch $Branch `
        "https://github.com/$Owner/$Repository.git" `
        $RepositoryRoot

    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed."
    }
}

# Build

Push-Location $RepositoryRoot

try {

    Write-Host ""
    Write-Host "Repository ready:"
    Write-Host $RepositoryRoot
    Write-Host ""

    # Android signing

    Write-Host "Building signed Android APK and AAB..."

    .\gradlew.bat `
        :app:androidApp:assembleRelease `
        :app:androidApp:bundleRelease `
        "-Pandroid.injected.signing.store.file=$KeystorePath" `
        "-Pandroid.injected.signing.store.password=$KeystorePassword" `
        "-Pandroid.injected.signing.key.alias=$KeyAlias" `
        "-Pandroid.injected.signing.key.password=$KeyPassword" `
        --stacktrace

    if ($LASTEXITCODE -ne 0) {
        throw "Android build failed."
    }

    # Locate APK

    $Apk = Get-ChildItem `
        "app\androidApp\build\outputs\apk\release" `
        -Filter "*.apk" `
        -File `
        -Recurse |
            Select-Object -First 1

    if (!$Apk) {
        throw "Could not find generated APK."
    }

    Write-Host "APK: $( $Apk.FullName )"

    # Locate AAB

    $Aab = Get-ChildItem `
        "app\androidApp\build\outputs\bundle\release" `
        -Filter "*.aab" `
        -File `
        -Recurse |
            Select-Object -First 1

    if (!$Aab) {
        throw "Could not find generated AAB."
    }

    Write-Host "AAB: $( $Aab.FullName )"

    # Verify APK

    Write-Host ""
    Write-Host "Verifying APK signature..."

    $BuildTools = Get-ChildItem `
        "$env:ANDROID_HOME\build-tools" `
        -Directory |
            Sort-Object Name -Descending |
            Select-Object -First 1

    if (!$BuildTools) {
        throw "Could not find Android build-tools."
    }

    $ApkSigner = Join-Path $BuildTools.FullName "apksigner.bat"

    & $ApkSigner verify --verbose $Apk.FullName

    if ($LASTEXITCODE -ne 0) {
        throw "APK signature verification failed."
    }

    # MSIX

    Write-Host ""
    Write-Host "Building signed MSIX..."

    $env:MSIX_PFX_PATH = $MsixPfxPath
    $env:MSIX_PFX_PASSWORD = $MsixPfxPassword

    .\gradlew.bat `
        :app:bakers-archive:createMsix `
        --stacktrace

    if ($LASTEXITCODE -ne 0) {
        throw "MSIX build failed."
    }

    # Locate MSIX

    $Msix = Get-ChildItem `
        "app\desktopApp\build" `
        -Filter "*.msix" `
        -File `
        -Recurse |
            Select-Object -First 1

    if (!$Msix) {
        throw "Could not find generated MSIX."
    }

    Write-Host "MSIX: $( $Msix.FullName )"

    # Copy artifacts

    Write-Host ""
    Write-Host "Copying artifacts..."

    Copy-Item `
        $Apk.FullName `
        (Join-Path $ArtifactDirectory "bakers-archive.apk") `
        -Force

    Copy-Item `
        $Aab.FullName `
        (Join-Path $ArtifactDirectory "bakers-archive.aab") `
        -Force

    Copy-Item `
        $Msix.FullName `
        (Join-Path $ArtifactDirectory "bakers-archive.msix") `
        -Force

    Write-Host ""
    Write-Host "========================================"
    Write-Host "BUILD SUCCESSFUL"
    Write-Host "========================================"
    Write-Host ""

}
finally {

    Pop-Location

    # Remove temporary Git credentials.
    if (Test-Path $CredentialHelper) {
        Remove-Item $CredentialHelper -Force
    }

    # Don't leave signing credentials in the environment.
    Remove-Item Env:\MSIX_PFX_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:\MSIX_PFX_PASSWORD -ErrorAction SilentlyContinue
}