## Kubernetes

The NixOS Kubernetes module is a collective term for a handful of individual submodules implementing the Kubernetes cluster components.

There are generally two ways of enabling Kubernetes on NixOS. One way is to enable and configure cluster components appropriately by hand:

```programlisting
{
  services.kubernetes = {
    apiserver.enable = true;
    controllerManager.enable = true;
    scheduler.enable = true;
    addonManager.enable = true;
    proxy.enable = true;
    flannel.enable = true;
  };
}
```

Another way is to assign cluster roles (“master” and/or “node”) to the host. This enables apiserver, controllerManager, scheduler, addonManager, kube-proxy and etcd:

```programlisting
{ services.kubernetes.roles = [ "master" ]; }
```

While this will enable the kubelet and kube-proxy only:

```programlisting
{ services.kubernetes.roles = [ "node" ]; }
```

Assigning both the master and node roles is usable if you want a single node Kubernetes cluster for dev or testing purposes:

```programlisting
{
  services.kubernetes.roles = [
    "master"
    "node"
  ];
}
```

Note: Assigning either role will also default both [`services.kubernetes.flannel.enable`](options.html#opt-services.kubernetes.flannel.enable) and [`services.kubernetes.easyCerts`](options.html#opt-services.kubernetes.easyCerts) to true. This sets up flannel as CNI and activates automatic PKI bootstrapping.

### Note

It is mandatory to configure: [`services.kubernetes.masterAddress`](options.html#opt-services.kubernetes.masterAddress). The masterAddress must be resolveable and routeable by all cluster nodes. In single node clusters, this can be set to `localhost`.

Role-based access control (RBAC) authorization mode is enabled by default. This means that anonymous requests to the apiserver secure port will expectedly cause a permission denied error. All cluster components must therefore be configured with x509 certificates for two-way tls communication. The x509 certificate subject section determines the roles and permissions granted by the apiserver to perform clusterwide or namespaced operations. See also: [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/).

The NixOS kubernetes module provides an option for automatic certificate bootstrapping and configuration, [`services.kubernetes.easyCerts`](options.html#opt-services.kubernetes.easyCerts). The PKI bootstrapping process involves setting up a certificate authority (CA) daemon (cfssl) on the kubernetes master node. cfssl generates a CA-cert for the cluster, and uses the CA-cert for signing subordinate certs issued to each of the cluster components. Subsequently, the certmgr daemon monitors active certificates and renews them when needed. For single node Kubernetes clusters, setting [`services.kubernetes.easyCerts`](options.html#opt-services.kubernetes.easyCerts) = true is sufficient and no further action is required. For joining extra node machines to an existing cluster on the other hand, establishing initial trust is mandatory.

To add new nodes to the cluster: On any (non-master) cluster node where [`services.kubernetes.easyCerts`](options.html#opt-services.kubernetes.easyCerts) is enabled, the helper script `nixos-kubernetes-node-join` is available on PATH. Given a token on stdin, it will copy the token to the kubernetes secrets directory and restart the certmgr service. As requested certificates are issued, the script will restart kubernetes cluster components as needed for them to pick up new keypairs.

### Note

Multi-master (HA) clusters are not supported by the easyCerts module.

In order to interact with an RBAC-enabled cluster as an administrator, one needs to have cluster-admin privileges. By default, when easyCerts is enabled, a cluster-admin kubeconfig file is generated and linked into `/etc/kubernetes/cluster-admin.kubeconfig` as determined by [`services.kubernetes.pki.etcClusterAdminKubeconfig`](options.html#opt-services.kubernetes.pki.etcClusterAdminKubeconfig). `export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig` will make kubectl use this kubeconfig to access and authenticate the cluster. The cluster-admin kubeconfig references an auto-generated keypair owned by root. Thus, only root on the kubernetes master may obtain cluster-admin rights by means of this file.

# Administration

This chapter describes various aspects of managing a running NixOS system, such as how to use the **systemd** service manager.

**Table of Contents**

[Service Management](#sec-systemctl)

[Rebooting and Shutting Down](#sec-rebooting)

[User Sessions](#sec-user-sessions)

[Control Groups](#sec-cgroups)

[Logging](#sec-logging)

[Necessary system state](#ch-system-state)

[Cleaning the Nix Store](#sec-nix-gc)

[Container Management](#ch-containers)

[Troubleshooting](#ch-troubleshooting)
