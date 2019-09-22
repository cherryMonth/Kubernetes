#!/bin/bash
# 以下命令仅做参考，不对产生任何的负面结果负责

# 更新系统镜像源
# 在所有节点的/etc/hosts 添加各个节点的ip映射
wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
yum clean all
yum makecache
yum install docker

# docker环境准备
# vim /etc/fstab
# 注销掉swap或者安装操作系统时不创建swap

# 格式化/var/lib/docker为ftype=1, 在笔者集群/dev/sda2为docker分区
# umount /dev/sda2
# mkfs.xfs -f -n ftype=1 /dev/sda2
# blkid /dev/sda2
# 根据上文的UUID修改/etc/fstab中的/var/lib/docker
# mount /dev/sda2 /var/lib/docker

# 修改本机网络设置
cat >> /etc/sysctl.conf  <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
vm.swappiness = 0
EOF

# 关闭selinux
# vim /etc/selinux/conf
# 设置SELINUX=disabled
sed -i '7c SELINUX=disabled' /etc/selinux/config

# 添加k8s软件源
cat > /etc/yum.repos.d/k8s.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
EOF

# 指定docker镜像源
echo '{"registry-mirrors": ["https://registry.docker-cn.com"]}' > /etc/docker/daemon.json

# 安装k8s(最好指定版本)
yum install kubelet-1.14.0 kubeadm-1.14.0  kubectl-1.14.0 --disableexcludes=kubernetes -y

systemctl start docker && systemctl enable docker && systemctl start kubelet && systemctl enable kubelet

# 生效
sysctl -p

kubeadm config print init-defaults

kubeadm config print init-defaults > init.default.yaml

cp init.default.yaml init-default.yaml

# 修改init-default.yaml 
# imageRepository: docker.io/dustise
# podSubnet: "192.168.0.0/16"
# 根据实际情况修改 advertiseAddress: 10.0.2.15

# 到此处最好重启一次
# reboot

# 从配置文件创建k8s
# 如果出现错误使用kubeadm reset撤销
kubeadm config images pull --config=init-default.yaml

kubeadm init --config init-default.yaml

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl get -n kube-system configmap

# 如果是单机部署，需要执行命令取消master标签
kubectl taint nodes --all node-role.kubernetes.io/master-

# 此时由于缺少网络组件，使用weave一键式安装
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"

kubectl get pod --all-namespaces
