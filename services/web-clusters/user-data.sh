#!/bin/bash

mkdir -p /var/www

cat > /var/www/index.html <<EOF
<h1>Hello from the server!</h1>
<p>DB Address: ${db_address}</p>
<p>DB Port: ${db_port}</p>
EOF

cd /var/www
nohup python3 -m http.server ${server_port} &