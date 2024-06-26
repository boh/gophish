#!/bin/bash

# Example run:
# wget https://raw.githubusercontent.com/boh/gophish/master/run.sh && chmod +x run.sh && source ./run.sh phisher.com,www.phisher.com

HOSTS=$1

systemctl stop gophish.service

# Install Prerequisites
apt-get update
apt-get -y install git
apt-get -y upgrade
apt-get -y install build-essential
apt-get -y install sqlite3
apt-get -y install fping
apt-get -y install host

# Install Go
rm -r /usr/local/go
wget https://dl.google.com/go/go1.13.3.linux-amd64.tar.gz
tar -xvf go1.13.3.linux-amd64.tar.gz
rm go1.13.3.linux-amd64.tar.gz
mv go /usr/local

export GOROOT=/usr/local/go
export GOPATH=$HOME
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH

# Install GoPhish
go get -u github.com/boh/gophish
cd $GOPATH/src/github.com/boh/gophish
go get -v && go build -v

# Update or create GoPhish application
installPath=/opt/gophish
mv ${installPath}/gophish.db ${installPath}/../gophish.db
rm -r ${installPath}
cp -r $GOPATH/src/github.com/boh/gophish $installPath
mv ${installPath}/../gophish.db ${installPath}/gophish.db

# Check if the HOSTS variables resolves, to prevent Let's Encrypt blocks for too many invalid attempts
for i in $(echo $HOSTS | sed "s/,/ /g")
do
  if ! host -t a $i | grep "has address"; then
    echo "Host $i did not resolve, wait for your DNS to update"
    exit 0
  fi
done

# Generate SSL certificate
# next section is obsolete since certbot-auto can't be installed this way anymore 
# wget https://dl.eff.org/certbot-auto
# mv certbot-auto /usr/local/bin/certbot-auto
# chown root /usr/local/bin/certbot-auto
# chmod 0755 /usr/local/bin/certbot-auto

# use snap to install certbot
apt -y install snapd
snap install core
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot
/usr/bin/certbot certonly --expand -d $HOSTS -n --standalone --agree-tos --email bfho@pm.me

unset -v latest
for file in /etc/letsencrypt/live/*; do
  [[ $file =~ README ]] && continue
  [[ $file -nt $letsencryptPath ]] && letsencryptPath=$file
done

# Create config
echo "{
	\"admin_server\": {
		\"listen_url\": \"0.0.0.0:3333\",
		\"use_tls\": true,
		\"cert_path\": \"$letsencryptPath/fullchain.pem\",
		\"key_path\": \"$letsencryptPath/privkey.pem\"
	},
	\"phish_server\": {
		\"listen_url\": \"0.0.0.0:443\",
		\"use_tls\": true,
		\"cert_path\": \"$letsencryptPath/fullchain.pem\",
		\"key_path\": \"$letsencryptPath/privkey.pem\"
	},
	\"db_name\": \"sqlite3\",
	\"db_path\": \"gophish.db\",
	\"migrations_prefix\": \"db/db_\",
	\"contact_address\": \"\",
	\"logging\": {
		\"filename\": \"\"
	}
}" > $installPath/config.json

# Install and start as a service
echo "[Unit]
Description=Gophishtest

[Service]
WorkingDirectory=$installPath
ExecStart=$installPath/gophish
Type=simple

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/gophish.service

systemctl daemon-reload
systemctl start gophish.service
