# Debian Web Server Config

This script configure a Debian web server.

##Feature:
  1. get server's IP automatically
  2. setup bind9, nginx, mysql, php5-fpm, and ...
  3. config bind9
  4. config hostname
  4. config nginx minimally


##TODO:
  * config nginx
  * config php


##Usage: 

    # bash setup.bash <HOSTNAME> [<IP>]


##Example:

    # bash setup.bash example.com
    # bash setup.bash example.com 127.0.0.1
