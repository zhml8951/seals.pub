#!/bin/sh
. /home/u01/app/oracle/product/11.2.0/dbhome_1/install/utl/rootmacro.sh "$*"
. /home/u01/app/oracle/product/11.2.0/dbhome_1/install/utl/rootinstall.sh
/home/u01/app/oracle/product/11.2.0/dbhome_1/install/unix/rootadd.sh

#
# Root Actions related to network
#
/home/u01/app/oracle/product/11.2.0/dbhome_1/network/install/sqlnet/setowner.sh 

#
# Invoke standalone rootadd_rdbms.sh
#
/home/u01/app/oracle/product/11.2.0/dbhome_1/rdbms/install/rootadd_rdbms.sh

/home/u01/app/oracle/product/11.2.0/dbhome_1/rdbms/install/rootadd_filemap.sh 
