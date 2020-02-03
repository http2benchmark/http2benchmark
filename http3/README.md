# README.md
## Install the HTTP/3 package
Client machine will need to run following command to build h2load to support http/3 protocol.
```
http2benchmark/http3/script/prepare_client.sh
```
Server machine will only need to run following command to build Quich for Nginx server since LiteSpeed web Server has HTTP/3 supported by default. 
```
http2benchmark/http3/script/prepare_server.sh
```
## How to test
Run command to benchmark LSWS, OpenLiteSpeed and Nginx
```
bash benchmark.sh http3.profile
```