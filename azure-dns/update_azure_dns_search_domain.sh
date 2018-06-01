#!/bin/sh

#
# Copyright (c) 2018 Cloudera, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# This bootstrap script is required when using Azure DNS for private domains.
#
# This script queries Azure DNS with the VM's own IP address (reverse DNS
# lookup) to retrieve the private domain string, then configures the DNS
# search domain as default domain name for dhcpclient.
#
# If custom DNS is used, this script will fall back to doing a reverse lookup
# with the DNS server IP (to acquire domain name), then sending nsupdate to
# the DNS server to register the dynamic DNS record.
#

set -xe

generate_dhclient_cfg()
{
    echo "Generate dhclient config for eth0"
    rm -f /etc/dhcp/dhclient-eth0.conf
    echo "supersede domain-name \"$domain\";" > /etc/dhcp/dhclient-eth0.conf
    cat /etc/dhcp/dhclient-eth0.conf
}

disable_waagent_hostname_monitor()
{
    echo "Disable hostname monitoring in WALinuxAgent"
    cp -f /etc/waagent.conf /etc/waagent.conf-bak
    sed -i "s/Provisioning\\.MonitorHostName=y/Provisioning\\.MonitorHostName=n/" /etc/waagent.conf
    systemctl restart waagent
}

custom_dns_update()
{
    echo "Start custom DNS update."

    #
    # CentOS and RHEL 7 use NetworkManager. Add a script to be automatically invoked when interface comes up.
    #
    cat > /etc/NetworkManager/dispatcher.d/12-register-dns <<"EOF"
#!/bin/bash
# NetworkManager Dispatch script
# Deployed by Cloudera Director Bootstrap
#
# Expected arguments:
#    $1 - interface
#    $2 - action
#
# See for info: http://linux.die.net/man/8/networkmanager

# Register A and PTR records when interface comes up
# only execute on the primary nic
if [ "$1" != "eth0" ] || [ "$2" != "up" ]
then
    exit 0;
fi

# when we have a new IP, perform nsupdate
new_ip_address="$DHCP4_IP_ADDRESS"

host=$(hostname -s)
dns_server_ip="$(grep -i nameserver /etc/resolv.conf | cut -d ' ' -f 2)"
domain=$(dig +short -x "$dns_server_ip" | cut -d ' ' -f 3 | cut -d '.' -f 2- | rev | cut -c 2- | rev)
if [ -z "$domain" ]; then
    echo "Reverse DNS lookup with DNS server IP $dns_server_ip failed."
    exit 1;
fi
ptrrec="$(printf %s "$new_ip_address." | tac -s.)in-addr.arpa"
nsupdatecmds=$(mktemp -t nsupdate.XXXXXXXXXX)
resolvconfupdate=$(mktemp -t resolvconfupdate.XXXXXXXXXX)
echo updating resolv.conf
grep -iv "search" /etc/resolv.conf > "$resolvconfupdate"
echo "search $domain" >> "$resolvconfupdate"
cat "$resolvconfupdate" > /etc/resolv.conf
echo "Attempting to register $host.$domain and $ptrrec"
{
    echo "update delete $host.$domain a"
    echo "update add $host.$domain 600 a $new_ip_address"
    echo "send"
    echo "update delete $ptrrec ptr"
    echo "update add $ptrrec 600 ptr $host.$domain"
    echo "send"
} > "$nsupdatecmds"
nsupdate "$nsupdatecmds"
exit 0;
EOF
    chmod 755 /etc/NetworkManager/dispatcher.d/12-register-dns
    service network restart

    # Confirm DNS record has been updated, retry if update did not work
    i=0
    until [ $i -ge 5 ]
    do
        sleep 5
        i=$((i+1))
        hostname | nslookup && break
        service network restart
    done

    if [ $i -ge 5 ]; then
        echo "Dynamic DNS update failed."
        exit 1
    fi

    echo "Successfully updated custom DNS."
}

# hostname change monitoring is disabled regardless of using Azure or
# custom DNS
disable_waagent_hostname_monitor

echo "Start updating DNS search domain."

# Currently there is a 2 minutes SLA for the DNS record to update.
# We'll wait up to 1 SLA period (2 minutes in total).
TOTAL_WAIT_CYCLES=12
SLEEP_INTERVAL_SECONDS=10
SHORT_NAME="$(hostname -s)"
i=1
until [ $i -ge $TOTAL_WAIT_CYCLES ]
do
    # Extract search domain from reverse lookup reply.
    # Reverse lookup reply (from dig) will look like the following:
    #   altus-123456.domain.name
    # The domain name is than extracted in reverse.
    # Note that the extra grep is added to handle the case where more than one
    # address is returned from reverse look up by grepping for the correct one.
    # There is a bug with Azure DNS where DNS records for deleted VMs may remain
    # visible for some time.
    domain=$(dig +short -x "$(hostname -I | tr -d ' ')" | grep "$SHORT_NAME" | cut -d ' ' -f 3 | cut -d '.' -f 2- | rev | cut -c 2- | rev)
    if [ ! -z "$domain" ]; then
        generate_dhclient_cfg

        # verify host FQDN
        service network restart
        sleep $SLEEP_INTERVAL_SECONDS

        hostname -f | grep -e "$domain" && break

        echo "Host FQDN $(hostname -f) does not contain $domain, retry update."
        i=$((i+1))
        continue
    fi

    sleep $SLEEP_INTERVAL_SECONDS
    i=$((i+1))
done

if [ $i -ge $TOTAL_WAIT_CYCLES ]; then
    echo "Failed to update DNS search domain after $((i*SLEEP_INTERVAL_SECONDS)) seconds. Falling back to custom DNS."
    # Fall back to trying custom DNS update.
    custom_dns_update
else
    echo "Successfully updated DNS search domain after $((i*SLEEP_INTERVAL_SECONDS)) seconds."
fi

# Set hostname to FQDN after we verified DNS is working as expected.
# IMPORTANT Notes:
# 1) Hostname change must be done after the host FQDN check above is complete;
# 2) waagent hostname change monitoring must be disabled (performed earlier)
# before changing hostname to FQDN. Otherwise this change will effectively
# remove the Azure DNS record for the VM.
# 3) When using custom DNS, set the hostname to FQDN as well so that the names
# are consistent with what we have using Azure DNS
hostnamectl set-hostname "$(hostname -f)"

exit 0
