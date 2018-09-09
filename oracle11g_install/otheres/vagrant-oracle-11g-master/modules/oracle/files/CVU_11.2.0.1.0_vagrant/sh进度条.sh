#!/bin/env sh

# 解压tar文件进度条， 要先计算文件容量
function untar_process_bar {
	# 解压一个tar文件，并显示进度条
	#
	if [ $# -ne 1 ]; then
	        echo "Usage: $0 file"
	        exit 1
	fi
	 
	TSIZE=0
	 
	for FSIZE in $(tar tvvf $1 | awk '{print $3}'); do
	    if [ "$FSIZE" = "${FSIZE//[^0-9]/}" ]; then
	        TSIZE=$((TSIZE+FSIZE))
	    fi
	done
	 
	[ $TSIZE -eq 0 ] && exit 1
	 
	MSG="Extracting..."
	PROG_POS=$((${#MSG}+1))
	PERC_POS=$((${#MSG}+53))
	 
	echo $MSG
	 
	PREV=-1
	NSIZE=0
	for FSIZE in $(tar xvvf $1 | awk '{print $3}'); do
	    if [ "$FSIZE" = "${FSIZE//[^0-9]/}" ]; then
	        NSIZE=$((NSIZE+FSIZE))
	        PERCENT=$((NSIZE*100/TSIZE))
	        if [ $PERCENT -ne $PREV ]; then
	            PLUS=$((PERCENT/2))
	            PROGRESS=$(printf "%.${PLUS}d" | tr '0' '+')
	            echo -e "\e[A\e[${PROG_POS}G${PROGRESS}=>"
	            echo -e "\e[A\e[${PERC_POS}G${PERCENT}%"
	            PREV=$PERCENT
	        fi
	    fi
	done
}


# 常用进度条
proc_bar() {
	function _bar {
		local _current=$1; local _total $2;
		local _maxlen=80; local _barlen=66;
		local _format="%-${_barlen}s%$((_maxlen-_barlen))s"
		local _perc="[$_current/$_total]"
		local _progress=$((_current*_barlen/_total))
		local _prog=$(for i in `seq 0 $_progress`; do printf '#'; done)
		printf "\r$_format" $_prog $_perc
	}

	for i in `seq 1 20`; do{
		_bar $i 20
		sleep 0.5
	}done
	echo ""
}

# 简容进度条
processbar_simple(){
	b=''
	i=0
	while [ $i -le  100 ]
	do
	    printf "progress:[%-50s]%d%%\r" $b $i
	    sleep 0.5 
	    i=`expr 2 + $i`    
	    b=#$b
	done
	echo
}






