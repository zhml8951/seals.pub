#!/bin/sh
# oracle auto install shell.  oraInsall.sh
#
#	NAME: mainInstaller.sh
#	
# 	DESCRIPTION:	Oracle Preinstall Script
# 
# 	Authors:      zheng_mingli@eseals.cn
# 
# 	Modify:		20190911
#
#
set -e
export LANG=en_US.utf8
DIRNAME=$(cd `dirname $0` && pwd)
EXIT_CODE=0
ASSETS="$DIRNAME/assets"

source $ASSETS/colorecho
source $ASSETS/config
# default logs folder
LOG_FILES="$DIRNAME/logs"
log_file=$LOG_FILES/oraInstall.log

# oracle zip file check
check_zip_files() {
	local __path=$1
	if [ 'x' == 'x'"${__path}" ];then 
		__path="$DIRNAME"
	fi

    for(( _i=1; _i<=2; _i++ )); do
        __file="ZIP_FILE_$_i"
        __path_file="$__path/"$(eval echo '$'"${__file}")
        if [ ! -f $__path_file ];then
            echo_red '####ERROR. Oracle packages zip file' "$__path_file" "not found $__path" | tee -a $log_file
            exit 1
        fi
        _sumsize=`sum $__path_file`
        _sum=$(echo $_sumsize | awk '{print $1}')
        _size=$(echo $_sumsize | awk '{print $2}')
        if [ 'x'"$_sum" == 'x'"$(echo "$(eval echo '$'"${__file}_SUM")")" -a \
            'x'"$_size" == 'x'"$(echo "$(eval echo '$'"${__file}_SIZE")")" ]; then
            echo_green '***LOG. Oracle package file: '"$__path_file"' is ok..' | tee -a $log_file
        else
            echo_yellow '###Wrong. Oracle package file: '"$__path_file"' has be changed..' | tee -a $log_file
            if [ `echo $SIGNORE_SUM | tr A-Z a-z` != 'true' ]; then
            	echo_red '###ERROR. Oracle Packages error..' | tee -a $log_file
            	exit 1
            fi
        fi  
    done
}

unzip_files() {
	
	trap '' HUP INT
	if ! unzip >/dev/null 2>&1; then
		yum install -y zip unzip
	fi
	echo_green "***LOG. Begin... unzip packages. "  | tee -a $log_file
	{
		unzip $ZIP_FILE_1 >/dev/null 2>&1
		unzip $ZIP_FILE_2 >/dev/null 2>&1
	}&
	proc_bar
	wait
	echo_green "***LOG. end... unzip packages. "  | tee -a $log_file
}
#
# process bar..
proc_bar() {
	# print # ...
    function _bar {
        local _current=$1; local _total=$2;
        local _maxlen=100; local _barlen=90;
        local _format="%-${_barlen}s%$((_maxlen-_barlen))s"
        local _perc="[$_current/$_total]"
        local _progress=$((_current*_barlen/_total))
        local _prog=$(for i in `seq 0 $_progress`; do printf '#'; done)
        printf "\r$_format" $_prog $_perc
    }   
    for i in `seq 1 100`; do {   
        _bar $i 100 
        sleep 0.1 
    }; done
    echo ""
}

# check oracle pid current is exists
check_ora_pids() {
	local _handle=$1
	local cmd_pids="ps -ef | grep -v grep | grep ora | wc -l"
	local _sum_pids=`eval $cmd_pids`
	local _wrong="echo_yellow '### WRONG. Found [\$_sum_pids] oracle pids in current system.. ' | tee -a \$log_file"
	# decide check oracle pid for setup oracle
	if [ "$_handle" == 'setup' ]; then
		if [ "$_sum_pids" == '0' ]; then
			echo_green 'No oracle processes. install continue. >>>>' | tee -a $log_file
		else
			if [ "`echo $CHECK_ORACLE_PID | tr A-Z a-z`" == "true" ]; then
				#CHECK_ORACLE_PID="True"
				eval "$_wrong"; exit 1
			else
				eval "$_wrong"; true
			fi
		fi
		# decide check oracle processes for oracle running..
	else
		echo_green '***.LOG. Oracle running processes sum:'"[$_sum_pids]" | tee -a $log_file
		ora_general_proc
	fi
}
# 
# oracle general process
ora_general_proc() {
	# oracle normal processes
	local _ora_gen_proc=(_pmon _vktm _dbrm _mman _smon _mmon _mmnl _smco tnslsnr)
	declare -i local _errs=0

	for _pid in "${_ora_gen_proc[@]}" ; do
		local _ps="ps -ef | grep -v grep | grep $_pid"
		if ! eval "$_ps"; then
			echo_yellow '###.WRONG. '"ora$_pid not running. " | tee -a $log_file
			let _errs++
		fi
	done
	if [[ $_errs > 0 ]]; then
		echo_red '###.WRONG. Must Check ORACLE processes. '| tee -a $log_file
		exit 1
	fi
	# oracle listener check
	if [ $_errs -eq 0 ]; then {
		local _lister="su -l oracle -c'lsnrctl status' | grep $ORACLE_SID"
		if eval $_lister | grep 'READY'; then 
			echo_green '***.LOG. oracle listener be running.. OK ' | tee -a $log_file
		else
			echo_yellow '###.WRONG. Must check oracle listener..' | tee -a $log_file
		fi
	}; fi
}


#
#Lookup the system release
get_sys_release() {
	local __version=$1
	local rel_file="/etc/redhat-release"
	local release=''
	# define a lookup fun
	function lookRel {
		local r_file=$1
		local __rel=`grep 'release' "$r_file"`
		if [ 'x' != 'x'"$__rel" ]; then
			__rel=$(echo "$__rel" | sed -e 's/[^0-9]*//' -e 's/[^0-9].*//')
			if [ 'x' == 'x'"$__rel" ]; then 
				__rel=1
			fi
		else
			__rel=1
		fi
		echo $__rel
	}

	if [ -f "$rel_file" ]; then 
		release=`lookRel "$rel_file"`
	else
		rel_file="/etc/centos-release"
		if [ -f $rel_file ]; then
			release=`lookRel "$rel_file"`
		else
			rel_file="/etc/oracle-release"
			if [ -f $rel_file ]; then
				release=`lookRel "$rel_file"`
			else
				release=1
			fi
		fi
	fi

	if [[ "$__version" ]]; then
		eval $__version="'$release'"
	else
		echo "$release"
	fi
}
#
#local iso file yum repos config
#
yum_local() {
	local _iso_file=$1
	local _mount_pt='/media'; local _dd_tmp=/tmp/dd_tmp
	local _dd_test="dd if=\${_iso_file} of=\${_dd_tmp} bs=1024 count=8192 >/dev/null 2>&1"
	local _rm_umount="command rm \${_dd_tmp}; mount -l | grep \${_iso_file} >/dev/null && umount \$_iso_file >/dev/null 2>&1"
	if [ $# -eq 0 ]; then
		_iso_file=/dev/sr0
		if eval $_dd_test; then
			eval $_rm_umount
		else 
			echo_red '###.ERROR. No specify image file. DVD-rom no image. ' | tee -a $log_file
			exit 1
		fi

	else
		if [ -f $_iso_file ]; then
			eval $_dd_test || {
			  echo_yellow '###WRONG. image file read error ' | tee -a $log_file
			  exit 1
			} && { eval $_rm_umount; }
		else
			echo_red '###.ERROR. image file not readable. ' | tee -a $log_file
			exit 1
		fi
	fi

	[ $(ls $_mount_pt | wc -l) != '0' ] && {
		_mount_pt='/mnt/iso'
	} 
	

	if [ ! -d $_mount_pt ]; then
		mkdir -p $_mount_pt
	fi

	mount -t iso9660 -o loop,ro $_iso_file $_mount_pt >/dev/null 2>&1 || {
		echo_red '###.ERROR. image file mount error. ' | tee -a $log_file
		exit 1
	} && {
		mkdir -p /mnt/repos_bak
		mv /etc/yum.repos.d/* /mnt/repos_bak/
		cat <<EOF >>/etc/yum.repos.d/local_yum.repo
# local yum repos
[local-repo]
name=local_repo
baseurl=file://\$_mount_pt/
gpgcheck=0
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY
EOF
		yum clean all > /dev/null
		if ! yum makecache > /dev/null 2>&1; then
			echo_red '###. ERROR. yum repos config error. '
		fi
	}
}

# 
# network check and test speed
# 
check_network(){
	local destination=$1
	local _xcode=0
	# coproc buildin 
	# ping...
	coproc PING_TEST {
		read _dest
		local ping_dest="ping -q -A -c5 \$dest "
		if eval "$ping_dest &>/dev/null"; then
			local _speed=$(eval "$ping_dest | grep '^rtt' | cut -d'=' -f2")
			_speed=${_speed%%*ms}
			_speed=${_speed%%/*}
			echo $_speed
		else
			echo '1'
		fi
	}

	rfd=${PING_TEST[0]}
	wfd=${PING_TEST[1]}

	echo ${destination:-'baidu.com'} >&$wfd

	read -u $rfd ping_result
	ping_result=${ping_result:-1}

	if [ $ping_result -le 5 ]; then
		echo_red '### ERROR. Check network error..' | tee -a $log_file
		_xcode=1
	elif [ $ping_result -le 80 ]; then
		echo_green '**** LOG. Network speed fast. ' | tee -a $log_file
	elif [ $ping_result -le 400 ]; then
		echo_green '**** LOG. Network speed normal.'| tee -a $log_file
	else
		echo_yellow '### WRONG. Network speed slow. '| tee -a $log_file
		_xcode=2
	fi
	return $_xcode
}
#
# config aliyun yum repos
# 
config_aliyum() {
	_CURL=/usr/bin/curl
	if [ "`echo $CHECK_SYSTEM_RELEASE | tr A-Z a-z`" == "true" ]; then
		local _ver=`get_sys_release`
	else
		local _ver=${SYS_RELEASE:-6}
	fi
	repos_path="/etc/yum.repos.d"

	if [ $_ver -eq 1 ]; then
		echo_yellow '## WRONG. system check release error, nothing to do.' | tee -a $log_file
		return 1
	fi
	
	# get aliyun yum mirrors
	local _curl_ali="$_CURL -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-\$_ver.repo"

	# look for /etc/yum.repos.d, if here is no repo file use ali yum repos
	if ! ls "$repos_path/*.repo" &>/dev/null; then
		eval $_curl_ali &>/dev/null
	else
		mkdir -p /mnt/repos_bak
		mv "${repos_path}/*" /mnt/repos_bak
	fi

	return 0
	# The system current yum url check speed no run
	# # look yum url
	# _get_url="cat \$repo_f | grep -v '^#' | grep -E '^mirror|baseurl.*' | head -n1"
	# for _repo_f in $(ls $repos_path); do
	# 	local yum_url=`eval $_get_url`
	# 	yum_url=${yum_url#*//}; yum_url=${yum_url%%/*}
	# 	# CentOS-Base.repo file lookup
	# 	if check_network $yum_url; then
	# 		echo ${_repo_f} | grep 'Base' >/dev/null 2>&1 && return 0 
	# 	fi
	# done

}
#
# oracle depend package install
#
yumPackageInstall() {
	local system_release=`get_sys_release`
	if [ "$system_release" == '1' ]; then 
		echo_red '##### ERROR. System release check Error. ' | tee -a $log_file
		echo_red '##### ERROR. Script support redhat.centos.oracle. '
		echo_red '##### ERROR. Only support release 6/7 x86_64.   '
		echo -e '\n'
		echo_yellow  -n '<<<Ensure System releases is CentOS6 Press [Y/y]Continue O Exit>>>'
		read __en
		if [ "$(echo "$__en" | tr A-Z a-z)" == 'y' ]; then
			system_release=6
		else
			echo_red '***** LOG. System Release error, Install exit. ' | tee -a $log_file
			exit 2
		fi
	fi
	local packages=''
	case "$system_release" in 
	6)
		packages=(`echo "${PACKAGES_OS6}"`)
		true
		;;
	7)
		packages=(`echo "${PACKAGES_OS7}"`)
		true
		;;
	*)
		echo_red '#### ERROR. Occured unknown error between install.... **** ' | tee -a $log_file
		exit 3
		;;
	esac

	echo_green 'oracle depend packages begining install.>>>>>>' | tee -a $log_file

	for _package in "${packages[@]}"; do
		yum install -y $_package
	done

}
# generate password for user
gen_passwd(){
	username=$1
	if [ $# -eq 0 ]; then
		username=${ORAUSER:-eseals}
	fi
	local password=''
	OPENSSL=/usr/bin/openssl
	if [ -f $OPENSSL -a -x $OPENSSL ]
		then
		password=$($OPENSSL passwd $username)
	else
		password=$(strings /dev/urandom | grep -o '[[:alnum:]]' | head -n 14 | tr -d '\n')
	fi
	# return the password
	echo $password
}
#
#Add oracle user 
#
add_user() {
	groupadd $ORAGROUP
	groupadd $ORAGROUPS
	local password=`gen_passwd $ORAUSER`
	useradd -g $ORAGROUP -G $ORAGROUPS --password "$password" -m $ORAUSER
	echo $password > $(eval echo ~$ORAUSER/.PASSWD)
}
#
# Manage oracle user  
#
oracle_user_manage() {
	if id $ORAUSER &> /dev/null; then
		if ps -ef | awk '{print $1}' | grep "$ORAUSER"; then
			echo_red '####ERROR. Oracle user currently is logining..' | tee -a $log_file
			exit 1
		fi
		# This step resort violence 
		userdel $ORAUSER 2>/dev/null
		groupdel $ORAGROUP 2>/dev/null
		groupdel $ORAGROUPS 2>/dev/null
	fi
		add_user
}
# 
# ip address get. default get the interface_1 ipaddress 
# 
get_ip() {
	local ip_getter="ip -f inet addr show | grep 'inet' | grep -v '127.0.0'"
	local interfaces=`eval "$ip_getter | wc -l"`
	if [ $interfaces -lt 1 ]; then 
		echo_red '###ERROR. get ip address occured error. set ip addr by normal. ' >> $log_file
		return 1
	fi	
	if [ $interfaces -gt 1 ]; then
		echo_yellow '###WRONG. System has more then 1 interfaces, setup ip address default interface 1' >> $log_file
	fi
	local ip_addr=`eval "$ip_getter | head -n1 | awk '{print $2}'"`
	HOST_IP=${ip_addr%/*}
	echo $HOST_IP
	return 0
}

# check setting ip address 
check_ifconfig(){
	local addr="$1"
	local _ifconfig="`/sbin/ifconfig 2>/dev/null`"
	if [ "$?" != 0 ]; then
		_ifconfig="`ip -f inet addr show`"
	fi
	case "$_ifconfig" in
		*addr:"$addr"*)
		return 0
		;;
		*)
		;;
	esac
	echo_yellow '### WRONG. IP address \"$addr\" is not associate with any interface. ' | tee -a $log_file
	return 1
}
#
# specify oralce service ip 
#
set_ip() {
	if [ $# -eq 1 ]; then
		HOST_IP=$1
		check_ifconfig $HOST_IP && return 0
	fi

	local _ip=`echo $SSH_CONNECTION | awk '{print $3}'`
	if [ 'x'"$_ip" == 'x' ]; then
		get_ip &>/dev/null && return 0
	fi
	HOST_IP=$_ip
	return 0
}

# 
#  manage hostname and /etc/hosts
# 
manage_hostname() {

	local _host=`hostname`
	if echo $_host|grep 'localhost' ; then
		_host='eseals-'"$(hostid)"
	fi
	ORACLE_HOST=$_host
	if [ $SYS_RELEASE == '6' ]; then
		local _sys_network='/etc/sysconfig/network'
		if ! grep $_host $_sys_network; then
			sed -i -e "/^HO.*/s/=.*/$_host/" -e "/^HO.*/s/HO.*ME/HOSTNAME=/" $_sys_network
		fi
	else
		hostnamectl set-hostname $_host
	fi

	_hosts='/etc/hosts'

	if [ -z $HOST_IP ] ;then
		set_ip >/dev/null 2>&1
	fi

	grep $HOST_IP "$_hosts" &>/dev/null && sed -i "/$HOST_IP/d" $_hosts
	grep $ORACLE_HOST "$_hosts" &> /dev/null && sed -i "/$ORACLE_HOST/d" $_hosts
	
	echo "$HOST_IP $ORACLE_HOST" >> "$_hosts"
	export ORACLE_HOST
	hostname $ORACLE_HOST
}
#
# User environment modify
#
function oraUserModify {
	local oracleGid=''
	local dbaGid=''
	if [ cat /etc/oraInst.loc > /dev/null 2>&1 ]; then
		true
	else
		true
	fi
}
# 
#  set kernel parameter SHMMAX 
# 
set_shmmax() {
	if [ -n "$SHMMAX" ]; then
    	# find the line which contains shmmax in the /etc/sysctl.conf
    	if grep "^kernel.shmmax[[:space:]]*=[[:space:]]*[0-9]\+" /etc/sysctl.conf; then
    	{    
    	    line=`sed -ne '/^kernel.shmmax/p' /etc/sysctl.conf`
    	    #remove extra spaces in the line
    	    line=`echo $line | sed 's/ //g'` 
    	    #Now extract the value of shmmax
    	    fileValue=`echo $line | cut -d= -f2`
    	    echo "shmmax in response file:$SHMMAX" >> $log_file
    	    echo "shmmax in /etc/sysctl.conf:$fileValue" >>$log_file
    	    if [ ! $SHMMAX ] || [ ! $fileValue ]; then
    	       echo "Could not find SHMMAX from /etc/sysctl.conf or response file.";
    	       EXIT_CODE=1;
    	    else
    	      if [ $SHMMAX -gt $fileValue ]; then
    	        sed -ie '/^kernel.shmmax/d' /etc/sysctl.conf
    	        echo "kernel.shmmax = $SHMMAX" >> /etc/sysctl.conf
    	      else
    	         echo "The value for shmmax in response file is not greater than value for shmmax in /etc/sysctl.conf file. Hence not changing it." |tee -a $log_file
    	      fi
    	    fi
    	}
    	else
    	   echo "kernel.shmmax = $SHMMAX" >> /etc/sysctl.conf
    	fi

    	#current value of shmmax - value in /proc/sys/kernel/shmmax
    	cur_shmmax=`/sbin/sysctl -n kernel.shmmax`
    	#remove the extra spaces in the line.
    	cur_shmmax=`echo $cur_shmmax | sed 's/ //g'`
    	echo "shmmax for current session:$cur_shmmax" >> $log_file
    	if [ $SHMMAX -gt $cur_shmmax ];then
    	    if  ! $SYSCTL_LOC -w kernel.shmmax="$SHMMAX"; then
    	      echo "$SYSCTL_LOC failed to set shmmax" |tee -a $log_file
    	    fi
    	else
    	    echo "The value for shmmax is not greater than value of shmmax for current session. Hence not changing it." |tee -a $log_file
    	fi
    fi
}
# 
# set kernel parameter shmmni default 4096 
# 
set_shmmni() {
	if [ -n "$SHMMNI" ]; then
		if grep "^kernel.shmmni[[:space:]]*=[[:space:]]*[0-9]\+" /etc/sysctl.conf ; then
			#extract the line which contains shmmni in the /etc/sysctl.conf
			line=`sed -ne '/^kernel.shmmni/p' /etc/sysctl.conf`
			#remove extra spaces in the line
			line=`echo $line | sed 's/ //g'` 
			#Now extract the value of shmmni
			fileValue=`echo $line | cut -d= -f2`
			echo "shmmni in response file:$SHMMNI" >> $log_file
			echo "shmmni in /etc/sysctl.conf:$fileValue" >>$log_file
			if [ ! $SHMMNI ] || [ ! $fileValue ]; then
		    	echo "Could not find SHMMNI from /etc/sysctl.conf or response file.";
		    	EXIT_CODE=1;
		 	else
		 		if [ $SHMMNI -gt $fileValue ]; then
		    		sed -ie '/^kernel.shmmni/d' /etc/sysctl.conf
		    		echo "kernel.shmmni = $SHMMNI" >> /etc/sysctl.conf
		    	else
		    		echo "The value for shmmni in response file is not greater than value for shmmni in /etc/sysctl.conf file. Hence not changing it." | tee -a $log_file
		    	fi
		    fi
		else
	    	echo "kernel.shmmni = $SHMMNI" >> /etc/sysctl.conf
	    fi

		#current value of shmmni - value in /proc/sys/kernel/shmmni
		cur_shmmni=`/sbin/sysctl -n kernel.shmmni`
		#remove the extra spaces in the line.
		cur_shmmni=`echo $cur_shmmni | sed 's/ //g'`
		echo "shmmni for current session:$cur_shmmni" >> $log_file
		if [ $SHMMNI -gt $cur_shmmni ];then 
			if  ! $SYSCTL_LOC -w kernel.shmmni="$SHMMNI"; then
				echo "$SYSCTL_LOC failed to set shmmni" |tee -a $log_file
			fi
		else
			echo "The value for shmmni in response file is not greater than value of shmmni for current session. Hence not changing it." |tee -a $log_file
		fi
	fi
}
# 
#  set shmall parameter 
# 
set_shmall() {
	if [ -n "$SHMALL" ]; then
		if grep "^kernel.shmall[[:space:]]*=[[:space:]]*[0-9]\+" /etc/sysctl.conf; then
        	#extract the line which contains shmall in the /etc/sysctl.conf
        	line=`sed -ne '/^kernel.shmall/p' /etc/sysctl.conf`
        	#remove extra spaces in the line
        	line=`echo $line | sed 's/ //g'` 
        	#Now extract the value of shmall
        	fileValue=`echo $line | cut -d= -f2`
        	echo "shmall in response file:$SHMALL" >> $log_file
        	echo "shmall in /etc/sysctl.conf:$fileValue" >> $log_file
        	if [ ! $SHMALL ] || [ ! $fileValue ]; then
        	   echo "Could not find SHMALL from /etc/sysctl.conf or response file.";
        	   EXIT_CODE=1;
        	else 
        		if [ $SHMALL -gt $fileValue ]; then
        		  sed -ie '/^kernel.shmall/d' /etc/sysctl.conf
        		  echo "kernel.shmall = $SHMALL" >> /etc/sysctl.conf
        		else
        		  echo "The value for shmall in response file is not greater than value for shmall in /etc/sysctl.conf file. Hence not changing it." | tee -a $log_file
        		fi
        	fi
        else
           echo "kernel.shmall = $SHMALL" >> /etc/sysctl.conf
        fi

        #current value of shmmni - value in /proc/sys/kernel/shmall
        cur_shmall=`/sbin/sysctl -n kernel.shmall`
        #remove the extra spaces in the line.
        cur_shmall=`echo $cur_shmall | sed 's/ //g'`
        echo "shmall for current session:$cur_shmall" >> $log_file
        if [ $SHMALL -gt $cur_shmall ]; then
        	if  ! $SYSCTL_LOC -w kernel.shmall="$SHMALL"; then
        	   echo "$SYSCTL_LOC failed to set shmall" |tee -a $log_file
        	fi
    	else
    	   echo "The value for shmall in response file is not greater than value of shmall for current session. Hence not changing it." | tee -a $log_file
    	fi
    fi
}

#  
# set the semaphore parameters: semmsl, semmns, semopm, semmni
# 	the parameter from /proc/sys/kernel/sem
#	the global values :  SEMMSL SEMMNS SEMOPM SEMMNI
#
set_sem() {
	local file_semmsl file_semmns file_semopm file_semmni flag_cur flag_file
	if [ -n "$SEMMSL" -o -n "$SEMMNS" -o -n "$SEMOPM" -o -n "$SEMMNI" ]; then
		#change values for current session in /proc/sys/kernel/sem only if specified values are greater.
		cur_semmsl=`awk '{print $1}' /proc/sys/kernel/sem`
    	cur_semmns=`awk '{print $2}' /proc/sys/kernel/sem`
    	cur_semopm=`awk '{print $3}' /proc/sys/kernel/sem`
    	cur_semmni=`awk '{print $4}' /proc/sys/kernel/sem`
    	line=`sed -ne '/^kernel.sem/p' /etc/sysctl.conf`
    	if [ -n $line ]; then
    		fileValue=`echo $line | cut -d'=' -f2 `
    		file_semmsl=`echo $fileValue | awk '{print $1}'`
        	file_semmns=`echo $fileValue | awk '{print $2}'`
        	file_semopm=`echo $fileValue | awk '{print $3}'`
        	file_semmni=`echo $fileValue | awk '{print $4}'` 
    	fi

    	if [ ! -z "$SEMMSL" ]; then
    		echo "semmsl in response file:$SEMMSL" >> $log_file
    		echo "semmsl for current session:$cur_semmsl" >> $log_file
    		if [ $SEMMSL -gt $cur_semmsl ]; then
    			cur_semmsl=$SEMMSL
    			flag_cur="true"
    		else
    			echo "The value for semmsl in response file is not greater than value of semmsl for current session. Hence not changing it." | tee -a $log_file
    		fi
    		echo "semmsl in /etc/sysctl.conf:$file_semmsl" >>$log_file
    		if test -z "$file_semmsl" || test $SEMMSL -gt $file_semmsl; then
    			file_semmsl=$SEMMSL
    			flag_file="true"
    		else
    			echo "The value for semmsl in response file is not greater than value for semmsl in /etc/sysctl.conf file. Hence not changing it." | tee -a $log_file
    		fi
    	fi

		if [ ! -z "$SEMMNS" ]; then
		     echo "semmns in response file:$SEMMNS" >> $log_file
		     echo "semmns for current session:$cur_semmns" >> $log_file      
		     if [ $SEMMNS -gt $cur_semmns ]; then
		          cur_semmns=$SEMMNS
		          flag_cur="true"
		     else
		          echo "The value for semmns in response file is not greater than value of semmns for current session. Hence not changing it." | tee -a $log_file
		     fi
		     echo "semmns in /etc/sysctl.conf:$file_semmns" >>$log_file
		     if test -z "$file_semmns" || test $SEMMNS -gt $file_semmns; then
		          file_semmns=$SEMMNS
		          flag_file="true"
		     else
		          echo "The value for semmns in response file is not greater than value for semmns in /etc/sysctl.conf file. Hence not changing it." | tee -a $log_file
		     fi
		fi

		if [ ! -z "$SEMOPM" ]; then
		     echo "semopm in response file:$SEMOPM" >> $log_file
		     echo "semopm for current session:$cur_semopm" >> $log_file
		     if [ $SEMOPM -gt $cur_semopm ]; then
		          cur_semopm=$SEMOPM
		          flag_cur="true"
		     else
		          echo "The value for semopm in response file is not greater than value of semopm for current session. Hence not changing it." | tee -a $log_file
		     fi
		     echo "semopm in /etc/sysctl.conf:$file_semopm" >>$log_file
		     if test -z "$file_semopm" || test $SEMOPM -gt $file_semopm; then
		          file_semopm=$SEMOPM
		          flag_file="true"
		     else
		          echo "The value for semopm in response file is not greater than value for semopm in /etc/sysctl.conf file. Hence not changing it." | tee -a $log_file
		     fi
		fi

		if [ ! -z "$SEMMNI" ]; then
		     echo "semmni in response file:$SEMMNI" >> $log_file
		     echo "semmni for current session:$cur_semmni" >> $log_file
		     if [ $SEMMNI -gt $cur_semmni ]; then
		          cur_semmni=$SEMMNI
		          flag_cur="true"
		     else
		          echo "The value for semmni in response file is not greater than value of semmni for current session. Hence not changing it." | tee -a $log_file
		     fi
		     echo "semmni in /etc/sysctl.conf:$file_semmni" >>$log_file
		     if test -z "$file_semmni" || test $SEMMNI -gt $file_semmni ; then
		          file_semmni=$SEMMNI
		          flag_file="true"
		     else
		          echo "The value for semmni in response file is not greater than value for semmni in /etc/sysctl.conf file. Hence not changing it." | tee -a $log_file
		     fi
		fi

		if [ $flag_cur == "true" ]; then
		     if ! $SYSCTL_LOC -w kernel.sem="$cur_semmsl $cur_semmns $cur_semopm $cur_semmni"; then
		          echo "$SYSCTL_LOC failed to set semaphore parameters" |tee -a $log_file
		     fi
		fi
		#Now edit the /etc/sysctl.conf file  
		if [ $flag_file == "true" ]; then
		     sed -ie '/^kernel.sem/d' /etc/sysctl.conf
		     echo "kernel.sem = $file_semmsl $file_semmns $file_semopm $file_semmni" >> /etc/sysctl.conf
		fi
    fi
}
#  FILE_MAX_KERNEL set.
set_file_max_kernel() {
	if [ -n "$FILE_MAX_KERNEL" ]; then
		if grep "^fs.file-max[[:space:]]*=[[:space:]]*[0-9]\+" /etc/sysctl.conf; then
			#extract the line which contains filemax in the /etc/sysctl.conf
			line=`sed -ne '/^fs.file-max/p' /etc/sysctl.conf`
			#remove extra spaces in the line
			line=`echo $line | sed 's/ //g'` 
			#Now extract the value of filemax
			fileValue=`echo $line | cut -d= -f2`
			echo "file-max in response file:$FILE_MAX_KERNEL" >> $log_file
			echo "file-max in /etc/sysctl.conf:$fileValue" >>$log_file
			if [ ! $FILE_MAX_KERNEL ] || [ ! $fileValue ]; then
				echo "Could not find FILE_MAX_KERNEL from /etc/sysctl.conf or response file.";
				EXIT_CODE=1;
			else
				if [ $FILE_MAX_KERNEL -gt $fileValue ]; then
					sed -ie '/^fs.file-max/d' /etc/sysctl.conf
					echo "fs.file-max = $FILE_MAX_KERNEL" >> /etc/sysctl.conf
				else
					echo "The value for file-max in response file is not greater than value for file-max in /etc/sysctl.conf file. Hence not changing it." | tee -a $log_file
				fi
			fi
		else
			echo "fs.file-max = $FILE_MAX_KERNEL" >> /etc/sysctl.conf
		fi
		
		#current value of filemax - value in /proc/sys/fs
		cur_filemax=`/sbin/sysctl -n fs.file-max`
		#remove the extra spaces in the line.
		cur_filemax=`echo $cur_filemax | sed 's/ //g'`
		echo "file-max for current session:$cur_filemax" >> $log_file
		if [ $FILE_MAX_KERNEL -gt $cur_filemax ]
			then
			if ! $SYSCTL_LOC -w fs.file-max="$FILE_MAX_KERNEL"
				then
				echo "$SYSCTL_LOC failed to set fs.file-max parameter" |tee -a $log_file
			fi
		else
			echo "The value for file-max in response file is not greater than value of file-max for current session. Hence not changing it." | tee -a $log_file
		fi
	fi
}
# 
# set 
# 
set_ip_local_port_range() {
	if [ -n "$IP_LOCAL_PORT_RANGE" ]; then
	     #extract the line which contains ip_local_port_range in the /etc/sysctl.conf
	     line=`sed -ne '/^net.ipv4.ip_local_port_range/p' /etc/sysctl.conf`
	     #Now extract the value of ip_local_port_range
	     fileValue=`echo $line | cut -d= -f2`
	     file_atleast=`echo $fileValue | awk '{print $1}'`
	     file_atmost=`echo $fileValue | awk '{print $2}'`

	     #change values for current session in /proc/sys/net/ipv4 only if specified values are greater.
	     cur_atleast=`awk '{print $1}' /proc/sys/net/ipv4/ip_local_port_range`
	     cur_atmost=`awk '{print $2}' /proc/sys/net/ipv4/ip_local_port_range`

	     #find the user specified atleast and atmost values:
	     user_atleast=`echo $IP_LOCAL_PORT_RANGE | awk '{print $1}'`
	     user_atmost=`echo $IP_LOCAL_PORT_RANGE | awk '{print $2}'`
	     echo "ip_local_port_range in response file:$IP_LOCAL_PORT_RANGE" >> $log_file
	     echo "ip_local_port_range in /etc/sysctl.conf:$file_atleast $file_atmost" >> $log_file
	     flag="false"
	     echo "ip_local_port_range for current session:$cur_atleast $cur_atmost" >> $log_file
	     # removing the less than equals check for atleast
	     if [ -n "$user_atleast" ]; then
	          file_atleast=$user_atleast
	          flag="true"
	     fi

	     if test -z "$file_atmost" || test $user_atmost -gt $file_atmost; then
	          file_atmost=$user_atmost
	          flag="true"
	     else
	          echo "The upper limit of ip_local_port range in reponse file is not greater than value in /etc/sysctl.conf, hence not changing it."|tee -a $log_file
	     fi
	     if [ $flag == "true" ]; then
	          sed -ie '/^net.ipv4.ip_local_port_range/d' /etc/sysctl.conf
	          echo "net.ipv4.ip_local_port_range = $file_atleast $file_atmost" >> /etc/sysctl.conf
	     fi

	     #Now change for current session if reqd.
	     flag="false"
	     # bug fix 8445702 
	     # removing the less than equals check for atleast
	     if [ -n "$user_atleast" ]; then
	          cur_atleast=$user_atleast
	          flag="true"
	     fi

	     if [ $user_atmost -gt $cur_atmost ]; then
	          cur_atmost=$user_atmost
	          flag="true"
	     else
	          echo "The upper limit of ip_local_port range in response file is not greater than value for current session, hence not changing it."|tee -a $log_file
	     fi
	     if [ $flag == "true" ];then
	          if ! $SYSCTL_LOC -w net.ipv4.ip_local_port_range="$cur_atleast $cur_atmost"; then
	               echo "$SYSCTL_LOC failed to set net.ipv4.ip_local_port_range parameter"  |tee -a $log_file
	          fi
	     fi 
	fi
}

# 
# set net.core.rmem_default parameter
# 
set_net_core_rmem_default() {
	if [ -n "$RMEM_DEFAULT" ]; then
	    if grep "^net.core.rmem_default[[:space:]]*=[[:space:]]*[0-9]\+" /etc/sysctl.conf; then
	      #extract the line which contains rmem_default in the /etc/sysctl.conf
	      line=`sed -ne '/^[[:space:]]*net.core.rmem_default/p' /etc/sysctl.conf`
	      #remove extra spaces in the line
	      line=`echo $line | sed 's/ //g'` 
	      #Now extract the value of rmem_default
	      fileValue=`echo $line | cut -d= -f2`
	      echo "rmem_default in response file:$RMEM_DEFAULT" >> $log_file
	      echo "rmem_default in /etc/sysctl.conf:$fileValue" >>$log_file
	      if [ ! $RMEM_DEFAULT ] || [ ! $fileValue ]; then
	           echo "Could not find RMEM_DEFAULT from /etc/sysctl.conf or response file.";
	           EXIT_CODE=1;
	      else
	           if [ $RMEM_DEFAULT -gt $fileValue ]; then
	                sed -ie '/^net.core.rmem_default/d' /etc/sysctl.conf
	                echo "net.core.rmem_default = $RMEM_DEFAULT" >> /etc/sysctl.conf
	           else
	                echo "The value for rmem_default in response file is not greater than value for rmem_default in /etc/sysctl.conf file. Hence not changing it." | tee -a $log_file
	           fi
	      fi
	      
	    else
	       echo "net.core.rmem_default = $RMEM_DEFAULT" >> /etc/sysctl.conf
		fi
	     #current value of rmem_default in /proc/sys/net/core
	     cur_rmem_default=`/sbin/sysctl -n net.core.rmem_default`
	     #remove the extra spaces in the line.
	     cur_rmem_default=`echo $cur_rmem_default | sed 's/ //g'`
	     echo "rmem_default for current session:$cur_rmem_default" >> $log_file
	     if [ $RMEM_DEFAULT -gt $cur_rmem_default ]; then
	        if ! $SYSCTL_LOC -w net.core.rmem_default="$RMEM_DEFAULT"
	             then
	             echo "$SYCTL_LOC failed to set net.core.rmem_default parameter" |tee -a $log_file
	        fi 
	     else
	       echo "The value for rmem_default in response file is not greater than value of rmem_default for current session. Hence not changing it." | tee -a $log_file
	     fi
	fi
}

# 
# set net.core.wmem_default parameters
# 
set_net_core_wmem_default() {
	if [ -n "$WMEM_DEFAULT" ]; then
	    if grep "^net.core.wmem_default[[:space:]]*=[[:space:]]*[0-9]\+" /etc/sysctl.conf; then
	          #extract the line which contains wmem_default in the /etc/sysctl.conf
	          line=`sed -ne '/^net.core.wmem_default/p' /etc/sysctl.conf`
	          #remove extra spaces in the line
	          line=`echo $line | sed 's/ //g'` 
	          #Now extract the value of wmem_default
	          fileValue=`echo $line | cut -d= -f2`
	          echo "wmem_default in response file:$WMEM_DEFAULT" >> $log_file
	          echo "wmem_default in /etc/sysctl.conf:$fileValue" >>$log_file
	          if [ ! $WMEM_DEFAULT ] || [ ! $fileValue ]; then
	               echo "Could not find WMEM_DEFAULT from /etc/sysctl.conf or response file.";
	               EXIT_CODE=1;
	          else
	               if [ $WMEM_DEFAULT -gt $fileValue ]; then
	                    sed -ie '/^net.core.wmem_default/d' /etc/sysctl.conf
	                    echo "net.core.wmem_default = $WMEM_DEFAULT" >> /etc/sysctl.conf
	               else
	                    echo "The value for wmem_default in response file is not greater than value for wmem_default in /etc/sysctl.conf file. Hence not changing it." | tee -a $log_file
	               fi
	          fi
	     else
	          echo "net.core.wmem_default = $WMEM_DEFAULT" >> /etc/sysctl.conf
	     fi
	     #current value of rmem_default in /proc/sys/net/core
	     cur_wmem_default=`/sbin/sysctl -n net.core.wmem_default`
	     #remove the extra spaces in the line.
	     cur_wmem_default=`echo $cur_wmem_default | sed 's/ //g'`
	     echo "wmem_default for current session:$cur_wmem_default" >> $log_file
	     if [ $WMEM_DEFAULT -gt $cur_wmem_default ]; then
	          if ! $SYSCTL_LOC -w net.core.wmem_default="$WMEM_DEFAULT"; then
	               echo "$SYSCTL_LOC failed to set net.core.wmem_default parameter" >> $log_file
	          fi 
	     else
	          echo "The value for wmem_default in response file is not greater than value of wmem_default for current session. Hence not changing it." | tee -a $log_file
	     fi 
	fi
}
# 
# set net.core.rmem_max parameter 
# 
set_net_core_rmem_max(){
	if [ -n "$RMEM_MAX" ]; then
	    if grep "^net.core.rmem_max[[:space:]]*=[[:space:]]*[0-9]\+" /etc/sysctl.conf; then
	        #extract the line which contains rmem_max in the /etc/sysctl.conf
	        line=`sed -ne '/^net.core.rmem_max/p' /etc/sysctl.conf`
	        #remove extra spaces in the line
	        line=`echo $line | sed 's/ //g'` 
	        #Now extract the value of rmem_max
	        fileValue=`echo $line | cut -d= -f2`
	        echo "rmem_max in response file:$RMEM_MAX" >> $log_file
	        echo "rmem_max in /etc/sysctl.conf:$fileValue" >>$log_file
	        if [ ! $RMEM_MAX ] || [ ! $fileValue ]; then
	             echo "Could not find RMEM_MAX from /etc/sysctl.conf or response file.";
	             EXIT_CODE=1;
	        else
	             if [ $RMEM_MAX -gt $fileValue ]; then
	                  sed -ie '/^net.core.rmem_max/d' /etc/sysctl.conf
	                  echo "net.core.rmem_max = $RMEM_MAX" >> /etc/sysctl.conf
	             else
	                  echo "The value for rmem_max in response file is not greater than value for rmem_max in /etc/sysctl.conf file. Hence not changing it." | tee -a $log_file
	             fi
	        fi
	    else
	         echo "net.core.rmem_max = $RMEM_MAX" >> /etc/sysctl.conf
	    fi

	    #current value of rmem_max in /proc/sys/net/core
	    cur_rmem_max=`/sbin/sysctl -n net.core.rmem_max`
	    #remove the extra spaces in the line.
	    cur_rmem_max=`echo $cur_rmem_max | sed 's/ //g'`
	    echo "rmem_max for current session:$cur_rmem_max" >> $log_file
	    if [ $RMEM_MAX -gt $cur_rmem_max ]; then
	         if ! $SYSCTL_LOC -w net.core.rmem_max="$RMEM_MAX" ; then
	              echo "$SYSCTL_LOC failed to set net.core.rmem_max parameter" |tee -a $log_file
	         fi
	    else
	         echo "The value for rmem_max in response file is not greater than value of rmem_max for current session. Hence not changing it." | tee -a $log_file
	    fi
	fi
}
#  
# set net.core.wmem_max
# 
set_net_core_wmem_max() {
	if [ -n "$WMEM_MAX" ]; then
	    if grep "^net.core.wmem_max[[:space:]]*=[[:space:]]*[0-9]\+" /etc/sysctl.conf; then
	         #extract the line which contains wmem_max in the /etc/sysctl.conf
	         line=`sed -ne '/^net.core.wmem_max/p' /etc/sysctl.conf`
	         #remove extra spaces in the line
	         line=`echo $line | sed 's/ //g'` 
	         #Now extract the value of wmem_max
	         fileValue=`echo $line | cut -d= -f2`
	         echo "wmem_max in response file:$WMEM_MAX" >> $log_file
	         echo "wmem_max in /etc/sysctl.conf:$fileValue" >>$log_file
	         if [ ! $WMEM_MAX ] || [ ! $fileValue ]; then
	              echo "Could not find WMEM_MAX from /etc/sysctl.conf or response file.";
	              EXIT_CODE=1;
	         else 
	              if [ $WMEM_MAX -gt $fileValue ]; then
	                   sed -ie '/^net.core.wmem_max/d' /etc/sysctl.conf
	                   echo "net.core.wmem_max = $WMEM_MAX" >> /etc/sysctl.conf
	              else
	                   echo "The value for wmem_max in response file is not greater than value for wmem_max in /etc/sysctl.conf file. Hence not changing it." | tee -a $log_file
	              fi
	         fi
	    else
	         echo "net.core.wmem_max = $WMEM_MAX" >> /etc/sysctl.conf
	    fi
	    #current value of wmem_max in /proc/sys/net/core
	    cur_wmem_max=`/sbin/sysctl -n net.core.wmem_max`
	    #remove the extra spaces in the line.
	    cur_wmem_max=`echo $cur_wmem_max | sed 's/ //g'`
	    echo "wmem_max for current session:$cur_wmem_max" >> $log_file
	    if [ $WMEM_MAX -gt $cur_wmem_max ];then
	         if ! $SYSCTL_LOC -w net.core.wmem_max="$WMEM_MAX" ; then
	              echo "$SYSCTL_LOC failed to set net.core.wmem_max parameter" |tee -a $log_file
	         fi
	    else
	         echo "The value for wmem_max in response file is not greater than value of wmem_max for current session. Hence not changing it." | tee -a $log_file
	    fi
	fi
}
# set fs.aio-max-size parameters 
set_aio_max_size(){
	if [ -n "$AIO_MAX_SIZE" ]; then
	    if grep "^fs.aio-max-size[[:space:]]*=[[:space:]]*[0-9]\+" /etc/sysctl.conf ; then
	         #extract the line which contains aio_max_size in the /etc/sysctl.conf
	         line=`sed -ne '/^fs.aio-max-size/p' /etc/sysctl.conf`
	         #remove extra spaces in the line
	         line=`echo $line | sed 's/ //g'` 
	         #Now extract the value of aio_max_size
	         fileValue=`echo $line | cut -d= -f2`
	         echo "aio-max-size in response file:$AIO_MAX_SIZE" >> $log_file
	         echo "aio-max-size in /etc/sysctl.conf:$fileValue" >>$log_file
	         if [ ! $AIO_MAX_SIZE ] || [ ! $fileValue ]; then
	              echo "Could not find AIO_MAX_SIZE from /etc/sysctl.conf or response file.";
	              EXIT_CODE=1;
	         else
	              if [ $AIO_MAX_SIZE -gt $fileValue ]; then
	                   sed -ie '/^fs.aio-max-size/d' /etc/sysctl.conf
	                   echo "fs.aio-max-size = $AIO_MAX_SIZE" >> /etc/sysctl.conf
	              else
	                   echo "The value for aio-max-size in response file is not greater than value for aio-max-size in /etc/sysctl.conf file. Hence not changing it." | tee -a $log_file
	              fi
	         fi
	    else
	         echo "fs.aio-max-size = $AIO_MAX_SIZE" >> /etc/sysctl.conf
	    fi
	    #current value of aio_max_size in /proc/sys/fs
	    cur_aio_max_size=`/sbin/sysctl -n fs.aio-max-size`
	    #remove the extra spaces in the line.
	    cur_aio_max_size=`echo $cur_aio_max_size | sed 's/ //g'`
	    echo "aio-max-size for current session:$cur_aio_max_size" >> $log_file
	    if [ $AIO_MAX_SIZE -gt $cur_aio_max_size ]; then
	         if ! $SYSCTL_LOC -w fs.aio-max-size="$AIO_MAX_SIZE" ; then
	              echo "$SYSCTL_LOC failed to set fs.aio-max-size parameter" |tee -a $log_file
	         fi
	    else
	         echo "The value for aio-max-size in response file is not greater than value of aio-max-size for current session. Hence not changing it." | tee -a $log_file
	    fi
	fi
}
# set fs.aio-max-nr parameter
set_aio_max_nr(){
	if [ -n "$AIO_MAX_NR" ]; then
	    if grep "^fs.aio-max-nr[[:space:]]*=[[:space:]]*[0-9]\+" /etc/sysctl.conf ; then
	         #extract the line which contains aio-max-nr in the /etc/sysctl.conf
	         line=`sed -ne '/^fs.aio-max-nr/p' /etc/sysctl.conf`
	         #remove extra spaces in the line
	         line=`echo $line | sed 's/ //g'` 
	         #Now extract the value of aio-max-nr
	         fileValue=`echo $line | cut -d= -f2`
	         echo "aio-max-nr in response file:$AIO_MAX_NR" >> $log_file
	         echo "aio-max-nr in /etc/sysctl.conf:$fileValue" >>$log_file
	         if [ ! $AIO_MAX_NR ] || [ ! $fileValue ]; then
	              echo "Could not find AIO_MAX_NR from /etc/sysctl.conf or response file.";
	              EXIT_CODE=1;
	         else 
	              if [ $AIO_MAX_NR -gt $fileValue ]; then
	                   sed -ie '/^fs.aio-max-nr/d' /etc/sysctl.conf
	                   echo "fs.aio-max-nr = $AIO_MAX_NR" >> /etc/sysctl.conf
	              else
	                   echo "The value for aio-max-nr in response file is not greater than value for aio-max-nr in /etc/sysctl.conf file. Hence not changing it." | tee -a $log_file
	              fi
	         fi
	    else
	         echo "fs.aio-max-nr = $AIO_MAX_NR" >> /etc/sysctl.conf
	    fi
	    #current value of aio-max-nr in /proc/sys/fs
	    cur_aio_max_nr=`/sbin/sysctl -n fs.aio-max-nr`
	    #remove the extra spaces in the line.
	    cur_aio_max_nr=`echo $cur_aio_max_nr | sed 's/ //g'`
	    echo "aio-max-nr for current session:$cur_aio_max_nr" >> $log_file
	    if [ $AIO_MAX_NR -gt $cur_aio_max_nr ]; then
	         if ! $SYSCTL_LOC -w fs.aio-max-nr="$AIO_MAX_NR" ; then
	              echo "$SYSCTL_LOC failed to set fs.aio-max-nr parameter" |tee -a $log_file
	         fi
	    else
	         echo "The value for aio-max-nr in response file is not greater than value of aio-max-nr for current session. Hence not changing it." | tee -a $log_file
	    fi
	fi
}
# 
# set Kernel parameters
#
set_kernel() {
	if [ "`echo $SET_KERNEL_PARAMETERS | tr A-Z a-z`" == "true" ]; then
	    echo_green "***LOG. Setting Kernel Parameters..." | tee -a $log_file
	    if [ ! -d /proc/sys/kernel ]; then
	        echo_red "#### ERROR. No sysctl kernel interface - cannot set kernel parameters." |tee -a $log_file
	    fi
	    if [ -n "$KERNEL_PARAMETERS_FILE" ]; then   
	       if [ -r $KERNEL_PARAMETERS_FILE ]; then
	         $SYSCTL_LOC -p "$KERNEL_PARAMETERS_FILE"
	         if [ $? -ne 0 ]; then
	            echo_red "#### ERROR.Could not set the Kernel parameters." |tee -a $log_file
	         fi
	       else
	         echo_red "#### ERROR. File $KERNEL_PARAMETERS_FILE is not found/not readable" |tee -a $log_file
	       fi
	    else
			set_shmmax; 				set_shmmni; 	set_shmall; 	set_sem
			set_file_max_kernel; 		set_ip_local_port_range
			set_net_core_rmem_default; 	set_net_core_wmem_default
			set_net_core_rmem_max; 		set_net_core_wmem_max
			set_aio_max_size; 			set_aio_max_nr
	    fi
	fi
} 
# 
# set shell limits
# 
set_shell_limits() {
  if [ "`echo $SET_SHELL_LIMITS | tr A-Z a-z`" == "true" ]; then
  	echo "Setting Shell limits ..." | tee -a $log_file
    if [ ! -f /etc/security/limits.conf ]; then
      echo "/etc/security/limits.conf file not found. Unable to set shell limits" | tee -a $log_file
    elif ! id $ORAUSER; then
      echo "$ORAUSER does not exist on the system" | tee -a $log_file  
    else
      if [ -n "$MAX_PROCESSES_HARDLIMIT" ]; then
     	#get current value from /etc/security/limits.conf
        echo "Max processes hard limit in response file:$MAX_PROCESSES_HARDLIMIT" >> $log_file
        if grep "^$ORAUSER[[:space:]]\+hard[[:space:]]\+nproc[[:space:]]\+[0-9]\+" /etc/security/limits.conf ; then
            val=`grep "^$ORAUSER" /etc/security/limits.conf | awk '/hard[[:space:]]*nproc/ {print $4}'`
            echo "Max processes hard limit in /etc/security/limits.conf file: $val" >> $log_file
            if [ ! $MAX_PROCESSES_HARDLIMIT ] || [ ! $val ]; then
               echo "Could not find MAX_PROCESSES_HARDLIMIT from /etc/security/limits.conf or response file.";
               EXIT_CODE=1;
            else 
           if [ $MAX_PROCESSES_HARDLIMIT -gt $val ]
              then
            #delete the line and insert the new line
              grep -v "^$ORAUSER[[:space:]]\+hard[[:space:]]\+nproc[[:space:]]\+[0-9]\+" /etc/security/limits.conf > /tmp/limits.conf
              cp /tmp/limits.conf /etc/security/limits.conf
                 echo "$ORAUSER hard nproc $MAX_PROCESSES_HARDLIMIT" >> /etc/security/limits.conf
              else
                 echo "Value of MAX PROCESSES HARDLIMIT in response file is not greater than value in/etc/security/limits.conf. Hence not changing it." | tee -a $log_file
              fi
        fi
        else
          echo "$ORAUSER hard nproc $MAX_PROCESSES_HARDLIMIT" >> /etc/security/limits.conf
        fi 
     fi      
      
     if [ -n "$MAX_PROCESSES_SOFTLIMIT" ]
     then
        #if line is present then
     #get current value from /etc/security/limits.conf
        echo "Max processes softlimit in response file: $MAX_PROCESSES_SOFTLIMIT" >>$log_file
        if grep "^$ORAUSER[[:space:]]\+soft[[:space:]]\+nproc[[:space:]]\+[0-9]\+" /etc/security/limits.conf
        then
             val=`grep "^$ORAUSER" /etc/security/limits.conf | awk '/soft[[:space:]]*nproc/ {print $4}'`
             echo "Max processes soft limit in /etc/security/limits.conf: $val" >> $log_file
             if [ ! $MAX_PROCESSES_SOFTLIMIT ] || [ ! $val ]
             then
                echo "Could not find MAX_PROCESSES_SOFTLIMIT from /etc/security/limits.conf or response file.";
                EXIT_CODE=1;
            else 
              if [ $MAX_PROCESSES_SOFTLIMIT -gt $val ]
           then
           #delete the line and insert the new line
              grep -v "^$ORAUSER[[:space:]]\+soft[[:space:]]\+nproc[[:space:]]\+[0-9]\+" /etc/security/limits.conf > /tmp/limits.conf
              cp /tmp/limits.conf /etc/security/limits.conf
                 echo "$ORAUSER soft nproc $MAX_PROCESSES_SOFTLIMIT" >> /etc/security/limits.conf
               else
               echo "Value of MAX PROCESSES SOFTLIMIT in response file is not greater than value in /etc/security/limits.conf. Hence not changing it." | tee -a $log_file
               fi  
          fi
        else
          echo "$ORAUSER soft nproc $MAX_PROCESSES_SOFTLIMIT" >> /etc/security/limits.conf
        fi
     fi

     if [ -n "$MAX_STACK_SOFTLIMIT" ]
     then
       #if line is present then
       #get current value from /etc/security/limits.conf
        echo "Stack limit in response file:$MAX_STACK_SOFTLIMIT" >> $log_file
        if grep "^$ORAUSER[[:space:]]\+soft[[:space:]]\+stack[[:space:]]\+[0-9]\+" /etc/security/limits.conf
        then
             val=`grep "^$ORAUSER" /etc/security/limits.conf | awk '/soft[[:space:]]*stack/ {print $4}'`
             echo "Stack limit in /etc/security/limits.conf: $val" >> $log_file
                #delete the line and insert the new line
                grep -v "$ORAUSER[[:space:]]\+soft[[:space:]]\+stack[[:space:]]\+[0-9]\+" /etc/security/limits.conf > /tmp/limits.conf
                cp /tmp/limits.conf /etc/security/limits.conf
                echo "$ORAUSER soft stack $MAX_STACK_SOFTLIMIT" >> /etc/security/limits.conf
         else
            echo "$ORAUSER soft stack $MAX_STACK_SOFTLIMIT" >> /etc/security/limits.conf
         fi
     fi

     if [ -n "$MAX_STACK_HARDLIMIT" ]
     then
       #if line is present then
       #get current value from /etc/security/limits.conf
        echo "Stack limit in response file:$MAX_STACK_HARDLIMIT" >> $log_file
        if grep "^$ORAUSER[[:space:]]\+hard[[:space:]]\+stack[[:space:]]\+[0-9]\+" /etc/security/limits.conf
        then
             val=`grep "^$ORAUSER" /etc/security/limits.conf | awk '/hard[[:space:]]*stack/ {print $4}'`
             echo "Stack limit in /etc/security/limits.conf: $val" >> $log_file
                #delete the line and insert the new line
                grep -v "$ORAUSER[[:space:]]\+hard[[:space:]]\+stack[[:space:]]\+[0-9]\+" /etc/security/limits.conf > /tmp/limits.conf
                cp /tmp/limits.conf /etc/security/limits.conf
                echo "$ORAUSER hard stack $MAX_STACK_HARDLIMIT" >> /etc/security/limits.conf
         else
            echo "$ORAUSER hard stack $MAX_STACK_HARDLIMIT" >> /etc/security/limits.conf
         fi
     fi

     if [ -n "$FILE_OPEN_MAX_HARDLIMIT" ]
     then
       #if line is present then
       #get current value from /etc/security/limits.conf
        echo "File open max hard limit in response file:$FILE_OPEN_MAX_HARDLIMIT" >> $log_file
        if grep "^$ORAUSER[[:space:]]\+hard[[:space:]]\+nofile[[:space:]]\+[0-9]\+" /etc/security/limits.conf
        then
             val=`grep "^$ORAUSER" /etc/security/limits.conf | awk '/hard[[:space:]]*nofile/ {print $4}'`
             echo "File open max hard limit in /etc/security/limits.conf: $val" >> $log_file
             if [ ! $FILE_OPEN_MAX_HARDLIMIT ] || [ ! $val ]
              then
                 echo "Could not find FILE_OPEN_MAX_HARDLIMIT from /etc/security/limits.conf or response file.";
                 EXIT_CODE=1;
             else 
               if [ $FILE_OPEN_MAX_HARDLIMIT -gt $val ]; then
                 #delete the line and insert the new line
              	grep -v "$ORAUSER[[:space:]]\+hard[[:space:]]\+nofile[[:space:]]\+[0-9]\+" /etc/security/limits.conf > /tmp/limits.conf
                 cp /tmp/limits.conf /etc/security/limits.conf
                 echo "$ORAUSER hard nofile $FILE_OPEN_MAX_HARDLIMIT" >> /etc/security/limits.conf
                else
                   echo "Value of FILE OPEN MAX HARDLIMIT in response file is not greater than value in /etc/security/limits.conf.Hence not changing it."  | tee -a $log_file 
                fi
             fi
         else
            echo "$ORAUSER hard nofile $FILE_OPEN_MAX_HARDLIMIT" >> /etc/security/limits.conf
         fi
     fi
      
     if [ -n "$FILE_OPEN_MAX_SOFTLIMIT" ]
     then
        #if line is present in the file then
        #get current value from /etc/security/limits.conf
        echo "File open max softlimit in response file:$FILE_OPEN_MAX_SOFTLIMIT" >> $log_file
        if grep "^$ORAUSER[[:space:]]\+soft[[:space:]]\+nofile[[:space:]]\+[0-9]\+" /etc/security/limits.conf
        then
            val=`grep "^$ORAUSER" /etc/security/limits.conf | awk '/soft[[:space:]]*nofile/ {print $4}'`
            echo "File open max softlimit in /etc/security/limits.conf:$val" >> $log_file
            if [ ! $FILE_OPEN_MAX_SOFTLIMIT ] || [ ! $val ]
            then
               echo "Could not find FILE_OPEN_MAX_SOFTLIMIT from /etc/security/limits.conf or response file.";
               EXIT_CODE=1;
            else
              if [ $FILE_OPEN_MAX_SOFTLIMIT -gt $val ]
           then
                  #delete the line and insert the new line
               grep -v "^$ORAUSER[[:space:]]\+soft[[:space:]]\+nofile[[:space:]]\+[0-9]\+" /etc/security/limits.conf > /tmp/limits.conf
                  cp /tmp/limits.conf /etc/security/limits.conf
               echo "$ORAUSER soft nofile $FILE_OPEN_MAX_SOFTLIMIT" >> /etc/security/limits.conf
              else
                  echo "File open max softlimit in response file is not greater than value in /etc/security/limits.conf. Hence not changing it." |tee -a $log_file
           fi
            fi
         else
          echo "$ORAUSER soft nofile $FILE_OPEN_MAX_SOFTLIMIT" >> /etc/security/limits.conf
         fi
     fi
     fi
 fi  
}
mk_ora_dir(){
	ora_path=`df -lP | grep -v 'Filesystem' | grep -v 'tmpfs' | sort -k2 -n -r | head -n1 | awk '{print $NF}'`
	if [ "$ora_path" == '/' ]; then
		ora_path=/opt
	fi

	if [[ ! -d "${ora_path}/u01" ]]; then
		ora_path="${ora_path}/u01"
	else
		ora_path=${ora_path}/u01_1
	fi
	mkdir -p $ora_path
	ln -s $ora_path $ORACLE_ROOT
	mkdir -p $ORACLE_BASE
	mkdir -p $INVENTORY_LOCATION
	chown -R $ORAUSER:$ORAGROUP $ORACLE_BASE
	chown -R $ORAUSER:$ORAGROUP $INVENTORY_LOCATION
}

generate_ora_env() {
	local tmp_env=/tmp/oracle_env
	echo '#this oracle environment ' > $tmp_env
	echo "ORACLE_ROOT=${ORACLE_ROOT}" >> $tmp_env
	echo "ORACLE_BASE=${ORACLE_BASE}" >> $tmp_env
	echo "ORACLE_SID=${ORACLE_SID}" >> $tmp_env
	echo "ORACLE_HOME=${ORACLE_HOME}" >> $tmp_env
	echo "LANG=en_US.utf8" >> $tmp_env
	echo 'NLS_LANG="AMERICAN_AMERICA.ZHS16GBK"' >> $tmp_env
	echo "PATH=$PATH:$ORACLE_HOME/bin"			>> $tmp_env
	echo 'export ORACLE_ROOT ORACLE_BASE ORACLE_HOME ORACLE_SID LANG NLS_LANG PATH' >> $tmp_env
	su -l $ORAUSER -c "cp $tmp_env ~/.oracle_env"
	su -l $ORAUSER -c '{ cd ~ ; grep .oracle_env .bash_profile &>/dev/null || sed -i \$asource\ .oracle_env .bash_profile ; }'
}
# 
install_oracle(){
	RSP_FILE="${1:-$ASSETS/db_install.rsp}"
	# oracle response file check 
	if [ ! -f $RSP_FILE -o ! -r $RSP_FILE  ];then
	    echo_red "#####ERROR. Response file is not exist! " | tee -a $log_file
        exit 1
	fi
	# set rsp file 
	sed -i -e "/^ORA.*NAME/s/=.*$/$ORACLE_HOST/" $RSP_FILE -e "/^ORA.*NAME/s/NAME/&=/" $RSP_FILE
	local total_mem=`free -m | grep '^Mem' | awk '{print $2}'`
	if [[ $total_mem < 2048 ]]; then
		ora_mem=1024
	elif [[ $total_mem < 8192 ]]; then
		ora_mem=$(( total_mem / 2))
	else
		ora_mem=$(( total_mem / 3))
	fi
	unset DISPLAY
	sed -i -e "/^ora.*memoryLimit=/s/[[:digit:]]\+/$ora_mem/" $RSP_FILE
	if [ -d $DIRNAME/database ]; then
		database_dir="$DIRNAME/database"
		su -l $ORAUSER -c "{ cd $database_dir && yes | ./runInstaller -silent -force -ignorePrereq -responseFile $RSP_FILE ; }"
		if [ $? = 0 ]; then
			sh "$INVENTORY_LOCATION/orainstRoot.sh" 2>/dev/null
			sh "$ORACLE_HOME/root.sh" 2>/dev/null
		fi
	else
		echo_red '####ERROR. oracle database folder ? ' | tee -a $log_file
	fi
}

# create eseals instance 
ora_instance_init() {
	DBCA_RSP="${1:-$ASSETS/dbca_eseals.rsp}"
	local dbca_auto=/tmp/dbca_auto
	test -f $dbca_auto && rm $dbca_auto

	cat << END >> $dbca_auto
# dbca tmp file auto 
#
source $ASSETS/colorecho
if test -f $DBCA_RSP -a -r $DBCA_RSP; then
  echo_green 'Begin create eseals instance....'
  dbca -silent -responseFile $DBCA_RSP \\
    && echo_green "oracle instance $ORACLE_SID install success" \\
    || echo_red "install oracle instance error... "
else
  echo_red "$DBCA_RSP read ERROR..."
  exit 1
fi
END

	su -l $ORAUSER -c "sh $dbca_auto"
}

# install oracle listener and tns
ora_netca_init(){
	NETCA_RSP="${1:-$ASSETS/netca_eseals.rsp}"
	local netca_auto=/tmp/netca_auto
	test -f $netca_auto && rm $netca_auto
	cat << END >> $netca_auto
# oracle netca temp file 
source $ASSETS/colorecho
unset DISPLAY
if [ -f $NETCA_RSP -a -r $NETCA_RSP ]; then
  echo_green "Begin oracle net listener install..... "
  netca /silent /responsefile $ASSETS/netca_eseals.rsp \\
    && echo_green "oracle net listener install success" \\
    || echo_red 'oracle net listener install error. '
else
  echo_red "$NETCA_RSP read error.. "
fi
END

	su -l $ORAUSER -c "sh $netca_auto"

}
# create eseals tablespace 
create_tablespace(){
	TABLESPACE_FILE=${1:-$ASSETS/eseals_tablespace.sql}
	local dbca_auto=/tmp/dbca_auto
	test -f $dbca_auto && rm $dbca_auto
	cat << END >> $dbca_auto
# oracle dbca temp file
source $ASSETS/colorecho
if [[ -f $TABLESPACE_FILE && -r $TABLESPACE_FILE ]]; then
  echo 'Begin create tablespace '
  sqlplus / as sysdba @$TABLESPACE_FILE
  if [ $? == 0 ]; then
  	echo_green 'create tablespace success..'
  else
  	echo_red 'tablespace create error. '
  fi
else
  echo_red 'tablespace.sql file error.'
  exit 1
fi
END
	# 
	su -l $ORAUSER -c "sh $dbca_auto"
}

# import eseals db dump
import_eseals_db(){
	DMP_FILE=${1:-$ASSETS/eseals.dmp}
	local imp_auto=/tmp/imp_auto
	test -f $imp_auto && rm $imp_auto
	cat << END >> $imp_auto
# oracle imp data 
if [ -f $DMP_FILE -a -r $DMP_FILE ]; then
  echo "Begin backup...."
  imp eseals/biceng@$ORACLE_SID file=$DMP_FILE full=y 
  echo "Backup success."
else
  echo 'dmp file error....'
  exit 1
fi
END

su -l $ORAUSER -c "sh $imp_auto"

}
set_iptables(){
	IPTABLES="/sbin/iptables"
	$IPTABLES -t filter -L INPUT | grep -v '^Chain' | grep -v '^target' &>/dev/null 
	if [ $? != 0 ]; then
		echo_yellow 'system iptables service no running...'
		exit 0
	fi
	num=$($IPTABLES -t filter -L INPUT --line-number -n | grep 'NEW' | head -n1 | cut -d ' ' -f1)
	let num++

	$IPTABLES -t filter -I INPUT $num -p tcp -m state --state NEW -m tcp --dport $ORA_PORT -j ACCEPT \
		&& { echo_green " oracle netport $ORA_PORT set success ."; /etc/init.d/iptables save;} \
		|| echo_red " set oracle port error."
}

# =
# oracle install by automatic 
# 
auto_oracle_install() {
	if [ "$(echo $CHECK_ZIP_FILE | tr A-Z a-z)" == 'true' ]; then
		check_zip_files
	fi

	if [ "`echo $CHECK_SYSTEM_RELEASE | tr A-Z a-z`" == "true" ]; then
		get_sys_release SYS_RELEASE
	fi
	if [ "`echo $CHECK_ORACLE_PID | tr A-Z a-z`" == "true" ]; then
		check_ora_pids setup
	fi
	if [ "`echo $CHECK_NETWORK | tr A-Z a-z`" == "true" ]; then
		check_network
	fi
	if [ "`echo $CONFIG_YUM | tr A-Z a-z`" == "true" ]; then
		config_aliyum
	fi
	echo_green '****LOG. begin install oracle...' | tee -a $log_file
	oracle_user_manage
	manage_hostname
	mk_ora_dir
	yumPackageInstall
	wait
	set_kernel
	set_shell_limits
	generate_ora_env
	unzip_files
	install_oracle
}

# display help messages
display_help_msg(){
	cat << END
 --help                   print the help messages
 --auto                   automatic install the oracle 
 --netca                  oracle net listener set 
 --dbca                   oracle instance setting 
 --tablespace             create eseals tablespace 
 --imp                    import eseals.dmp to oracle 
 --iptables               setting firewall iptables
 --other                  -----add later....
END
	exit 0
}
# 
# process command line options 
# 
process_command_options(){

	_echo_line_help(){
		echo "" 
		echo_yellow "$0 --help|--auto|--netca|--dbca|--tablespace|\
--imp|--iptables"
		echo ""
	}

	if [ "x$1" == "x" ]; then
		_echo_line_help
	fi

	for option
	do
		case "$option" in
			-*=*) value=`echo "$option" | sed -e 's/[-_a-zA-Z0-9]*=//'` 			;;
			   *) value="" ;;
		esac

		case "$option" in 
			--help|-h)					
				display_help_msg													;;
			--auto)						
				auto_oracle_install													;;
			--netca)
				ora_netca_init														;;
			--dbca)
				ora_instance_init													;;
			--tablespace)
				create_tablespace													;;
			--imp)
				import_eseals_db													;;
			--iptables)
				set_iptables														;;
			-*|*)
				_echo_line_help														;;
		esac
	done
	
}

#
# main fun, entry-point
#
main(){
	argv="$@"
	#  check the base install environment
	if [ $(id -u) != 0 ]; then
		echo_red '#####ERROR. Current user is not root, install can not continue.'
		exit 1
	fi
	if test ! -d $LOG_FILES ; then
		mkdir $LOG_FILES
	fi
	if ! echo_green "****LOG. This is the oracle install script logs file. " >> $LOG_FILES/oraInstall.log
		then
		LOG_FILES="/tmp"
		echo_green "*****LOG. This is the oracle install script logs file. " >> $LOG_FILES/oraInstall.log
	fi
	
	echo_green "****LOG. Script begin timestamp:  $($TIME) " >> $log_file
	
	 # 
	process_command_options $argv
}

#  --------------- begin here -----

main "$@"
