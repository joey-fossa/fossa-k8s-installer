    #!/bin/bash

    #exec 2>&1 | tee ~/fossa_install.log
    exec 2>&2 | tee ~/fossa_install.log
    exec 1>&1 | tee ~/fossa_install.log
    #exec 1> ~/fossa_install.log 2>&1


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

    if [ -d "/root/fossacerts/" ] 
    then
        echo "Directory /root/fossacerts/ exists." 2> ~/fossa_install.log 
    else
        mkdir /root/fossacerts/ 2> ~/fossa_install.log
        if [ $? -ne 0 ]
            then
                echo "Unable to create /root/fossacerts directory. Halting"
                exit 1
        fi
    fi

    cp $fossa_file_dir/$fossa_key /root/fossacerts/tls.key 2> ~/fossa_install.log
    if [ $? -ne 0 ]
    then
      echo "Unable to copy FOSSA key file. Halting"
      exit 1
    fi

    cp $fossa_file_dir/$fossa_cert /root/fossacerts/tls.crt 2> ~/fossa_install.log
    if [ $? -ne 0 ]
    then
      echo "Unable to copy FOSSA certificate file. Halting"
      exit 1
    fi
    echo "Finished copying FOSSA TLS files"
    ##Prompt for path and file names for Minio key
    read -ep "Enter directory path for Minio Certificate Files (Example: /xxx/yyy/certs) " minio_file_dir
    #capture key file name
    read -ep "Enter the file name of your Minio key file " minio_key
    #capture certificate file name
    read -ep "Enter the file name of your Minio certificate file " minio_cert

    if [ -d "/root/miniocerts/" ] 
    then
        echo "Directory /root/miniocerts/ exists." 2> ~/fossa_install.log 
    else
        mkdir /root/miniocerts/ 2> ~/fossa_install.log 2> ~/fossa_install.log
        if [ $? -ne 0 ]
            then
                echo "Unable to create /root/miniocerts directory. Halting" 
                exit 1
        fi
    fi
    echo "Finished copying Minio TLS files"
    cp $minio_file_dir/$minio_key /root/miniocerts/tls.key 2> ~/fossa_install.log
    if [ $? -ne 0 ]
    then
      echo "Unable to copy Minio key file. Halting"
      exit 1
    fi
    cp $minio_file_dir/$minio_cert /root/miniocerts/tls.crt 2> ~/fossa_install.log
    if [ $? -ne 0 ]
    then
      echo "Unable to copy Minio certificate file. Halting"
      exit 1
    fi
    cp $minio_file_dir/$minio_cert /root/miniocerts/minio.pem 2> ~/fossa_install.log
    if [ $? -ne 0 ]
    then
      echo "Unable to copy Minio cert to Minio pem file. Halting"
      exit 1
    fi    

    #Check for EC2
    #Set Environment Variables
    read -p "Install in EC2 (y/n)? " ec2_answer
    case ${ec2_answer:0:1} in
        y|Y )
            export PRIMARY_IP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4 2> ~/fossa_install.log) 
            #export PRIMARY_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
            export FQN=$(curl http://169.254.169.254/latest/meta-data/public-hostname 2> ~/fossa_install.log)
        ;;
        * )
            export PRIMARY_IP=$(ip route get 1 | awk '{print $NF;exit}' 2> ~/fossa_install.log) 
            export FQN=$(nslookup $(hostname -i) 2> ~/fossa_install.log) ; fqn=${fqn##*name = } ; fqn=${fqn%.*} ; echo $fqn 2> ~/fossa_install.log
            #turn swap off
            sudo swapoff –a 2> ~/fossa_install.log
        ;;
    esac
    #Update packages
    echo "Initiating OS Package Updates"
    if [ "$OS_CHECK" = "aptgetpm" ]; then
        #Install expect
        sudo apt-get install -qq -y expect 2> ~/fossa_install.log
        ################################################################################################
        #Install Docker
        sudo apt-get -qq -y install docker.io 2> ~/fossa_install.log
        #Create links
        sudo ln -sf /usr/bin/docker.io /usr/local/bin/docker 2> ~/fossa_install.log

        ################################################################################################
        #Install PostgreSQL
        #sudo apt-get -y install postgresql postgresql-contrib
    fi
    if [ "$OS_CHECK" = "yumpm" ]; then
        sudo yum update -qq -y 2> ~/fossa_install.log
        #Install expect
        sudo yum install -qq -y expect 2> ~/fossa_install.log
        #Install XXD which is used in the configure.sh
        sudo yum install -qq -y vim-common 2> ~/fossa_install.log
        ################################################################################################

        ###############################################################################################
        ####download setup.sh for Centos support
    #    sudo mv /opt/fossa/setup.sh /opt/fossa/setup.sh.bak
        yum install -qq -y wget 2> ~/fossa_install.log
    #    wget -c https://raw.githubusercontent.com/joey-fossa/fossa-install/master/setup_centos.sh -O /opt/fossa/setup.sh
    #    sudo chmod +x /opt/fossa/setup.sh
    fi
    echo "Finished OS Package Updates"
    ################################################################################################
    ################################################################################################
    # Get the Docker gpg key
    echo "Get Docker GPG key"
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - 1> ~/fossa_install.log
    #Add the Docker repository:
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" 1> ~/fossa_install.log
    #Get the Kubernetes gpg key
    echo "Get Kubernetes GPG key"
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - 2> ~/fossa_install.log
    # Add the Kubernetes repository:
    cat << EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
    #Update packages
    echo "Apt-Get Update line 164"
    sudo apt-get -qq update 1> ~/fossa_install.log
    #Install Docker, kubelet, kubeadm and kubectl
    echo "Install docker-ce, kubelet, kubeadm, kubectl"
    sudo apt-get install -qq -y docker-ce=18.06.1~ce~3-0~ubuntu kubelet=1.13.5-00 kubeadm=1.13.5-00 kubectl=1.13.5-00 1> ~/fossa_install.log
    #Hold them at the current version:
    sudo apt-mark -qq hold docker-ce kubelet kubeadm kubectl 1> ~/fossa_install.log
    #Add the iptables rules to sysctl.conf
    echo "net.bridge.bridge-nf-call-iptables=1" | sudo tee -a /etc/sysctl.conf 1> ~/fossa_install.log 
    #enable iptables immediately:
    sudo sysctl -p 1> ~/fossa_install.log
    #Initialize the cluster (run only on the master)
    echo "Initializing Kubernetes"
    sudo kubeadm init --pod-network-cidr=10.244.0.0/16 2> ~/fossa_install.log
    echo "Kubernetes Initialization Complete"
    #set up local kubeconfig:
    mkdir -p $HOME/.kube 2> ~/fossa_install.log
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config 2> ~/fossa_install.log
    sudo chown $(id -u):$(id -g) $HOME/.kube/config 2> ~/fossa_install.log
    #Apply Flannel CNI network overlay:
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/bc79dd1505b0c8681ece4de4c0d86c5cd2643275/Documentation/kube-flannel.yml 1> ~/fossa_install.log
    #Verify the kubernetes node:
    echo "Check Kubernetes Node Status"
    kubectl get nodes 2> ~/fossa_install.log
    #Remove tain from the master node
    kubectl taint nodes --all node-role.kubernetes.io/master- 2> ~/fossa_install.log
    ###################################################################################################
    #Deploy FOSSA
    ###################################################################################################
    echo "Deploying FOSSA"
    cd /opt/ 2> ~/fossa_install.log
    #Clone Github repo for Fossa
    git clone https://github.com/chiphwang/FossaAllinOne.git 1> ~/fossa_install.log
    #create FOSSA namespace
    kubectl create ns fossa 1> ~/fossa_install.log
    #Create FOSSA directories
    cd /opt; mkdir fossa; cd fossa; mkdir database; mkdir minio; chmod 777 database; chmod 777 minio 1> ~/fossa_install.log
    # Create image pull secret for Quay to pull images
    cd /opt/FossaAllinOne 1> ~/fossa_install.log
    kubectl create secret docker-registry quay.io --docker-server=quay.io --docker-username=fossa+se --docker-password=WF5GM4KAVLBE1VS1O4Z6V4BRG5K25P94ZY09ANW5S6A08X3OXRDZHSI3CA4YD1WO --docker-email=xxx@yyy.com --dry-run -o yaml > quay_secret.yaml 2> ~/fossa_install.log
    kubectl -n fossa create -f quay_secret.yaml 1> ~/fossa_install.log
    #########################################################
    #Placeholders - here is where we need to edit the configmap.yaml
    #########################################################
    #
    #
    #Build in logicl to get primary_ip and update the ip host of the fossa.yaml file
    #replace ip: "54.149.177.110" with ip: "$PRIMARY_IP"
    sudo sed -i -e 's/54.149.177.110/'$PRIMARY_IP'/g' /opt/FossaAllinOne/fossa.yaml 2> ~/fossa_install.log
    #
    #Update host name in configmap.yaml & ingress.yaml for self entered host names
    sudo sed -i -e 's/fossa.local/'$fossa_hostname'/g' /opt/FossaAllinOne/configmap.yaml 2> ~/fossa_install.log
    sudo sed -i -e 's/minio.local/'$minio_hostname'/g' /opt/FossaAllinOne/configmap.yaml 2> ~/fossa_install.log
    #
    sudo sed -i -e 's/fossa.local/'$fossa_hostname'/g' /opt/FossaAllinOne/ingress.yaml 2> ~/fossa_install.log
    sudo sed -i -e 's/minio.local/'$minio_hostname'/g' /opt/FossaAllinOne/ingress.yaml 2> ~/fossa_install.log
    #
    sudo sed -i -e 's/minio.local/'$minio_hostname'/g' /opt/FossaAllinOne/fossa.yaml 2> ~/fossa_install.log
    #
    #Create configmap.yaml
    kubectl create -f configmap.yaml 1> ~/fossa_install.log
    #Create configmap for Minio
    kubectl create  -n fossa configmap ca-pemstore --from-file=/root/miniocerts/minio.pem 1> ~/fossa_install.log
    #Create Secret for FOSSA
    kubectl -n fossa create secret generic tls-ssl-fossa --from-file=/root/fossacerts/tls.crt --from-file=/root/fossacerts/tls.key 1> ~/fossa_install.log
    #Create Secret for Minio
    kubectl -n fossa create secret generic tls-ssl-minio  --from-file=/root/miniocerts/tls.crt --from-file=/root/miniocerts/tls.key 1> ~/fossa_install.log
    #Create the databse statefulset and the database service
    kubectl create -f database.yaml 2> ~/fossa_install.log
    sleep 10s
    set -f -- $(kubectl -n fossa get pod | grep database)
    while [ "$3" != "Running" ]
    do
        echo 'Waiting for Database'
        sleep 10s
        set -f -- $(kubectl -n fossa get pod | grep database)
    done
    echo "Database Ready"
    #migrate the databse schema
    kubectl create -f migrate-db.yaml 2> ~/fossa_install.log
    set -f -- $(kubectl -n fossa get pod | grep fossa-migrate)
    while [ "$3" != "Completed" ]
    do
        echo 'Waiting for Migration to complete'
        sleep 20s
        set -f -- $(kubectl -n fossa get pod | grep fossa-migrate)
    done
    echo "Migration Complete"
    #Create the Minio statefulset
    kubectl create -f minio.yaml 2> ~/fossa_install.log
    set -f -- $(kubectl -n fossa get pod | grep minio-0)
    while [ "$3" != "Running" ]
    do
        echo 'Waiting for Minio'
        sleep 10s
        set -f -- $(kubectl -n fossa get pod | grep minio-0)
    done
    echo "Minio Ready"
    #Create the ingress controller
    kubectl create -f ingress_controller.yaml 1> ~/fossa_install.log
    sleep 5s
    #Create the ingress for FOSSA and Minio
    kubectl create -f ingress.yaml 1> ~/fossa_install.log
    sleep 5s
    #Create FOSSA components
    kubectl create -f fossa.yaml 1> ~/fossa_install.log
    #
    kubectl get pods -n fossa 1> ~/fossa_install.log
    ################################################################################################
    echo '################################################################################################'
    echo '#Create a bucket in Minio named fossa.net'
    echo '#Minio Access Key: minio'
    echo '#Minio Secret Key: minio123'
    echo '################################################################################################'
    ################################################################################################

