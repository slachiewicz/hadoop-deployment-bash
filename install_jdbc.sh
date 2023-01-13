#!/bin/bash
# shellcheck disable=SC1090
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

PATH=/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin

# ARGV:
# 1 - JDBC driver type : mysql, postgresql, oracle, or sqlserver - optional
#                        installs mysql and postgresql JDBC drivers by default

MYSQL_VERSION=5.1.48

# Function to discover basic OS details.
discover_os() {
  if command -v lsb_release >/dev/null; then
    # CentOS, Ubuntu, RedHatEnterpriseServer, RedHatEnterprise, Debian, SUSE LINUX, OracleServer
    # shellcheck disable=SC2034
    OS=$(lsb_release -is)
    # CentOS= 6.10, 7.2.1511, Ubuntu= 14.04, RHEL= 6.10, 7.5, SLES= 11, OEL= 7.6
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
      if [ -f /etc/centos-release ]; then
        # shellcheck disable=SC2034
        OS=CentOS
        # shellcheck disable=SC2034
        OSREL=$(rpm -qf /etc/centos-release --qf='%{VERSION}\n' | awk -F. '{print $1}')
        # shellcheck disable=SC2034
        OSNAME=$(awk -F"[()]" '{print $2}' /etc/centos-release | sed 's| ||g')
        if [ -z "$OSNAME" ]; then
          # shellcheck disable=SC2034
          OSNAME="n/a"
        fi
        if [ "$OSREL" -le "6" ]; then
          # 6.10.el6.centos.12.3
          # shellcheck disable=SC2034
          OSVER=$(rpm -qf /etc/centos-release --qf='%{VERSION}.%{RELEASE}\n' | awk -F. '{print $1"."$2}')
        elif [ "$OSREL" == "7" ]; then
          # 7.5.1804.4.el7.centos
          # shellcheck disable=SC2034
          OSVER=$(rpm -qf /etc/centos-release --qf='%{VERSION}.%{RELEASE}\n' | awk -F. '{print $1"."$2"."$3}')
        elif [ "$OSREL" == "8" ]; then
          if [ "$(rpm -qf /etc/centos-release --qf='%{NAME}\n')" == "centos-stream-release" ]; then
            # shellcheck disable=SC2034
            OS=CentOSStream
            # shellcheck disable=SC2034
            OSVER=$(rpm -qf /etc/centos-release --qf='%{VERSION}\n' | awk -F. '{print $1}')
          else
            # shellcheck disable=SC2034
            OSVER=$(rpm -qf /etc/centos-release --qf='%{VERSION}.%{RELEASE}\n' | awk -F. '{print $1"."$2"."$4}')
          fi
        else
          # shellcheck disable=SC2034
          OS=CentOSStream
          # shellcheck disable=SC2034
          OSVER=$(rpm -qf /etc/centos-release --qf='%{VERSION}\n')
        fi
      elif [ -f /etc/oracle-release ]; then
        # shellcheck disable=SC2034
        OS=OracleServer
        # 7.6
        # shellcheck disable=SC2034
        OSVER=$(rpm -qf /etc/oracle-release --qf='%{VERSION}\n')
        # shellcheck disable=SC2034
        OSNAME="n/a"
      else
        # shellcheck disable=SC2034
        OS=RedHatEnterpriseServer
        # 8.6, 7.5, 6Server
        # shellcheck disable=SC2034
        OSVER=$(rpm -qf /etc/redhat-release --qf='%{VERSION}\n')
        # shellcheck disable=SC2034
        OSREL=$(echo "$OSVER" | awk -F. '{print $1}')
        if [ "$OSVER" == "6Server" ]; then
          # shellcheck disable=SC2034
          OSVER=$(rpm -qf /etc/redhat-release --qf='%{RELEASE}\n' | awk -F. '{print $1"."$2}')
        elif [ "$OSREL" == "8" ]; then
          # shellcheck disable=SC2034
          OS=RedHatEnterprise
        fi
        # shellcheck disable=SC2034
        OSNAME=$(awk -F"[()]" '{print $2}' /etc/redhat-release | sed 's| ||g')
      fi
      # shellcheck disable=SC2034
      OSREL=$(echo "$OSVER" | awk -F. '{print $1}')
    elif [ -f /etc/SuSE-release ]; then
      if grep -q "^SUSE Linux Enterprise Server" /etc/SuSE-release; then
        # shellcheck disable=SC2034
        OS="SUSE LINUX"
      fi
      # shellcheck disable=SC2034
      OSVER=$(rpm -qf /etc/SuSE-release --qf='%{VERSION}\n' | awk -F. '{print $1}')
      # shellcheck disable=SC2034
      OSREL=$(echo "$OSVER" | awk -F. '{print $1}')
      # shellcheck disable=SC2034
      OSNAME="n/a"
    fi
  fi
}

_get_proxy() {
  PROXY=$(grep -Eh '^ *http_proxy=http|^ *https_proxy=http' /etc/profile.d/*)
  eval "$PROXY"
  export http_proxy
  export https_proxy
  if [ -z "$http_proxy" ]; then
    PROXY=$(grep -El 'http_proxy=|https_proxy=' /etc/profile.d/*)
    if [ -n "$PROXY" ]; then
      . "$PROXY"
    fi
  fi
}

_jdk_major_version() {
  local JVER MAJ_JVER
  JVER=$(java -version 2>&1 | awk '/java version/{print $NF}' | sed -e 's|"||g')
  MAJ_JVER=$(echo "$JVER" | awk -F. '{print $2}')
  echo "$MAJ_JVER"
}

_install_oracle_jdbc() {
  cd "$(dirname "$0")" || exit
  if [ ! -f ojdbc6.jar ] && [ ! -f ojdbc8.jar ]; then
    echo "** NOTICE: ojdbc6.jar or ojdbc8.jar not found.  Please manually download from"
    echo "   http://www.oracle.com/technetwork/database/enterprise-edition/jdbc-112010-090769.html"
    echo "   or"
    echo "   http://www.oracle.com/technetwork/database/features/jdbc/jdbc-ucp-122-3110062.html"
    echo "   and place in the same directory as this script."
    exit 1
  fi
  if [ ! -d /usr/share/java ]; then
    install -o root -g root -m 0755 -d /usr/share/java
  fi
  if [ -f ojdbc6.jar ]; then
    cp -p ojdbc6.jar /tmp/ojdbc6.jar
    install -o root -g root -m 0644 /tmp/ojdbc6.jar /usr/share/java/
    ln -sf ojdbc6.jar /usr/share/java/oracle-connector-java.jar
    ls -l /usr/share/java/ojdbc6.jar
  fi
  if [ -f ojdbc8.jar ]; then
    cp -p ojdbc8.jar /tmp/ojdbc8.jar
    install -o root -g root -m 0644 /tmp/ojdbc8.jar /usr/share/java/
    ln -sf ojdbc8.jar /usr/share/java/oracle-connector-java.jar
    ls -l /usr/share/java/ojdbc8.jar
  fi
  ls -l /usr/share/java/oracle-connector-java.jar
}

_install_sqlserver_jdbc() {
  # https://www.cloudera.com/documentation/enterprise/5-10-x/topics/cdh_ig_jdbc_driver_install.html
  cd /tmp || exit
  _get_proxy
  SQLSERVER_VERSION=6.0.8112.100
  wget -q -c -O /tmp/sqljdbc_${SQLSERVER_VERSION}_enu.tar.gz https://download.microsoft.com/download/0/2/A/02AAE597-3865-456C-AE7F-613F99F850A8/enu/sqljdbc_${SQLSERVER_VERSION}_enu.tar.gz
  tar xf /tmp/sqljdbc_${SQLSERVER_VERSION}_enu.tar.gz -C /tmp
  if [ ! -d /usr/share/java ]; then
    install -o root -g root -m 0755 -d /usr/share/java
  fi
  JVER=$(_jdk_major_version)
  if [[ "$JVER" == 7 ]]; then
    install -o root -g root -m 0644 sqljdbc_6.0/enu/jre7/sqljdbc41.jar /usr/share/java/
    ln -sf sqljdbc41.jar /usr/share/java/sqlserver-connector-java.jar
    ls -l /usr/share/java/sqlserver-connector-java.jar /usr/share/java/sqljdbc41.jar
  elif [[ "$JVER" == 8 ]]; then
    install -o root -g root -m 0644 sqljdbc_6.0/enu/jre8/sqljdbc42.jar /usr/share/java/
    ln -sf sqljdbc42.jar /usr/share/java/sqlserver-connector-java.jar
    ls -l /usr/share/java/sqlserver-connector-java.jar /usr/share/java/sqljdbc42.jar
  else
    echo "ERROR: Java version either not supported or not detected."
  fi
}

echo "********************************************************************************"
echo "*** $(basename "$0")"
echo "********************************************************************************"
# Check to see if we are on a supported OS.
discover_os
if [ "$OS" != RedHatEnterpriseServer ] && [ "$OS" != CentOS ] && [ "$OS" != OracleServer ] && [ "$OS" != Debian ] && [ "$OS" != Ubuntu ]; then
  echo "ERROR: Unsupported OS."
  exit 3
fi

INSTALLDB=$1
if [ -z "$INSTALLDB" ]; then
  INSTALLDB=yes
fi

echo "Installing JDBC driver..."
if [ "$INSTALLDB" == yes ]; then
  echo "Driver type to install: mysql and postgresql"
else
  echo "Driver type to install: $INSTALLDB"
fi
if [ "$OS" == RedHatEnterpriseServer ] || [ "$OS" == CentOS ] || [ "$OS" == OracleServer ]; then
  # Test to see if JDK 6 is present.
  if rpm -q jdk >/dev/null; then
    HAS_JDK=yes
  else
    HAS_JDK=no
  fi
  if [ "$INSTALLDB" == yes ]; then
    echo "** NOTICE: Installing mysql and postgresql JDBC drivers."
    yum -y -e1 -d1 install mysql-connector-java postgresql-jdbc
    # Removes JDK 6 if it snuck onto the system. Tests for the actual RPM named
    # "jdk" to keep virtual packages from causing a JDK 8 uninstall.
    if [ "$HAS_JDK" == no ] && rpm -q jdk >/dev/null; then yum -y -e1 -d1 remove jdk; fi
  else
    if [ "$INSTALLDB" == mysql ]; then
      echo "** NOTICE: Installing mysql JDBC driver."
#      if [ "$OSREL" == 6 ]; then
        _get_proxy
        wget -q -O /tmp/mysql-connector-java-${MYSQL_VERSION}.tar.gz https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-${MYSQL_VERSION}.tar.gz
        tar xf /tmp/mysql-connector-java-${MYSQL_VERSION}.tar.gz -C /tmp
        if [ ! -d /usr/share/java ]; then
          install -o root -g root -m 0755 -d /usr/share/java
        fi
        install -o root -g root -m 0644 /tmp/mysql-connector-java-${MYSQL_VERSION}/mysql-connector-java-${MYSQL_VERSION}-bin.jar /usr/share/java/
        ln -sf mysql-connector-java-${MYSQL_VERSION}-bin.jar /usr/share/java/mysql-connector-java.jar
        ls -l /usr/share/java/*sql*
#      else
#        yum -y -e1 -d1 install mysql-connector-java
#        # Removes JDK 6 if it snuck onto the system. Tests for the actual RPM
#        # named "jdk" to keep virtual packages from causing a JDK 8 uninstall.
#        if [ "$HAS_JDK" == no ] && rpm -q jdk >/dev/null; then yum -y -e1 -d1 remove jdk; fi
#      fi
    elif [ "$INSTALLDB" == postgresql ]; then
      echo "** NOTICE: Installing postgresql JDBC driver."
      yum -y -e1 -d1 install postgresql-jdbc
    elif [ "$INSTALLDB" == oracle ]; then
      echo "** NOTICE: Installing oracle JDBC driver."
      _install_oracle_jdbc
    elif [ "$INSTALLDB" == sqlserver ]; then
      echo "** NOTICE: Installing sqlserver JDBC driver."
      _install_sqlserver_jdbc
    else
      echo "** ERROR: Argument must be either mysql, postgresql, oracle, or sqlserver."
    fi
  fi
elif [ "$OS" == Debian ] || [ "$OS" == Ubuntu ]; then
  export DEBIAN_FRONTEND=noninteractive
  if [ "$INSTALLDB" == yes ]; then
    echo "** NOTICE: Installing mysql and postgresql JDBC drivers."
    apt-get -y -q install libmysql-java libpostgresql-jdbc-java
  else
    if [ "$INSTALLDB" == mysql ]; then
      echo "** NOTICE: Installing mysql JDBC driver."
      apt-get -y -q install libmysql-java
    elif [ "$INSTALLDB" == postgresql ]; then
      echo "** NOTICE: Installing postgresql JDBC driver."
      apt-get -y -q install libpostgresql-jdbc-java
    elif [ "$INSTALLDB" == oracle ]; then
      echo "** NOTICE: Installing oracle JDBC driver."
      _install_oracle_jdbc
    elif [ "$INSTALLDB" == sqlserver ]; then
      echo "** NOTICE: Installing sqlserver JDBC driver."
      _install_sqlserver_jdbc
    else
      echo "** ERROR: Argument must be either mysql, postgresql, oracle, or sqlserver."
    fi
  fi
fi

