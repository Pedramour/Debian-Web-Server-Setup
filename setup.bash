#!/bin/bash

HOSTNAME=${1}
IP=${2}


if [ -z "${IP}" ]; then
  IP=$(/sbin/ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}')
fi

if [ -z "${IP}" ]; then
  IP='127.0.0.1'
fi


echo $HOSTNAME > /etc/hostname
echo -e $IP'\t'$HOSTNAME >> /etc/hosts


apt-get install -y less bind9 dnsutils nginx mysql-server mysql-client php5-fpm php5-mysql php-pear php5-gd
pear channel-discover pear.drush.org
pear install drush/drush


mkdir /etc/bind/data
mkdir -p /websites/webfiles/$HOSTNAME
mkdir -p /websites/log/nginx

rm /etc/nginx/sites-enabled/default
touch /etc/nginx/sites-available/$HOSTNAME
ln -s /etc/nginx/sites-available/$HOSTNAME /etc/nginx/sites-enabled/$HOSTNAME


cat << EOF > /etc/bind/data/db.$HOSTNAME
;
; BIND data file for local loopback interface
;
\$TTL	3600
@	IN	SOA	ns1.$HOSTNAME. jazaali.gmail.com. (
   2014071800		; Serial
         3600   ; Refresh [1h]
          900   ; Retry   [15m]
      1209600   ; Expire  [2w]
          300 ) ; Negative Cache TTL [30m]
;
@       IN      NS      ns1.$HOSTNAME.
@       IN      NS      ns2.$HOSTNAME.
@       IN      MX      10 mail.$HOSTNAME.

@       IN      A       $IP
ns1     IN      A       $IP
ns2     IN      A       $IP

www     IN      A       $IP
mail    IN      A       $IP
EOF


cat << EOF > /etc/bind/data/db.$(echo $IP | cut -d. -f1)
;
; BIND reverse data file for local loopback interface
;
\$TTL	3600
@	IN	SOA	ns1.$HOSTNAME. jazaali.gmail.com. (
   2014100500		; Serial
         3600   ; Refresh [1h]
          900   ; Retry   [15m]
      1209600   ; Expire  [2w]
          300 ) ; Negative Cache TTL [30m]
;
@       IN      NS      ns1.$HOSTNAME.
@       IN      NS      ns2.$HOSTNAME.
1       IN      PTR     www.$HOSTNAME.
2       IN      PTR     mail.$HOSTNAME.
EOF


cat << EOF >> /etc/bind/named.conf.local

zone "$HOSTNAME" {
  type master;
  file "/etc/bind/data/db.$HOSTNAME";
};
 
zone "0.$(echo $IP | cut -d. -f3).$(echo $IP | cut -d. -f2).$(echo $IP | cut -d. -f1).in-addr.arpa" {
  type master;
  notify no;
  file "/etc/bind/data/db.$(echo $IP | cut -d. -f1)";
};
EOF


# TODO: Config /etc/php5/fpm/php.ini
# TODO: Config /etc/php5/pool.d/www.conf


/etc/init.d/hostname.sh
/etc/init.d/bind9 restart
/etc/init.d/nginx start
/etc/init.d/php5-fpm restart 
