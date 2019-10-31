# HTTP2Benchmark
[<img src="https://img.shields.io/badge/Made%20with-BASH-orange.svg">](https://en.wikipedia.org/wiki/Bash_(Unix_shell)) 

# Preparation 
  - This test requires two servers - 
            - First one is where requests go(Test Server)
            - The second one is where the requests come from (Client Server)
  - You must have root-level access on both servers.
  - TCP 22, 80, 443, and 5001 and UDP 443 must be open and accessible on both the servers.

# How to benchmark

## Install Pre-Requisites
For CentOS/RHEL Based Systems - 
```bash
yum install git
```

For Debian/Ubuntu Based Systems - 
```bash
apt install git
```

## Server Install
``` bash
git clone https://github.com/http2benchmark/http2benchmark.git
```
``` bash
http2benchmark/setup/server/server.sh
```

## Client Server Install
``` bash
git clone https://github.com/http2benchmark/http2benchmark.git
```
``` bash
http2benchmark/setup/client/client.sh
```

During installation on the client server, The script will prompt  to input [Test Server IP], after which, it will show you a public key [copy the public key to the Test server], and then [click any key] to finish the installation, like so:
``` bash
Please input target server IP to continue: [Test Server IP]
```
``` bash
Please add the following key to ~/.ssh/authorized_keys on the Test server
ssh-rsa .................................................................
.........................................................................
.. root@xxx-client
```
``` bash
Once complete, click ANY key to continue: 
```

## How to test
Run the following commands on the Client Server - 
``` bash
/opt/benchmark.sh
```

## Log 
After benchmark testing is complete, an elaborated result is displayed, feel free to share it.

It also stores the same logs for each test here - `/opt/Benchmark/TIME_STAMP/`:
```
/opt/Benchmark/
   |_TIME_STAMP.tgz
   |_TIME_STAMP 
       |_RESULTS.csv
       |_RESULTS.txt
       |_apache
       |_lsws
       |_nginx
       |_env
```

`TIME_STAMP` will be replaced by actual server-time for each test.

## Customization
Feel free to play with the script, specially `benchmarks.sh` to edit options, You can also run `bash client.sh -h` on client-server to learn more about available options.

# Problems/Suggestions/Feedback/Contribution
Please raise an issue on the repository, or send a PR for contributing.
