#!/bin/bash

    #exec 2>&1 | tee ~/fossa_install.log
    exec 2>&2 | tee ~/fossa_install.log
    exec 1>&1 | tee ~/fossa_install.log
    #exec &>> ~/fossa_install.log 2>&1

if [ "$(id -u)" != "0" ]; then
exec sudo "$0" "$@"
fi
cd /opt/
#Check OS to use appropriate package manager & turn off selinux for Centos 7
if [ -f /etc/redhat-release ]; then
  OS_CHECK=yumpm
  sed -i 's/enforcing/disabled/g' /etc/selinux/config /etc/selinux/config
  set enforce 0 sestatus
fi

if [ -f /etc/lsb-release ]; then
  OS_CHECK=aptgetpm
fi
    sleep 5s
    clear
    ##Prompt for FOSSA server hostname
    read -ep "Enter the hostname for the FOSSA server " fossa_hostname

    ##Prompt for Minio hostname
    read -ep "Enter the hostname for the Minio server " minio_hostname


    ##Prompt for path and file names for FOSSA key
    read -ep "Enter directory path for FOSSA Certificate Files (Example: /xxx/yyy/certs) " fossa_file_dir
    #capture key file name
    read -ep "Enter the file name of your FOSSA key file " fossa_key
    #capture certificate file name
    read -ep "Enter the file name of your FOSSA certificate file " fossa_cert


    ##Prompt for path and file names for Minio key
    read -ep "Enter directory path for Minio Certificate Files (Example: /xxx/yyy/certs) " minio_file_dir
    #capture key file name
    read -ep "Enter the file name of your Minio key file " minio_key
    #capture certificate file name
    read -ep "Enter the file name of your Minio certificate file " minio_cert


    #Check for EC2
    #Set Environment Variables
    read -p "Install in EC2 (y/n)? " ec2_answer
    sleep 5s
    clear
    case ${ec2_answer:0:1} in
        y|Y )
            export PRIMARY_IP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4) 
            #export PRIMARY_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
            export FQN=$(curl http://169.254.169.254/latest/meta-data/public-hostname)
        ;;
        * )
            export PRIMARY_IP=$(ip route get 1 | awk '{print $NF;exit}'  &>> ~/fossa_install.log) 
            export FQN=$(nslookup $(hostname -i)  &>> ~/fossa_install.log) ; fqn=${fqn##*name = } ; fqn=${fqn%.*} ; echo $fqn  &>> ~/fossa_install.log
            #turn swap off
            sudo swapoff –a  &>> ~/fossa_install.log
        ;;
    esac
    #Update packages
    echo "Initiating OS Package Updates"
    if [ "$OS_CHECK" = "aptgetpm" ]; then
        #Install Docker
        sudo apt-get -qq -y install docker.io  &>> ~/fossa_install.log
        #Create links
        sudo ln -sf /usr/bin/docker.io /usr/local/bin/docker  &>> ~/fossa_install.log

        ################################################################################################
        #Install PostgreSQL
        #sudo apt-get -y install postgresql postgresql-contrib
    fi
    if [ "$OS_CHECK" = "yumpm" ]; then
        sudo yum update -qq -y  &>> ~/fossa_install.log
        #Install XXD which is used in the configure.sh
        sudo yum install -qq -y vim-common  &>> ~/fossa_install.log
        ################################################################################################

        ###############################################################################################
        ####download setup.sh for Centos support
    #    sudo mv /opt/fossa/setup.sh /opt/fossa/setup.sh.bak
        yum install -qq -y wget  &>> ~/fossa_install.log
    #    wget -c https://raw.githubusercontent.com/joey-fossa/fossa-install/master/setup_centos.sh -O /opt/fossa/setup.sh
    #    sudo chmod +x /opt/fossa/setup.sh
    fi
    echo "Finished OS Package Updates"
    ################################################################################################
    ################################################################################################
    # Get the Docker gpg key
    sleep 5s
    clear
    echo "Install GPG Keys"
    echo "Get Docker GPG key"
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - &>> ~/fossa_install.log
    #Add the Docker repository:
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" &>> ~/fossa_install.log
    #Get the Kubernetes gpg key
    echo "Get Kubernetes GPG key"
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -  &>> ~/fossa_install.log
    # Add the Kubernetes repository:
    cat << EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
    #Update packages
    echo "Apt-Get Update"
    sudo apt-get -qq update &>> ~/fossa_install.log
    #Install Docker, kubelet, kubeadm and kubectl
    echo "Install docker-ce, kubelet, kubeadm, kubectl"
    sudo apt-get install -qq -y docker-ce=18.06.1~ce~3-0~ubuntu kubelet=1.13.5-00 kubeadm=1.13.5-00 kubectl=1.13.5-00 &>> ~/fossa_install.log
    #Hold them at the current version:
    sudo apt-mark -qq hold docker-ce kubelet kubeadm kubectl &>> ~/fossa_install.log
    #Add the iptables rules to sysctl.conf
    echo "net.bridge.bridge-nf-call-iptables=1" | sudo tee -a /etc/sysctl.conf &>> ~/fossa_install.log 
    #enable iptables immediately:
    sudo sysctl -p &>> ~/fossa_install.log
    #Initialize the cluster (run only on the master)
    sleep 5s
    clear
    echo "Initializing Kubernetes"
    sudo kubeadm init --pod-network-cidr=10.244.0.0/16  &>> ~/fossa_install.log
    echo "Kubernetes Initialization Complete"
    #set up local kubeconfig:
    mkdir -p $HOME/.kube  &>> ~/fossa_install.log
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config  &>> ~/fossa_install.log
    sudo chown $(id -u):$(id -g) $HOME/.kube/config  &>> ~/fossa_install.log
    #Apply Flannel CNI network overlay:
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/bc79dd1505b0c8681ece4de4c0d86c5cd2643275/Documentation/kube-flannel.yml &>> ~/fossa_install.log
    #Verify the kubernetes node:
    echo "Check Kubernetes Node Status"
    kubectl get nodes  &>> ~/fossa_install.log
    #Remove tain from the master node
    kubectl taint nodes --all node-role.kubernetes.io/master-  &>> ~/fossa_install.log

###################################################################################################
#Deplyo FOSSA
###################################################################################################
sleep 5s
clear
echo "Deploying FOSSA"
cd /opt/  &>> ~/fossa_install.log
#Clone Github repo for Fossa
git clone https://github.com/chiphwang/fossa_helm.git  &>> ~/fossa_install.log
##############################################################################
#create FOSSA namespace
kubectl create ns fossa &>> ~/fossa_install.log
#Create FOSSA directories
cd /opt; mkdir fossa; cd fossa; mkdir database; mkdir minio; chmod 777 database; chmod 777 minio &>> ~/fossa_install.log
# Create image pull secret for Quay to pull images
cd /opt/fossa_helm/ &>> ~/fossa_install.log
##############################################################################
####Copy Certificate files
cp $fossa_file_dir/$fossa_key /opt/fossa_helm/fossa/certs/fossa.key  &>> ~/fossa_install.log
if [ $? -ne 0 ]
then
  echo "Unable to copy FOSSA key file. Halting"
  exit 1
fi

cp $fossa_file_dir/$fossa_cert /opt/fossa_helm/fossa/certs/fossa.pem  &>> ~/fossa_install.log
if [ $? -ne 0 ]
then
  echo "Unable to copy FOSSA certificate file. Halting"
  exit 1
fi
echo "Finished copying FOSSA TLS files"


cp $minio_file_dir/$minio_key /opt/fossa_helm/fossa/certs/minio.key  &>> ~/fossa_install.log
if [ $? -ne 0 ]
then
  echo "Unable to copy Minio key file. Halting"
  exit 1
fi
cp $minio_file_dir/$minio_cert /opt/fossa_helm/fossa/certs/minio.pem  &>> ~/fossa_install.log
if [ $? -ne 0 ]
then
  echo "Unable to copy Minio certificate file. Halting"
  exit 1
fi

echo "Finished copying Minio TLS files"


##############################################################################
kubectl create secret docker-registry quay.io --docker-server=quay.io --docker-username=fossa+se --docker-password=WF5GM4KAVLBE1VS1O4Z6V4BRG5K25P94ZY09ANW5S6A08X3OXRDZHSI3CA4YD1WO --docker-email=xxx@yyy.com --dry-run -o yaml > quay_secret.yaml
kubectl -n fossa create -f quay_secret.yaml 

kubectl -n fossa create secret tls tls-ssl-fossa --cert=/opt/fossa_helm/fossa/certs/fossa.pem --key=/opt/fossa_helm/fossa/certs/fossa.key
kubectl -n fossa create secret tls tls-ssl-minio --cert=/opt/fossa_helm/fossa/certs/minio.pem --key=/opt/fossa_helm/fossa/certs/minio.key

#Create configmap for Minio
kubectl create  -n fossa configmap ca-pemstore --from-file=/opt/fossa_helm/fossa/certs/minio.pem
##############################################################################
sleep 5s
clear
echo "Installing Helm"
# install helm
curl -LO https://git.io/get_helm.sh &>> ~/fossa_install.log
chmod 700 get_helm.sh &>> ~/fossa_install.log
./get_helm.sh &>> ~/fossa_install.log

# install Tiller

kubectl -n kube-system create serviceaccount tiller &>> ~/fossa_install.log

kubectl create clusterrolebinding tiller \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:tiller &>> ~/fossa_install.log

# initialize Helm
helm init --service-account tiller &>> ~/fossa_install.log
###########################################################
# move to working directory
cd /opt/fossa_helm &>> ~/fossa_install.log

sleep 60s
clear
/usr/local/bin/helm install --name fossa ./fossa --set fossahostname=$fossa_hostname,hostip=$PRIMARY_IP,miniohostname=$minio_hostname --namespace fossa
################################################################################################
#Add while checks for status of pods
sleep 10s
clear
#Check for Database running
set -f -- $(kubectl -n fossa get pod | grep database)
while [ "$3" != "Running" ]
do
    echo 'Waiting for Database'
    sleep 10s
    set -f -- $(kubectl -n fossa get pod | grep database)
done
echo "Database Ready"

#check for migration pod Completed
set -f -- $(kubectl -n fossa get pod | grep fossa-migrate)
while [ "$3" != "Completed" ]
do
    echo 'Waiting for Migration to complete'
    sleep 20s
    set -f -- $(kubectl -n fossa get pod | grep fossa-migrate)
done
echo "Migration Complete"

#Check for Minio pod running
set -f -- $(kubectl -n fossa get pod | grep minio-0)
while [ "$3" != "Running" ]
do
    echo 'Waiting for Minio'
    sleep 10s
    set -f -- $(kubectl -n fossa get pod | grep minio-0)
done
echo "Minio Ready"

#Check for Core pod Running
set -f -- $(kubectl -n fossa get pod | grep fossa-core)
while [ "$3" != "Running" ]
do
    echo 'Waiting for FOSSA Core'
    sleep 10s
    set -f -- $(kubectl -n fossa get pod | grep fossa-core)
done
echo "FOSSA Core Ready"
sleep 5s
clear
echo '################################################################################################'
echo '                                '
echo '#Automated Installation Complete'
echo '                                '
echo '################################################################################################'
echo '                                '
echo '################################################################################################'
echo '# Manually create a bucket in Minio named fossa.net'
echo '# Minio Access Key: minio'
echo '# Minio Secret Key: minio123'
echo '################################################################################################'
################################################################################################  
