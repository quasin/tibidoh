#!/usr/bin/env bash

dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$dir"

mkdir -p data/share/log data/.ipfs temp apps
(echo -e "$(date -u) Tibidoh installation started.") >> $PWD/data/log.txt
read -p "Enter IPFS port(default 4002): " IPFSPORT
if [ -z "$IPFSPORT" ]; then
    IPFSPORT=4002
fi

sudo DEBIAN_FRONTEND=noninteractive apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y docker.io build-essential python3-dev python3-pip python3-venv tmux cron ufw git \
    net-tools fuse3 unzip wget openssl curl jq
sudo usermod -aG docker $USER
sudo systemctl restart docker

echo "NC_PASS='$(openssl rand -base64 12)'" > ~/.secrets
chmod 600 ~/.secrets
source ~/.secrets

python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install --upgrade pip
pip3 install -r requirements.txt
pip3 --version

arch=$(uname -m)
if [[ "$arch" == "x86_64" ]]; then
    ipfsdistr="https://github.com/ipfs/kubo/releases/download/v0.39.0/kubo_v0.39.0_linux-amd64.tar.gz"
    yggdistr="https://github.com/yggdrasil-network/yggdrasil-go/releases/download/v0.5.12/yggdrasil-0.5.12-amd64.deb"
elif [[ "$arch" == "aarch64" ]]; then
    ipfsdistr="https://github.com/ipfs/kubo/releases/download/v0.39.0/kubo_v0.39.0_linux-arm64.tar.gz"
    yggdistr="https://github.com/yggdrasil-network/yggdrasil-go/releases/download/v0.5.12/yggdrasil-0.5.12-arm64.deb"
elif [[ "$arch" == "riscv64" ]]; then
    ipfsdistr="https://github.com/ipfs/kubo/releases/download/v0.39.0/kubo_v0.39.0_linux-riscv64.tar.gz"
    sudo wget -O /usr/local/bin/yggdrasil https://ipfs.sweb.ru/ipfs/QmZUem3W4YV8R4Zm8xEFfJoyWJskx4nDJ1rpDR6MSoVM3N?filename=yggdrasil
    sudo wget -O /usr/local/bin/yggdrasilctl https://ipfs.sweb.ru/ipfs/QmZUem3W4YV8R4Zm8xEFfJoyWJskx4nDJ1rpDR6MSoVM3N?filename=yggdrasilctl
    sudo chmod +x /usr/local/bin/yggdrasil /usr/local/bin/yggdrasilctl
    sudo mkdir /etc/yggdrasil
    yggdrasil -genconf | sudo tee /etc/yggdrasil/yggdrasil.conf
echo -e "\
[Unit]\n\
Description=Yggdrasil Network Service\n\
After=network.target\n\
\n\
[Service]\n\
Type=simple\n\
User=root\n\
Group=root\n\
ExecStart=/usr/local/bin/yggdrasil -useconffile /etc/yggdrasil/yggdrasil.conf\n\
Restart=on-failure\n\
RestartSec=5s\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n\
" | sudo tee /etc/systemd/system/yggdrasil.service
    sudo systemctl daemon-reload
    sudo systemctl enable --now yggdrasil
else
    echo "Unsupported architecture: $arch"
    exit 1
fi

echo PATH="$PATH:/home/$USER/.local/bin:$PWD/bin" | sudo tee /etc/environment
echo TIBIDOH="$PWD" | sudo tee -a /etc/environment
echo IPFS_PATH="$PWD/data/.ipfs" | sudo tee -a /etc/environment
echo ". /etc/environment" | tee -a ~/.bashrc
export PATH="$PATH:/home/$USER/.local/bin:$PWD/bin"
export TIBIDOH="$PWD"
export IPFS_PATH="$PWD/data/.ipfs"
echo -e "PATH=$PATH\nTIBIDOH=$PWD\nIPFS_PATH=$IPFS_PATH\n$(sudo crontab -l)\n" | sudo crontab -
sudo systemctl enable --now cron

sudo mkdir data/ipfs data/ipns data/mfs
sudo chmod 777 data/ipfs
sudo chmod 777 data/ipns
sudo chmod 777 data/mfs
wget -O temp/kubo.tar.gz $ipfsdistr
tar xvzf temp/kubo.tar.gz -C temp
sudo mv temp/kubo/ipfs /usr/local/bin/ipfs
ipfs init --profile server
ipfs config Mounts.IPFS "$dir/data/ipfs"
ipfs config Mounts.IPNS "$dir/data/ipns"
ipfs config Mounts.MFS  "$dir/data/mfs"
ipfs config --json Experimental.FilestoreEnabled true
ipfs config --json Pubsub.Enabled true
ipfs config --json Ipns.UsePubsub true
ipfs config profile apply lowpower
#ipfs config Addresses.Gateway /ip4/127.0.0.1/tcp/8082
#ipfs config Addresses.API /ip4/127.0.0.1/tcp/5002
sed -i "s/4001/$IPFSPORT/g" $PWD/data/.ipfs/config
sed -i "s/104.131.131.82\/tcp\/$IPFSPORT/104.131.131.82\/tcp\/4001/g" $PWD/data/.ipfs/config
sed -i "s/104.131.131.82\/udp\/$IPFSPORT/104.131.131.82\/udp\/4001/g" $PWD/data/.ipfs/config
echo -e "\
[Unit]\n\
Description=InterPlanetary File System (IPFS) daemon\n\
Documentation=https://docs.ipfs.tech/\n\
After=network.target\n\
\n\
[Service]\n\
MemorySwapMax=0\n\
TimeoutStartSec=infinity\n\
Type=simple\n\
User=$USER\n\
Group=$USER\n\
Environment=IPFS_PATH=$PWD/data/.ipfs\n\
ExecStart=/usr/local/bin/ipfs daemon --enable-gc --mount --migrate=true\n\
Restart=on-failure\n\
KillSignal=SIGINT\n\
\n\
[Install]\n\
WantedBy=default.target\n\
" | sudo tee /etc/systemd/system/ipfs.service
sudo systemctl daemon-reload
sudo systemctl enable ipfs
sudo systemctl restart ipfs

cat <<EOF >>$PWD/bin/ipfssub.sh
#!/usr/bin/env bash

/usr/local/bin/ipfs pubsub sub tibidoh >> $PWD/data/sub.txt
EOF
chmod +x $PWD/bin/ipfssub.sh

echo -e "\
[Unit]\n\
Description=InterPlanetary File System (IPFS) subscription\n\
After=network.target\n\
\n\
[Service]\n\
Type=simple\n\
User=$USER\n\
Group=$USER\n\
Environment=IPFS_PATH=$PWD/data/.ipfs\n\
ExecStartPre=/usr/bin/sleep 5\n\
ExecStart=$PWD/bin/ipfssub.sh\n\
Restart=on-failure\n\
KillSignal=SIGINT\n\
\n\
[Install]\n\
WantedBy=default.target\n\
" | sudo tee /etc/systemd/system/ipfssub.service
sudo systemctl daemon-reload
sudo systemctl enable ipfssub
sudo systemctl restart ipfssub
sleep 9

echo -e "$(sudo crontab -l)\n@reboot sleep 9; systemctl restart yggdrasil; echo \"\$(date -u) System is rebooted\" >> $PWD/data/log.txt\n* * * * * su $USER -c \"bash $PWD/bin/cron.sh\"" | sudo crontab -

sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt install -y ca-certificates curl gnupg
sudo rm /etc/apt/keyrings/nodesource.gpg
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
NODE_MAJOR=24
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
sudo apt-get update && sudo apt-get install nodejs -y
sudo npm install -g npm@11.7.0
node -v
npm -v

echo -n -e "\n\nIPFS status:"
ipfs cat QmYwoMEk7EvxXi6LcS2QE6GqaEYQGzfGaTJ9oe1m2RBgfs/test.txt
echo -n "IPFSmount status:"
cat $dir/data/ipfs/QmYwoMEk7EvxXi6LcS2QE6GqaEYQGzfGaTJ9oe1m2RBgfs/test.txt

sudo ufw disable
sudo ufw default deny incoming
sudo ufw allow 22
sudo ufw allow 9001
sudo ufw allow from 200::/7
yes | sudo ufw enable

str=$(ipfs id) && echo $str | cut -c10-61 > $PWD/data/id.txt
wget -O temp/ygg.deb $yggdistr
sudo dpkg -i temp/ygg.deb
sudo sed -i "s/  Peers: \[\]/  Peers: \[\n    tls:\/\/ip4.01.msk.ru.dioni.su:9003\n  \]/g" /etc/yggdrasil/yggdrasil.conf
sudo sed -i "s/  NodeInfo: {}/  NodeInfo: {\n    name: tibidoh$(cat $PWD/data/id.txt)\n}/g" /etc/yggdrasil/yggdrasil.conf
sudo systemctl restart yggdrasil
sudo systemctl enable yggdrasil
sudo chmod u+s $(which ping)
ping -6 -c 5 21e:a51c:885b:7db0:166e:927:98cd:d186

sudo usermod -aG www-data $USER
sudo usermod -aG $USER www-data
sudo apt install -y apache2 postgresql php libapache2-mod-php imagemagick librsvg2-bin php-gd php-curl php-mbstring php-intl php-xml \
    php-zip php-imagick php-apcu php-pgsql php-gmp
sudo apt install -y libmagickcore-6.q16-6-extra
sudo apt install -y libmagickcore-7.q16-10-extra
sudo systemctl enable --now apache2 postgresql
sudo systemctl status apache2 postgresql --no-pager
sudo systemctl reload apache2
sudo -u postgres psql <<'SQL'
CREATE USER tibidoh WITH PASSWORD 'TIBIDOH' CREATEDB;
CREATE DATABASE nextcloud TEMPLATE template0 ENCODING 'UTF8';
ALTER DATABASE nextcloud OWNER TO tibidoh;
GRANT ALL PRIVILEGES ON DATABASE nextcloud TO tibidoh;
GRANT ALL PRIVILEGES ON SCHEMA public TO tibidoh;
SQL
cd /var/www; sudo wget -O nc.zip https://download.nextcloud.com/server/releases/latest.zip; sudo unzip nc.zip; cd $dir
sudo chown -R www-data:www-data /var/www/nextcloud/
sudo rm /var/www/nc.zip
sudo tee /etc/apache2/sites-available/nextcloud.conf >/dev/null <<'EOF'
<VirtualHost *:80>
  ServerName cloud.example.com
  DocumentRoot /var/www/nextcloud/

  <Directory /var/www/nextcloud/>
    Require all granted
    AllowOverride All
    Options FollowSymLinks MultiViews
    <IfModule mod_dav.c>
      Dav off
    </IfModule>
  </Directory>
</VirtualHost>
EOF
sudo sed -i "s|VirtualHost \*:80|VirtualHost *:81|g" /etc/apache2/sites-available/000-default.conf
sudo sed -i -E 's/^\s*memory_limit\s*=.*/memory_limit = 512M/' /etc/php/*/apache2/php.ini
sudo sed -i -E 's/^\s*upload_max_filesize\s*=.*/upload_max_filesize = 60G/' /etc/php/*/apache2/php.ini
sudo sed -i -E 's/^\s*post_max_size\s*=.*/post_max_size = 60G/' /etc/php/*/apache2/php.ini
sudo sed -i -E 's/^\s*max_input_time\s*=.*/max_input_time = -1/' /etc/php/*/apache2/php.ini
sudo sed -i -E 's/^\s*max_execution_time\s*=.*/max_execution_time = 3600/' /etc/php/*/apache2/php.ini
sudo a2ensite nextcloud.conf
sudo a2enmod rewrite headers env dir mime
sudo systemctl restart apache2
cd /var/www/nextcloud
sudo -E -u www-data php occ maintenance:install \
  --database "pgsql" \
  --database-name "nextcloud" \
  --database-user "tibidoh" \
  --database-pass "TIBIDOH" \
  --database-host "localhost" \
  --admin-user "admin" \
  --admin-pass $NC_PASS
TUN0_IP6="$(ip -6 -o addr show dev tun0 scope global | awk 'NR==1{split($4,a,"/"); print a[1]}')"
sudo -E -u www-data php occ config:system:set trusted_domains 1 --value="$TUN0_IP6"
sudo -E -u www-data php occ config:system:set trusted_domains 2 --value="[$TUN0_IP6]"
sudo -E -u www-data php occ config:system:set overwrite.cli.url --value="http://[$TUN0_IP6]"
sudo -E -u www-data php occ db:add-missing-indices
sudo -E -u www-data php occ app:install news
sudo -E -u www-data mkdir /var/www/nextcloud/data/admin/files/tibidoh
sudo mount --bind $dir/data/share /var/www/nextcloud/data/admin/files/tibidoh
sudo -E -u www-data php occ files:scan --path="/admin/files/tibidoh"
sudo -E -u www-data php occ config:app:set news autoPurgeCount --value=-1
echo "$dir/data/share /var/www/nextcloud/data/admin/files/tibidoh none bind 0 0" | sudo tee -a /etc/fstab
cd $dir
( sudo crontab -u www-data -l 2>/dev/null; echo '*/5 * * * * /usr/bin/php -f /var/www/nextcloud/cron.php' ) | sudo crontab -u www-data -
( sudo crontab -u www-data -l 2>/dev/null; echo '* * * * * /usr/bin/php -f /var/www/nextcloud/occ files:scan admin' ) | sudo crontab -u www-data -

rm -rf temp
mkdir temp
(echo -n "$(date -u) Tibidoh system is installed. ID=" && cat $PWD/data/id.txt) >> $PWD/data/log.txt
ipfspub 'Initial message'
ipfs pubsub pub tibidoh $PWD/data/log.txt
sleep 9
sudo reboot
