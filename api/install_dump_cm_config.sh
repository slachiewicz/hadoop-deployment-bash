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
# Copyright Clairvoyant 2015
#
if [ -n "$DEBUG" ]; then set -x; fi
#
##### START CONFIG ###################################################

APIUSER=api

##### STOP CONFIG ####################################################
PATH=/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin
ADMINUSER="admin"
ADMINPASS="admin"
CMHOST="localhost"
CMPORT=7180
API="v5"

# Function to print the help screen.
print_help() {
  echo "Usage:     $1 [-u <admin username>] [-p <admin password>] [-H <host>] [-P <port>]"
  echo "           $1 [-h|--help]"
  echo "           $1 [-v|--version]"
  echo "defaults:  $1 -u admin -p admin -H localhost -P 7180"
  echo ""
  echo "   ex.     $1 -u userA -p mypass -P 7183"
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
    -u|--user)
      shift
      ADMINUSER=$1
      ;;
    -p|--password)
      shift
      ADMINPASS=$1
      ;;
    -H|--host)
      shift
      CMHOST=$1
      ;;
    -P|--port)
      shift
      CMPORT=$1
      ;;
    -h|--help)
      print_help "$(basename "$0")"
      ;;
    -v|--version)
      echo "Install cronjob to perform Cloudera Manager configuration backup."
      exit 0
      ;;
    *)
      print_help "$(basename "$0")"
      ;;
  esac
  shift
done

# Check to see if we have the required parameters.
if [[ -z "$ADMINUSER" || -z "$ADMINPASS" || -z "$CMHOST" || -z "$CMPORT" ]]; then print_help "$(basename "$0")"; fi

# Lets not bother continuing unless we have the privs to do something.
check_root

echo "********************************************************************************"
echo "*** $(basename "$0")"
echo "********************************************************************************"
# Check to see if we are on a supported OS.
discover_os
if [ "$OS" != RedHatEnterpriseServer ] && [ "$OS" != CentOS ] && [ "$OS" != AlmaLinux ] && [ "$OS" != Debian ] && [ "$OS" != Ubuntu ]; then
  echo "ERROR: Unsupported OS."
  exit 3
fi

if [ "$CMPORT" -eq 7183 ]; then
  CMSCHEME=https
  OPT="-k"
else
  CMSCHEME=http
fi
BASEURL=${CMSCHEME}://${CMHOST}:${CMPORT}

if ! (exec 6<>"/dev/tcp/${CMHOST}/${CMPORT}"); then
  echo "ERROR: cloudera-scm-server not listening on host: ${CMHOST} port: ${CMPORT}..."
  exit 10
fi

if [ "$OS" == RedHatEnterpriseServer ] || [ "$OS" == CentOS ] || [ "$OS" == AlmaLinux ]; then
  # https://discourse.criticalengineering.org/t/howto-password-generation-in-the-gnu-linux-cli/10
  PWCMD='< /dev/urandom tr -dc A-Za-z0-9 | head -c 20;echo'
  if ! rpm -q apg >/dev/null; then
    echo "Installing apg. Please wait..."
    yum -y -d1 -e1 install apg
  fi
  if rpm -q apg >/dev/null; then
    export PWCMD='apg -a 1 -M NCL -m 20 -x 20 -n 1'
  fi
elif [ "$OS" == Debian ] || [ "$OS" == Ubuntu ]; then
  # https://discourse.criticalengineering.org/t/howto-password-generation-in-the-gnu-linux-cli/10
  PWCMD='< /dev/urandom tr -dc A-Za-z0-9 | head -c 20;echo'
  if ! dpkg -l apg >/dev/null; then
    echo "Installing apg. Please wait..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get -y -q install apg
  fi
  if dpkg -l apg >/dev/null; then
    export PWCMD='apg -a 1 -M NCL -m 20 -x 20 -n 1'
  fi
fi

APIPASS=$(eval "$PWCMD")
# shellcheck disable=SC2086
APIVERSION=$(curl -s $OPT -u "${ADMINUSER}:${ADMINPASS}" "${BASEURL}/api/version")
API=${APIVERSION:-$API}

if curl -s $OPT -X GET -u "${ADMINUSER}:${ADMINPASS}" "${BASEURL}/api/${API}/users/${APIUSER}" | grep -q "does not exist"; then
  curl -s $OPT -X POST -u "${ADMINUSER}:${ADMINPASS}" -H "content-type:application/json" -d \
  "{
    \"items\" : [ {
      \"name\" : \"$APIUSER\",
      \"password\" : \"$APIPASS\",
      \"roles\" : [ \"ROLE_ADMIN\" ]
    } ]
  }" "${BASEURL}/api/${API}/users"
  echo ""
  echo "****************************************"
  echo "****************************************"
  echo "****************************************"
  echo "*** SAVE THIS PASSWORD"
  echo "APIUSER : $APIUSER"
  echo "APIPASS : $APIPASS"
  echo "****************************************"
  echo "****************************************"
  echo "****************************************"

  sed -e "/^APIUSER=/s|=.*|=${APIUSER}|" \
      -e "/^APIPASS=/s|=.*|=${APIPASS}|" \
      -e "/^CMHOST=/s|=.*|=${CMHOST}|" \
      -e "/^CMPORT=/s|=.*|=${CMPORT}|" \
      "$(dirname "$0")/dump_cm_config.sh" >/usr/local/sbin/dump_cm_config.sh
  chown 0:0 /usr/local/sbin/dump_cm_config.sh
  chmod 700 /usr/local/sbin/dump_cm_config.sh
  rm -f /tmp/$$
  crontab -l | grep -Ev 'dump_cm_config.sh' >/tmp/$$
  echo '1 0 * * * /usr/local/sbin/dump_cm_config.sh >/var/log/cm_config.dump'>>/tmp/$$
  crontab /tmp/$$
  rm -f /tmp/$$
else
  echo "ERROR: APIUSER ${APIUSER} already exists or ${ADMINUSER} password is incorrect.  Exiting without installing crontab."
  exit 11
fi

