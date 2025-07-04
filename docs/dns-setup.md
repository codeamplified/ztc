# DNS Setup Guide for ZTC Services

This guide walks you through configuring your network to use ZTC's DNS server for seamless access to homelab services.

## Overview

ZTC deploys a DNS server on the storage node (192.168.50.20) that provides automatic resolution for all homelab services using the `*.homelab.lan` domain. This eliminates the need to manually edit hosts files on every device.

**Benefits:**
- Access services from any device: `http://gitea.homelab.lan`, `http://argocd.homelab.lan`
- Works on phones, tablets, laptops, and IoT devices
- No manual configuration needed per device
- Automatic DNS for new services

## Prerequisites

1. ZTC infrastructure deployed (`make infra`)
2. DNS server running on storage node (automatically deployed)
3. Router administrator access

## Step 1: Deploy DNS Server

The DNS server is automatically deployed as part of `make infra`, but you can deploy it separately:

```bash
# Deploy DNS server only
make deploy-dns

# Check DNS server status
make dns-status
```

## Step 2: Configure Your Router

You need to configure your router to use the ZTC DNS server. The exact steps vary by router brand, but the concept is the same.

### Common Router Types

#### TP-Link Routers
1. Open web browser to your router's IP (usually 192.168.50.1)
2. Login with admin credentials
3. Go to **Advanced** → **Network** → **DHCP Server**
4. Set **Primary DNS** to: `192.168.50.20`
5. Keep **Secondary DNS** as: `8.8.8.8` (fallback)
6. Click **Save**
7. Reboot router or renew DHCP leases

#### Netgear Routers  
1. Open web browser to your router's IP (usually 192.168.50.1)
2. Login with admin credentials
3. Go to **Dynamic DNS** → **DNS Settings**
4. Set **Primary DNS Server** to: `192.168.50.20`
5. Set **Secondary DNS Server** to: `8.8.8.8`
6. Click **Apply**

#### Linksys Routers
1. Open web browser to your router's IP (usually 192.168.50.1)
2. Login with admin credentials  
3. Go to **Smart Wi-Fi Tools** → **Internet Settings**
4. Under **DNS Settings**, choose **Manual**
5. Set **DNS 1** to: `192.168.50.20`
6. Set **DNS 2** to: `8.8.8.8`
7. Click **Save**

#### ASUS Routers
1. Open web browser to your router's IP (usually 192.168.50.1)
2. Login with admin credentials
3. Go to **Advanced Settings** → **LAN** → **DHCP Server**
4. Set **DNS Server 1** to: `192.168.50.20`
5. Set **DNS Server 2** to: `8.8.8.8`
6. Click **Apply**

#### pfSense/OPNsense
1. Login to pfSense/OPNsense web interface
2. Go to **Services** → **DHCP Server** → **LAN**
3. Under **Servers**, set:
   - **DNS Server 1**: `192.168.50.20`
   - **DNS Server 2**: `8.8.8.8`
4. Click **Save**
5. Go to **Status** → **DHCP Leases** and release/renew client leases

#### Generic Router Instructions
If your router isn't listed above:

1. Access your router's web interface (usually 192.168.50.1)
2. Look for sections like:
   - **DHCP Settings**
   - **DNS Settings** 
   - **Internet Settings**
   - **LAN Settings**
3. Find **DNS Server** or **Name Server** settings
4. Set **Primary DNS** to: `192.168.50.20`
5. Set **Secondary DNS** to: `8.8.8.8`
6. Save and restart router if needed

## Step 3: Verify DNS Resolution

### Test DNS Resolution

```bash
# Test from any device on your network
nslookup gitea.homelab.lan
# Should return: 192.168.50.10 (or Traefik ingress IP)

# Test external domain resolution
nslookup google.com
# Should work normally
```

### Test Service Access

```bash
# Test service access (HTTP for Phase 1)
curl http://gitea.homelab.lan
curl http://argocd.homelab.lan

# Or open in browser:
# http://gitea.homelab.lan
# http://argocd.homelab.lan
```

### Verify from Different Devices

Test from multiple devices to ensure router DHCP is working:
- Desktop/laptop
- Smartphone 
- Tablet
- IoT devices

## Step 4: Troubleshooting

### DNS Server Health Check

```bash
# Check DNS server status
make dns-status

# Manual health check on storage node
ssh ubuntu@192.168.50.20 'sudo /usr/local/bin/dns-health-check.sh'
```

### Common Issues

#### Services not resolving
**Symptoms:** `nslookup gitea.homelab.lan` fails
**Solutions:**
1. Check DNS server status: `make dns-status`
2. Verify router DNS settings point to 192.168.50.20
3. Restart router or renew DHCP lease
4. Check storage node connectivity: `ping 192.168.50.20`

#### External domains not resolving
**Symptoms:** `nslookup google.com` fails
**Solutions:**
1. Check upstream DNS configuration in router
2. Verify internet connectivity from storage node
3. Check DNS server logs: `ssh ubuntu@192.168.50.20 'sudo journalctl -u dnsmasq -f'`

#### Some devices use old DNS
**Symptoms:** Works on some devices but not others
**Solutions:**
1. Renew DHCP lease on affected devices:
   - **Windows:** `ipconfig /release && ipconfig /renew`
   - **macOS/Linux:** `sudo dhclient -r && sudo dhclient`
   - **iOS:** Settings → Wi-Fi → Forget and rejoin network
   - **Android:** Wi-Fi → Forget and rejoin network

#### Router doesn't support custom DNS
**Symptoms:** No DNS settings in router interface
**Solutions:**
1. Set DNS manually on each device (not recommended):
   - **Windows:** Network settings → Change adapter options → Properties → IPv4 → DNS
   - **macOS:** System Preferences → Network → Advanced → DNS
   - **iOS:** Settings → Wi-Fi → Configure DNS → Manual
   - **Android:** Wi-Fi → Modify → Advanced → DNS
2. Consider upgrading to a more capable router

### Direct DNS Testing

```bash
# Test DNS server directly (from any machine)
nslookup test.homelab.lan 192.168.50.20
# Should return the Traefik ingress IP

# Test specific service
nslookup gitea.homelab.lan 192.168.50.20

# Test with dig (more detailed)
dig @192.168.50.20 gitea.homelab.lan
```

### DNS Server Logs

```bash
# View dnsmasq logs
ssh ubuntu@192.168.50.20 'sudo journalctl -u dnsmasq -f'

# View recent DNS queries (if logging enabled)
ssh ubuntu@192.168.50.20 'sudo tail -f /var/log/dnsmasq.log'
```

## Advanced Configuration

### Custom DNS Overrides

To add custom DNS entries, create `/etc/dnsmasq.d/custom.conf` on the storage node:

```bash
# SSH to storage node
ssh ubuntu@192.168.50.20

# Create custom DNS entries
sudo tee /etc/dnsmasq.d/custom.conf << EOF
# Custom homelab DNS entries
address=/nas.homelab.lan/192.168.50.100
address=/router.homelab.lan/192.168.50.1
EOF

# Restart dnsmasq
sudo systemctl restart dnsmasq
```

### Enable Query Logging

To enable DNS query logging for debugging:

```bash
# SSH to storage node
ssh ubuntu@192.168.50.20

# Edit dnsmasq config
sudo nano /etc/dnsmasq.conf

# Uncomment or add:
# log-queries
# log-facility=/var/log/dnsmasq.log

# Restart service
sudo systemctl restart dnsmasq

# View logs
sudo tail -f /var/log/dnsmasq.log
```

## Next Steps

Once DNS is working correctly:

1. **Phase 2:** Deploy certificates for HTTPS access (`https://service.homelab.lan`)
2. **Monitoring:** DNS health is automatically monitored by Prometheus
3. **Backup:** DNS configuration is included in ZTC backups

## Support

- Check DNS server status: `make dns-status`
- View health check: `ssh ubuntu@192.168.50.20 'sudo /usr/local/bin/dns-health-check.sh'`
- ZTC documentation: See other files in `docs/`
- Network issues: Verify router DHCP and DNS settings