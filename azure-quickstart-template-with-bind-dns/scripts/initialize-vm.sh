#!/bin/bash
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#
# See the License for the specific language governing permissions and
# limitations under the License.

#
# Master script that drives installation and setup of:
# - Basic dependencies
# - DNS server (bind)
#

LOG_FILE="/var/log/cloudera-azure-initialize.log"

ADMIN_USER=$1
INTERNAL_FQDN_SUFFIX=$2
HOST_IP=$3

SLEEP_INTERVAL=10

log() {
  echo "$(date): $*" >> ${LOG_FILE}
}

log "---------- VM extension scripts starting ----------"

log "DNS server ..."

#
# Disable the need for a tty when running sudo and allow passwordless sudo for the admin user
#

log "Enabling password-less sudoer ..."

sed -i '/Defaults[[:space:]]\+!*requiretty/s/^/#/' /etc/sudoers
echo "$ADMIN_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

log "Enabling password-less sudoer ... Successful"

#
# Install wget, Director server and other required packages
#

log "Installing basic tools ..."

sudo yum clean all >> ${LOG_FILE}

# install with retry
n=0
until [ ${n} -ge 5 ]
do
    sudo yum install -y wget expect epel-release>> ${LOG_FILE} 2>&1 && break
    n=$((n+1))
    sleep ${SLEEP_INTERVAL}
done

if [ ${n} -ge 5 ]; then
  log "Installing basic tools ... Failed" & exit 1;
fi

log "Installing basic tools ... Successful"

log "Installing BIND and dependencies ..."

# install with retry
n=0
until [ ${n} -ge 5 ]
do
    sudo yum install -y bind bind-utils >> ${LOG_FILE} 2>&1 && break
    n=$((n+1))
    sleep ${SLEEP_INTERVAL}
done

if [ ${n} -ge 5 ]; then
  log "Installing BIND and dependencies ... Failed" & exit 1;
fi

log "Installing BIND and dependencies ... Successful"

#
# Setup DNS server
#

log "Initializing DNS server ..."

bash ./initialize-dns-server.sh "${INTERNAL_FQDN_SUFFIX}" "${HOST_IP}" "${LOG_FILE}"
status=$?
if [ ${status} -ne 0 ]; then
  log "Initializing DNS server ... Failed" & exit status;
fi

log "Initializing DNS server ... Successful"
