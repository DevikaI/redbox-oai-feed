#!/bin/sh
#Copyright (C) 2014 Queensland Cyber Infrastructure Foundation (http://www.qcif.edu.au/)

#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation; either version 2 of the License, or
#(at your option) any later version.

#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.

#You should have received a copy of the GNU General Public License along
#with this program; if not, write to the Free Software Foundation, Inc.,
#51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
#
#----------------------------------------------------------------

PROG=`basename "$0"`
PROGDIR="$( cd "$( dirname "$0" )" && pwd )"

#----------------------------------------------------------------
# Configuration  

NGINX_CONFIG_DIR=/etc/nginx/conf.d
DEFAULT_TMPDIR=/tmp/install-redbox-oaipmh-feed
BASE_DIR=/opt/harvester
MNT_DIR=/mnt/harvester
PGSQL_BASE=/opt/pgsql
PGSQL_ORIG_BASE=/var/lib/pgsql
HARVESTER_WORK_DIR=".json-harvester-manager-production"
OAISERVER_WORK_DIR=".oai-server"
HARVESTER_MANAGER_URL="http://dev.redboxresearchdata.com.au/nexus/service/local/artifact/maven/redirect?r=snapshots&g=au.com.redboxresearchdata&a=json-harvester-manager&v=LATEST&e=war"
OAISERVER_URL="http://dev.redboxresearchdata.com.au/nexus/service/local/artifact/maven/redirect?r=snapshots&g=au.com.redboxresearchdata.oai&a=oai-server&v=LATEST&e=war"
HARVESTER_CONFIG_SRC="https://raw.github.com/redbox-harvester/redbox-oai-feed/master/support/install"
OAISERVER_CONFIG_SRC="https://raw.github.com/redbox-mint/oai-server/master/support/install"
HARVESTER_NGINX_CONFIG_FILE="jsonHarvesterManager.conf"
HARVESTER_NGINX_CONFIG_URL="$HARVESTER_CONFIG_SRC/$HARVESTER_NGINX_CONFIG_FILE"
OAISERVER_NGINX_CONFIG_FILE="oaiServer.conf"
OAISERVER_NGINX_CONFIG_URL="$OAISERVER_CONFIG_SRC/$OAISERVER_NGINX_CONFIG_FILE"
OAISERVER_INITSQL="init.sql"
OAISERVER_USERSQL="user.sql"
HARVESTER_OAIPMH_FILE="redbox-oaipmh-feed.zip"
HARVESTER_OAIPMH_URL="http://dev.redboxresearchdata.com.au/nexus/service/local/artifact/maven/redirect?r=snapshots&g=au.com.redboxresearchdata.oai&a=redbox-oai-feed&v=LATEST&e=zip&c=bin"
# Sniffing OS...
if [ -e "/etc/redhat-release" ]; then
    echo "Detected a CENTOS/Fedora/RHEL distro..."
    #--quiet # not verbose, so run yum in quiet mode 
    YUM_VERBOSE=    
    REQUIRED_CMDS="curl yum adduser"
    REQUIRED_APPS="tomcat7 tomcat7-admin-webapps nginx postgresql93-server"
    INSTALL_CMD="yum install -y $YUM_VERBOSE"
    TOMCAT_HOME="/usr/share/tomcat7"    
else
    echo "This OS is not supported yet."
    exit 1        
fi


#----------------------------------------------------------------
# Abort after an error has been detected

function die () {
    echo "$PROG: aborted." >&2
    exit 1
}
#----------------------------------------------------------------
# Install Required apps 
function install_apps () {   
    rpm -ivh http://yum.postgresql.org/9.3/redhat/rhel-6-x86_64/pgdg-centos93-9.3-1.noarch.rpm
    yum install yum-priorities
    rpm -ivh http://mirrors.dotsrc.org/jpackage/6.0/generic/free/RPMS/jpackage-release-6-3.jpp6.noarch.rpm    
    echo "Checking for $REQUIRED_APPS installations..."
    for PACKAGE in $REQUIRED_APPS; do
	rpm -q $PACKAGE >/dev/null 2>&1
	if [ $? -ne 0 ]; then
	    # Package not installed: install it
	    echo "Installing package: $PACKAGE (downloading, please wait)"        
	    $INSTALL_CMD $PACKAGE || die
	else
	    # Package already installed
	    if [ -n "$VERBOSE" ]; then
		  echo "Package already installed: $PACKAGE"
	    fi
	fi
    done        
}
#----------------------------------------------------------------
# Uninstall Required apps

function uninstall_apps () {
    echo "Removing $REQUIRED_APPS installations..."
    
    for PACKAGE in $REQUIRED_APPS; do
	echo "Uninstalling package: $PACKAGE "
	yum erase -y $YUM_VERBOSE $PACKAGE || die
    done
}

#----------------------------------------------------------------
# Installs ReDBox OAI-PMH Harvester

function install () {
    echo "Checking if the Harvester is installed..."
    if [ -e "$INSTALL_DIR" ]; then
	echo "$PROG: error: found $INSTALL_DIR: ReDBox OAI-PMH Harvester already installed" >&2
	exit 1
    fi

    #----------------
    echo "Checking for root privileges..."
    if [ `id -u` -ne 0 ]; then
	echo "$PROG: error: root privileges required" >&2
	exit 1
    fi
    #----------------
    echo "Checking for required commands..."
    for COMMAND in tar $REQUIRED_CMDS; do
  	which $COMMAND >/dev/null 2>&1
  	if [ $? -ne 0 ]; then
  	    echo "$PROG: error: command not available: $COMMAND" >&2
  	    exit 1
  	fi
    done
    #----------------
    echo "Creating directories..."
    mkdir $TMPDIR
    cd $TMPDIR
    mkdir $MNT_DIR
    chown tomcat $MNT_DIR
    chmod o+w $MNT_DIR 
    ln -s $MNT_DIR $BASE_DIR            

    install_apps
    #----------------    
    echo "Creating app work dirs.."
    sudo -u tomcat mkdir "$BASE_DIR/$HARVESTER_WORK_DIR"
    sudo -u tomcat mkdir "$BASE_DIR/$OAISERVER_WORK_DIR" 
    ln -s "$BASE_DIR/$HARVESTER_WORK_DIR" "$TOMCAT_HOME/$HARVESTER_WORK_DIR"
    ln -s "$BASE_DIR/$OAISERVER_WORK_DIR" "$TOMCAT_HOME/$OAISERVER_WORK_DIR"
    
    #----------------    
    echo "Installing ReDBox OAI-PMH Harvester"                
    echo "Downloading OAI-PMH Server: $OAISERVER_URL"
    curl -L -o "$TOMCAT_HOME/webapps/oai-server.war" "$OAISERVER_URL" || die
    echo "Downloading JSON Harvester Manager: $HARVESTER_MANAGER_URL"
    curl -L -o "$TOMCAT_HOME/webapps/json-harvester-manager.war" "$HARVESTER_MANAGER_URL" || die
    echo "Starting nginx..."
    service nginx start
    echo "Configuring nginx..."
    echo "Creating '$NGINX_CONFIG_DIR/$OAISERVER_NGINX_CONFIG_FILE' from '$OAISERVER_NGINX_CONFIG_URL'"
    curl -L -o "$NGINX_CONFIG_DIR/$OAISERVER_NGINX_CONFIG_FILE" "$OAISERVER_NGINX_CONFIG_URL" || die
    mv $NGINX_CONFIG_DIR/default.conf $NGINX_CONFIG_DIR/default.bak
    service nginx restart     
    #echo "Creating '$NGINX_CONFIG_DIR/$HARVESTER_NGINX_CONFIG_FILE' from '$HARVESTER_NGINX_CONFIG_URL'"
    #curl -L -o "$NGINX_CONFIG_DIR/$HARVESTER_NGINX_CONFIG_FILE" "$HARVESTER_NGINX_CONFIG_URL" || die
    echo "Configuring DB..."
    mv $PGSQL_ORIG_BASE $PGSQL_BASE
    ln -s $PGSQL_BASE $PGSQL_ORIG_BASE  
    service postgresql-9.3 initdb
    mv $PGSQL_BASE/9.3/data/pg_hba.conf $PGSQL_BASE/9.3/data/pg_hba.conf.bak 
    curl -L -o $PGSQL_BASE/9.3/data/pg_hba.conf "$OAISERVER_CONFIG_SRC/pg_hba.conf"        
    service postgresql-9.3 start
    curl -L -O "$OAISERVER_CONFIG_SRC/$OAISERVER_USERSQL"
    sudo -u postgres psql < $OAISERVER_USERSQL || die    
    curl -L -O "$OAISERVER_CONFIG_SRC/$OAISERVER_INITSQL" || die
    export PGPASSWORD=oaiserver    
    psql -U oaiserver < $OAISERVER_INITSQL || die
    echo "Starting tomcat..."
    service tomcat7 start
    tomcat_ready    
    echo "Deploying Harvester to Manager..."
    curl -L -o $HARVESTER_OAIPMH_FILE "$HARVESTER_OAIPMH_URL"
    curl -i -F "harvesterPackage=@$HARVESTER_OAIPMH_FILE" -H "Accept: application/json" "http://localhost:8080/json-harvester-manager/harvester/upload/redbox-oai-pmh-feed"
    curl -o harvester.check -i -H "Accept: application/json" "http://localhost:8080/json-harvester-manager/harvester/"
    grep 'redbox-oai-pmh-feed' harvester.check >/dev/null
    if [ $? -eq 0 ]; then
      echo "Starting Harvester..."
      curl -i -H "Accept: application/json" "http://localhost:8080/json-harvester-manager/harvester/start/redbox-oai-pmh-feed"      
    else
        echo "Failed to start Harvester... please check configuration."      
    fi                                                
}


#----------------------------------------------------------------
# Uninstall ReDBox OAI-PMH Harvester

function uninstall () {

    if [ -n "$VERBOSE" ]; then
	echo "Uninstalling ReDBox OAI-PMH Harvester stack and deleting all application data..."
    fi

    #----------------
    # Check for root privileges

    if [ `id -u` -ne 0 ]; then
	echo "$PROG: error: root privileges required" >&2
	exit 1
    fi
    echo "Stopping apps.."
    
    service nginx stop
    service tomcat7 stop
    service postgresql-9.3 stop
    
    uninstall_apps
    
    cleanup

    if [ -n "$VERBOSE" ]; then
	echo "ReDBox OAI-PMH Harvester uninstalled"
    fi
}

#----------------------------------------------------------------
# Remove installation files

function cleanup () {

    if [ -e "$TMPDIR" -a ! -w "$TMPDIR" ]; then
        echo "$PROG: error: insufficient permissions to clean up: $TMPDIR" >&2
        exit 1
    fi

    echo "Remove temporary install files"

    if [ -d "$TMPDIR" ]; then
	   rm -rf "$TMPDIR" || die
    elif [ -e "$TMPDIR" ]; then
	   echo "Error: not a directory: please delete it manually: $TMPDIR" >&2
	exit 1
    fi
    
    echo "Remove work data directories"
    if [ -d "$MNT_DIR" ]; then
        rm -rf "$MNT_DIR" || die
    fi
    if [ -d "$PGSQL_BASE" ]; then
        rm -rf "$PGSQL_BASE" || die
    fi
    rm -f $BASE_DIR || die
    rm -f $PGSQL_ORIG_BASE || die
    
    rm -rf "$TOMCAT_HOME" || die    
    
    rm -f "$TOMCAT_HOME/$HARVESTER_WORK_DIR" || die
    rm -f "$TOMCAT_HOME/$OAISERVER_WORK_DIR" || die
    
    rm -f "$NGINX_CONFIG_DIR/$OAISERVER_NGINX_CONFIG_FILE" || die
    rm -f "$NGINX_CONFIG_DIR/$HARVESTER_NGINX_CONFIG_FILE" || die                                

    if [ -n "$VERBOSE" ]; then
	   echo "----------All data and config files removed.--------------"
    fi
}

#----------------------------------------------------------------
# Determine if Tomcat is ready

function tomcat_ready () {
    MAIN_LOG_FILE="$TOMCAT_HOME/logs/catalina.out"

    echo "Waiting for Tomcat to be ready..."

    STARTUP_COMPLETED=
    TIMEOUT=300 # max 5 minutes
    TIMER=0
    while [ $TIMER -lt $TIMEOUT ]; do

        if [ -r "$MAIN_LOG_FILE" ]; then
	    grep 'Server startup' \
                "$MAIN_LOG_FILE" >/dev/null
            if [ $? -eq 0 ]; then
                # Found the message: assume it has started
                # Is there might be a better (and accurate) way to do this?
                STARTUP_COMPLETED=yes
                break;
            fi
        fi
        sleep 1
        TIMER=`expr $TIMER + 1`
    done

    if [ -n "$STARTUP_COMPLETED" ]; then
        echo " done (${TIMER}s)"
        return 0
    else
        echo
        echo "Warning: timeout: Tomcat not fully running" >&2
        return 1
    fi
}

#================================================================
# Parse command line arguments

HELP=
DO_UNINSTALL=
DO_INSTALL=
TMPDIR="$DEFAULT_TMPDIR"
VERBOSE=

getopt -T > /dev/null
if [ $? -eq 4 ]; then
    # GNU enhanced getopt is available
    ARGS=`getopt --name "$PROG" --long help,tmpdir,install,uninstall,verbose --options ht:iucv -- "$@"`
else
    # Original getopt is available (no long option names, no whitespace, no sorting)
    ARGS=`getopt ht:iucv "$@"`
fi
if [ $? -ne 0 ]; then
    echo "$PROG: usage error (use -h for help)" >&2
    exit 2
fi
eval set -- $ARGS

while [ $# -gt 0 ]; do
    case "$1" in
        -h | --help)         HELP=yes;;
        -i | --install)      DO_INSTALL=yes;;
        -u | --uninstall)    DO_UNINSTALL=yes;;        
        -t | --tmpdir)       TMPDIR="$2"; shift;;
        -v | --verbose)      VERBOSE=yes;;
        --)                  shift; break;; # end of options
    esac
    shift
done

if [ -n "$HELP" ]; then
    echo "Usage: $PROG [options] "
    echo "Options:"
    echo "  -i | --install     install ReDBox OAIPMH Harvester (default action)"
    echo "  -u | --uninstall   uninstall ReDBox OAIPMH Harvester "    
    echo "  -t | --tmpdir dir  directory for install files (default: $DEFAULT_TMPDIR)"
    echo "  -v | --verbose     print extra information during execution"
    echo "  -h | --help        show this message"    
    exit 0
fi

if [ -z "$DO_INSTALL" -a -z "$DO_UNINSTALL" ]; then
    # No action explicitly specified: default to install
    DO_INSTALL=yes
fi

#----------------------------------------------------------------
# Main

# Perform requested action(s).

# Note: this is designed to allow multiple actions to be specified
# and they are each performed in a sensible order.
#
# install = install ReDBox OAIPMH Harvester  
# uninstall = remove all trace of ReDBox OAIPMH Harvester 
# uninstall + install = redownload and do a fresh reinstall

if [ -n "$DO_UNINSTALL" ]; then
    uninstall
fi

if [ -n "$DO_INSTALL" ]; then
    install
fi

exit 0

#----------------------------------------------------------------
#EOF