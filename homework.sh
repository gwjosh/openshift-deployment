#!/bin/bash

#Openshift Advanced Deployment Homework
#Plano TX Class - 10/22/2018
#Instructor: Judd Maltin
#Student: Josh Guilbert
#Openshift 3.11.16
#Run: /root/openshift-deployment/homework.sh
#
## NOTE! ## You need to provide a Red Hat registry username and password when kicking off the script ##

#Capture API Username
echo "====== Please enter your registry service account name ======"
echo "note: If you do not have one you can generate one at https://access.redhat.com/terms-based-registry/"
read API_USER

#Capture API Key
echo "====== Please enter your registry service key ======"
echo "note: If you do not have one you can generate one at https://access.redhat.com/terms-based-registry/"
read API_KEY

#Prepare scripts
chmod 755 /root/openshift-deployment/* -R

echo "Preparing hosts for installation..."
#Add GUID to localhost
export GUID=`hostname | cut -d"." -f2`; echo "export GUID=$GUID" >> $HOME/.bashrc
#Copy Ansible hosts file
cp /root/openshift-deployment/hosts /etc/ansible/hosts
#Update Anible hosts file with GUID and oreg info
sed -i "s/GUID/$GUID/g" /etc/ansible/hosts
sed -i "s/API_USER/$API_USER/g" /etc/ansible/hosts
sed -i "s/API_KEY/$API_KEY/g" /etc/ansible/hosts

#Run Sanity Checks
echo "Running sanity checks before installation..."
ansible-playbook -i /etc/ansible/hosts /root/openshift-deployment/files/ansible/sanityChecks.yml

#Run Openshift Prereqs
echo "Running Openshift installer prerequisite checks..."
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/prerequisites.yml

#Run Openshift Installation
echo "Running Openshift installation..."
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml

#Copy kube config from master to bastion
echo "Copying authentication config from Master"
ansible masters[0] -b -m fetch -a "src=/root/.kube/config dest=/root/.kube/config flat=yes"

#Prepare NFS PVs
echo "Preparing NFS PVs..."
ansible-playbook -i /etc/ansible/hosts /root/openshift-deployment/files/ansible/prepareNFS.yml

#Set default project template
##Limit per node 2CPU and 8GB RAM
oc create -f /root/openshift-deployment/files/template.yaml -n default

#Remove self-provisioning from non-admins
oc patch clusterrolebinding.rbac self-provisioners -p '{"subjects": null}'
oc patch clusterrolebinding.rbac self-provisioners -p '{ "metadata": { "annotations": { "rbac.authorization.kubernetes.io/autoupdate": "false" } } }'

###Set up multi tenancy###
#tag nodes client=alpha, client=beta, client=common, env=infra
oc label node infranode1.$GUID.internal env=infra
oc label node infranode2.$GUID.internal env=infra
oc label node node1.$GUID.internal client=alpha
oc label node node2.$GUID.internal client=beta
oc label node node3.$GUID.internal client=common
oc label node node4.$GUID.internal client=common

#Set default node selector for new projects to client=common
ansible-playbook -i /etc/ansible/hosts /root/openshift-deployment/files/ansible/updateMasters.yml

#Copy updated htpasswd file to masters
ansible masters -m copy -a "src=/root/openshift-deployment/files/htpasswd dest=/etc/origin/master/htpasswd"

#create brian
oc create user brian
oc create identity htpasswd_auth:brian
oc create useridentitymapping htpasswd_auth:brian brian
oc label user/brian client=beta

#create betty
oc create user betty
oc create identity htpasswd_auth:betty
oc create useridentitymapping htpasswd_auth:betty betty
oc label user/betty client=beta

#create amy
oc create user amy
oc create identity htpasswd_auth:amy
oc create useridentitymapping htpasswd_auth:amy amy
oc label user/amy client=alpha

#create andrew
oc create user andrew
oc create identity htpasswd_auth:andrew
oc create useridentitymapping htpasswd_auth:andrew andrew
oc label user/andrew client=alpha

#create clusteradmin
oc create user clusteradmin
oc create identity htpasswd_auth:clusteradmin
oc create useridentitymapping htpasswd_auth:clusteradmin clusteradmin
oc create clusterrolebinding clusteradmins --clusterrole=cluster-admin --user=clusteradmin

#create alpha corp resources
oc adm groups new alpha_group amy andrew
oc new-project alpha-project01
oc adm policy add-role-to-group admin alpha_group -n alpha-project01
oc patch namespace alpha-project01 -p '{"metadata":{"annotations":{"openshift.io/node-selector":"client=alpha"}}}'

#create beta corp resources
oc adm groups new beta_group brian betty
oc new-project beta-project01
oc adm policy add-role-to-group admin beta_group -n beta-project01
oc patch namespace beta-project01 -p '{"metadata":{"annotations":{"openshift.io/node-selector":"client=beta"}}}'

oc new-project nodejs-demo01
oc new-app nodejs-mongo-persistent -n nodejs-demo01

##Create CICD Environment
#Create CICD Projects
oc new-project cicd-dev
oc new-project tasks-build
oc new-project tasks-dev
oc new-project tasks-test
oc new-project tasks-prod

#Create Jenkins app 
oc new-app -e OPENSHIFT_ENABLE_OAUTH=true jenkins-persistent -n cicd-dev

#Create Jenkins pipeline permissions
oc policy add-role-to-user edit system:serviceaccount:cicd-dev:jenkins -n cicd-dev
oc policy add-role-to-user edit system:serviceaccount:cicd-dev:jenkins -n tasks-build
oc policy add-role-to-user edit system:serviceaccount:cicd-dev:jenkins -n tasks-dev
oc policy add-role-to-user edit system:serviceaccount:cicd-dev:jenkins -n tasks-test
oc policy add-role-to-user edit system:serviceaccount:cicd-dev:jenkins -n tasks-prod

oc policy add-role-to-user edit system:serviceaccount:admin -n cicd-dev
oc policy add-role-to-user edit system:serviceaccount:admin -n tasks-build
oc policy add-role-to-user edit system:serviceaccount:admin -n tasks-dev
oc policy add-role-to-user edit system:serviceaccount:admin -n tasks-test
oc policy add-role-to-user edit system:serviceaccount:admin -n tasks-prod

sleep 30

oc policy add-role-to-group system:image-puller system:serviceaccount:cicd-dev:jenkins -n cicd-dev
oc policy add-role-to-group system:image-puller system:serviceaccounts:admin -n cicd-dev
oc policy add-role-to-group system:image-puller system:serviceaccount:cicd-dev:jenkins -n tasks-build
oc policy add-role-to-group system:image-puller system:serviceaccounts:admin -n tasks-build

#Create Openshift Tasks application for pipeline
oc new-app --template=eap71-basic-s2i --param APPLICATION_NAME=openshift-tasks --param SOURCE_REPOSITORY_URL=https://github.com/OpenShiftDemos/openshift-tasks.git --param SOURCE_REPOSITORY_REF=master --param CONTEXT_DIR=/ -n cicd-dev
oc new-app --template=eap71-basic-s2i --param APPLICATION_NAME=openshift-tasks --param SOURCE_REPOSITORY_URL=https://github.com/OpenShiftDemos/openshift-tasks.git --param SOURCE_REPOSITORY_REF=master --param CONTEXT_DIR=/ -n tasks-build
oc new-app --template=eap71-basic-s2i --param APPLICATION_NAME=openshift-tasks --param SOURCE_REPOSITORY_URL=https://github.com/OpenShiftDemos/openshift-tasks.git --param SOURCE_REPOSITORY_REF=master --param CONTEXT_DIR=/ -n tasks-dev
oc new-app --template=eap71-basic-s2i --param APPLICATION_NAME=openshift-tasks --param SOURCE_REPOSITORY_URL=https://github.com/OpenShiftDemos/openshift-tasks.git --param SOURCE_REPOSITORY_REF=master --param CONTEXT_DIR=/ -n tasks-test
oc new-app --template=eap71-basic-s2i --param APPLICATION_NAME=openshift-tasks --param SOURCE_REPOSITORY_URL=https://github.com/OpenShiftDemos/openshift-tasks.git --param SOURCE_REPOSITORY_REF=master --param CONTEXT_DIR=/ -n tasks-prod

oc create -f /root/openshift-deployment/files/openshift-tasks-pipeline.yaml -n cicd-dev

sleep 600

#Start build
oc start-build openshift-tasks-pipeline -n cicd-dev

#Create HPA for tasks-prod
oc create -f /root/openshift-deployment/files/tasks-prod-hpa.yaml -n tasks-prod

#end