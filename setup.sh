#!/bin/bash

is_ubuntu=`awk -F '=' '/PRETTY_NAME/ { print $2 }' /etc/os-release | egrep Ubuntu -i`
is_centos=`awk -F '=' '/PRETTY_NAME/ { print $2 }' /etc/os-release | egrep CentOS -i`

echo "################# SETUP NEW SERVER SCRIPT #####################"
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

#sudo apt install policycoreutils selinux-utils selinux-basics -y


function ubuntu_basic_install()
{
	sudo apt -y update	
	sudo apt -y install git wget telnet rsync sysstat lsof nfs-common cifs-utils iptables chrony curl htop net-tools
	timedatectl set-timezone Asia/Ho_Chi_Minh
    ufw disable 
}

function centos_basic_install()
{
  	yum update -y
  	yum install -y epel-release
  	yum groupinstall 'Development Tools' -y
	timedatectl set-timezone Asia/Ho_Chi_Minh 
	yum install -y git wget telnet rsync sysstat lsof nfs-utils cifs-utils iptables-services chrony curl htop net-tools 
	systemctl stop firewalld
	systemctl disable firewalld
	systemctl mask --now firewalld
	systemctl enable iptables
	systemctl start iptables
	systemctl enable chronyd
	systemctl restart chronyd
	chronyc sources
	timedatectl set-local-rtc 0
    echo "Enable limiting resources"
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    echo 'GRUB_CMDLINE_LINUX="cdgroup_enable=memory swapaccount=1"' | sudo tee -a /etc/default/grub
    sudo update-grub
}



# Setup new server
function create_user()
{   

    username_1000=$(getent passwd 1000 | awk -F ':' '{print $1}')
    sudo userdel -r -f $username_1000


    sudo useradd -u 1000 -m -s /bin/bash isofh
    echo "isofh:123123" | chpasswd
    echo "isofh ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

    #Create user monitor
    echo "Create user monitor 'ucmea'"
    useradd -ms /bin/bash ucmea
    echo "ucmea:I!@#fh@123" | sudo chpasswd

    echo "fs.file-max=150000
    vm.swappiness=10" | sudo tee -a /etc/sysctl.conf && sudo sysctl -p
    echo "* soft nofile 100000" | sudo tee -a /etc/security/limits.conf
    echo "* hard nofile 100000" | sudo tee -a /etc/security/limits.conf

}


#Install docker
if [ ! -z "$is_ubuntu" ]; then
	is_docker_exist=`dpkg -l | grep docker -i`
elif [ ! -z "$is_centos" ]; then
	is_docker_exist=`rpm -qa | grep docker`
else
	echo "Error: Current Linux release version is not supported, please use either centos or ubuntu. "
	exit
fi

if [ ! -z "$is_docker_exist" ]; then
	echo "Warning: docker already exists. "
fi


function ubuntu_docker_install()
{
	#Install docker
	sudo apt-get -y update
	sudo apt-get remove docker docker-engine docker.io containerd runc 
	sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common  git vim 
	
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
	echo \
		"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
		$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
	sudo apt-get -y update
	sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose
	sudo bash -c 'touch /etc/docker/daemon.json' && sudo bash -c "echo -e \"{\n\t\\\"bip\\\": \\\"55.55.1.1/24\\\"\n}\" > /etc/docker/daemon.json"

	sudo systemctl enable docker.service
	sudo systemctl start docker
	usermod -aG docker isofh	
}

function centos_docker_install()
{
	#Install docker
	sudo yum install -y yum-utils device-mapper-persistent-data lvm2 git vim 
	sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
	sudo yum -y install docker-ce docker-ce-cli containerd.io docker-compose
	sudo bash -c 'touch /etc/docker/daemon.json' && sudo bash -c "echo -e \"{\n\t\\\"bip\\\": \\\"55.55.1.1/24\\\"\n}\" > /etc/docker/daemon.json"

	sudo systemctl enable docker.service
	sudo systemctl start docker
	
	is_docker_success=`sudo docker run hello-world | grep -i "Hello from Docker"`
	if [ -z "$is_docker_success" ]; then
		echo "Error: Docker installation Failed."
		exit
	fi

	usermod -aG docker isofh

	echo "Docker has been installed successfully."		
}

function runAgent(){
sudo docker run -d \
    --name node-exporter-isofh \
    --restart unless-stopped \
    --publish 19100:9100 \
    --volume /proc:/host/proc:ro \
    --volume /sys:/host/sys:ro \
    --volume /:/rootfs:ro \
    prom/node-exporter:latest \
    --path.procfs /host/proc \
    --path.rootfs /rootfs \
    --path.sysfs /host/sys \
    --collector.filesystem.mount-points-exclude "^/(sys|proc|dev|host|etc)($$|/)"
		 
sudo docker run \
  --volume=/:/rootfs:ro \
  --volume=/var/run:/var/run:ro \
  --volume=/sys:/sys:ro \
  --volume=/var/lib/docker/:/var/lib/docker:ro \
  --volume=/dev/disk/:/dev/disk:ro \
  --publish=19093:8080 \
  --detach=true \
  --restart always \
  --name=cadvisor-isofh \
  --privileged \
  --device=/dev/kmsg \
  gcr.io/cadvisor/cadvisor:latest
}

function setupSSHkey(){
    mkdir -p /home/isofh/.ssh && cd /home/isofh/.ssh && touch authorized_keys
    echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCo2oHJfJqkX4SSk3S7L1mQNPm2v8NpcmP5Epd3uA8AymFx6aHlT0rBoUCAS7/mh9h6mISz07a55pzV9uUWGTf1QOFmhLyo+zBmaYaJFS7bcBBsNWJzYDyX9QcA04RGQHmVEo/xcL0Tii4KydBT6dPJbS50uOv1UwYJ5RfrS5xjylvskLxqcq/zEaPFNlrQLwEhHUjdzwN9h464wQLYriZt0YnSFBYA/n/hWWANsrX4jzOSCCwEmIBmYh8tB4vGf8PssXT9pxWyQ8Pl/I0lx77HbY6nq6GCFQ6Q0SmL8WxeZganr+j2c4NM/HkefnS4GjUxPckJdU1mb7VUWvFuDlLJMrK4omuT+MTVekZwAldObM2j/rialRuSfKWgoWUYTIPOqztOKdP6QcsvbWcj1vCPL+gJ8/CzeXNCfC3So9YQbasTSRgSwH7alYK+fDRdpkFhpoz7GI+7WR9OH6WJzOYOlXYF0fvfMOnbD/qPanQSFCJXwVc31BQeSkIWFq+9dM0= jenkins@jenkins-Tuan-System" >> /home/isofh/.ssh/authorized_keys

    echo "#Jenkins52" >> /home/isofh/.ssh/authorized_keys
    echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDFwLR6DpxhpkEWUTpYgBfjS2++FknUWTZJzkAALwijP0d2kSr0Q0jipKWRX1KtqOOsb/ZFwRr7MLmfqJ8x+Dl+81fbE5PX8eifLwAaD6RyAS4xo87eS8xIvLmavL6gELP5Dm6y1npnNIkEiXMYYKDFm8nb3xlQv89EdBMV+2jCdfhwRKFk8l4O3Yw3klL5Kvs4d2T/n/3zYOgfmh/8XXuXraBJIyEVOGzQcd+0xzz4+vs9u6IAgxXaknPoksycsTjCENaN4Fy8ylpKYrYOzLZkSh7IEjUoXHEXwvfWNc7jNW1KbRRrVSmusBDDC+eNbjw7tlp1LACjzoHQQOnHBLFb @isofh-jenkins52" >> /home/isofh/.ssh/authorized_keys

    echo "#Minh-CTO" >> /home/isofh/.ssh/authorized_keys
    echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC2VWlYeeDegqIDIQbQh/PZgouGv7LYmUMEOZEQPwSKuYg+teuyBcTNYqRdzjS0dDX1PPPS39xgHm5sa0G6L73L9hRONTMBicqXMdO7aNEFPucfBkfhJ8tDok5xE1e+dtMwwybqmUjfRi6fxao/AM606FOUa1MN4d9w3Qhu1NyiAlCjcyw+qeAGnD1yz3LRxKEq0H5uGSKW672fwx7UvX91wByw+WqYo2UkwVKW9vqa4jvAi0haPJPvENlFpJ3jQ+hJ+ewZWSi4YXmZ8cQkBNWGdZzuOb3VOTWyJIAjiBpeti+arChguoMmFeY3WNFlICfLZ4IbmRtIh3FL/QexYBJYKhjML+Ub3AgUU9t63Lj+9WD7s4QOejH5s3x/V8eP/ZomJetnB6x5zmbu+d6/znoe2J/PIUjHsp7b0qu4XP0/dIY/YqdIjOgOVckHCmjekXnOuXmdxvUOn7GO4uSgHcUh15eCJss1Jahl8q2xrnB8JCEbSMi/PAasKRAxZEKECxigkE7cvbF0UlsYJrFtWY+56BsqTH+64mN/0EtP4bnkoc/2SBt0WBIX6WJfptnfyhd02D0SvEpl22r443JaW2HhL7QUZMwmKm1ZU1rra8oYqB18mG1f4RJlpn9fgvskDFNxGuhoiVMZdWeM935UaO2O+v8LwLO5K8LIpK/avwXw6Q== vanminh.ph23@gmail.com" >> /home/isofh/.ssh/authorized_keys

    echo "#mainam"  >> /home/isofh/.ssh/authorized_keys
    echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC6Z2jlEIpRxFYHGHQptmi0bL08TvEY9zcNVN2pa3GkzIxgt80tRaWWlPG79vji9xAzh1ZGSxOnQeVseTYHzGWtPZrApMgEXC8FM4FF9pL9LzcFPQSRM1KVLs3wYdw7ns2CvHBV2CI0uQEg77Pj/NB1uR6EnauGLwqvBhEAPK3mV1aGZ1QkiVGyAu2FNYSVhO8D/m9UZeENk6IYO/GKyCRX/iG/VNcSZZWG2NMLGmCHRk8KR2q2xGppVAeKT3W50BGxWXl6a8hKOkvQG9z+TAjgDcHK8cJajjd8cXDQBWEIA0Zx2nV0217s049pgb9JH2guWPfpBGpH2NMoyqdTVLyiT3ixHnIjzSB6ZmhqKSC6WXdlc+dHBdyZcSHGIJQSpVHRA/0JQV4E5ML9gN76MiMHjXzKDl7vrQfgeM4iwVqS3V6jRebuTh7bza2QuglXlicDaRLN8DA4bvlOcuDISF641hLqIQoz4jbTzOnyHZHpbgYbqNKUlrk915W4Yanr+tE= mainam@mais-macbook-pro.local" >> /home/isofh/.ssh/authorized_keys

}

function createFileCrontab(){
    mkdir -p /root/clearcache && touch clearcache.sh
    echo "sync; echo 1 > /proc/sys/vm/drop_caches" >> /root/clearcache/clearcache.sh
    echo "sync; echo 2 > /proc/sys/vm/drop_caches" >> /root/clearcache/clearcache.sh
    echo "sync; echo 3 > /proc/sys/vm/drop_caches" >> /root/clearcache/clearcache.sh

}

function setupCrontab() {
    createFileCrontab
    cron_schedule1="* 01 * * *"
    cron_schedule2="* 03 * * *"
    cron_schedule3="* 06 * * *"
    cron_schedule4="* 09 * * *"
    cron_schedule5="* 10 * * *"
    cron_schedule6="* 12 * * *"
    cron_schedule7="* 15 * * *" 
    cron_schedule8="* 17 * * *"
    cron_schedule9="* 19 * * *"

    command='sudo sh -c "truncate -s 0 /var/lib/docker/containers/*/*-json.log"'
    # command2='docker start $(docker container ls -q -f "status=exited")'
    command3='bash /root/clearcache/clearcache.sh'
    (crontab -l ; echo "$cron_schedule1 $command") | crontab -
    (crontab -l ; echo "$cron_schedule1 $command3") | crontab -
    (crontab -l ; echo "$cron_schedule3 $command3") | crontab -
    (crontab -l ; echo "$cron_schedule4 $command3") | crontab -
    (crontab -l ; echo "$cron_schedule5 $command3") | crontab -
    (crontab -l ; echo "$cron_schedule6 $command3") | crontab -
    (crontab -l ; echo "$cron_schedule7 $command3") | crontab -
    (crontab -l ; echo "$cron_schedule8 $command3") | crontab -
    (crontab -l ; echo "$cron_schedule9 $command3") | crontab -
    echo "Setup Crontab thành công !"      

}


#Linux install basic tools
echo "Linux setup Server"
if [ ! -z "$is_ubuntu" ]; then
    echo "----- CÀI ĐẶT CƠ BẢN -----"
	ubuntu_basic_install
    echo "----- TẠO USER -----"    
    create_user
    echo "----- CÀI ĐẶT DOCKER VÀ AGENT MONITOR -----"
    ubuntu_docker_install
    echo "----- CÀI ĐẶT AGENT -----"
    runAgent
    echo "----- CÀI ĐẶT SSH KEY -----"
    setupSSHkey
    echo "----- CÀI ĐẶT CRONTAB SERVER -----"
    setupCrontab
    echo "----SETUP DONE----"
elif [ ! -z "$is_centos" ]; then
	centos_basic_install
    create_user
    centos_docker_install
    runAgent
    setupSSHkey
    setupCrontab
    echo "Done!"
fi
