# Setup kubernetes on simple multi node on Amazon linux 2

This example creates a multi-node kubernetes cluster on AWS using Amazon Linux 2 AMI.

* 1 Control plane as master
* 2 Worker nodes

Calico is used as CNI for the cluster.

(!) The installation should be done as `sudouser``

```bash
sudo su
```

## Prerequisite [All nodes]

### Upgrade Amazon Linux 2 kernel version 4.14.x to Amazon Linux Extra kernel versions

The minimal version required by kubernetes is 4.15 and the recommended version is 5.8+. For more information, see [How do I upgrade my standard Amazon Linux 2 kernel version 4.14.x to Amazon Linux Extra kernel versions?](<https://repost.aws/knowledge-center/amazon-linux-2-kernel-upgrade>)

To review the current active kernel version.

```bash
uname -r
```

The current system kernel version is 4.14.268-205.500.
Patch your Amazon Linux so that it's up to date, and then reboot

```bash
yum -y upgrade
reboot
```

Review the kernel versions that the amazon-linux-extras repository offers:

```bash
amazon-linux-extras | grep kernel
```

This output lists the three kernel options available from the Amazon Linux Extra repository:

* kernel-5.4
* kernel-5.10
* kernel-5.15

To install the kernel 5.10, use the amazon-linux-extras tool:

```bash
amazon-linux-extras install kernel-5.10 -y
```

After the installation completes, verify that the state is changed in amazon-linux-extras:

```bash
amazon-linux-extras |grep kernel
```

The output lists the three kernel options again. The following example shows that kernel-5.10 is enabled:

```text
  _  kernel-5.4               available    [ =stable ]
 55  kernel-5.10=latest       enabled      [ =stable ]
 62  kernel-5.15              available    [ =stable ]
```

The following output line shows that the state is changed from available to enabled:

```text
 55  kernel-5.10=latest       enabled      [ =stable ]
```

Verify the installed kernels from the RPM database:

```bash
rpm -qa | grep kernel
```

The output lists the installed kernel packages. The following example shows that both the old and new kernel versions are installed:

```text
kernel-tools-4.14.268-205.500.amzn2.x86_64
kernel-4.14.268-205.500.amzn2.x86_64
kernel-5.10.201-191.748.amzn2.x86_64
kernel-tools-5.10.201-191.748.amzn2.x86_64
```

There are now two different kernel versions available: `kernel-4.14.268-205.500` `and 5.10.201-191.748`.

The following example shows that the old kernel is still active:

```bash
uname -r
```

The output shows that the current active kernel version is still `4.14.268-205.500.amzn2.x86_64`

To activate the latest installed kernel version, reboot the instance:

```bash
sudo reboot
```

Log in to the instance again, and then verify that the new kernel is active:

```bash
reboot
```

### Local Hostname Resolution

It ensures that the local machine's hostname resolves to the loopback IP (127.0.0.1). This helps the system internally resolve the hostname without needing to query external DNS servers.

```bash
echo "127.0.0.1 $HOSTNAME" >> /etc/hosts
```

## Install container management tool [All nodes]

### Install Containerd

Kubernetes components such as the API server, controller manager, and scheduler are run inside containers. Containerd helps to run and manage these containers on the nodes.

```bash
yum install containerd -y
```

### Modify the configuration file for containerd

Copy the default config

```bash
containerd config default > /etc/containerd/config.toml
```

When you install a Kubernetes cluster using kubeadm, the kubelet agent needs to interface with the container runtime (like containerd) to manage containers. Both kubelet and containerd must use the same cgroup manager to ensure consistency and proper management of resources across the system.

```bash
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
```

### Start the Containerd service

Ensures Docker starts on boot and verify Docker service status.

```bash
systemctl enable containerd
systemctl start containerd
systemctl status containerd
```

### Create network bridge settings

* These settings are critical for proper network packet forwarding in a Kubernetes (kubeadm) cluster.
* Kubernetes heavily relies on networking for communication between containers (pods), nodes, and services. Ensuring that bridged traffic is processed through iptables is critical for allowing Kubernetes to manage and control network traffic properly.
* Kubernetes networking plugins (like Calico, Flannel, or Weave) rely on these kernel parameters to ensure that network packets are correctly routed between nodes and pods. These settings ensure that the rules set by Kubernetes for pod communication, service discovery, and network policies are enforced.

```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward=1
EOF
```

Reload and apply kernel parameters from configuration file
Running sysctl --system applies the kernel parameter changes stored in system configuration files, including those necessary for Kubernetes networking.

```bash
sysctl --system
```

## Prerequisite for Installing Kubeadm cluster [All nodes]

### Disable swap space on the system

* Disabling swap improves cluster stability, performance, and ensures consistent resource allocation, as Kubernetes expects physical memory to be the primary resource for scheduling and managing containers.

```bash
swapoff -a
```

* The swapoff -a command turns off swap space, meaning the system will no longer use disk space as virtual memory. It effectively forces the system to rely only on physical memory (RAM).
* To ensure swap remains disabled after a system reboot, you also need to remove or comment out swap entries from the /etc/fstab file, which defines disk partitions and mount points. Otherwise, swap will be re-enabled after a reboot. You can do this by editing the file with: `sudo vi /etc/fstab`

### Disable SELinux or put it into permissive mode

* Disabling or setting SELinux to permissive mode is crucial for avoiding conflicts with Kubernetes components, particularly with container networking and storage.

```bash
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
```

* `setenforce 0` temporarily switches SELinux to permissive mode to allow Kubernetes to function without interference.
* `sed` command modifies the SELinux configuration file to ensure that the system stays in permissive mode after reboots.

## Install Kubeadm Cluster

### Create a new YUM repository configuration file for Kubernetes packages [All nodes]

* Create a YUM repository configuration file for Kubernetes packages, enabling you to install and manage Kubernetes components.
* It sets the repository URL, ensures package signature verification, and excludes specific Kubernetes packages to avoid conflicts.

```bash
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.32/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.32/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
```

* By excluding specific packages (kubelet, kubeadm, kubectl, cri-tools, kubernetes-cni), you avoid potential conflicts with other repositories or ensure that you are using versions of these packages from another trusted source, like the official Kubernetes repository.

### Install the Kubernetes components kubelet, kubeadm, and kubectl [All nodes]

```bash
yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
```

* `kubelet`: The Kubernetes node agent that runs on each node in the cluster, managing containerized applications and ensuring they run according to the specifications.
* `kubeadm`: A tool used to bootstrap and manage Kubernetes clusters. It simplifies the process of setting up a Kubernetes control plane and worker nodes.
* `kubectl`: The command-line tool for interacting with Kubernetes clusters, allowing you to manage and troubleshoot cluster resources.

### Bash completion (optional, helpful)

```bash
yum install -y bash-completion
echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -F __start_kubectl k' >> ~/.bashrc
source ~/.bashrc
```

### Start kubelet service automatically [All nodes]

```bash
systemctl enable --now kubelet
```

* The purpose of the command is to ensure that the kubelet service starts automatically on system boot and starts immediately on the current session.
* `--now` option makes sure that kubelet starts immediately

### Initializing the Kubernetes control plane node [Control plane only]

* Running `kubeadm init` sets up the master node, which is responsible for managing the cluster's state and scheduling workloads. It configures the core components of the Kubernetes control plane.

```bash
kubeadm init --control-plane-endpoint=<CP_PRIVATE_IP>:6443 \
  --apiserver-advertise-address=<CP_PRIVATE_IP> \
  --pod-network-cidr=10.244.0.0/16
```

* `kubeadm init`: This command initializes a Kubernetes control plane node.
* `-pod-network-cidr=10.244.0.0/16`: This option specifies the CIDR (Classless Inter-Domain Routing) range for the pod network. It will be used to configure the CNI. See below in `Calico` configuration
* `--control-plane-endpoint=<CP_PRIVATE_IP>:6443`: This option sets the endpoint for the control plane, which is used by `kubeadm` to configure the API server and other components to listen on this address.
* `--apiserver-advertise-address=<CP_PRIVATE_IP>`: This option specifies the IP address that the API server will advertise to other components in the cluster.

### Configure Local Access to the Kubernetes Cluster [Control plane only]

```bash
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

These commands set up your local environment to interact with the Kubernetes cluster by copying the cluster configuration file to the default location (~/.kube/config) and ensuring that it has the appropriate permissions for the current user.
This setup allows you to use kubectl to manage and interact with your Kubernetes cluster from your local machine.

### Initializes a Kubernetes worker node and joins it to the cluster [Worker nodes only]

```bash
kubeadm join <ip-masternode>:6443 --token dv45rt.qe7gq4crzx1rsvv6 \
 --discovery-token-ca-cert-hash sha256:e4589020a032d2417b174023a99148908eec2f00b86f05112a9e04dc0ab7
```

Replace `<ip-masternode>` with the private IP address of the control plane node

## Install calico [Control plane only]

For more information, see [documentation - Step 2](https://docs.tigera.io/calico/latest/getting-started/kubernetes/quickstart)

1. Install the Tigera Operator and custom resource definitions.

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.3/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.3/manifests/tigera-operator.yaml
```

2. Apply a minimal Installation CR (no calico-apiserver)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: operator.tigera.io/v1        # Calico Operator API group/version
kind: Installation                        # Cluster-wide Calico install spec
metadata:
  name: default                           # Must be named 'default' (singleton)
spec:
  calicoNetwork:                          # Calico networking settings
    bgp: Disabled                         # Enabled by default, turn off BGP for VXLAN-only networking
    ipPools:
    - cidr: 10.244.0.0/16                # Pod CIDR (matches kubeadm --pod-network-cidr)
      natOutgoing: Enabled                # SNAT pod→external traffic at node egress
      blockSize: 26                       # Per-node IP block size (/26 = 64 pod IPs)
      encapsulation: VXLANCrossSubnet     # Use VXLAN; skip encapsulation within same L2 subnet
      nodeSelector: all()                 # Apply this pool to all nodes
EOF
```

3. Monitor the deployment by running the following command

```bash
watch kubectl get pods -n calico-system
```

After a few minutes, all the Calico components display True in the AVAILABLE column and cluster nodes will become `Ready`.

### Verify the installed version of Kubernetes

* Print the client and server version information for the current context

```bash
kubectl version
```

Response:

```text
Client Version: v1.30.5
Kustomize Version: v5.0.4-0.20230601165947-6ce0bf390ce3
Server Version: v1.30.1
```

### Verify the nodes in the cluster

* The kubectl get nodes command lists all the nodes in a Kubernetes cluster

```bash
kubectl get nodes
```

Response:

```text
NAME            STATUS   ROLES           AGE     VERSION
master         Ready    control-plane   61m     v1.32.9
worker1        Ready    <none>          3m21s   v1.32.9
```

Elevate your Kubernetes journey with a hands-on guide to setting up a Kubeadm cluster on Amazon Linux 2023. Discover the power of Kubernetes to streamline your application deployment and management."

## Test cluster installation

```bash
# See nodes and system pods
kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide

# Tiny demo app + Service
kubectl create deploy web --image=nginx --replicas=3
kubectl expose deploy/web --port=80 --type=NodePort

# Discover the NodePort
kubectl get svc web -o wide
kubectl get svc web -o jsonpath='{.spec.ports[0].nodePort}'; echo

# Test from your machine (security groups must allow it)
curl -I http://<worker-1-public-or-private-ip>:<nodeport>
curl -I http://<worker-2-public-or-private-ip>:<nodeport>
```
