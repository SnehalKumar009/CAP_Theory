# Break the standby: disconnect it from the network so it can no longer ACK WAL.
# After this, writes on the primary will BLOCK (Consistency over Availability).
Write-Host "Disconnecting pg-standby from syncrepl-net ..." -ForegroundColor Yellow
docker network disconnect syncrepl-net pg-standby
Write-Host "Standby is now partitioned. Try a write -> it will hang." -ForegroundColor Red
