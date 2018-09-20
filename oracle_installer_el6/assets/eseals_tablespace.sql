create tablespace esealsspace
logging
datafile 'eseals01.dbf'
size 400m
autoextend on
next 32m maxsize 4096m
extent management local;

create tablespace esealsspace2
logging
datafile 'eseals02.dbf'
size 200m
autoextend on
next 32m maxsize 4096m
extent management local;

create tablespace esealsspace3
logging
datafile 'eseals03.dbf'
size 200m
autoextend on
next 32m maxsize 4096m
extent management local;


create temporary tablespace esealsspace_temp
tempfile 'eseals01_temp.dbf'
SIZE 4m
autoextend on
next 16m maxsize 2048m
extent management local;

create temporary tablespace esealsspace_temp2
tempfile 'eseals02_temp.dbf'
size 4m
autoextend on
next 4m maxsize 2048m
extent management local;

create temporary tablespace esealsspace_temp3
tempfile 'eseals03_temp.dbf'
size 4m
autoextend on
next 4m maxsize 2048m
extent management local;

create user eseals identified by "biceng"
default tablespace esealsspace
temporary tablespace esealsspace_temp;


GRANT CREATE USER, DROP USER, ALTER USER , CREATE ANY
VIEW , DROP ANY VIEW, EXP_FULL_DATABASE, IMP_FULL_DATABASE,
DBA, CONNECT, RESOURCE, CREATE SESSION  TO eseals; 
quit;