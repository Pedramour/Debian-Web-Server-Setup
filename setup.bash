#!/bin/bash

HOSTNAME=${1}
IP=${2}


if [ -z "${HOSTNAME}" ]; then
  echo "HOSTNAME must be set."
  exit 0
fi

if [ -z "${IP}" ]; then
  IP=$(/sbin/ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}')
fi

if [ -z "${IP}" ]; then
  IP='127.0.0.1'
fi


echo $HOSTNAME > /etc/hostname
echo -e $IP'\t'$HOSTNAME >> /etc/hosts


cat << EOF >> /etc/apt/sources.list

# NGINX
deb http://nginx.org/packages/debian/ wheezy nginx
deb-src http://nginx.org/packages/debian/ wheezy nginx
EOF

wget -P /etc/ssh/ http://nginx.org/keys/nginx_signing.key
apt-key add /etc/ssh/nginx_signing.key


apt-get update
apt-get upgrade -y


dpkg-reconfigure tzdata
apt-get install -y less bind9 dnsutils nginx mysql-server mysql-client php5-fpm php5-mysql php-pear php5-gd
pear channel-discover pear.drush.org
pear install drush/drush


mkdir /etc/bind/data
mkdir -p /websites/webfiles
mkdir -p /websites/log/nginx


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


cat << EOF > /etc/nginx/sites-available/$HOSTNAME
server {
  listen 80;
  server_name $HOSTNAME www.$HOSTNAME;
  root        /websites/webfiles/$HOSTNAME;
  error_log   /websites/log/nginx/$HOSTNAME-error.log;
  access_log  /websites/log/nginx/$HOSTNAME-access.log;

  # Enable compression, this will help if you have for instance advagg‎ module
  # by serving Gzip versions of the files.
  #gzip_static on;

  location = /favicon.ico {
    log_not_found off;
    access_log off;
  }

  location = /robots.txt {
    allow all;
    log_not_found off;
    access_log off;
  }

  # This matters if you use drush prior to 5.x
  # After 5.x backups are stored outside the Drupal install.
  location = /backup {
    deny all;
  }

  # Very rarely should these ever be accessed outside of your lan
  location ~* \.(txt|log)$ {
    allow 192.168.0.0/16;
    deny all;
  }

  location ~ \..*/.*\.php$ {
    return 403;
  }

  # No no for private
  location ~ ^/sites/.*/private/ {
  return 403;
  }

  # Block access to "hidden" files and directories whose names begin with a
  # period. This includes directories used by version control systems such
  # as Subversion or Git to store control files.
  location ~ (^|/)\. {
    return 403;
  }

  location / {
    # This is cool because no php is touched for static content
    try_files \$uri @rewrite;
  }

  location @rewrite {
    # You have 2 options here
    # For D7 and above:
    # Clean URLs are handled in drupal_environment_initialize().
    #rewrite ^ /index.php;
    # For Drupal 6 and bwlow:
    # Some modules enforce no slash (/) at the end of the URL
    # Else this rewrite block wouldn't be needed (GlobalRedirect)
    rewrite ^/(.*)$ /index.php?q=\$1;
    # Drupal in a subdirectory
    #rewrite ^/([^/]*)/(.*)(/?)$ /\$1/index.php?q=\$2&\$args;
  }

  location ~ \.php$ {
    fastcgi_split_path_info ^(.+\.php)(/.+)$;
    #NOTE: You should have "cgi.fix_pathinfo = 0;" in php.ini
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME \$request_filename;
    fastcgi_intercept_errors on;
    fastcgi_pass 127.0.0.0:9000;
  }

  # Fighting with Styles? This little gem is amazing.
  # This is for D6
  #location ~ ^/sites/.*/files/imagecache/ {
  # This is for D7 and D8
  location ~ ^/sites/.*/files/styles/ {
    try_files \$uri @rewrite;
  }

  location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
    expires max;
    log_not_found off;
  }
}
EOF


replace ";cgi.fix_pathinfo=1" "cgi.fix_pathinfo=0" -- /etc/php5/fpm/php.ini
replace "listen = /var/run/php5-fpm.sock" "listen = 127.0.0.1:9000" -- /etc/php5/fpm/pool.d/www.conf


rm /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/$HOSTNAME /etc/nginx/sites-enabled/$HOSTNAME


cd /websites/webfiles
drush dl
mv drupal-* $HOSTNAME
cd $HOSTNAME


/etc/init.d/hostname.sh
/etc/init.d/bind9 restart
/etc/init.d/php5-fpm restart
/etc/init.d/nginx restart


rm /etc/ssh/ssh_*
dpkg-reconfigure openssh-server
replace "Port 22" "Port 50005" -- /etc/ssh/sshd_config

/etc/init.d/ssh restart
