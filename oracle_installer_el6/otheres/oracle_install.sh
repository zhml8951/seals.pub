#!/bin/sh
#
# description:	Oracle Preinstall  Script
# Authors:      zheng_mingli@eseals.cn
# Modify:		20161108
#

#
# oracle 依赖包处理
#
preInstPackage() {
	yum install -y binutils*.x86_64
	yum install -y compat-libcap1*.x86_64
	yum install -y compat-libstdc++*.x86_64
	yum install -y compat-libstdc++-33.i686
	yum install -y gcc*.x86_64
	yum install -y gcc-c++*.x86_64
	yum install -y glibc.x86_64
	yum install -y glibc.i686
	yum install -y glibc-devel.x86_64
	yum install -y glibc-devel.i686
	yum install -y ksh.x86_64
	yum install -y libgcc.x86_64
	yum install -y libgcc.i686
	yum install -y libstdc++.x86_64
	yum install -y libstdc++-devel.x86_64
	yum install -y libstdc++.i686
	yum install -y libstdc++-devel.i686
	yum install -y libaio.i686
	yum install -y libaio.x86_64
	yum install -y libaio-devel.i686
	yum install -y libaio-devel.x86_64
	yum install -y make.x86_64
	yum install -y sysstat.x86_64
}
#
# user environment modify 
#
function orUserModify {
	local oracleGid=''
	local dbaGid=''
	if [ cat /etc/oraInst.loc > /dev/null 2>&1 ]; then
		if [ grep  oinstall /etc/group >/dev/null 2>&1 ]; then 
			oracleGid=$(grep oinstall /etc/group | cut -d':' -f3)
			if [ grep dba /etc/group > /dev/null 2>&1 ]; then
				dbaGid=$(grep dba /etc/group | cut -d':' -f3)
				echo "-------------------------------------------------------------------"
				echo "|            请确认本系统是否已经安装和运行了oracle!!！           |"
				echo "|            继续可能会破坏本来Oracle数据库系统!!!                |"
				echo "|            	    Y(继续)/N(结束)                                 |"
				echo "-------------------------------------------------------------------"
				read en</dev/tty
				if [ $en = 'y' -a $en = 'Y' ]; then
					usermod -g $oracleGid -G $dbaGid oracle >/dev/null 2>&1
				else
					echo "GoodBye!!！"
					exit 1
				fi
			fi
		fi
	else
		
	fi	

}

ps -ef | grep -v grep | grep pmon && echo -e "\nOralce PMON is running...\n"
ps -ef | grep -v grep | grep mmon && echo -e "\nOracle MMON is running...\n"
ps -ef | grep -v grep | grep tnslsnr && echo -e "\nOracle All service is running...\n" && exit 10

if [ id oracle >/dev/null 2>&1 ]; then
	oinstallId=$(id -g oracle)
	dbaId=$(id -G oracle | cut -d' ' -f2)
	grep oinstall /etc/group >/dev/null 2>&1 && grep dba /etc/group > /dev/null 2>&1
	

ora_user_add() {

}
ora_User_mod() {			
	grep dba /etc/group >/dev/null 2>&1  ||　/usr/sbin/groupadd dba
	id oracle >/dev/null 2>&1 && /usr/sbin/usermod -g oinstall -G dba oracle
	id oracle >/dev/null 2>&1 || useradd -g oinstall -G dba oracle
	passwd oracle 
}
  else
  
  
  fi
  
# 系统参数配置
# /etc/sysctl.conf
fs.aio-max-nr = 1048576								#cat /proc/sys/fs/aio-max-nr						
fs.file-max = 6815744								#cat /proc/sys/fs/file-max							sysctl -a | grep file-max
kernel.shmall = 2097152								#cat /proc/sys/kernel/shmall						sysctl -a | grep shm
kernel.shmmax = 536870912							#cat /proc/sys/kernel/shmmax						sysctl -a | grep shm
kernel.shmmni = 4096								#cat /proc/sys/kernel/shmmni						sysctl -a | grep shm
kernel.sem = 250 32000 100 128						#cat /proc/sys/kernel/sem 							sysctl -a | grep sem
net.ipv4.ip_local_port_range = 9000 65500			#cat /proc/sys/net/ipv4/ip_local_port_range			sysctl -a | grep ip_local_port_range
net.core.rmem_default = 262144						#cat /proc/sys/net/core/rmem_default				sysctl -a | grep rmem_default
net.core.rmem_max = 4194304							#cat /proc/sys/net/core/rmem_max					sysctl -a | grep rmem_max
net.core.wmem_default = 262144						#cat /proc/sys/net/core/wmem_default				sysctl -a | grep wmem_default
net.core.wmem_max = 1048576							#cat /proc/sys/net/core/wmem_max					sysctl -a | grep wmem_max
#　这里面的值需要经过判断，这些是默认值也是最小值。如果现系统值超过这个值就不用改，如果小于则改到默认值
/sbin/sysctl -p

# 用户文件操作配置

### soft and hard limits for the file descriptor setting
#ulimit -Sn
#4096
#ulimit -Hn
#65536
### Check the soft and hard limits for the number of processes available to a user. 
#ulimit -Su
#2047
#ulimit -Hu
#16384
#### Check the soft limit for the stack setting. Ensure that the result is in the recommended range.
# ulimit -Ss
#10240
#ulimit -Hs
#32768
#
# update the resource limits in the /etc/security/limits.conf configuration file for the installation owner. 
@oinstall       hard    nproc           16384
@oinstall       soft    nproc           2047
@oinstall       hard    nofile          65535
@oinstall       soft    nofile          4096
@oinstall       hard    stack           32768
@oinstall       soft    stack           10240

#  创建 用户目录
# mkdir -p /mount_point/app/
# chown -R oracle:oinstall /mount_point/app/
# chmod -R 775 /mount_point/app/
#$ ORACLE_BASE=/u01/app/oracle
#$ ORACLE_SID=BBCA
#$ export ORACLE_BASE ORACLE_SID

export NLS_LANG=AMERICAN_AMERICA.ZHS16GBK









