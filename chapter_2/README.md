# 使用kubeadm工具快速安装Kubernetes

此处存在坑爹的地方，原书在修改init-default.yaml文件时，只修改了镜像仓库地址和podSubnet，但是没有修改一个很重要的属性advertiseAddress，这个要指定master的IP地址，默认是：1.2.3.4，如果不修改的话kubelet就会一直报节点不存在的错误，导致安装失败。

## 安装失败时解决方法
1、需要修改/etc/hosts文件，向其中添加本机的IP记录。
2、需要修改/etc/sysctl.conf，向其中添加:
```bash
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
vm.swappiness = 0
```
