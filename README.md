# Kubernetes权威指南

此处记录Kubernetes权威指南(第四版) 每一章创建和使用的配置文件、命令和代码。

节点名称   节点IP        角色              描述 

idc-134  172.18.9.134  Master && Slave  主节点和数据节点 

idc-135  172.18.9.135  Master && Slave  主节点和数据节点

idc-136  172.18.9.136  Master && Slave  主节点和数据节点 

idc-200  172.18.9.200  虚拟IP            高可用与负载均衡虚拟IP 

# 使用kubeadm部署分布式高可用集群

# 环境准备
>  **所有节点执行**

## 更新系统镜像源
wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo

yum clean all

yum makecache

yum install docker -y

- 要在各个节点的/etc/hosts文件添加所有节点的映射

## docker环境准备

```bash
# 注销掉swap或者安装操作系统时不创建swap
vim /etc/fstab

# 格式化/var/lib/docker为ftype=1, 在笔者集群/dev/sda2为docker分区
umount /dev/sda2
kfs.xfs -f -n ftype=1 /dev/sda2
blkid /dev/sda2
# 根据上文的UUID修改/etc/fstab中的/var/lib/docker
mount /dev/sda2 /var/lib/docker

# 修改本机网络设置
cat >> /etc/sysctl.conf  <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
vm.swappiness = 0
EOF

# 关闭selinux
# 设置SELINUX=disabled /etc/selinux/conf
sed -i '7c SELINUX=disabled' /etc/selinux/config

# 开机启动docker
systemctl start docker && systemctl enable docker

# 如果没有启动docker执行下面的命令会报错
sysctl -p

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

# 启动k8s
systemctl start kubelet && systemctl enable kubelet
```

## 部署keepalived和haproxy
### keepalived配置
idc-134的priority为100，idc-135的priority为90，idc-136的priority为80，其他配置一致。(配置文件需要改成如下格式，其他项需要删除)。
```bash
# cat /etc/keepalived/keepalived.conf

global_defs {
   notification_email {
     acassen@firewall.loc
     failover@firewall.loc
     sysadmin@firewall.loc
   }
   notification_email_from Alexandre.Cassen@firewall.loc
   smtp_server 127.0.0.1
   smtp_connect_timeout 30
   router_id LVS_DEVEL
   vrrp_skip_check_adv_addr
   vrrp_garp_interval 0
   vrrp_gna_interval 0
}

vrrp_instance VI_1 {
    state MASTER
    interface ens192
    virtual_router_id 51
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    virtual_ipaddress {
        172.18.9.200/22
    }
}
```

### haproxy配置
idc-134、idc-135、idc-136的haproxy配置是一样的，此处我们监听172.18.9.200的8443端口(使用6443会冲突)。
```bash
# cat /etc/haproxy/haproxy.cfg

global
    log         127.0.0.1 local2

    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon

    # turn on stats unix socket
    stats socket /var/lib/haproxy/stats

defaults
    mode                    tcp
    log                     global
    option                  dontlognull
    option http-server-close
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

listen https-apiserver
        bind 172.18.9.200:8443
        mode tcp
        balance roundrobin
        timeout server 900s
        timeout connect 15s

        server apiserver01 172.18.9.134:6443 check port 6443 inter 5000 fall 5
        server apiserver02 172.18.9.135:6443 check port 6443 inter 5000 fall 5
        server apiserver03 172.18.9.136:6443 check port 6443 inter 5000 fall 5
```

- 启动服务

```bash
systemctl enable keepalived && systemctl start keepalived 
systemctl enable haproxy && systemctl start haproxy 
```

- 验证keepalived是否正常工作

```bash
# 查看虚拟IP是否在master idc-134上
[root@idc-134 ~]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN qlen 1
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
2: ens192: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP qlen 1000
    link/ether 00:50:56:bb:72:51 brd ff:ff:ff:ff:ff:ff
    inet 172.18.9.134/22 brd 172.18.11.255 scope global ens192
       valid_lft forever preferred_lft forever
    inet 172.18.9.200/22 scope global secondary ens192
       valid_lft forever preferred_lft forever
    inet6 fe80::d288:7ec0:f505:d24/64 scope link tentative dadfailed
       valid_lft forever preferred_lft forever
    inet6 fe80::f6c3:6e8:6494:fe7c/64 scope link tentative dadfailed
       valid_lft forever preferred_lft forever
    inet6 fe80::ed3e:a960:7e0:3f87/64 scope link tentative dadfailed
       valid_lft forever preferred_lft forever
3: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN
    link/ether 02:42:75:59:3c:7b brd ff:ff:ff:ff:ff:ff
    inet 172.17.0.1/16 scope global docker0
       valid_lft forever preferred_lft forever
```

然后关闭idc-134的keepalived服务查看虚拟ip是否转移到idc-135。
```
[root@idc-134 ~]# systemctl stop keepalived.service

[root@idc-135 ~]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN qlen 1
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
2: ens192: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP qlen 1000
    link/ether 00:50:56:bb:27:56 brd ff:ff:ff:ff:ff:ff
    inet 172.18.9.135/22 brd 172.18.11.255 scope global ens192
       valid_lft forever preferred_lft forever
    inet 172.18.9.200/22 scope global secondary ens192
       valid_lft forever preferred_lft forever
    inet6 fe80::d288:7ec0:f505:d24/64 scope link tentative dadfailed
       valid_lft forever preferred_lft forever
    inet6 fe80::f6c3:6e8:6494:fe7c/64 scope link tentative dadfailed
       valid_lft forever preferred_lft forever
    inet6 fe80::ed3e:a960:7e0:3f87/64 scope link tentative dadfailed
       valid_lft forever preferred_lft forever
3: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN
    link/ether 02:42:58:5d:8b:a1 brd ff:ff:ff:ff:ff:ff
    inet 172.17.0.1/16 scope global docker0
       valid_lft forever preferred_lft forever
```

然后启动idc-134的keepalived服务，查看虚拟IP是否转移回来。

```bash
[root@idc-134 ~]# systemctl start keepalived.service

[root@idc-134 ~]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN qlen 1
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
2: ens192: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP qlen 1000
    link/ether 00:50:56:bb:72:51 brd ff:ff:ff:ff:ff:ff
    inet 172.18.9.134/22 brd 172.18.11.255 scope global ens192
       valid_lft forever preferred_lft forever
    inet 172.18.9.200/22 scope global secondary ens192
       valid_lft forever preferred_lft forever
    inet6 fe80::d288:7ec0:f505:d24/64 scope link tentative dadfailed
       valid_lft forever preferred_lft forever
    inet6 fe80::f6c3:6e8:6494:fe7c/64 scope link tentative dadfailed
       valid_lft forever preferred_lft forever
    inet6 fe80::ed3e:a960:7e0:3f87/64 scope link tentative dadfailed
       valid_lft forever preferred_lft forever
3: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN
    link/ether 02:42:75:59:3c:7b brd ff:ff:ff:ff:ff:ff
    inet 172.17.0.1/16 scope global docker0
       valid_lft forever preferred_lft forever
[root@idc-134 ~]#
```


# k8s Master部署
> 只需在一台master节点执行

```bash
# 创建k8s配置依赖
kubeadm config print init-defaults > init-default.yaml

# 需要修改的项如下（根据真实情况修改）
localAPIEndpoint:
  advertiseAddress: 172.18.9.134

controlPlaneEndpoint: "172.18.9.200:8443"

imageRepository: docker.io/dustise

# 如果此处不配置，则无法安装flannel插件
# 如果忘记配置podSubnet仍希望使用flannel则需要使用kubeadm reset重新安装
podSubnet: "10.244.0.0/16" 

# cat init-default.yaml
apiVersion: kubeadm.k8s.io/v1beta1
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: abcdef.0123456789abcdef
  ttl: 24h0m0s
  usages:
  - signing
  - authentication
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 172.18.9.134
  bindPort: 6443
nodeRegistration:
  criSocket: /var/run/dockershim.sock
  name: idc-134
  taints:
  - effect: NoSchedule
    key: node-role.kubernetes.io/master
---
apiServer:
  timeoutForControlPlane: 4m0s
apiVersion: kubeadm.k8s.io/v1beta1
certificatesDir: /etc/kubernetes/pki
clusterName: kubernetes
controlPlaneEndpoint: "172.18.9.200:8443"
controllerManager: {}
dns:
  type: CoreDNS
etcd:
  local:
    dataDir: /var/lib/etcd
imageRepository: docker.io/dustise
kind: ClusterConfiguration
kubernetesVersion: v1.14.0
networking:
  dnsDomain: cluster.local
  podSubnet: "10.244.0.0/16"
  serviceSubnet: 10.96.0.0/12
scheduler: {}

# 镜像预下载
[root@idc-134 ~]# kubeadm config images pull --config=init-default.yaml
[config/images] Pulled docker.io/dustise/kube-apiserver:v1.14.0
[config/images] Pulled docker.io/dustise/kube-controller-manager:v1.14.0
[config/images] Pulled docker.io/dustise/kube-scheduler:v1.14.0
[config/images] Pulled docker.io/dustise/kube-proxy:v1.14.0
[config/images] Pulled docker.io/dustise/pause:3.1
[config/images] Pulled docker.io/dustise/etcd:3.3.10
[config/images] Pulled docker.io/dustise/coredns:1.3.1

# k8s初始化
kubeadm init --config init-default.yaml

# 成功时结果如下（需要保存token，以便后续节点扩展）
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

You can now join any number of control-plane nodes by copying certificate authorities
and service account keys on each node and then running the following as root:

  kubeadm join 172.18.9.200:8443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:f833a5df22c6642f529767dd208df99ec24bbf8bd22b8e9f3a78b2bacad6ee8a \
    --experimental-control-plane

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 172.18.9.200:8443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:f833a5df22c6642f529767dd208df99ec24bbf8bd22b8e9f3a78b2bacad6ee8a
[root@idc-134 ~]#
```

- 为kubectl准备Kubeconfig文件
- 
kubectl默认会在执行的用户家目录下面的.kube目录下寻找config文件。这里是将在初始化时[kubeconfig]步骤生成的admin.conf拷贝到.kube/config。

```bash
[root@idc-134 ~]# mkdir -p $HOME/.kube
[root@idc-134 ~]# sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
[root@idc-134 ~]# sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

在该配置文件中，记录了API Server的访问地址，所以后面直接执行kubectl命令就可以正常连接到API Server中。

- 查看组件状态
```bash
[root@idc-134 ~]# kubectl get cs
NAME                 STATUS    MESSAGE             ERROR
scheduler            Healthy   ok
controller-manager   Healthy   ok
etcd-0               Healthy   {"health":"true"}
[root@idc-134 ~]#
[root@idc-134 ~]# kubectl get node
NAME      STATUS     ROLES    AGE     VERSION
idc-134   NotReady   master   3m57s   v1.14.0
```
目前只有一个节点，角色是Master，状态是NotReady。

- 其他master部署
  将idc-134的证书文件拷贝至其他master节点

```bash
# vim ca-cp.sh 

USER=root
CONTROL_PLANE_IPS="idc-135 idc-136"
for host in ${CONTROL_PLANE_IPS}; do
    ssh "${USER}"@$host "mkdir -p /etc/kubernetes/pki/etcd"
    scp /etc/kubernetes/pki/ca.* "${USER}"@$host:/etc/kubernetes/pki/
    scp /etc/kubernetes/pki/sa.* "${USER}"@$host:/etc/kubernetes/pki/
    scp /etc/kubernetes/pki/front-proxy-ca.* "${USER}"@$host:/etc/kubernetes/pki/
    scp /etc/kubernetes/pki/etcd/ca.* "${USER}"@$host:/etc/kubernetes/pki/etcd/
    scp /etc/kubernetes/admin.conf "${USER}"@$host:/etc/kubernetes/
done

# bash ca-cp.sh
```

- 使用kubeadm join加入master，具体的token
> 其他master节点执行

```bash
kubeadm join 172.18.9.200:8443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:f833a5df22c6642f529767dd208df99ec24bbf8bd22b8e9f3a78b2bacad6ee8a \
    --experimental-control-plane
    
# 完成之后也需要创建Kubeconfig文件
```

- 部署网络插件flannel
Master节点NotReady的原因就是因为没有使用任何的网络插件，此时Node和Master的连接还不正常。目前最流行的Kubernetes网络插件有Flannel、Calico、Canal、Weave这里选择使用flannel。

```bash
[root@idc-134 ~]#  kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
podsecuritypolicy.policy/psp.flannel.unprivileged created
clusterrole.rbac.authorization.k8s.io/flannel created
clusterrolebinding.rbac.authorization.k8s.io/flannel created
serviceaccount/flannel created
configmap/kube-flannel-cfg created
daemonset.apps/kube-flannel-ds-amd64 created
daemonset.apps/kube-flannel-ds-arm64 created
daemonset.apps/kube-flannel-ds-arm created
daemonset.apps/kube-flannel-ds-ppc64le created
daemonset.apps/kube-flannel-ds-s390x created
[root@idc-134 ~]#
```

- 查看节点状态
所有节点已经处于ready状态。
```bash
[root@idc-134 ~]# kubectl get node
NAME      STATUS   ROLES    AGE     VERSION
idc-134   Ready    master   19m     v1.14.0
idc-135   Ready    master   3m53s   v1.14.0
idc-136   Ready    master   2m34s   v1.14.0
[root@idc-134 ~]#
```

- 查看Pod状态
如果出现coredns和flannel无法使用，则是因为没有在kubeadm init设置podSubnet的缘故，需要使用kubeadm reset重新安装。

```bash
[root@idc-134 ~]# kubectl get pod -n kube-system
NAME                              READY   STATUS    RESTARTS   AGE
coredns-6897bd7b5-fzjmg           1/1     Running   0          4m5s
coredns-6897bd7b5-t86sg           1/1     Running   0          4m5s
etcd-idc-134                      1/1     Running   0          3m22s
etcd-idc-135                      1/1     Running   0          2m51s
etcd-idc-136                      1/1     Running   0          117s
kube-apiserver-idc-134            1/1     Running   0          3m5s
kube-apiserver-idc-135            1/1     Running   0          2m52s
kube-apiserver-idc-136            1/1     Running   1          45s
kube-controller-manager-idc-134   1/1     Running   1          3m18s
kube-controller-manager-idc-135   1/1     Running   0          2m51s
kube-controller-manager-idc-136   1/1     Running   0          78s
kube-flannel-ds-amd64-klhhm       1/1     Running   0          19s
kube-flannel-ds-amd64-qp57c       1/1     Running   0          19s
kube-flannel-ds-amd64-x287l       1/1     Running   0          19s
kube-proxy-6hhjs                  1/1     Running   0          4m5s
kube-proxy-smmzt                  1/1     Running   0          2m52s
kube-proxy-wlcdg                  1/1     Running   0          117s
kube-scheduler-idc-134            1/1     Running   1          3m20s
kube-scheduler-idc-135            1/1     Running   0          2m52s
kube-scheduler-idc-136            1/1     Running   0          75s
[root@idc-134 ~]#
```

- 如果希望master也参与pod部署，则需要取消master标签
```bash
kubectl taint nodes --all node-role.kubernetes.io/master-
```
