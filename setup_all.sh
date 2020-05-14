numberOfWebContainers=3
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
