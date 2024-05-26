# Ansible RKE2 HA Cluster with Kube-VIP and MetalLB


This playbook will build an HA Kubernetes cluster with `rke2`, `kube-vip` and MetalLB via `ansible`.


If you want more context on how this works, see:

📄 [Documentation](https://technotim.live/posts/k3s-etcd-ansible/) (including example commands)


## 📖 k3s Ansible Playbook

Build a Kubernetes cluster using Ansible with k3s. The goal is easily install a HA Kubernetes cluster on machines running:

- [x] Debian (tested on version 11)
- [x] Ubuntu (tested on version 22.04)

on processor architecture:

- [X] x64
- [X] arm64
- [X] armhf

## ✅ System requirements

- Control Node (the machine you are running `ansible` commands) must have Ansible 2.11+ 

- You will also need to install collections that this playbook uses by running `ansible-galaxy collection install -r ./collections/requirements.yml` (important❗)

- [`netaddr` package](https://pypi.org/project/netaddr/) must be available to Ansible. If you have installed Ansible via apt, this is already taken care of. If you have installed Ansible via `pip`, make sure to install `netaddr` into the respective virtual environment.

- `server` and `agent` nodes should have passwordless SSH access, if not you can supply arguments to provide credentials `--ask-pass --ask-become-pass` to each command.

## 🚀 Getting Started

### 🍴 Preparation

First create a new directory based on the `sample` directory within the `inventory` directory:

```bash
cp -R inventory/sample inventory/my-cluster
```

Second, edit `inventory/my-cluster/hosts.ini` to match the system information gathered above

For example:

```ini
[master]
192.168.10.31
192.168.10.32
192.168.10.33


[k3s_cluster:children]
master

```

If multiple hosts are in the master group, the playbook will automatically set up rke2 in [HA mode with etcd]

Finally, copy `ansible.example.cfg` to `ansible.cfg` and adapt the inventory path to match the files that you just created.

This requires at least k3s version `1.19.1` however the version is configurable by using the `k3s_version` variable.

If needed, you can also edit `inventory/my-cluster/group_vars/all.yml` to match your environment.

### ☸️ Create Cluster

Start provisioning of the cluster using the following command:

```bash
ansible-playbook site.yml -i inventory/my-cluster/hosts.ini
```

After deployment control plane will be accessible via virtual ip-address which is defined in inventory/group_vars/all.yml as `apiserver_endpoint`

### 🔥 Remove k3s cluster

```bash
ansible-playbook reset.yml -i inventory/my-cluster/hosts.ini
```

>You should also reboot these nodes due to the VIP not being destroyed

## ⚙️ Kube Config

To copy your `kube config` locally so that you can access your **Kubernetes** cluster run:

```bash
scp ubuntu@master_ip:/etc/rancher/rke2/config.yaml ~/.kube/config
```
If you get file Permission denied, go into the node and temporarly run:
```bash
sudo chmod 777 /etc/rancher/rke2/config.yaml
```
Then copy with the scp command and reset the permissions back to:
```bash
sudo chmod 600 /etc/rancher/rke2/config.yaml
```

You'll then want to modify the config to point to master IP by running:
```bash
sudo nano ~/.kube/config
```
Then change `server: https://127.0.0.1:6443` to match your master IP: `server: https://192.168.10.111:6443`

### 🔨 Testing your cluster

See the commands [here](https://technotim.live/posts/k3s-etcd-ansible/#testing-your-cluster).

### Troubleshooting

Be sure to see [this post](https://github.com/techno-tim/k3s-ansible/discussions/20) on how to troubleshoot common problems

### Testing the playbook using molecule

This playbook includes a [molecule](https://molecule.rtfd.io/)-based test setup.
It is run automatically in CI, but you can also run the tests locally.
This might be helpful for quick feedback in a few cases.
You can find more information about it [here](molecule/README.md).

### Pre-commit Hooks

This repo uses `pre-commit` and `pre-commit-hooks` to lint and fix common style and syntax errors.  Be sure to install python packages and then run `pre-commit install`.  For more information, see [pre-commit](https://pre-commit.com/)

## 🌌 Ansible Galaxy

This collection can now be used in larger ansible projects.

Instructions:

- create or modify a file `collections/requirements.yml` in your project

```yml
collections:
  - name: ansible.utils
  - name: community.general
  - name: ansible.posix
  - name: kubernetes.core
  - name: https://github.com/imaginestack/collections/rke2-ansible
    type: git
    version: master
```

- install via `ansible-galaxy collection install -r ./collections/requirements.yml`
- every role is now available via the prefix `cto.rke2_ansible.` e.g. 

## Thanks 🤝

