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
# This script inserts a DNS search domain update script that is executed every
# time eth0 comes up. The DNS search domain update script works by querying
# Azure DNS with the VM's own IP address (reverse DNS lookup) to retrieve the
# private domain string, then sets the search domain in /etc/resolv.conf
#

cat > /etc/NetworkManager/dispatcher.d/12-update-dns-search-domain <<"EOF"
# get search domain when nslookup starts to work
# currently there is a 2 minutes SLA for the DNS record to update
echo "Updating resolv.conf"

i=0
until [ $i -ge 24 ]
do
    domain=$(nslookup "$(hostname -I | tr -d ' ')" | grep -m 1 -i "name =" | cut -d ' ' -f 3 | cut -d '.' -f 2- | rev | cut -c 2- | rev)
    [ ! -z "$domain" ] && break
    sleep 5
    i=$((i+1))
done

if [ $i -ge 24 ]; then
    echo "Update resolv.conf failed"
    exit 1
fi

# default content of resolv.conf before update
cat /etc/resolv.conf

resolvconfupdate=$(mktemp -t resolvconfupdate.XXXXXXXXXX)
grep -iv "search" /etc/resolv.conf > "$resolvconfupdate"
echo "search $domain" >> "$resolvconfupdate"
cat "$resolvconfupdate" > /etc/resolv.conf

echo "Update resolv.conf successful"

# content of resolv.conf after update
cat /etc/resolv.conf

exit 0
EOF

chmod 755 /etc/NetworkManager/dispatcher.d/12-update-dns-search-domain
service network restart

# currently there is a 2 minutes SLA for the DNS record to update
i=0
until [ $i -ge 24 ]
do
    sleep 5
    i=$((i+1))
    # Confirm search domain in resolv.conf is successfully updated to what
    # reverse lookup returns
    domain=$(nslookup "$(hostname -I | tr -d ' ')" | grep -m 1 -i "name =" | cut -d ' ' -f 3 | cut -d '.' -f 2- | rev | cut -c 2- | rev)
    if [ ! -z "$domain" ]; then
        hostname -f | grep -e "$domain" && break
    fi
done

if [ $i -ge 24 ]; then
    echo "Failed to update DNS search domain."
    exit 1
fi

echo "Successfully updated DNS search domain."

exit 0
