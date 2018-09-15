#!/usr/env bash
#
#

ORACLE_USER=oracle
ORACLE_BASH=''
ORACLE_HOME=''
LOCALYUM=1


MEMORY=`cat /proc/meminfo | grep -F 'MemTotal' | awk '{prinf $2}'`
DIRNAME=`dirname $0`
PROGNAME=`basename $0`

# check current user 
uid=`id -u`
if [ $uid != '0' ]; then
    echo 'install oracle must root'
	exit 1
fi

PACKAGE_PATH=/mnt/_package
if [ ! -d $PACKAGE_PATH ]; then
    mkdir -p $PACKAGE_PATH
fi

checkRelease() {
    lsb="lsb_release -a"
	if ! $lsb &>/dev/null ; then
	    lsb="cat /etc/issue"
	fi
	
	
}
checkNet() {
    PING="ping -c1 www.baidu.com"
	if ! $PING ; then
	    echo "ping internet timeout, must use local yum repo! "
		return 2
	else
	    PING=$PING"| grep -F 'icmp_seq' | awk '{print $7}' | cut -d'=' -f2"
	fi
	
}
# make local yum repo
localeYum() {
    local isoFile=CentOS-6.7-x86_64-bin-DVD1.iso
}


unzipFile() {
    file1=${file1:-$DIRNAME/"linux.x64_11gR2_database_1of2.zip"}
	file2=${file1:-$DIRNAME/"linux.x64_11gR2_database_2of2.zip"}
	
	# install zip unzip package
	if ! unzip &>/dev/null; then
	    yum -y install unzip zip 
	fi
	# package sum value
	file1-cksum=3152418844
	file2-cksum=3669256139
	
	
	
	if [[ -f $file1 && -f $file2 ]]; then
	    # file sum check 
		sum1=`cksum $file1 | awk '{print $1}'`
		sum2=`cksum $file2 | awk '{print $1}'`
		    
		if [[ $sum1 -eq ${file1-cksum} && $sum2 -eq ${file2-cksum} ]]; then
		true
		fi
	else
	    echo "Oracle package is not "
	fi
}