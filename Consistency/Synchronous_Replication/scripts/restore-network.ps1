# Heal the partition: reconnect the standby. It catches up via WAL and blocked
# writes complete. Availability is restored with no data loss.
Write-Host "Reconnecting pg-standby to syncrepl-net ..." -ForegroundColor Yellow
docker network connect syncrepl-net pg-standby
Write-Host "Standby reconnected. Replication catches up; writes resume." -ForegroundColor Green
