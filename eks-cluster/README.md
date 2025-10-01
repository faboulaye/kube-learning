# Kubernetes - Amazon EKS

This guide provides step-by-step instructions to set up an Amazon EKS cluster with the AWS Load Balancer Controller (formerly known as the ALB Ingress Controller).
The controller enables you to manage AWS Application Load Balancers (ALBs) for your Kubernetes applications.

## Prerequisites

* [eksctl cli installation](https://docs.aws.amazon.com/eks/latest/eksctl/tutorial.html)
* Set AWS_PROFILE in your current terminal in order to deploy the cluster in the right AWS account

## Provision EKS Cluster

```bash
eksctl create cluster -f eks-config.yaml
```

Verify the node distribution across AZs:

```bash
kubectl get nodes --show-labels | grep topology.kubernetes.io/zone
```

## Install AWS Load Balancer Controller

### Create IAM Policy

Create the policy in your AWS account:

```bash
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json
```

The created policy will be used to grant your controller the ability to call ELB, EC2, and IAM APIs. You can inspect the JSON file for exact permissions.

### Create an IAM-Backed Kubernetes Service Account

We now create a Kubernetes ServiceAccount that is linked to the IAM policy created above. This is achieved using eksctl, which automatically sets up the necessary IAM Role and CloudFormation resources under the hood.

```bash
eksctl create iamserviceaccount \
  --cluster=fab-eks-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --region eu-central-1 \
  --approve
```

This command does the following:

Creates an IAM Role with the required policy attached (visible in AWS CloudFormation).
Annotates a Kubernetes ServiceAccount with this role.
Binds the ServiceAccount to the controller pods that we will deploy in the next step.
To verify:

```bash
kubectl get sa -n kube-system aws-load-balancer-controller -o yaml
```

Example output:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::....:role/eksctl-fab-eks-cluster-addon-iamserviceacco-Role1-*******
```

This annotation allows the controller pod to assume the IAM role and make API calls securely from within the cluster.

### Install the AWS Load Balancer Controller Using Helm

Note: The AWS Load Balancer Controller was previously known as the ALB Ingress Controller. While the functionality has expanded beyond ALBs, many community articles and annotations still use the older term. The official and recommended name is now AWS Load Balancer Controller.

Add the AWS-maintained Helm chart repository:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
```

Install the controller:

```bash
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=fab-eks-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --version 1.13.0
```

The `--set serviceAccount.create=false` flag ensures that Helm does not attempt to create a new service account. We are using the one we created and annotated earlier using eksctl.

`helm list` alone won’t show the AWS Load Balancer Controller, as it’s installed in the kube-system namespace. Use `helm list -n kube-system` or `helm list -A` to view it.

Optional: List available versions of the chart

```bash
helm search repo eks/aws-load-balancer-controller --versions
```

Verify that the controller is installed:

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
```

Expected output:

```text
NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
aws-load-balancer-controller   2/2     2            2           84s
```

Inspect the pods to verify the correct service account is mounted:

```bash
kubectl describe pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

Look for this line under the pod description:

```text
Service Account: aws-load-balancer-controller
```

This confirms the pods are using the IAM-bound service account, enabling them to create ALBs, target groups, and associated rules when Ingress resources are created.

Reference Links

* **AWS Documentation**: [Installing AWS Load Balancer Controller](https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html)
* **GitHub Repository**: [AWS Load Balancer Controller GitHub](https://github.com/kubernetes-sigs/aws-load-balancer-controller)