#!/bin/bash

HOSTNAME=${1}
IP=${2}


if [ -z "${HOSTNAME}" ]; then
  echo "HOSTNAME must be set. (# sh setup.sh example.com)"
  exit 0
fi

if [ -z "${IP}" ]; then
  IP=$(/sbin/ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}')
fi

if [ -z "${IP}" ]; then
  IP='127.0.0.1'
fi


mkdir /etc/bind/data

echo $HOSTNAME > /etc/hostname
echo $IP $HOSTNAME >> /etc/hosts

passwd root

dpkg-reconfigure tzdata


apt-get update
apt-get upgrade -y
apt-get dist-upgrade -y
apt-get autoremove -y

apt-get install -y less ntp zip unzip curl bind9 dnsutils nginx-extras mysql-server php5-fpm php5-mysql php5-curl php5-gd

# Drush installation
php -r "readfile('https://s3.amazonaws.com/files.drush.org/drush.phar');" > drush
php drush core-status
chmod +x drush
mv drush /usr/local/bin
drush init


cat << EOF > /etc/bind/data/db.$HOSTNAME
;
; BIND data file for local loopback interface
;
\$TTL  3600
@  IN  SOA  ns1.$HOSTNAME.  support.wki.ir. (
   2016092000   ; Serial
         3600   ; Refresh [1h]
          900   ; Retry   [15m]
      1209600   ; Expire  [2w]
          300 ) ; Negative Cache TTL [30m]
;
@     IN  NS  ns1.$HOSTNAME.
@     IN  NS  ns2.$HOSTNAME.
@     IN  MX  10 mail.$HOSTNAME.

@     IN  A   $IP
ns1   IN  A   $IP
ns2   IN  A   $IP

www   IN  A   $IP
mail  IN  A   $IP

; SPF Record for MX.
$HOSTNAME.  IN  TXT  "v=spf1 a mx -all"
EOF


cat << EOF > /etc/bind/data/db.$(echo $IP | cut -d. -f1)
;
; BIND reverse data file for local loopback interface
;
\$TTL  3600
@  IN  SOA  ns1.$HOSTNAME.  support.wki.ir. (
   2014100500   ; Serial
         3600   ; Refresh [1h]
          900   ; Retry   [15m]
      1209600   ; Expire  [2w]
          300 ) ; Negative Cache TTL [30m]
;
@  IN  NS   ns1.$HOSTNAME.
@  IN  NS   ns2.$HOSTNAME.
1  IN  PTR  www.$HOSTNAME.
2  IN  PTR  mail.$HOSTNAME.
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


cat << EOF > /etc/nginx/conf.d/$HOSTNAME.conf
server {
  server_name $HOSTNAME www.$HOSTNAME;
  root        /websites/webfiles/$HOSTNAME;
  error_log   /var/log/nginx/$HOSTNAME-error.log;
  access_log  /var/log/nginx/$HOSTNAME-access.log;

  if (\$host = "$HOSTNAME") {
    return 301 http://www.$HOSTNAME\$request_uri;
  }

  location = /favicon.ico {
    log_not_found off;
    access_log off;
  }

  location = /robots.txt {
    allow all;
    log_not_found off;
    access_log off;
  }

  # Very rarely should these ever be accessed outside of your lan
  location ~* \.(txt|log)$ {
    allow 192.168.0.0/16;
    deny all;
  }

  location ~ \..*/.*\.php$ {
    return 403;
  }

  location ~ ^/sites/.*/private/ {
    return 403;
  }

  # Allow "Well-Known URIs" as per RFC 5785
  location ~* ^/.well-known/ {
    allow all;
  }

  # Block access to "hidden" files and directories whose names begin with a
  # period. This includes directories used by version control systems such
  # as Subversion or Git to store control files.
  location ~ (^|/)\. {
    return 403;
  }

  location / {
    # try_files \$uri @rewrite; # For Drupal <= 6
    try_files \$uri /index.php?\$query_string; # For Drupal >= 7
  }

  location @rewrite {
    rewrite ^/(.*)$ /index.php?q=\$1;
  }

  # Don't allow direct access to PHP files in the vendor directory.
  location ~ /vendor/.*\.php$ {
    deny all;
    return 404;
  }

  # In Drupal 8, we must also match new paths where the '.php' appears in
  # the middle, such as update.php/selection. The rule we use is strict,
  # and only allows this pattern with the update.php front controller.
  # This allows legacy path aliases in the form of
  # blog/index.php/legacy-path to continue to route to Drupal nodes. If
  # you do not have any paths like that, then you might prefer to use a
  # laxer rule, such as:
  #   location ~ \.php(/|$) {
  # The laxer rule will continue to work if Drupal uses this new URL
  # pattern with front controllers other than update.php in a future
  # release.
  location ~ '\.php$|^/update.php' {
    fastcgi_split_path_info ^(.+?\.php)(|/.*)$;
    # Security note: If you're running a version of PHP older than the
    # latest 5.3, you should have "cgi.fix_pathinfo = 0;" in php.ini.
    # See http://serverfault.com/q/627903/94922 for details.
    include fastcgi_params;
    # Block httpoxy attacks. See https://httpoxy.org/.
    fastcgi_param HTTP_PROXY "";
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    fastcgi_param PATH_INFO \$fastcgi_path_info;
    fastcgi_intercept_errors on;
    # PHP 5 socket location.
    fastcgi_pass unix:/var/run/php5-fpm.sock;
  }

  # Fighting with Styles? This little gem is amazing.
  # location ~ ^/sites/.*/files/imagecache/ { # For Drupal <= 6
  location ~ ^/sites/.*/files/styles/ { # For Drupal >= 7
    try_files \$uri @rewrite;
  }

  # Handle private files through Drupal.
  location ~ ^/system/files/ { # For Drupal >= 7
    try_files \$uri /index.php?\$query_string;
  }

  location ~* \.(js|css|png|jpg|jpeg|gif|ico|ttf|eot|woff|woff2)$ {
    expires max;
    log_not_found off;
  }
}
EOF


cp /etc/php5/fpm/php.ini /etc/php5/fpm/php.ini.bak
replace "max_execution_time = 30" "max_execution_time = 60" -- /etc/php5/fpm/php.ini
replace "post_max_size = 8M" "post_max_size = 128M" -- /etc/php5/fpm/php.ini
replace "upload_max_filesize = 2M" "upload_max_filesize = 500M" -- /etc/php5/fpm/php.ini


cp /etc/mysql/my.cnf /etc/mysql/my.cnf.bak
# config mysql for 8GB Ram
replace "key_buffer              = 16M" "key_buffer              = 64M" -- /etc/mysql/my.cnf
replace "max_allowed_packet      = 16M" "max_allowed_packet      = 64M" -- /etc/mysql/my.cnf
replace "query_cache_limit       = 1M"  "query_cache_limit       = 4M" -- /etc/mysql/my.cnf
replace "query_cache_size        = 16M" "query_cache_size        = 512M" -- /etc/mysql/my.cnf


rm /etc/ssh/ssh_*
dpkg-reconfigure openssh-server
replace "Port 22" "Port 50000" -- /etc/ssh/sshd_config


/etc/init.d/hostname.sh
/etc/init.d/bind9 restart
/etc/init.d/php5-fpm restart
/etc/init.d/nginx restart
/etc/init.d/ssh restart
