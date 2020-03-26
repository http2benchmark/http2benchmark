#!/bin/sh

NGDIR=/etc/nginx
sed -i "s#    listen      443 ssl http2 reuseport;#    listen      443 quic reuseport;\n    add_header alt-svc 'h3-27=\":443\"; ma=86400';\n    http3_max_requests 100000;\n\n    listen      443 ssl http2 reuseport;#g" $NGDIR/conf.d/default.conf

