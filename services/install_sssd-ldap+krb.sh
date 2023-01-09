#!/bin/bash
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
# Copyright Clairvoyant 2016
#
if [ -n "$DEBUG" ]; then set -x; fi
#
##### START CONFIG ###################################################

##### STOP CONFIG ####################################################
PATH=/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin
DATE=$(date '+%Y%m%d%H%M%S')
_TLS=no

# Function to print the help screen.
print_help() {
  echo "Authenticate via Kerberos and indentify via LDAP."
  echo ""
  echo "Usage:  $1 --realm <realm> --krbserver <host> --ldapserver <host> --suffix <search base>"
  echo ""
  echo "        -r|--realm         <Kerberos realm>"
  echo "        -k|--krbserver     <Kerberos server>"
  echo "        -l|--ldapserver    <LDAP server>"
  echo "        -s|--suffix        <LDAP search base>"
  echo "        [-L|--ldaps]       # use LDAPS on port 636"
  echo "        [-h|--help]"
  echo "        [-v|--version]"
  echo ""
  echo "   ex.  $1 --realm MYREALM --krbserver hostA --ldapserver hostB --suffix dc=mydomain,dc=local"
  exit 1
}

# Function to check for root privileges.
check_root() {
  if [[ $(/usr/bin/id | awk -F= '{print $2}' | awk -F"(" '{print $1}' 2>/dev/null) -ne 0 ]]; then
    echo "You must have root privileges to run this program."
    exit 2
  fi
}

# Function to discover basic OS details.
discover_os() {
  if command -v lsb_release >/dev/null; then
    # CentOS, Ubuntu, RedHatEnterpriseServer, Debian, SUSE LINUX
    # shellcheck disable=SC2034
    OS=$(lsb_release -is)
    # CentOS= 6.10, 7.2.1511, Ubuntu= 14.04, RHEL= 6.10, 7.5, SLES= 11
    # shellcheck disable=SC2034
    OSVER=$(lsb_release -rs)
    # 7, 14
    # shellcheck disable=SC2034
    OSREL=$(echo "$OSVER" | awk -F. '{print $1}')
    # Ubuntu= trusty, wheezy, CentOS= Final, RHEL= Santiago, Maipo, SLES= n/a
    # shellcheck disable=SC2034
    OSNAME=$(lsb_release -cs)
  else
    if [ -f /etc/redhat-release ]; then
      if [ -f /etc/almalinux-release ]; then
        # shellcheck disable=SC2034
        OS=AlmaLinux
        # 8.6
        # shellcheck disable=SC2034
        OSVER=$(rpm -qf /etc/almalinux-release --qf='%{VERSION}\n')
        # shellcheck disable=SC2034
        OSREL=$(echo "$OSVER" | awk -F. '{print $1}')
      elif [ -f /etc/centos-release ]; then
        # shellcheck disable=SC2034
        OS=CentOS
        # 7.5.1804.4.el7.centos, 6.10.el6.centos.12.3
        # shellcheck disable=SC2034
        OSVER=$(rpm -qf /etc/centos-release --qf='%{VERSION}.%{RELEASE}\n' | awk -F. '{print $1"."$2}')
        # shellcheck disable=SC2034
        OSREL=$(rpm -qf /etc/centos-release --qf='%{VERSION}\n')
      else
        # shellcheck disable=SC2034
        OS=RedHatEnterpriseServer
        # 7.5, 6Server
        # shellcheck disable=SC2034
        OSVER=$(rpm -qf /etc/redhat-release --qf='%{VERSION}\n')
        if [ "$OSVER" == "6Server" ]; then
          # shellcheck disable=SC2034
          OSVER=$(rpm -qf /etc/redhat-release --qf='%{RELEASE}\n' | awk -F. '{print $1"."$2}')
          # shellcheck disable=SC2034
          OSNAME=Santiago
        else
          # shellcheck disable=SC2034
          OSNAME=Maipo
        fi
        # shellcheck disable=SC2034
        OSREL=$(echo "$OSVER" | awk -F. '{print $1}')
      fi
    elif [ -f /etc/SuSE-release ]; then
      if grep -q "^SUSE Linux Enterprise Server" /etc/SuSE-release; then
        # shellcheck disable=SC2034
        OS="SUSE LINUX"
      fi
      # shellcheck disable=SC2034
      OSVER=$(rpm -qf /etc/SuSE-release --qf='%{VERSION}\n' | awk -F. '{print $1}')
      # shellcheck disable=SC2034
      OSREL=$(rpm -qf /etc/SuSE-release --qf='%{VERSION}\n' | awk -F. '{print $1}')
      # shellcheck disable=SC2034
      OSNAME="n/a"
    fi
  fi
}

## If the variable DEBUG is set, then turn on tracing.
## http://www.research.att.com/lists/ast-users/2003/05/msg00009.html
#if [ $DEBUG ]; then
#  # This will turn on the ksh xtrace option for mainline code
#  set -x
#
#  # This will turn on the ksh xtrace option for all functions
#  typeset +f |
#  while read F junk
#  do
#    typeset -ft $F
#  done
#  unset F junk
#fi

# Process arguments.
while [[ $1 = -* ]]; do
  case $1 in
    -r|--realm)
      shift
      _REALM_UPPER=$(echo "$1" | tr '[:lower:]' '[:upper:]')
      _REALM_LOWER=$(echo "$1" | tr '[:upper:]' '[:lower:]')
      ;;
    -k|--krbserver)
      shift
      _KRBSERVER=$1
      ;;
    -l|--ldapserver)
      shift
      _LDAPSERVER=$1
      ;;
    -s|--suffix)
      shift
      _LDAPSUFFIX=$1
      ;;
    -L|--ldaps)
      _TLS=yes
      ;;
    -h|--help)
      print_help "$(basename "$0")"
      ;;
    -v|--version)
      echo "Intall and configure SSSD to use the LDAP identity and Kerberos authN providers."
      exit 0
      ;;
    *)
      print_help "$(basename "$0")"
      ;;
  esac
  shift
done

echo "********************************************************************************"
echo "*** $(basename "$0")"
echo "********************************************************************************"
# Check to see if we are on a supported OS.
# Currently only EL.
discover_os
if [ "$OS" != RedHatEnterpriseServer ] && [ "$OS" != CentOS ] && [ "$OS" != AlmaLinux ]; then
#if [ "$OS" != RedHatEnterpriseServer ] && [ "$OS" != CentOS ] && [ "$OS" != AlmaLinux ] && [ "$OS" != Debian ] && [ "$OS" != Ubuntu ]; then
  echo "ERROR: Unsupported OS."
  exit 3
fi

# Check to see if we have the required parameters.
if [ -z "$_REALM_LOWER" ] || [ -z "$_KRBSERVER" ] || [ -z "$_LDAPSERVER" ] || [ -z "$_LDAPSUFFIX" ]; then print_help "$(basename "$0")"; fi

# Lets not bother continuing unless we have the privs to do something.
check_root

# main
echo "Installing SSSD for LDAP+Kerberos..."
if [ "$OS" == RedHatEnterpriseServer ] || [ "$OS" == CentOS ] || [ "$OS" == AlmaLinux ]; then
  echo "** Installing software."
  yum -y -e1 -d1 install sssd-ldap sssd-krb5 oddjob oddjob-mkhomedir

  echo "** Writing configs..."
  cp -p /etc/krb5.conf /etc/krb5.conf."${DATE}"
  cat <<EOF >/etc/krb5.conf
[logging]
 default = FILE:/var/log/krb5libs.log
 kdc = FILE:/var/log/krb5kdc.log
 admin_server = FILE:/var/log/kadmind.log

[libdefaults]
 default_realm = $_REALM_UPPER
 dns_lookup_realm = true
 ticket_lifetime = 24h
 renew_lifetime = 7d
 forwardable = true
 rdns = false
 # We have to use FILE: until JVM can support something better.
 # https://community.hortonworks.com/questions/11288/kerberos-cache-in-ipa-redhat-idm-keyring-solved.html
 default_ccache_name = FILE:/tmp/krb5cc_%{uid}

[realms]
$_REALM_UPPER = {
 kdc = ${_KRBSERVER}
 admin_server = ${_KRBSERVER}
}

[domain_realm]
 .${_REALM_LOWER} = $_REALM_UPPER
 $_REALM_LOWER = $_REALM_UPPER
EOF
  chown root:root /etc/krb5.conf
  chmod 0644 /etc/krb5.conf

  cp -p /etc/sssd/sssd.conf /etc/sssd/sssd.conf."${DATE}"
  cat <<EOF >/etc/sssd/sssd.conf
[sssd]
domains = $_REALM_LOWER
config_file_version = 2
services = nss, pam

[domain/${_REALM_LOWER}]
id_provider = ldap
access_provider = simple
#access_provider = ldap
auth_provider = krb5
chpass_provider = krb5
min_id = 10000
cache_credentials = true
EOF
  if [ "$_TLS" == yes ]; then
    cat <<EOF >>/etc/sssd/sssd.conf
ldap_uri = ldaps://${_LDAPSERVER}:636/
ldap_tls_cacert = /etc/pki/tls/certs/ca-bundle.crt
ldap_id_use_start_tls = true
ldap_tls_reqcert = demand
EOF
  else
    cat <<EOF >>/etc/sssd/sssd.conf
ldap_uri = ldap://${_LDAPSERVER}/
ldap_id_use_start_tls = false
ldap_tls_reqcert = never
EOF
  fi
  cat <<EOF >>/etc/sssd/sssd.conf
ldap_search_base = $_LDAPSUFFIX
#ldap_schema = rfc2307bis
ldap_pwd_policy = mit_kerberos
ldap_access_filter = memberOf=cn=sysadmin,ou=Groups,${_LDAPSUFFIX}
simple_allow_groups = sysadmin, hdpadmin, developer
krb5_realm = $_REALM_UPPER
krb5_server = $_KRBSERVER
krb5_lifetime = 24h
krb5_renewable_lifetime = 7d
krb5_renew_interval = 1h
# We have to use FILE: until JVM can support something better.
# https://community.hortonworks.com/questions/11288/kerberos-cache-in-ipa-redhat-idm-keyring-solved.html
krb5_ccname_template = FILE:/tmp/krb5cc_%U
krb5_store_password_if_offline = true

EOF
  chown root:root /etc/sssd/sssd.conf
  chmod 0600 /etc/sssd/sssd.conf

  authconfig --enablesssd --enablesssdauth --enablemkhomedir --update
  service sssd start
  chkconfig sssd on
  service oddjobd start
  chkconfig oddjobd on

  if [ -f /etc/nscd.conf ]; then
    echo "*** Disabling NSCD caching of passwd/group/netgroup/services..."
    if [ ! -f /etc/nscd.conf-orig ]; then
      cp -p /etc/nscd.conf /etc/nscd.conf-orig
    else
      cp -p /etc/nscd.conf /etc/nscd.conf."${DATE}"
    fi
    sed -e '/enable-cache[[:blank:]]*passwd/s|yes|no|' \
        -e '/enable-cache[[:blank:]]*group/s|yes|no|' \
        -e '/enable-cache[[:blank:]]*services/s|yes|no|' \
        -e '/enable-cache[[:blank:]]*netgroup/s|yes|no|' -i /etc/nscd.conf
    service nscd condrestart
    if ! service sssd status >/dev/null 2>&1; then
      service sssd restart
    fi
  fi
elif [ "$OS" == Debian ] || [ "$OS" == Ubuntu ]; then
  :
fi

