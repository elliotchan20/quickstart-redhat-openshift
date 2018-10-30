#!/bin/bash -xe

source ${P}

if [ -f /quickstart/pre-install.sh ]
then
  chmod +x /quickstart/pre-install.sh
  /quickstart/pre-install.sh
fi

qs_enable_epel &> /var/log/userdata.qs_enable_epel.log

case ${OCP_OR_ORIGIN} in
    origin)
        yum install -y centos-release-openshift-origin39
        ;;
    ocp)
        qs_retry_command 25 aws s3 cp ${QS_S3URI}scripts/redhat_ose-register-${OCP_VERSION}.sh ~/redhat_ose-register.sh
        chmod 755 ~/redhat_ose-register.sh
        qs_retry_command 20 ~/redhat_ose-register.sh ${RH_USER} ${RH_PASS} ${RH_POOLID}
        ;;
    *)
        echo "Unknown version ${OCP_OR_ORIGIN}"
        exit 1
        ;;
esac


# Using explicit path to ansible rpm. This resolves the issue of the version of Ansible changing in the repo (and Ansible 2.4 isn't supported
# by the openshift-ansible project)
# TODO: Add ansible as an RPM repo, then install the specific version. Make sure these values use parameters so users can define a custom repo 
# in the case this is used in a locked down enterprise environment.
qs_retry_command 10 yum -y install https://releases.ansible.com/ansible/rpm/release/epel-7-x86_64/ansible-2.6.5-1.el7.ans.noarch.rpm yum-versionlock
yum versionlock add ansible
yum repolist -v | grep OpenShift

qs_retry_command 10 pip install boto3 &> /var/log/userdata.boto3_install.log
mkdir -p /root/ose_scaling/aws_openshift_quickstart
mkdir -p /root/ose_scaling/bin
qs_retry_command 10 aws s3 cp ${QS_S3URI}scripts/scaling/aws_openshift_quickstart/__init__.py /root/ose_scaling/aws_openshift_quickstart/__init__.py
qs_retry_command 10 aws s3 cp ${QS_S3URI}scripts/scaling/aws_openshift_quickstart/logger.py /root/ose_scaling/aws_openshift_quickstart/logger.py
qs_retry_command 10 aws s3 cp ${QS_S3URI}scripts/scaling/aws_openshift_quickstart/scaler.py /root/ose_scaling/aws_openshift_quickstart/scaler.py
qs_retry_command 10 aws s3 cp ${QS_S3URI}scripts/scaling/aws_openshift_quickstart/utils.py /root/ose_scaling/aws_openshift_quickstart/utils.py
qs_retry_command 10 aws s3 cp ${QS_S3URI}scripts/scaling/bin/aws-ose-qs-scale /root/ose_scaling/bin/aws-ose-qs-scale
qs_retry_command 10 aws s3 cp ${QS_S3URI}scripts/scaling/setup.py /root/ose_scaling/setup.py


if [ "${OCP_VERSION}" == "3.9" ] ; then
    qs_retry_command 10 aws s3 cp ${QS_S3URI}scripts/predefined_openshift_vars.txt /tmp/openshift_inventory_predefined_vars
else
    qs_retry_command 10 aws s3 cp ${QS_S3URI}scripts/predefined_openshift_vars_3.10.txt /tmp/openshift_inventory_predefined_vars
fi
pip install /root/ose_scaling

qs_retry_command 10 cfn-init -v --stack ${AWS_STACKNAME} --resource AnsibleConfigServer --configsets cfg_node_keys --region ${AWS_REGION}

echo openshift_master_cluster_hostname=${INTERNAL_MASTER_ELBDNSNAME} >> /tmp/openshift_inventory_userdata_vars
echo openshift_master_cluster_public_hostname=${MASTER_ELBDNSNAME} >> /tmp/openshift_inventory_userdata_vars

if [ "$(echo ${MASTER_ELBDNSNAME} | grep -c '\.elb\.amazonaws\.com')" == "0" ] ; then
    echo openshift_master_default_subdomain=${MASTER_ELBDNSNAME} >> /tmp/openshift_inventory_userdata_vars
fi

if [ "${ENABLE_HAWKULAR}" == "True" ] ; then
    if [ "$(echo ${MASTER_ELBDNSNAME} | grep -c '\.elb\.amazonaws\.com')" == "0" ] ; then
        echo openshift_metrics_hawkular_hostname=metrics.${MASTER_ELBDNSNAME} >> /tmp/openshift_inventory_userdata_vars
    else
        echo openshift_metrics_hawkular_hostname=metrics.router.default.svc.cluster.local >> /tmp/openshift_inventory_userdata_vars
    fi
    echo openshift_metrics_install_metrics=true >> /tmp/openshift_inventory_userdata_vars
    echo openshift_metrics_start_cluster=true >> /tmp/openshift_inventory_userdata_vars
    echo openshift_metrics_cassandra_storage_type=dynamic >> /tmp/openshift_inventory_userdata_vars
fi

if [ "${ENABLE_AUTOMATIONBROKER}" == "Disabled" ] ; then
    echo ansible_service_broker_install=false >> /tmp/openshift_inventory_userdata_vars
fi

if [ "${OCP_VERSION}" != "3.9" ] ; then
    echo openshift_hosted_registry_storage_s3_bucket=${REGISTRY_BUCKET} >> /tmp/openshift_inventory_userdata_vars
    echo openshift_hosted_registry_storage_s3_region=${AWS_REGION} >> /tmp/openshift_inventory_userdata_vars
fi

echo openshift_master_api_port=443 >> /tmp/openshift_inventory_userdata_vars
echo openshift_master_console_port=443 >> /tmp/openshift_inventory_userdata_vars

qs_retry_command 10 yum -y install wget git net-tools bind-utils iptables-services bridge-utils bash-completion kexec-tools sos psacct
# Workaround this not-a-bug https://bugzilla.redhat.com/show_bug.cgi?id=1187057
pip uninstall -y urllib3
qs_retry_command 10 yum -y update
qs_retry_command 10 pip install urllib3
if [ "${OCP_VERSION}" == "3.9" ] ; then
    qs_retry_command 10 yum -y install atomic-openshift-utils
fi

case ${OCP_OR_ORIGIN} in
    origin)
        qs_retry_command 10 yum -y install atomic-openshift-utils origin-docker-excluder origin-excluder origin-clients
        origin-excluder unexclude
        echo 'openshift_deployment_type=origin' >> /tmp/openshift_inventory_userdata_vars
        echo 'oreg_url=docker.io/openshift/origin-${component}:${version}' >> /tmp/openshift_inventory_userdata_vars
        ;;
    ocp)
        qs_retry_command 10 yum -y install atomic-openshift-excluder atomic-openshift-docker-excluder atomic-openshift-clients
        atomic-openshift-excluder unexclude
        ;;
    *)
        echo "Unknown version ${OCP_OR_ORIGIN}"
        exit 1
        ;;
esac



cd /tmp
qs_retry_command 10 wget https://s3-us-west-1.amazonaws.com/amazon-ssm-us-west-1/latest/linux_amd64/amazon-ssm-agent.rpm
qs_retry_command 10 yum install -y ./amazon-ssm-agent.rpm
systemctl start amazon-ssm-agent
systemctl enable amazon-ssm-agent
rm ./amazon-ssm-agent.rpm
cd -

if [ "${GET_ANSIBLE_FROM_GIT}" == "True" ]; then
  rm -rf /usr/share/ansible
  mkdir -p /usr/share/ansible
  # TODO: need to account for locked down enterprise environment
  git clone --single-branch -b release-${OCP_VERSION} https://github.com/openshift/openshift-ansible.git /usr/share/ansible/openshift-ansible
else
  qs_retry_command 10 yum -y install openshift-ansible
fi



qs_retry_command 10 aws s3 cp ${QS_S3URI}scripts/scaleup_wrapper.yml  /usr/share/ansible/openshift-ansible/
qs_retry_command 10 aws s3 cp ${QS_S3URI}scripts/bootstrap_wrapper.yml /usr/share/ansible/openshift-ansible/
qs_retry_command 10 aws s3 cp ${QS_S3URI}scripts/playbooks/post_scaledown.yml /usr/share/ansible/openshift-ansible/
qs_retry_command 10 aws s3 cp ${QS_S3URI}scripts/playbooks/post_scaleup.yml /usr/share/ansible/openshift-ansible/
qs_retry_command 10 aws s3 cp ${QS_S3URI}scripts/playbooks/pre_scaleup.yml /usr/share/ansible/openshift-ansible/
qs_retry_command 10 aws s3 cp ${QS_S3URI}scripts/playbooks/pre_scaledown.yml /usr/share/ansible/openshift-ansible/
qs_retry_command 10 aws s3 cp ${QS_S3URI}scripts/playbooks/remove_node_from_etcd_cluster.yml /usr/share/ansible/openshift-ansible/

ASG_COUNT=3
if [ "${ENABLE_GLUSTERFS}" == "Enabled" ] && [ "${OCP_VERSION}" != "3.9" ] ; then
    ASG_COUNT=4
fi
while [ $(aws cloudformation describe-stack-events --stack-name ${AWS_STACKNAME} --region ${AWS_REGION} --query 'StackEvents[?ResourceStatus == `CREATE_COMPLETE` && ResourceType == `AWS::AutoScaling::AutoScalingGroup`].LogicalResourceId' --output json | grep -c 'OpenShift') -lt ${ASG_COUNT} ] ; do
    echo "Waiting for ASG's to complete provisioning..."
    sleep 120
done

export OPENSHIFTMASTERASG=$(aws cloudformation describe-stack-resources --stack-name ${AWS_STACKNAME} --region ${AWS_REGION} --query 'StackResources[? ResourceStatus == `CREATE_COMPLETE` && LogicalResourceId == `OpenShiftMasterASG`].PhysicalResourceId' --output text)

qs_retry_command 10 aws autoscaling suspend-processes --auto-scaling-group-name ${OPENSHIFTMASTERASG} --scaling-processes HealthCheck --region ${AWS_REGION}
qs_retry_command 10 aws autoscaling attach-load-balancer-target-groups --auto-scaling-group-name ${OPENSHIFTMASTERASG} --target-group-arns ${OPENSHIFTMASTERINTERNALTGARN} --region ${AWS_REGION}

/bin/aws-ose-qs-scale --generate-initial-inventory --ocp-version ${OCP_VERSION} --write-hosts-to-tempfiles --debug
cat /tmp/openshift_ansible_inventory* >> /tmp/openshift_inventory_userdata_vars || true
# Ansible configuration
# Setting host_key_checking to false is NOT best practices, but a stop gap here. Assuming you trust your DNS generating the known_hosts file before hand would be ideal.
sed -i 's/#host_key_checking = False/host_key_checking = False/g' /etc/ansible/ansible.cfg
sed -i 's/#pipelining = False/pipelining = True/g' /etc/ansible/ansible.cfg
sed -i 's/#log_path/log_path/g' /etc/ansible/ansible.cfg
sed -i 's/#stdout_callback.*/stdout_callback = json/g' /etc/ansible/ansible.cfg
sed -i 's/#deprecation_warnings = True/deprecation_warnings = False/g' /etc/ansible/ansible.cfg

qs_retry_command 50 ansible -m ping all

ansible-playbook /usr/share/ansible/openshift-ansible/bootstrap_wrapper.yml > /var/log/bootstrap.log

ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/prerequisites.yml >> /var/log/bootstrap.log
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml >> /var/log/bootstrap.log

# Alternative authentication will be handled in pre-install hooks.
# Check if htpasswd is defined in ansible vars file, if it is, then it's using local auth and the htpasswd needs to be
# generated.
if [ ! -z "$(grep htpasswd /etc/ansible/hosts)" ]
then
    ansible masters -a "htpasswd -b /etc/origin/master/htpasswd admin ${OCP_PASS}"
fi

aws autoscaling resume-processes --auto-scaling-group-name ${OPENSHIFTMASTERASG} --scaling-processes HealthCheck --region ${AWS_REGION}
AWSSB_SETUP_HOST=$(head -n 1 /tmp/openshift_initial_masters)
mkdir -p ~/.kube/
scp $AWSSB_SETUP_HOST:~/.kube/config ~/.kube/config

if [ "${ENABLE_AWSSB}" == "Enabled" ]; then
    mkdir -p ~/aws_broker_install
    cd ~/aws_broker_install
    qs_retry_command 10 wget https://raw.githubusercontent.com/awslabs/aws-servicebroker/release-${SB_VERSION}/packaging/openshift/deploy.sh
    qs_retry_command 10 wget https://raw.githubusercontent.com/awslabs/aws-servicebroker/release-${SB_VERSION}/packaging/openshift/aws-servicebroker.yaml
    qs_retry_command 10 wget https://raw.githubusercontent.com/awslabs/aws-servicebroker/release-${SB_VERSION}/packaging/openshift/parameters.env
    chmod +x deploy.sh
    sed -i "s/TABLENAME=awssb/TABLENAME=${SB_TABLE}/" parameters.env
    sed -i "s/TARGETACCOUNTID=/TARGETACCOUNTID=${SB_ACCOUNTID}/" parameters.env
    sed -i "s/TARGETROLENAME=/TARGETROLENAME=${SB_ROLE}/" parameters.env
    sed -i "s/VPCID=/VPCID=${VPCID}/" parameters.env
    sed -i "s/^REGION=us-east-1$/REGION=${AWS_REGION}/" parameters.env
    export KUBECONFIG=/root/.kube/config
    ./deploy.sh
    cd ../
    rm -rf ./aws_broker_install/
fi

rm -rf /tmp/openshift_initial_*

if [ -f /quickstart/post-install.sh ]
then
  chmod +x /quickstart/post-install.sh
  # OR with true to ignore errors - this prevents the post-install hooks from causing the entire deployment to fail.
  /quickstart/post-install.sh || true
fi