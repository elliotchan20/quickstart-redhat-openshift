# quickstart-redhat-openshift
## Red Hat OpenShift Container Platform on the AWS Cloud


This Quick Start deploys Red Hat OpenShift Container Platform on the AWS Cloud in a highly available configuration.

Red Hat OpenShift Container Platform is a platform as a service (PaaS) solution that is based on Docker-formatted Linux containers, Google Kubernetes orchestration, and the Red Hat Enterprise Linux (RHEL) operating system.

The Quick Start includes AWS CloudFormation templates that build the AWS infrastructure using AWS best practices, and then pass that environment to Ansible playbooks to build out the OpenShift environment. The deployment provisions OpenShift master instances, etcd instances, and node instances in a virtual private cloud (VPC) across three Availability Zones.

The Quick Start offers two deployment options:

- Deploying OpenShift Container Platform into a new VPC
- Deploying OpenShift Container Platform into an existing VPC

You can also use the AWS CloudFormation templates as a starting point for your own implementation.

![Quick Start architecture for OpenShift Container Platform on AWS](https://d0.awsstatic.com/partner-network/QuickStart/datasheets/redhat-openshift-on-aws-architecture.png)

For architectural details, best practices, step-by-step instructions, and customization options, see the [deployment guide](https://fwd.aws/dwpPW).

To post feedback, submit feature ideas, or report bugs, use the **Issues** section of this GitHub repo.
If you'd like to submit code for this Quick Start, please review the [AWS Quick Start Contributor's Kit](https://aws-quickstart.github.io/).

## Usage
Using this Quick Start requires credentials for a Red Hat account that includes a subscription for Red Hat OpenShift Enterprise (note that that may require a non-personal email address registration).

The default provisioning in this Quick Start will launch 10 m4.xlarge EC2 instances (3 masters, 3 workers, 3 etcd nodes and 1 ansible configuration server).

If you have a Red Hat account and do not have easy access to the Red Hat subscription manager you can launch an RHEL instance in the AWS to determine if your account includes the necessary subscription and associated Pool ID.

Launch an RHEL instance and do the following on it to access your account

    $ sudo subscription-manager register

This will prompt you for your account name and password.

Now get a list of what is available to you with this

    $ sudo subscription-manager list --available --all

The output may include a number of sections.
If the output includes something like ```Red Hat OpenShift Enterprise``` then look for something after it called ```Pool ID: xxx```.
If you see that value keep it for use with the CloudFormation stack that you will be launching.

You also need to confirm that you have ```Entitlements Available```.
If that value is zero or does not appear at all that you may not be able to use the Quick Start.

Once you are finished with determining what you need you can unregister the host and then terminate the instance.
Unregister the instance with this

    $ sudo subscription-manager unregister
**Important**
This Quick Start will allocate from your subscription entitlements.
Before you use this ensure that you will not be taking them away from a pool that needs to be available for your company usage.

It is a good idea to go to your Red Hat account portal and ensure that your hosts and subscription entitlements have been removed after you are finished with this exercise and your instances have been terminated.

If you do not already have access to a Red Hat account then go to the following to register and get access (note that that may require a non-personal email address for registration)

[https://www.redhat.com/wapps/eval/index.html?evaluation_id=1026](https://www.redhat.com/wapps/eval/index.html?evaluation_id=1026)

## Origin Support
The CFN templates support choosing Origin as the platform instead of OCP. This will use the CentOS7 as the base.
A few things to be aware of:
* The templates still require the RedHat Username, Password and PoolID to have entries. It is recommended to use parameter store for these instead of CFN parameters. You can use encrypted values to protect passwords and pool IDs.
* I created these for us in ca-central-1 region, so one would need to add AMIs for CentOS7 in other regions if they are needed
* ca-central-1 only has two AZ's so I've modified the templates to use only two AZ's
* I extensively use the pre-install and post-install hooks. I use the pre-install hooks to set up OpenID Connect authentication and the post-install hooks to create some daemonsets for logging and metrics to be sent out of the cluster.
