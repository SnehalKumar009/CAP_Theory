# Simple demo driver: write a record, then read all back.
param(
    [string]$Payload = ("demo-" + (Get-Date -Format "HHmmss"))
)

$body = @{ payload = $Payload } | ConvertTo-Json

Write-Host "POST /api/records/write  payload=$Payload" -ForegroundColor Cyan
try {
    $resp = Invoke-RestMethod -Uri "http://localhost:8080/api/records/write" `
        -Method Post -ContentType "application/json" -Body $body -TimeoutSec 15
    Write-Host ("Write OK -> id=" + $resp.id) -ForegroundColor Green
} catch {
    Write-Host "Write did NOT complete (blocked/failed) — this is expected when the standby is down." -ForegroundColor Red
}

Write-Host "`nGET /api/records/read" -ForegroundColor Cyan
Invoke-RestMethod -Uri "http://localhost:8080/api/records/read" -Method Get | Format-Table
