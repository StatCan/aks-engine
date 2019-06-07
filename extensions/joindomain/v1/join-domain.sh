#!/bin/bash
# Add support for registering with Active Directory domain.

set -e

# From: https://github.com/Azure/aks-engine/blob/master/parts/k8s/cloud-init/artifacts/cse_helpers.sh
wait_for_apt_locks() {
    while fuser /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do
        echo 'Waiting for release of apt locks'
        sleep 3
    done
}

apt_get_update() {
    retries=10
    apt_update_output=/tmp/apt-get-update.out
    for i in $(seq 1 $retries); do
        wait_for_apt_locks
        export DEBIAN_FRONTEND=noninteractive
        dpkg --configure -a
        apt-get -f -y install
        ! (apt-get update 2>&1 | tee $apt_update_output | grep -E "^([WE]:.*)|([eE]rr.*)$") && \
        cat $apt_update_output && break || \
        cat $apt_update_output
        if [ $i -eq $retries ]; then
            return 1
        else sleep 5
        fi
    done
    echo Executed apt-get update $i times
    wait_for_apt_locks
}

apt_get_install() {
    retries=$1; wait_sleep=$2; timeout=$3; shift && shift && shift
    for i in $(seq 1 $retries); do
        wait_for_apt_locks
        export DEBIAN_FRONTEND=noninteractive
        dpkg --configure -a
        apt-get install -o Dpkg::Options::="--force-confold" --no-install-recommends -y ${@} && break || \
        if [ $i -eq $retries ]; then
            return 1
        else
            sleep $wait_sleep
            apt_get_update
        fi
    done
    echo Executed apt-get install --no-install-recommends -y \"$@\" $i times;
    wait_for_apt_locks
}

# Parameters
DOMAINNAME=$1
KERBEROS_REALM=$2
AD_JOIN_USER=$3
AD_JOIN_PASSWORD=$4
AD_OU=$5
AD_SERVER=$6
AD_BACKUP_SERVER=$7

if [ -z "$DOMAINNAME" -o -z "$KERBEROS_REALM" -o -z "$AD_JOIN_USER" -o -z "$AD_JOIN_PASSWORD" -o -z "$AD_OU" -o -z "$AD_SERVER" -o -z "$AD_BACKUP_SERVER" ]; then
    echo "Not all parameters provided. See documentation" 1>&2
    exit 1
fi

# Install dependencies
apt_get_update
apt_get_install 20 30 120 realmd sssd sssd-tools samba-common samba samba-common python2.7 samba-libs packagekit adcli

# Setup krb5.conf
cat > /etc/krb5.conf <<EOF
[logging]
 default = FILE:/var/log/krb5libs.log
 kdc = FILE:/var/log/krb5kdc.log
 admin_server = FILE:/var/log/kadmind.log

[libdefaults]
 default_realm = $KERBEROS_REALM
 dns_lookup_realm = false
 ticket_lifetime = 24h
 renew_lifetime = 7d
 forwardable = true
 rdns = false
 default_ccache_name = KEYRING:persistent:%{uid}

[realms]
 $KERBEROS_REALM = {
 }

[domain_realm]
 $DOMAINNAME = $KERBEROS_REALM
 .$DOMAINNAME = $KERBEROS_REALM
EOF

# Configure SSSD
cat > /etc/sssd/sssd.conf <<EOF
[sssd]
domains = $DOMAINNAME
config_file_version = 2
services = nss, pam, ssh, sudo

[domain/$DOMAINNAME]
ad_hostname = $(hostname -s).$DOMAINNAME
ad_domain = $DOMAINNAME
krb5_realm = $KERBEROS_REALM
realmd_tags = manages-system joined-with-samba
cache_credentials = True
id_provider = ad
krb5_store_password_if_offline = True
default_shell = /bin/bash
ldap_id_mapping = True
use_fully_qualified_names = False
fallback_homedir = /home/%u
access_provider = ad

ad_server = $AD_SERVER
ad_backup_server = $AD_BACKUP_SERVER

dyndns_update = True
dyndns_refresh_interval = 43200
dyndns_update_ptr = False
dyndns_ttl = 3600
EOF

chmod 600 /etc/sssd/sssd.conf

if ! grep -Fq "${DOMAINNAME}" /etc/dhcp/dhclient.conf
then
    echo $(date) " - Adding domain to dhclient.conf"

    echo "supersede domain-name \"${DOMAINNAME}\";" >> /etc/dhcp/dhclient.conf
    echo "prepend domain-search \"${DOMAINNAME}\";" >> /etc/dhcp/dhclient.conf
fi

# Join the domain
echo -n "$AD_JOIN_PASSWORD" | adcli join --stdin-password --domain-ou="$AD_OU" --login-user=$AD_JOIN_USER -S "$AD_SERVER" "$DOMAINNAME"

# Start sssd
systemctl restart sssd

# service networking restart
echo $(date) " - Restarting network"
sudo ifdown eth0 && sudo ifup eth0