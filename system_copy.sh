#!/bin/sh
# System Copy  setup
#This script will Generat SQL cmds with SAP Note
# Get toplogy from Back.
# Add Servce
# Delroy Blake
echo  "hello"
# check if files exists and then remove it called with the filename augment

#help documention to be writeen later.
useage()
{}

clean_up()
{
if [ -e $1 ]
	then 
	rm $1
fi
}


#read data from file or declare needed  variables here

get_backup_topology_settings()
{
.
if [ -s source_backup.cfg ]
	then 
	include source_backup.cfg
else 
	SID=DEL
	PATH_TO_BACKUP="/backup/orginal/data/"
	BACKUP_PREFIX="COMPLETE_DATA_BACKUP"
fi
}


#This command goes against the orignal backups and gets the topology it is called with 3 augments SID,PATH_TO_BACKUP and BACKUP_PREFIX
get_backup_top()
{
clean_up svolume_id.tmp
clean_up s_volume_id.2tmp

local SID
local PATH_TO_BACKUP
local BACKUP_PREFIX

SID=$1
PATH_TO_BACKUP=$2
BACKUP_PREFIX=$3

/usr/sap/${SID}/SYS/exe/hdb/hdbbackupdiag -v -d ${PATH_TO_BACKUP} -b ${BACKUP_PREFIX} | grep "\ServiceName\|VolumeId" >> s_volume_id.tmp
awk 'NR%2{printf $0" ";next;}1'  s_volume_id.tmp > s_volume_id.2tmp
uniq s_volume_id.2tmp > source_volume_id.cfg
clean_up s_volume_id.2tmp
clean_up svolume_id.tmp
}

#read variable from file or declare them here
echo "read"

set_var()
{
	
if  [ -s system_copy.cfg ]
	then 
	include system_copy.cfg
else  
	TENANT_DB=MY_DB0
	NODE=mo-21313196d
	USERNAME=SYSTEM
	PASSSWD=MultiT3nant
	DATABASE=SYSTEMDB
	INST=00
	SQL_CMD=hdbsql
	CONN_STRING=" -i ${INST} -n ${NODE} -u ${USERNAMME} -p ${PASSSWD} -d SYSTEMDB -I"
fi

if [ -s source_volume_id.cfg ]
	then 
	INDEX_VOLUME_ID=$(awk '/indexserver/ {printf $4}'  source_volume_id.cfg) 
	XS_VOLUME_ID=$(awk '/xsengine/ {printf $4}' source_volume_id.cfg) 
else
	printf "%s\n" "INDEX_VOLUME_ID and XS_VOLUME_ID cannot be set without source_volume_id.cfg file"
fi
}

set_var

hdbsql_cmd()
{
cat > sql_cmd <<EOF
${SQL_CMD} ${CONN_STRING} 
EOF
}

#Here is where we get the services  and volumes that are running on the tenant DB called with augment of tenant DB NAME

get_info() 
{
local TENANT_DB
TENANT_DB=$1

cat > get_${TENANT_DB}_info.sql <<EOF
SELECT S.DATABASE_NAME, S.HOST, S.SERVICE_NAME, S.PORT, V.VOLUME_ID
FROM SYS_DATABASES.M_SERVICES S, SYS_DATABASES.M_VOLUMES V 
WHERE S.HOST = V.HOST AND S.PORT = V.PORT AND S.DATABASE_NAME = V.DATABASE_NAME AND S.DATABASE_NAME = '${TENANT_DB}';
EOF

cat > get_list_of_tenantdb.sql <<EOF
SELECT * FROM M_DATABASES;
EOF

cat > get_${TENANT_DB}_volumes.sql <<EOF
SELECT CONCAT(SUBSTRING(PATH, 1, LOCATE(PATH, '/', 0, 2)), SUBSTR_BEFORE(NAME, '@')) PATH, SUBSTR_BEFORE(NAME, '@') DB_VOLUME_ID, SUBSTR_AFTER(NAME, '@') NAME, VALUE
FROM M_TOPOLOGY_TREE 
WHERE PATH = '/volumes/*+|@' AND NAME LIKE CONCAT((SELECT SUBSTR_BEFORE(name, '@') DB_ID FROM M_TOPOLOGY_TREE WHERE PATH='/databases/*+|@' and NAME like '%name' and value = '${TENANT_DB}'), ':%');
EOF
}

get_status()
{

cat > get_${TENANT_DB}_status.sql <<EOF
select ${TENANT_DB} from M_DATABASES;
EOF
}

stop_tdb() 
{
cat > stop_${TENANT_DB}.sql <<EOF
alter system stop database ${TENANT_DB};
EOF
}

start_tdb() 
{
cat >  start_${TENANT_DB}.sql <<EOF
alter system start database ${TENANT_DB};
EOF
}

unset_tdb_index() 
{
cat > unset_${TENANT_DB}_INDEX__volumes.sql <<EOF
ALTER SYSTEM ALTER CONFIGURATION ('topology.ini', 'system') UNSET ('/volumes', '${INDEX_CURRENT_DB_VOLUME}')";
EOF
}

set_tdb_index_volume_id()
{
cat > set_${TENANT_DB}_volume_id.sql <<EOF
ALTER SYSTEM ALTER CONFIGURATION ('topology.ini', 'system') SET ('/host/${NODE}/indexserver/${INDEX_PORT}', 'volume')= '${INDEX_VOLUME_ID}';
EOF
}

alter_index_volumes()
{
cat > set_${TENANT_DB}_index_volumes.sql <<EOF
ALTER SYSTEM ALTER CONFIGURATION ('topology.ini', 'system') SET ('/volumes/${INDEX_TARGET_VOLUME}', 'active')= 'yes'
ALTER SYSTEM ALTER CONFIGURATION ('topology.ini', 'system') SET ('/volumes/${INDEX_TARGET_VOLUME}', 'catalog')= 'yes'
ALTER SYSTEM ALTER CONFIGURATION ('topology.ini', 'system') SET ('/volumes/${INDEX_TARGET_VOLUME}', 'database')= '${DATABASE_NUM}'
ALTER SYSTEM ALTER CONFIGURATION ('topology.ini', 'system') SET ('/volumes/${INDEX_TARGET_VOLUME}', 'location')= '${NODE}:${INDEX_PORT}'
ALTER SYSTEM ALTER CONFIGURATION ('topology.ini', 'system') SET ('/volumes/${INDEX_TARGET_VOLUME}', 'path')='${INDEX_PATH}'
ALTER SYSTEM ALTER CONFIGURATION ('topology.ini', 'system') SET ('/volumes/${INDEX_TARGET_VOLUME}', 'servicetype')= 'indexserver'
ALTER SYSTEM ALTER CONFIGURATION ('topology.ini', 'system') SET ('/volumes/${INDEX_TARGET_VOLUME}', 'tenant')= '-'
EOF
}

get_info()
{

cat > get_${TENANT_DB}_info.cmd <<EOF
${SQL_CMD} ${CONN_STRING} get_${TENANT_DB}_info.sql -o ${TENANT_DB}_service.cfg
EOF

cat > get_tenant_db.cmd <<EOF
${SQL_CMD} ${CONN_STRING}  get_list_of_tenantdb.sql -o tenant_db_list.cfg
EOF

cat >  get_${TENANT_DB}_volumes.cmd <<EOF
${SQL_CMD} ${CONN_STRING} get_${TENANT_DB}_volumes.sql -o ${TENANT_DB}_volumes.cfg
EOF
}

execute_cmd()
{
if [ -e $1 ]
then 
chmod 775 $1
$1
else 
printf "%s\n" "$1 does not exist"
fi
}


#setup information For Index server we get the current DB_VOLUME looks like 3:2 this will allow one to select indexserver xsengine etc by path and VOLUME_ID
#This will make dtabse changes for the services

get_index_info()
{
INDEX_CURRENT_DB_VOLUME=$(awk -F, '/indexserver/ {printf $2}' ${TENANT_DB}_volumes.cfg | sed 's/"//g')
INDEX_PORT=$(awk -F, '/indexserver/ {printf $4}'  ${TENANT_DB}_service.cfg)
INDEX_CURRENT_VOLUME_ID=$(awk -F, '/indexserver/ {printf $5}'  ${TENANT_DB}_service.cfg)
INDEX_TARGET_VOLUME=$(awk -v INDEX_V_ID="${INDEX_CURRENT_DB_VOLUME_ID}"-F, '/path/ && "/$INDEX_V_ID/" {printf $2}' ${TENANT_DB}_volumes.cfg | sed 's/"//g' | awk -v  ID="${INDEX_VOLUME_ID}" -F: 'BEGIN {OFS=":";} {print $1,ID}')
DATABASE_NUM=$(awk -v INDEX_V_ID="${INDEX_CURRENT_DB_VOLUME_ID}" -F, '/database/ && "/$INDEX_V_ID/" {printf $4}' ${TENANT_DB}_volumes.cfg | sed 's/"//g')
HDB_INDEX_TP=$(awk -v INDEX_V_ID="${INDEX_CURRENT_DB_VOLUME_ID}" -F, '/path/ && "/$INDEX_V_ID/" {print $4}' ${TENANT_DB}_volumes.cfg  | awk -F "/" '{print $2}' | awk -F "." '{print $1}' | sed "s/${INDEX_CURRENT_VOLUME_ID}$/${INDEX_VOLUME_ID}/")
HDB_INDEX_SP=$(awk -v INDEX_V_ID="${INDEX_CURRENT_DB__VOLUME_ID}" -F, '/path/ && "/$INDEX_V_ID/" {print $4}' ${TENANT_DB}_volumes.cfg  | awk -F "/" '{print $2}' | awk -F "." '{print $1}')
INDEX_PATH=$(awk -v INDEX_V_ID="$INDEX_CURRENT_DB_VOLUME_ID}" -F, '/path/ && "/$INDEX_V_ID/" {print $4}' ${TENANT_DB}_volumes.cfg | sed -e "s/${HDB_INDEX_SP}/${HDB_INDEX_TP}/" -e 's/"//g' )
}
get_xs_info()
{
	XS_CURRENT_DB_VOLUME=$(awk -F, '/xsengine/ {printf $2}' ${TENANT_DB}_volumes.cfg | sed 's/"//g')
	XS_PORT=$(awk -F, '/xsengine/ {printf $4}'  ${TENANT_DB}_service.cfg)
	XS_CURRENT_VOLUME_ID=$(awk -F, '/indexserver/ {printf $5}'  ${TENANT_DB}_service.cfg)
	XS_TARGET_VOLUME=$(awk -v INDEX_V_ID="${INDEX_CURRENT_DB_VOLUME_ID}"-F, '/path/ && "/$INDEX_V_ID/" {printf $2}' ${TENANT_DB}_volumes.cfg | sed 's/"//g' | awk -v  ID="${INDEX_VOLUME_ID}" -F: 'BEGIN {OFS=":";} {print $1,ID}')
	XS_DATABASE_NUM=$(awk -v INDEX_V_ID="${INDEX_CURRENT_DB_VOLUME_ID}" -F, '/database/ && "/$INDEX_V_ID/" {printf $4}' ${TENANT_DB}_volumes.cfg | sed 's/"//g')
	HDB_XS_TP=$(awk -v INDEX_V_ID="${INDEX_CURRENT_DB_VOLUME_ID}" -F, '/path/ && "/$INDEX_V_ID/" {print $4}' ${TENANT_DB}_volumes.cfg  | awk -F "/" '{print $2}' | awk -F "." '{print $1}' | sed "s/${INDEX_CURRENT_VOLUME_ID}$/${INDEX_VOLUME_ID}/")
	HDB_XS_SP=$(awk -v INDEX_V_ID="${INDEX_CURRENT_DB__VOLUME_ID}" -F, '/path/ && "/$INDEX_V_ID/" {print $4}' ${TENANT_DB}_volumes.cfg  | awk -F "/" '{print $2}' | awk -F "." '{print $1}')
	XS_PATH=$(awk -v INDEX_V_ID="$INDEX_CURRENT_DB_VOLUME_ID}" -F, '/path/ && "/$INDEX_V_ID/" {print $4}' ${TENANT_DB}_volumes.cfg | sed -e "s/${HDB_INDEX_SP}/${HDB_INDEX_TP}/" -e 's/"//g' )
	
}

print_test()
{
echo "INDEX_CURRENT_DB_VOLUME"=${INDEX_CURRENT_DB_VOLUME}
echo "INDEX_PORT"=${INDEX_PORT}
echo "INDEX_TARGET_VOLUME"=${INDEX_TARGET_VOLUME}
echo "DATABASE_NUM"=${DATABASE_NUM}
echo "HDB_INDEX_TP"=${HDB_INDEX_TP}
echo "HBD_INDEX_SP"=${HDB_INDEX_SP}
echo "INDEX_CURRENT_VOLUME_ID"=${INDEX_CURRENT_VOLUME_ID}
echo "INDEX_PATH"=${INDEX_PATH}
}


set_var
get_index_info
print_test
#print_test

alter_index_volumes
cat set_${TENANT_DB}_index_volumes.sql