#!/bin/sh


if [ -e /etc/h2o/h2o.conf -a ! -e /etc/h2o/h2o.bak ]
then
        mv /etc/h2o/h2o.conf /etc/h2o/h2o.bak
fi
#sed -e 's=examples/h2o/server.crt=/etc/ssl/http2benchmark.crt=' -e 's=examples/h2o/server.key=/etc/ssl/http2benchmark.key=' -e 's/#listen:/listen:/' -e 's/#  <<:/  <<:/' -e 's/#  type: quic/  type: quic/'  < /usr/local/share/doc/h2o/examples/h2o/h2o.conf > /usr/local/etc/h2o.conf
# The PHP test was done during the build phase
PHP=`ls /var/run/php|grep .sock`
sed -e "s/php7.2-fpm.sock/$PHP/" -e 's=run/h2o.pid=tmp/h2o.pid=' -e "s/www-data/${USER}/g" -e '0,/listen:/! s/listen:/listen: \&ssl_listen/' -e 's/    cipher-suite: "ECDHE-ECDSA-AES128-GCM-SHA256"/    cipher-suite: "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256"/' -e '/neverbleed: OFF/ a\
\# The following three lines enable HTTP/3\
\listen:\
\  <<: *ssl_listen\
\  type: quic
' < ../../webservers/h2o/conf/h2o.conf > /etc/h2o/h2o.conf


