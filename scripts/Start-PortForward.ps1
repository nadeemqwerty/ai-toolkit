<#
.SYNOPSIS
    Auto-reconnecting kubectl port-forward with health checks.
.DESCRIPTION
    Wraps kubectl port-forward in a retry loop. When the connection drops
    (idle timeout, pod restart, network blip), it waits briefly and reconnects.
.PARAMETER Service
    Kubernetes service name (e.g., my-service)
.PARAMETER Namespace
    Kubernetes namespace (e.g., my-namespace)
.PARAMETER LocalPort
    Local port to bind (e.g., 9200)
.PARAMETER RemotePort
    Remote port on the service (defaults to LocalPort)
.PARAMETER Context
    kubectl context (e.g., my-context)
.PARAMETER RetryDelay
    Seconds to wait before reconnecting (default: 3)
.EXAMPLE
    .\Start-PortForward.ps1 -Service my-service -Namespace my-namespace -LocalPort 9200 -Context my-context
#>
param(
    [Parameter(Mandatory)][string]$Service,
    [Parameter(Mandatory)][string]$Namespace,
    [Parameter(Mandatory)][int]$LocalPort,
    [int]$RemotePort = 0,
    [string]$Context = "",
    [int]$RetryDelay = 3
)

if ($RemotePort -eq 0) { $RemotePort = $LocalPort }

$attempt = 0
while ($true) {
    $attempt++
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $contextLabel = if ($Context) { $Context } else { "current" }
    Write-Host "[$ts] Port-forward attempt #$attempt  =>  localhost:$LocalPort -> svc/$Service`:$RemotePort (ns=$Namespace, ctx=$contextLabel)"

    $kubectlArgs = @("port-forward", "svc/$Service", "${LocalPort}:${RemotePort}", "-n", $Namespace)
    if ($Context) {
        $kubectlArgs += @("--context", $Context)
    }
    & kubectl @kubectlArgs 2>&1

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts] Port-forward dropped (exit $LASTEXITCODE). Reconnecting in ${RetryDelay}s..."
    Start-Sleep -Seconds $RetryDelay
}
