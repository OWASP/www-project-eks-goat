---

layout: col-sidebar
title: OWASP EKS Goat
tags: example-tag
level: 2
type: code
pitch: A very brief, one-line description of your project

---

<p align="center">
  <img src="../www-project-eks-goat/external-images/logo-1.png" alt="Logo" width="500"/>
</p>

OWASP EKS Goat is a hands-on AWS EKS security lab that teaches real-world attack and defense techniques for AWS managed Kubernetes clusters.

The lab simulates realistic attack paths and defense mechanisms including misconfigured IAM roles, IRSA abuse, ECR image backdooring, RBAC privilege escalation, and pod-to-node breakout. Participants walk through both the offensive and defensive scenarios.

**Attack Scenarios (includes CVE-2024-23897):**

* Exploit Jenkins CVE to leak IAM credentials via IMDSv2.
* Backdoor ECR images using leaked credentials.
* Deploy compromised image into the EKS cluster.
* Escalate privileges and breakout from pod to EC2 node.
* Abuse IAM roles to exfiltrate data from S3.

**Defense Scenarios:**

* Audit cluster state using Kubescape, Kubebench, and Hadolint.
* Implement Pod Security Context and enforce policies with Kyverno (CEL).
* Detect runtime behavior with eBPF-based Tetragon.
* Scan and lock down ECR repositories.
* Integrate AWS GuardDuty for monitoring.



## Lab Documentation

* Full walkthrough: [https://eksgoat.kubernetesvillage.com](https://eksgoat.kubernetesvillage.com)
 

* Alternate Link
  * In case of accessibility issues, use:  
[https://ekssecurity.netlify.app/](https://ekssecurity.netlify.app)




## 🏆 Scenarios Covered in Documentation

#### 📦 Container & Image Security

* Docker Image and Layer Analysis
* Container Secrets Misuse
* Static Scanning with Hadolint, Dockle
* Docker Bench Security (CIS benchmark)

#### 🔐 AWS ECR Exploitation

* ECR Image Scanning
* Immutable Tag Enforcement
* Credential Abuse for Private ECR Enumeration
* Backdooring Docker Images in ECR

#### ☁️ AWS EKS Exploitation

* Deploying Vulnerable EKS Infrastructure
* Metadata Service Abuse (IMDSv2) to Steal Credentials
* Web App Exploitation to AWS IAM Compromise
* ECR to EKS Cluster Compromise
* Pod-to-Node Breakout in EKS
* Privilege Escalation to S3 Access and Data Exfiltration
* EC2 Instance Cleanup Post Exploit

#### 🔍 Scanning & Auditing

* Kubescape for Compliance Assessment
* Kubebench for Node Security Benchmarking
* Hadolint for Dockerfile Linting

#### 🛡️ Runtime Defense & Hardening

* Pod Security Context Enforcement
* Kyverno (CEL) Policy Enforcement in EKS
* Real-time Runtime Detection via eBPF Tetragon
* AWS GuardDuty Alerts for EKS Threats

#### ⚙️ Environment Lifecycle

* Infra Spin-up for Vulnerable EKS Cluster
* Complete Infra Teardown Lab




### RoadMap

* Current State:
    * Created and open-sourced hands-on labs for AWS EKS misconfigurations and vulnerabilities.
    * Developed detailed documentation to accompany lab walkthrough and theoretical concepts.
    * Implementation of initial attack &  defense scenarios with IAM and Kubernetes RBAC.
    * Continue using mdbook for documentation.

* Short-Term Goals:
    * Transition existing infrastructure deployment scripts to Terraform.
    * Update documentation to include images and step-by-step instructions for each lab.
    * Expand the defensive scenarios, adding advance topics such as network policies.
    * Add quizes for interaction.

* Long-Term Objectives:
    * Establish a continuous integration/continuous deployment (CI/CD) pipeline to automate the deployment and teardown of lab environments.
    * Develop a community forum to facilitate participant interaction, knowledge sharing, and collaborative learning.
    * Integrate threat modeling lab for AWS EKS infrastructure using EKS Goat to detect and mitigate proactively.
 
