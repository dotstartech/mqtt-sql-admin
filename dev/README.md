# DEV Scripts and Configs

## External Nginx Reverse Proxy
`proxy.conf` is an example configuration for external Nginx reverse proxy (not the one running in this container). The variable mapping below shall be added to the Nginx configuration before the `server {}` block
```apacheconf
map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}
```

## Location-Role Setup
Run in the MQTT container the following command
```bash
./add-location.sh ENV LOCATION ADMIN_USER ADMIN_PSWD TERMINAL_PSWD WEBAPP_PSWD SERVER_PSWD
```
