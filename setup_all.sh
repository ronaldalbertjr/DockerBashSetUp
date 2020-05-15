numberOfWebContainers=3
numberOfDatabaseContainers=3
databaseContainerName="db"
databaseHostname="dbgc"
webContainerName="web"
webHostname="web"
lbContainerName="lb"
haproxyHostname="haproxy"

mkdir -p ~/volumes/web/html

for i in $(seq 1 1 $numberOfWebContainers)
do
    docker run --name "$webContainerName$i" --hostname "$webHostname$i" -p "808$i:80" -d -v ~/volumes/web/html/:/var/www/html richarvey/nginx-php-fpm:latest
done

mkdir -p ~/volumes/lb/haproxy

touch ~/volumes/lb/haproxy/haproxy.cfg

echo "frontend myfrontend
  bind *:80
  mode http
  default_backend mybackend

backend mybackend
  mode http
  balance roundrobin
  option httpchk HEAD
  server web1 172.17.0.2:80
  server web2 172.17.0.3:80
  server web3 172.17.0.4:80" > ~/volumes/lb/haproxy/haproxy.cfg

docker run -d --name "$lbContainerName" --hostname "$haproxyHostname" -p "80:80" -v ~/volumes/lb/haproxy:/usr/local/etc/haproxy:ro haproxy:latest

for i in $(seq 1 1 $numberOfDatabaseContainers)
do
        mkdir -p ~/volumes/db$i/conf.d
        touch ~/volumes/db$i/conf.d/my.cnf
        mkdir -p ~/volumes/db$i/datadir
        if [ $i -eq 1 ]; then
                docker run -d --name "$databaseContainerName$i" --hostname "$databaseHostname$i" --expose "3306" --expose "4444" --expose "4567" --expose "4568" --env MYSQL_ROOT_PASSWORD="rootpass" --env MYSQL_USER="maxscaleuser" --env MYSQL_PASSWORD="maxscalepass" --volume ~/volumes/db$i/datadir:/var/lib/mysql --volume ~/volumes/db$i/conf.d:/etc/mysql/mariadb.conf.d mariadb/server:10.4 --wsrep_cluster_address="gcomm://"
        else
                docker run -d --name "$databaseContainerName$i" --hostname $databaseHostname$i --add-host=dbgc1:172.17.0.6 --expose "3306" --expose "4444" --expose "4567" --expose "4568" --env MYSQL_ROOT_PASSWORD="rootpass" --env MYSQL_USER="maxscaleuser" --env MYSQL_PASSWORD="maxscalepass" --volume ~/volumes/db$i/datadir:/var/lib/mysql --volume ~/volumes/db$i/conf.d:/etc/mysql/mariadb.conf.d mariadb/server:10.4 --wsrep_cluster_address="gcomm://dbgc1"
        fi

        echo "[mysqld]
        bind-address = 0.0.0.0
        default_storage_engine = InnoDB
        binlog_format = ROW

        wsrep_on = ON
        wsrep_cluster_name = \"Galera\"
        wsrep_provider = /usr/lib/galera/libgalera_smm.so
        wsrep_sst_method = rsync
        wsrep_sst_auth=\"root:rootpass\"" > ~/volumes/db$i/conf.d/my.cnf
done

sleep 30

for i in $(seq 1 1 $numberOfDatabaseContainers)
do
        docker restart "$databaseContainerName$i"
        if [ $i -eq 1 ]; then
        	sleep 10
	fi
done

docker exec -it db1 mysql -uroot -prootpass -e "grant select on mysql.* to 'maxscaleuser'@'%' IDENTIFIED BY 'maxscalepass';"
docker exec -it db1 mysql -uroot -prootpass -e "grant replication slave on *.* to 'maxscaleuser'@'%';"
docker exec -it db1 mysql -uroot -prootpass -e "grant replication client on *.* to 'maxscaleuser'@'%';"
docker exec -it db1 mysql -uroot -prootpass -e "grant show databases on *.* to 'maxscaleuser'@'%';"
docker exec -it db1 mysql -uroot -prootpass -e "GRANT CREATE, DROP, SELECT, INSERT, UPDATE, DELETE ON *.* TO 'maxscaleuser'@'%';"
docker exec -it db1 mysql -uroot -prootpass -e "flush privileges;"

mkdir ~/volumes/dbproxy
touch ~/volumes/dbproxy/maxscale.cnf

echo "[db1]
type = server
address = dbgc1
port = 3306
protocol = MariaDBBackend
serv_weight = 2

[db2]
type = server
address = dbgc2
port = 3306
protocol = MariaDBBackend
serv_weight = 1

[db3]
type = serveraddress = dbgc3
port = 3306
protocol = MariaDBBackend
serv_weight = 1

[MariaDB-Monitor]
type = monitor
module = galeramon
servers = db1, db2, db3
user = maxscaleuser
password = maxscalepass
monitor_interval = 2000
disable_master_failback = 1

[Read-Write-Listener]
type = listener
service = Read-Write-Service
protocol = MariaDBClient
port = 3306
address = 0.0.0.0

[Read-Write-Service]
type = service
router = readwritesplit
servers = db1, db2, db3
user = maxscaleuser
password = maxscalepass
slave_selection_criteria = LEAST_GLOBAL_CONNECTIONS
master_failure_mode = error_on_write
max_slave_connections = 1
weightby = serv_weight
enable_root_user = true" >  ~/volumes/dbproxy/maxscale.cnf

docker run -d --name dbproxy --hostname maxscale --add-host=dbgc1:172.17.0.6 --add-host=dbgc2:172.17.0.7 --add-host=dbgc3:172.17.0.8 -p 4006:4006 -p 4008:4008 -p 8989:8989 -v ~/volumes/dbproxy/maxscale.cnf:/etc/maxscale.cnf mariadb/maxscale:latest

mv ../webapp/phpcode/* ~/volumes/web/html
mv ../webapp/database/studentinfo-db.sql ~/volumes
docker exec -it db1 mysql -uroot -prootpass -e "source ~/volumes/studentinfo-db.sql;"
