<#
.SYNOPSIS
    Switch between Java 8 and Java 17 for the current session and persist as default.
.USAGE
    switch-java 8    # Switch to Java 8 (Temurin)
    switch-java 17   # Switch to Java 17 (Microsoft OpenJDK)
#>
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("8","17")]
    [string]$Version
)

$java8  = "C:\Program Files\Eclipse Adoptium\jdk-8.0.482.8-hotspot"
$java17 = "C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot"

switch ($Version) {
    "8"  { $javaHome = $java8 }
    "17" { $javaHome = $java17 }
}

if (-not (Test-Path $javaHome)) {
    Write-Error "Java $Version not found at $javaHome"
    return
}

# Set for current session
$env:JAVA_HOME = $javaHome
$env:PATH = "$javaHome\bin;" + ($env:PATH -replace [regex]::Escape("$java8\bin;"), "" -replace [regex]::Escape("$java17\bin;"), "")

# Persist as user environment variable
[Environment]::SetEnvironmentVariable("JAVA_HOME", $javaHome, "User")

Write-Host "✅ Switched to Java $Version"
java -version 2>&1 | Select-Object -First 1
