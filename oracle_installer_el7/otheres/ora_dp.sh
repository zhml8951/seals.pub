#!/bin/sh
if [ `id -u` == '0' ];then
    echo "Don't run as root"
    exit 1
fi
USER=eseals
PASS=biceng
SID=eseals
DUMP_NAME=dump_eseals
DMP_FILE="eseals_`date +%F`.dmp"
LOG="dump_`date +%F`.log"
home_dir=$(cd ~; pwd)
dmp_dir="$home_dir/db_dump/dump_eseals"

if [ ! -d $dmp_dir ];then
    mkdir -p $dmp_dir
fi

sqlplus / as sysdba <<EOF
create directory $DUMP_NAME as '$dmp_dir';
EOF
sqlplus / as sysdba <<EOF
grant read,write on directory $DUMP_NAME to $USER;
EOF

exp_dp(){
    expdp $USER/$PASS@$SID schemas=$USER dumpfile=$DMP_FILE directory=$DUMP_NAME logfile=$LOG
}

imp_dp(){
    if [ "x$1" == 'x' ]; then
        dmp_file=eseals.dmp
    else
        dmp_file=$1
    fi

    impdp $USER/$PASS@SID schemas=$USER directory=$DUMP_NAME dumpfile=$dmp_file schemas=$USER;
}

if [ "x$1" == 'x' ]; then
    echo "$0 --imp | --exp"
    exit 0
fi

for option
do
    case "$option" in 
      --exp)
        exp_dp ;;
      --imp)
        shift; 
        imp_dp $1 ;;
    esac
done
