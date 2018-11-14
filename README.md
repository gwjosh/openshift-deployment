Introduction:

This guide will walk you through the steps to deploy your own OpenShift POC environment. The deployment can be
initiated with a single command, and once initiated will take 45-60 minutes to complete. At the end of the
deployment there will be a functional test environment with internal and client environments as well as test
applications deployed.


Requirements:

• A POC environment with 3 master nodes, 2 infra nodes, 1 support node, 1 bastion node and 4 compute
nodes.

• Ansible installed on all nodes

• Docker installed on all nodes

• Access to a Red Hat Registry Service Account (you will be prompted for credentials)


Deploying Environment:

Log in to your bastion host, sign in as root and clone the repository with the following commands:

sudo -i

tmux

git clone https://github.com/gwjosh/openshift-deployment.git


Run the following command to initiate the installation:

/root/openshift-deployment/homework.sh


Upon kicking off the script, you will be prompted for a registry service API user and Key. If you do not have one, you
can create one at the following URL: https://access.redhat.com/terms-based-registry/
