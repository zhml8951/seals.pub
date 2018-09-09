#!/usr/bin/env bash
#
# eseals jboss auto install script 
# Authors zheng_mingli@eseals
# Date: 2016-12-10
# Version: 0.11
#

JBOSS_USER=jboss
SHELL=/bin/bash
PASSWORD=123456
JBOSS_ZIP="jboss.zip"
JDK_FILE="jdk-7u60-linux-x64.tar.gz"
JBOSS_FILE="eseals.jboss.tar.gz"
JAVA_HOME="/home/jboss/jdk1.7.0_60"
CLASSPATH=".:$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar"
JAVAPTH=$JAVA_HOME/bin
JBOSS_HOME='/home/jboss/jboss-4.2.3.GA'
JAVA_ENV=.javaenv
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
IP_PORT=80
JBOSS_PORT=8080
# *****  此参数需慎重,默认启用iptables. 关闭iptables设置为0;      *****
IPTAB_ON=1
JBOSS_AND_ORACLE=1
WAR='ssm.war'

test -z $DIR &&  { echo "install file path error!"; exit 1; }
test `pwd` != $DIR && cd $DIR

# decide jboss status
pid=`jps 2>/dev/null | grep -i 'main'| cut -d' ' -f1`
if [ "x$pid" != 'x' ];then
	echo "Jboss is running..."
	exit 1
fi

if [ `id -u` != 0 ]; then
	echo "Use this jboss install script must root!"
	exit 2
fi
# decide jboss user 
if ( id $JBOSS_USER >/dev/null 2>&1 ); then
	Rjboss_home=`su - $JBOSS_USER -c'echo $JBOSS_HOME 2>/dev/null'`
	if [ 'x' != 'x'$Rjboss_home ]; then 
		echo "Jboss is installed. you cann't reinstall.."
		echo "JBOSS_HOME=$Rjboss_home" 
		exit 1
	fi
	read -p "jboss user is exist. [ Enter (Y|y) to <continue>, other to <Stop> ]: " prmp
	test ! "$prmp" && exit 1
	if [[ $prmp = 'y' || $prmp = 'Y' ]]; then
		userdel $JBOSS_USER
	else
		exit 6
	fi
fi

# search the largest partion to install jboss...
JbossBase=`df -lkP | grep -v 'File.*' | grep -v 'tmp.*' | grep -v '.*boot' |grep -v '100%' | sort -k2 -n -r | awk '{print $NF}' | head -n1`
if [ x"$JbossBase" = 'x/' ]; then
    JbossBase='/home'
fi

if [ ! -f "$JBOSS_ZIP" ]; then
	JBOSS_ZIP=`ls | grep "^jboss.*\.zip"` || {
		echo "Jboss_zip file $JBOSS_ZIP not exist.";
		exit 3;
	}
fi

trap "" INT
unzip -o $JBOSS_ZIP

# select jdkFile
if [ ! -f "$JDK_FILE" ]; then
	JDK_FILE=`ls | grep "^jdk.*\.tar\.gz" | grep ".*7.*"` || {
		echo "jdk7 file $JDK_FILE not exist! "
		exit 4
	}
fi
JDK_FILE="$DIR/$JDK_FILE"
echo "jdkFile=$JDK_FILE"
# select jbossFile
if [ ! -f "$JBOSS_FILE" ]; then
	JBOSS_FILE=`ls | grep ".*jboss.*\.tar\.gz" | tail -n1`
	test -z $JBOSS_FILE && { echo "jboss file $JBOSS_FILE not exist!! "; exit 5; }
fi
JBOSS_FILE="$DIR/$JBOSS_FILE"
echo "jbossFile=$JBOSS_FILE"

# generate a random password 
getPasswd() {
	strings /dev/urandom | grep -o '[[:alnum:]]' | head -n 14 | tr -d '\n';
}

PASSWORD=`getPasswd`
home_dir="${JbossBase}/${JBOSS_USER}"
useradd --home-dir "$home_dir" --create-home --shell "$SHELL" --password "$PASSWORD" jboss 2>/dev/null
echo "${PASSWORD}" > "$home_dir/password" ; chown $JBOSS_USER:$JBOSS_USER $home_dir/password
echo "$JBOSS_USER password: $PASSWORD, the password in $home_dir/password"
subit="su - ${JBOSS_USER} -c "

# jdk install
tar_xFile="tar -xzv -f $JDK_FILE -C $home_dir"
$subit "$tar_xFile " >/dev/null 2>&1
jdkFolder=`ls $home_dir | grep "^jdk.*" | head -n1`
echo "$jdkFolder installed ok."
JAVA_HOME="$home_dir/${jdkFolder}"
echo "JAVA_HOME=$JAVA_HOME"
echo "CLASSPATH=$CLASSPATH"

# jboss install
tar_xFile="tar -xzvf $JBOSS_FILE -C $home_dir"
$subit "$tar_xFile " >/dev/null 2>&1
jbossFolder=`ls $home_dir | grep "^jboss.*" | head -n1`
echo $jbossFolder "installed Ok!."
JBOSS_HOME="$home_dir/$jbossFolder"
echo "JBOSS_HOME=$JBOSS_HOME"

# export JBOSS_PORT JBOSS_HOME JAVA_HOME CLASS_PATH
# set iptables for jboss port
function set_iptab () {
	# modify the jboss service port
	server_xml="$JBOSS_HOME/server/default/deploy/jboss-web.deployer/server.xml"
	r_port=`sed -n '/<Conn.*/p' $server_xml | head -n1 | awk '{print $2}' | cut -d'=' -f2 | sed 's/\"//g'`
	if [ $r_port != $JBOSS_PORT ]; then
		sed -i 1,\/\<Conn\.\*\/s\/$r_port\/$JBOSS_PORT\/ $server_xml
	fi
	
	# Add iptables allow port $IP_PORT for web  and redirect t0  $JBOSSS_PORT
	iptables -t filter -L INPUT | grep 'NEW' >/dev/null 2>&1 || {
		/etc/init.d/iptables start ;
		chkconfig --level 35 iptables on;
	}
	
	iptables -P INPUT DROP
	st_num=$(iptables -t filter -L INPUT  --line-number | grep NEW | head -n1 | awk '{print $1}')
	iptables -t filter -L INPUT -n | grep "$JBOSS_PORT" ||\
	 iptables -t filter -I INPUT $st_num -p tcp -m state --state NEW -m tcp --dport $JBOSS_PORT -j ACCEPT
	iptables -t nat -L PREROUTING -n | grep $IP_PORT ||\
	 iptables -t nat -A PREROUTING -p tcp --dport $IP_PORT -j REDIRECT --to-port $JBOSS_PORT
	/etc/init.d/iptables save
}
# check the host and natwork
hostsCheck() {
	local netInfo=''
	local defNet=''	
	if netInfo=$(route | grep 'default'); then
		true
	else
		netInfo=`ip addr show | grep inet | grep -v '127.0' | grep -v 'inet6' | head -n1`
	fi
	# network information 
	local defNet=`echo $netInfo | awk '{print $2}' | cut -d'.' -f '1-3'`
	local ipUsed=$(ip addr show | grep $defNet | awk '{print $2}' | cut -d'/' -f1)
	local adapterUsed=$(ip addr show | grep $defNet | awk '{print $NF}')
	
	# host name get and set 
	local hostName=`hostname`
	hosts_u=`grep -v 'localhost' /etc/hosts`
	li=`wc -l /etc/hosts | cut -d' ' -f1`
	to_hosts="echo $ipUsed $hostName"
	if [ x"$hosts_u" = 'x' ]; then
		if [ $li -ne 2 ]; then
			cat << EOF >/etc/hosts
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
EOF
		fi
		$to_hosts >> /etc/hosts
	else
		if [ $li -gt 3 ]; then
			cat << EOF > /etc/hosts
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
EOF
			$to_hosts >> /etc/hosts
		fi
		hosts_i=`echo "$hosts_u" | cut -d' ' -f1` && hosts_n=`echo "$hosts_u" | cut -d' ' -f2`
		if [ $hosts_i != $ipUsed -o $hosts_n != $hostName ];then
			sed -i \/$hosts_i\/d /etc/hosts
			$to_hosts >> /etc/hosts
		fi 
	fi
	grep -v 'localhost' /etc/hosts
}


if [ $IPTAB_ON = 1 ]; then
	set_iptab
else
	/etc/init.d/iptables stop
	chkconfig iptables off
fi

# check the /etc/hosts file 
hostsCheck

getDay=`date`
# generate java env file 	javaenv.shell
cat << EOF > $home_dir/$JAVA_ENV
# Java and Jboss env profile
# id .javaenv java env file
# Auth: zheng_mingli@eseals.cn
# $getDay 
JAVA_HOME=$JAVA_HOME
CLASSPATH=.:\$JAVA_HOME/lib/dt.jar:\$JAVA_HOME/lib/tools.jar
JAVAPTH=\$JAVA_HOME/bin
JBOSS_HOME=$JBOSS_HOME
JBOSS_USER=$JBOSS_USER
PATH=\$JAVAPTH:\$HOME/bin:\$PATH
# LC_ALL="zh_CN.GBK"   
export LANG="zh_CN.GBK"
export JAVA_HOME CLASSPATH JBOSS_HOME JBOSS_USER
export PATH
EOF

chown $JBOSS_USER:$JBOSS_USER $home_dir/$JAVA_ENV
echo ". $JAVA_ENV" >> $home_dir/.bash_profile

#generate the jboss service file to /etc/init.d/jboss
cat << EOF >/etc/init.d/jboss
#!/bin/sh
# chkconfig: 345 96 3
# description:	JBoss Control Script
# Authors:      Bill Nottingham <notting@redhat.com>
# Modify:	zheng_mingli@eseals.cn
# date: $getDay
### BEGIN INIT INFO
# Provides: $JBOSS_USER
# Short-Description: JBoss Control Script
# Description: JBoss Control Script
### END INIT INFO
#
# Id: jboss_init_redhat.sh 71252 2008-03-25 17:52:00Z dbhole
#
# JBoss Control Script
#
#define where java is  - this is the JavaHome 
source $home_dir/$JAVA_ENV

JAVA_HOME=\${JAVA_HOME:-"$JAVA_HOME"}

#define where jboss is - this is the directory containing directories log, bin, conf etc
JBOSS_HOME=\${JBOSS_HOME:-"$JBOSS_HOME"}

#define the user under which jboss will run, or use 'RUNASIS' to run as the current user
JBOSS_USER=\${JBOSS_USER:-"$JBOSS_USER"}

#make sure java is in your path
JAVAPTH=\${JAVAPTH:-"\$JAVA_HOME/bin"}

#configuration to use, usually one of 'minimal', 'default', 'all'
JBOSS_CONF=\${JBOSS_CONF:-"default"}

#if JBOSS_HOST specified, use -b to bind jboss services to that address
JBOSS_BIND_ADDR=\${JBOSS_HOST:+"-b \$JBOSS_HOST"}

#define the script to use to start jboss
JBOSSSH=\${JBOSSSH:-"\$JBOSS_HOME/bin/run.sh -c \$JBOSS_CONF \$JBOSS_BIND_ADDR"}

# 
JBOSSSCRIPT=\${JBOSSSCRIPT:-"\$JBOSS_HOME/bin/run.sh"}

if [ "\$JBOSS_USER" = "RUNASIS" ]; then
  SUBIT=""
else
  SUBIT="su - \$JBOSS_USER -c "
fi

if [ -n "\$JBOSS_CONSOLE" -a ! -d "\$JBOSS_CONSOLE" ]; then
  # ensure the file exists
  touch \$JBOSS_CONSOLE
  if [ ! -z "\$SUBIT" ]; then
    chown \$JBOSS_USER \$JBOSS_CONSOLE
  fi 
fi

if [ -n "\$JBOSS_CONSOLE" -a ! -f "\$JBOSS_CONSOLE" ]; then
  echo "WARNING: location for saving console log invalid: \$JBOSS_CONSOLE"
  echo "WARNING: ignoring it and using /dev/null"
  JBOSS_CONSOLE="/dev/null"
fi

#define what will be done with the console log
JBOSS_CONSOLE=\${JBOSS_CONSOLE:-"/dev/null"}

JBOSS_CMD_START="cd \$JBOSS_HOME/bin; \$JBOSSSH"

if [ -z "\`echo \$PATH | grep \$JAVAPTH\`" ]; then
  export PATH=\$JAVAPTH:\$PATH
fi

if [ ! -d "\$JBOSS_HOME" ]; then
  echo JBOSS_HOME does not exist as a valid directory : \$JBOSS_HOME
  exit 1
fi

echo JBOSS_CMD_START = \$JBOSS_CMD_START

function procrunning() {
   procid=0
   for procid in \`/sbin/pidof -x "\$JBOSSSCRIPT"\`; do
       ps -fp \$procid | grep "\${JBOSSSH% *}" > /dev/null && pid=\$procid
   done
}


stop() {
    pid=0
    procrunning
    if [ \$pid = '0' ]; then
        echo -n -e "\nNo JBossas is currently running\n"
        exit 1
    fi

    RETVAL=1

    # If process is still running

    # First, try to kill it nicely
    for id in \`ps --ppid \$pid | awk '{print \$1}' | grep -v "^PID\$"\`; do
       if [ -z "\$SUBIT" ]; then
           kill -9 \$id
       else
           \$SUBIT "kill -9 \$id"
       fi
    done

    sleep=0
    while [ \$sleep -lt 120 -a \$RETVAL -eq 1 ]; do
        echo -n -e "\nwaiting for processes to stop";
        sleep 10
        sleep=\`expr \$sleep + 10\`
        pid=0
        procrunning
        if [ \$pid == '0' ]; then
            RETVAL=0
        fi
    done

    # Still not dead... kill it

    count=0
    pid=0
    procrunning

    if [ \$RETVAL != 0 ] ; then
        echo -e "\nTimeout: Shutdown command was sent, but process is still running with PID \$pid"
        exit 1
    fi

    echo
    exit 0
}

case "\$1" in
start)
    cd \$JBOSS_HOME/bin
    if [ -z "\$SUBIT" ]; then
        eval \$JBOSS_CMD_START >\${JBOSS_CONSOLE} 2>&1 &
    else
        \$SUBIT "\$JBOSS_CMD_START >\${JBOSS_CONSOLE} 2>&1 &" 
    fi
    ;;
stop)
    stop
    ;;
restart)
    \$0 stop
    \$0 start
    ;;
*)
    echo "usage: \$0 (start|stop|restart|help)"
esac
EOF

chmod +x /etc/init.d/jboss
chkconfig --add jboss && chkconfig --level 35 jboss on
upgr="/home/upgrade"
	
if [ ! -d $upgr ];then
	mkdir -p $upgr
fi
chown -R $JBOSS_USER:$JBOSS_USER $upgr

# Jvm memory set -- 
mem=`free -m | grep -w 'Mem' | awk '{print $2}'`
if [ $JBOSS_AND_ORACLE = 1 ]; then
	mem=$(expr $mem / 4)
else
	mem=$(expr $mem / 2)
fi
xmx=${mem}"m"
perm=$(($mem / 8))"m"
new=$(($mem / 6))"m"
run_conf="$JBOSS_HOME/bin/run.conf"

if [ -f $run_conf ]; then
	mv -f $run_conf $run_conf"_bak"
fi

cat << EOF > $run_conf
# ### run.conf $getDay zheng_mingli@eseals.com  $
#
# JBoss Bootstrap Script Configuration
#
# default Xss=Xms=TotalMem/4 or TotalMem/2 you can modify by Production environment to optimize the jvm
# default PermSize=Xms/8
# default NewSize=Xms/6
#
#

  
if [ "x\$JAVA_OPTS" = "x" ]; then
   JAVA_OPTS="-server -Xss256k -Xms$xmx -Xmx$xmx -XX:PermSize=$perm -XX:MaxPermSize=$perm -XX:NewSize=$new -XX:MaxNewSize=$new -XX:+UseParallelGC -XX:+UseParallelOldGC -XX:ParallelGCThreads=12 -Dsun.rmi.dgc.client.gcInterval=3600000 -Dsun.rmi.dgc.server.gcInterval=3600000 -Djava.awt.headless=true"
fi
EOF
chown $JBOSS_USER:$JBOSS_USER $run_conf
#
# generate the jboss file in JBOSS_USER/bin/jboss.sh. 
# jboss.sh to manage the jboss start stop ...
# 
bin_dir="${home_dir}/bin"
if [ ! -d $bin_dir ]; then
	mkdir -p $bin_dir
fi

cat << EOF > $bin_dir/jboss
#!/usr/bin/env bash
# id jboss.sh 
# eseals jboss manage script 
# by.zheng_mingli@eseals.cn
# $getDay

# source $home_dir/$JAVA_ENV

JAVA_HOME=\${JAVA_HOME:-"$JAVA_HOME"}

#define where jboss is - this is the directory containing directories log, bin, conf etc
JBOSS_HOME=\${JBOSS_HOME:-"$JBOSS_HOME"}

#define the user under which jboss will run, or use 'RUNASIS' to run as the current user
JBOSS_USER=\${JBOSS_USER:-"$JBOSS_USER"}

#make sure java is in your path
JAVAPTH=\${JAVAPTH:-"\$JAVA_HOME/bin"}

#configuration to use, usually one of 'minimal', 'default', 'all'
JBOSS_CONF=\${JBOSS_CONF:-"default"}

#if JBOSS_HOST specified, use -b to bind jboss services to that address
JBOSS_BIND_ADDR=\${JBOSS_HOST:+"-b \$JBOSS_HOST"}

#define the script to use to start jboss
JBOSSSH=\${JBOSSSH:-"\$JBOSS_HOME/bin/run.sh -c \$JBOSS_CONF \$JBOSS_BIND_ADDR"}

# current user name
RUNASIS=\`whoami\`

# Jboss script file
JBOSSSCRIPT=\${JBOSSSCRIPT:-"\$JBOSS_HOME/bin/run.sh"}

if [ "\$JBOSS_USER" = "\$RUNASIS" ]; then
  SUBIT=""
else
  SUBIT="su - \$JBOSS_USER -c "
fi
if [ -n "\$JBOSS_CONSOLE" -a ! -d "\$JBOSS_CONSOLE" ]; then
  # ensure the file exists
  touch \$JBOSS_CONSOLE
  if [ ! -z "\$SUBIT" ]; then
    chown \$JBOSS_USER \$JBOSS_CONSOLE
  fi
fi

if [ -n "\$JBOSS_CONSOLE" -a ! -f "\$JBOSS_CONSOLE" ]; then
  echo "WARNING: location for saving console log invalid: \$JBOSS_CONSOLE"
  echo "WARNING: ignoring it and using /dev/null"
  JBOSS_CONSOLE="/dev/null"
fi
#define what will be done with the console log
JBOSS_CONSOLE=\${JBOSS_CONSOLE:-"/dev/null"}

JBOSS_CMD_START="cd \$JBOSS_HOME/bin; \$JBOSSSH"

if [ -z "\`echo \$PATH | grep \$JAVAPTH\`" ]; then
  export PATH=\$JAVAPTH:\$PATH
fi

if [ ! -d "\$JBOSS_HOME" ]; then
  echo JBOSS_HOME does not exist as a valid directory : \$JBOSS_HOME
  exit 1
fi

function procrunning() {
   procid=0
   for procid in \`/sbin/pidof -x "\$JBOSSSCRIPT"\`; do
       ps -fp \$procid | grep "\${JBOSSSH% *}" > /dev/null && pid=\$procid
   done
}
function procJps() {
   pid=\`ps -ef | grep jboss | grep -w 'Main' | grep -v 'grep'\`
}

stop() {
    pid=0
    procrunning
    if [ \$pid = '0' ]; then
        pid=\`\$JAVAPTH/jps | grep -w 'Main'| awk '{print \$1}'\`
        if [[ -n \$pid && \$pid != '0' ]];then
                echo "jboss running by dubug......"
                kill -9 \$pid && {
                        echo "Waiting for stop jboss..."
                        echo "Jboss Shutdown complete!"
                        exit 0;
                }||{
                        echo "Current Jboss service status is WRONG.."
                        echo "start Jboss service must by \$JBOSS_USER"
                        exit 1;
                }

        fi
        echo -n -e "\nNo JBossas is currently running\n"
        exit 1
    fi

    RETVAL=1
    for id in \`ps --ppid \$pid | awk '{print \$1}' | grep -v "^PID\$"\`; do
       if [ -z "\$SUBIT" ]; then
           kill -9 \$id
       else
           \$SUBIT "kill -9 \$id"
       fi
    done

    sleep=0
    while [ \$sleep -lt 120 -a \$RETVAL -eq 1 ]; do
        echo -n -e "\nwaiting for processes to stop";
        sleep 10
        sleep=\`expr \$sleep + 10\`
        pid=0
        procrunning
        if [ \$pid == '0' ]; then
            RETVAL=0
        fi
    done
  # Still not dead... kill it

    count=0
    pid=0
    procrunning
    if [ \$RETVAL != 0 ] ; then
        echo -e "\nTimeout: Shutdown command was sent, but process is still running with PID \$pid"
        exit 1
    fi
    echo 
    exit 0
}
status() {
    pid=0
    procrunning
    if [ \$pid = '0' ];then
        pid=\`\$JAVAPTH/jps | grep -w 'Main'| awk '{print \$1}'\`
        if [[ -n \$pid && \$pid != '0' ]];then
                echo "jboss running by dubug. jboss pid: \$pid "
                echo
                exit 0
        fi
        echo -n -e "\nNo JBossas is currently running\n"
        exit 0
    fi

    for id in \`ps --ppid \$pid | awk '{print \$1}' | grep -v "^PID\$"\`; do
        echo "Jboss is running. pid:  \$id"      
    done
    echo 
    exit 0
}

clean() {
    tmpFile="\$JBOSS_HOME/server/default/tmp"
    workFile="\$JBOSS_HOME/server/default/work"
    pid=\$(jps | grep 'Main' | awk '{print \$1}')
    if [ 'x'\$pid != 'x' ]; then
        echo "jboss is running. pid: \${pid}. clean cache must stop jboss."
        exit 1
    fi
    cd \$tmpFile && rm -rf *
    cd \$workFile && rm -rf *
    echo "Clean cache ok.." 
    exit 0
}

backup() {
    WAR=$WAR
    if [ \$JBOSS_CONF = 'default' ]; then
        depPath=\$JBOSS_HOME/server/default/deploy
    fi
    day=\`date +%F\`
    eval "cd ~\$JBOSS_USER"
    if [ ! -d war_bak ]; then
        mkdir -p war_bak
    fi
 
    if [ -f \$depPath/\$WAR ]; then
        cp \$depPath/\$WAR war_bak/\$WAR_\$day
        echo "backup ok. war_bak/\$WAR_\$day"
    else
        echo "war file not find. backup failed!"
    fi
}

deploy() {
    pid=0
    procJps
    if [[ -n \$pid && \$pid -gt 0 ]];then
        echo "Jboss service is running, pid: \${pid}. " 
        exit 1
    fi
    uid=\`id -u\`
    if (( \$uid  == 0 )); then
        echo "deploy war package must be jboss"
        exit 1
    fi
    #if (( \$# < 1 ));then
    #    echo "deploy file not found."
    #    echo "usage: jboss deploy eseals.war"
    #    exit 1
    #fi
    backup
    if [ \$JBOSS_CONF = 'default' ]; then
        war_file="\$JBOSS_HOME/server/default/deploy/\$WAR"
    fi
    war=\$1
    if [ -f \$war ];then
        cp \$war \$war_file && echo "deploy success, you can use <jboss start> to start jboss service!"
    fi 
}
case "\$1" in
start)
    cd \$JBOSS_HOME/bin
    if [ -z "\$SUBIT" ]; then
        eval \$JBOSS_CMD_START >\${JBOSS_CONSOLE} 2>&1 &
    else
        \$SUBIT "\$JBOSS_CMD_START >\${JBOSS_CONSOLE} 2>&1 &"
    fi
    echo "Jboss start ok!"
    ;;
stop)
    stop
    ;;
restart)
    \$0 stop
    \$0 start
    ;;
debug)
   \$JBOSSSCRIPT &
   ;;
clean)
   clean
   ;;
status)
   status
   ;;
deploy)
   if (( \$# == 2 )); then
       war=\$2
       pth=\`dirname \$war\`
  echo "pth=\$pth"
       if [ \$pth = '.' ];then
           pth=\`pwd\`'/'
echo \$pth
       else
           pth=''
       fi
       if [ -f \$war ];then
           deploy "\$pth\$war"
       fi
   else
      echo "Deploy argument error."
   fi
   ;;
help)
   uName=`basename \$0`
   echo "\$uName start    ---   start jboss service.    root you can use >>>>service jboss start"
   echo "\$uName stop     ---   stop jboss service.     root can use >>>> service jboss stop" 
   echo "\$uName restart  ---   stop jboss and start jboss."
   echo "\$uName status   ---   get the jboss service status. "
   echo "\$uName debug    ---   run jboss service debug mode." 
   echo "\$uName deploy   ---   deploy the war. "
   echo "\$uName backup   ---   backup the jboss war package." 
   echo "\$uName clean    ---   clean the jboss cache. "
   echo "\$uName help     ---   display this help. "
   ;;
*)
   echo "usage: \$0 (start|stop|restart|status|debug|deploy|clean|help)"
esac
EOF

chmod +x $bin_dir/jboss
chown -R $JBOSS_USER:$JBOSS_USER $home_dir
echo;echo;echo;echo;
echo "Jboss  installed sucess. goodluck!!"
echo "You can use PORT: $JBOSS_PORT, $IP_PORT "
echo ""
echo "======================================================"
echo "       JAVA_HOME:  $JAVA_HOME "
echo "      JBOSS_HOME:  $JBOSS_HOME "
echo "      JBOSS_USER:  $JBOSS_USER "
echo "      JBOSS_PORT:  $JBOSS_PORT  "
echo "        WEB_PORT:  $IP_PORT    "
echo "" 
echo "      Manage Jboss, you can:   "
echo '      1.  su - jboss  '
echo '      2.  jboss start '
echo '      3.  jboss stop  '
echo '      4.  jboss deploy '
echo '      5.  jboss help   '
echo "====================================================="

# Jboss install over.