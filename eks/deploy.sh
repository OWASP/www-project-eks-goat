#!/bin/bash

echo "To deploy the infrastructure, please use the following command: bash deploy.sh --region <region>"
echo "If no region is selected, the script will default to us-west-2."
echo ""
echo "Note: Only the regions us-east-1 and us-west-2 are supported."
echo ""

# Disable AWS CLI pager for non-interactive mode
export AWS_PAGER=""

# Prompt the user to confirm if they want to continue
read -p "Do you want to continue with the deployment? (Y/N): " confirm
case $confirm in
    [Yy]* ) 
        echo "Continuing with the deployment...";;
    [Nn]* ) 
        echo "Deployment aborted."
        exit 0;;
    * ) 
        echo "Invalid input. Please enter Y or N."
        exit 1;;
esac

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo "Error: AWS CLI is not configured. Please configure the AWS CLI with valid credentials and try again."
    echo "Note: The current regions supported are us-east-1 and us-west-2."
    exit 1
else
    echo "AWS CLI is configured. Please ensure you have admin privileges to deploy the infrastructure."
    echo "Note: The current regions supported are us-east-1 and us-west-2."
fi


# Default region & account ID
export DEFAULT_REGION="us-west-2"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

# Generate a 4-byte random hex string
export REPO_SUFFIX=$(openssl rand -hex 4)

# Define the repository name with the random suffix
export REPO_NAME="peachycloudsecurity-${REPO_SUFFIX}"

export EKS_CLUSTER_NAME="peachycloudsecurity-${REPO_SUFFIX}"

export ROLE_NAME="peachycloudsecurity-${REPO_SUFFIX}"
export EKS_ROLE_NAME="peachycloudsecurity-eks-${REPO_SUFFIX}"
export INSTANCE_PROFILE_NAME="peachycloudsecurity-ip-${REPO_SUFFIX}"
export S3_POLICY_NAME="peachycloudsecurity-listSpecificS3Buckets-${REPO_SUFFIX}"

# Check if a region argument is provided, otherwise use the default region
if [ -z "$1" ]; then
  echo "Warning: No region specified. Defaulting to ${DEFAULT_REGION}."
  export REGION=$DEFAULT_REGION
else
  if [[ "$1" == "--region" && -n "$2" ]]; then
    export REGION=$2
  else
    echo "Warning: Unrecognized option or missing region. Please pass the region with --region."
    echo "Usage: $0 --region <region>"
    exit 1
  fi
fi

# Check CPU architecture
ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" ]]; then
  echo "Error: This script only supports Intel/AMD64 architecture. Detected architecture: $ARCH."
  exit 1
fi

# Function to check if a binary is installed
check_binary() {
    if ! command -v $1 &> /dev/null; then
        echo "$1 could not be found. Check installation..."
        exit 1
    fi
}

# Check if required binaries are installed
echo "Checking and validating aws cli."
check_binary aws

echo "Checking and validating eksctl binary."
check_binary eksctl

echo "Checking and validating kubectl binary."
check_binary kubectl

echo "Starting Deployment of Lab:"

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "Terraform could not be found. Check installation..."
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq could not be found. Check installation..."
    exit 1
fi

echo "Checking if default vpc & security group present in the selected region..."

# Check if the default VPC exists
export DEFAULT_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --region ${REGION} --output text)

if [ -z "$DEFAULT_VPC_ID" ] || [ "$DEFAULT_VPC_ID" == "None" ]; then
    echo "Default VPC does not exist. Creating default VPC..."
    DEFAULT_VPC_ID=$(aws ec2 create-default-vpc --query "Vpc.VpcId" --region ${REGION} --output text)
    echo "Created default VPC with ID $DEFAULT_VPC_ID"
else
    echo "Default VPC exists with ID $DEFAULT_VPC_ID"
fi

# Check if the default security group exists in the default VPC
echo "Checking default security group in region: ${REGION}..."
export DEFAULT_SG_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" "Name=group-name,Values=default" --region ${REGION} --query "SecurityGroups[0].GroupId" --output text)

if [ -z "$DEFAULT_SG_ID" ] || [ "$DEFAULT_SG_ID" == "None" ]; then
    echo "Default security group does not exist. Creating a new security group with default-like settings..."
    # Create a new security group
    export SG_ID=$(aws ec2 create-security-group \
        --group-name default-like-sg \
        --description "Replacement for default security group" \
        --vpc-id $DEFAULT_VPC_ID \
        --region ${REGION} \
        --query "GroupId" --output text)
    echo "Created default security group with ID $SG_ID"
    # Authorize inbound rules to allow all traffic from the same security group
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol -1 \
        --port -1 \
        --source-group $SG_ID \
        --region ${REGION}
    echo "Set inbound rules to allow all traffic from the same security group."
else
    echo "Default security group exists with ID $DEFAULT_SG_ID"
fi


# Create the ECR repository
aws ecr create-repository \
    --repository-name ${REPO_NAME} \
    --image-tag-mutability MUTABLE \
    --image-scanning-configuration scanOnPush=false \
    --region ${REGION}

# Get the repository URL
export REPO_URL=$(aws ecr describe-repositories \
    --repository-names ${REPO_NAME} \
    --query 'repositories[0].repositoryUri' \
    --output text \
    --region ${REGION})

# Authenticate Docker to the ECR repository
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin $REPO_URL

# Build the Docker image
export DOCKER_IMAGE_NAME="peachycloudsecurity"
docker build -t ${DOCKER_IMAGE_NAME} .

# Tag the Docker image
docker tag ${DOCKER_IMAGE_NAME}:latest ${REPO_URL}:latest

# Push the Docker image
docker push ${REPO_URL}:latest

# EKS Deployment

# Create the EKS cluster
echo "Creating EKS cluster with name ${EKS_CLUSTER_NAME} in region ${REGION}..."

cat <<EOF > peachycloudsecurity-eks-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListAllMyBuckets"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": "arn:aws:s3:::peachycloudsecurity-*",
            "Condition": {
                "StringEquals": {
                    "aws:RequestedRegion": "${REGION}"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": "arn:aws:s3:::peachycloudsecurity-*/*",
            "Condition": {
                "StringEquals": {
                    "aws:RequestedRegion": "${REGION}"
                }
            }
        }
    ]
}
EOF


# Create IAM
aws iam create-policy --policy-name ${S3_POLICY_NAME} --policy-document file://peachycloudsecurity-eks-policy.json


cat <<EOF > peachycloudsecurity-ekstrust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF


# Create IAM Role and attach policy to read data from s3 bucket on the EKS node
aws iam create-role --role-name ${EKS_ROLE_NAME} --assume-role-policy-document file://peachycloudsecurity-ekstrust-policy.json
aws iam attach-role-policy --role-name ${EKS_ROLE_NAME} --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${S3_POLICY_NAME}
aws iam attach-role-policy --role-name ${EKS_ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam attach-role-policy --role-name ${EKS_ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam attach-role-policy --role-name ${EKS_ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam attach-role-policy --role-name ${EKS_ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

aws iam create-instance-profile --instance-profile-name ${EKS_ROLE_NAME}-profile
aws iam add-role-to-instance-profile --instance-profile-name ${EKS_ROLE_NAME}-profile --role-name ${EKS_ROLE_NAME}


cat <<EOF > eks-cluster-config.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${EKS_CLUSTER_NAME}
  region: ${REGION}

upgradePolicy:
  supportType: STANDARD

vpc:
  publicAccessCIDRs: ["0.0.0.0/0"]

managedNodeGroups:
  - name: standard-workers
    instanceType: t3.small
    desiredCapacity: 2
    minSize: 2
    maxSize: 4
    amiFamily: AmazonLinux2023
    iam:
      instanceRoleARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${EKS_ROLE_NAME}
EOF

#Create eks cluster
eksctl create cluster -f eks-cluster-config.yaml


# Check if the cluster creation was successful
if [ $? -eq 0 ]; then
    echo "Cluster ${EKS_CLUSTER_NAME} created successfully. Checking cluster status..."
    
    # Check the status of the cluster
    eksctl get cluster --name ${EKS_CLUSTER_NAME} --region ${REGION}
    
    if [ $? -eq 0 ]; then
        echo "Cluster ${EKS_CLUSTER_NAME} is active. Deploying YAML files..."
        
        # Update YAML templates with the new image repository URL
        sed -i "s|IMAGE_PLACEHOLDER|${REPO_URL}:latest|g" k8sapp/deployment.yaml
        sed -i "s|IMAGE_PLACEHOLDER|${REPO_URL}:latest|g" k8sapp/cron_job.yaml
        
        # Deploy all YAML files
        for yaml_file in k8sapp/*.yaml; 
        do
            kubectl apply -f $yaml_file
        done
        
        # Check the status of all pods
        echo "Checking the status of all pods..."
        kubectl get pods --all-namespaces
    else
        echo "Failed to get the status of the cluster ${EKS_CLUSTER_NAME}. Exiting."
        exit 1
    fi
else
    echo "Failed to create the EKS cluster ${EKS_CLUSTER_NAME}. Exiting."
    exit 1
fi

# Terraform Deployment
# Default region
export REGION=${REGION:-"us-west-2"}
export AMI="ami-0323ead22d6752894"

# Select AMI based on region
if [ "$REGION" == "us-east-1" ]; then
  AMI="ami-01fccab91b456acc2"
  echo "Using AMI: $AMI for region $REGION"
else
  echo "Using default AMI: $AMI for region $REGION"
fi

# Display a warning about admin privileges
echo "Warning: Admin privileges are required to deploy EKS Red Team infra."

# Directory containing Terraform configuration
export TF_DIR="ec2_terraform"

# Initialize Terraform
terraform -chdir="$TF_DIR" init

# Apply Terraform configuration with the selected region and AMI
terraform -chdir="$TF_DIR" apply -var="region=$REGION" -var="ec2_ami=$AMI" -auto-approve

# Save the EC2 instance name to ec2_output.json
terraform -chdir="$TF_DIR" output -json > ec2_output.json

# Consolidate output information into one file
export OUTPUT_FILE="deployment_output.txt"
touch deployment_output.txt
export INSTANCE_ID=$(jq -r '.instance_arn.value | split(":") | .[-1] | split("/") | .[-1]' ec2_output.json) 

#Create Json
cat <<EOF > ec2_terraform/ec2_policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:DescribeRepositories",
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:RequestedRegion": "${REGION}"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [ 
                "ecr:ListImages",
                "ecr:CompleteLayerUpload",
                "ecr:InitiateLayerUpload",
                "ecr:PutImage",
                "ecr:UploadLayerPart",
                "ecr:DescribeImages",
                "ecr:BatchGetImage",
                "ecr:GetDownloadUrlForLayer"
            ],
            "Resource": "arn:aws:ecr:${REGION}:*:repository/peachycloudsecurity*",
            "Condition": {
                "StringEquals": {
                    "aws:RequestedRegion": "${REGION}"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "eks:ListClusters"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:RequestedRegion": "${REGION}"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster"
            ],
            "Resource": "arn:aws:eks:${REGION}:*:cluster/peachycloudsecurity*"
        }
    ]
}
EOF


cat <<EOF > ec2_terraform/trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF



# Attach iam role to ec2 instance
echo "Creating IAM role..."
aws iam create-role --role-name peachycloudsecurity-redteam-${REPO_SUFFIX} --assume-role-policy-document file://ec2_terraform/trust-policy.json
if [ $? -eq 0 ]; then
    echo "Successfully created IAM role."
else
    echo "Failed to create IAM role." >&2

fi

echo "Attaching policy to the role..."
aws iam put-role-policy --role-name peachycloudsecurity-redteam-${REPO_SUFFIX} --policy-name peachycloudsecurity-policy --policy-document file://ec2_terraform/ec2_policy.json
if [ $? -eq 0 ]; then
    echo "Successfully attached policy."
else
    echo "Failed to attach policy." >&2

fi

echo "Creating the instance profile..."
aws iam create-instance-profile --instance-profile-name ${INSTANCE_PROFILE_NAME}
sleep 1  # Increased sleep to ensure AWS has time to register the new instance profile

echo "Adding role to the instance profile..."
aws iam add-role-to-instance-profile --instance-profile-name ${INSTANCE_PROFILE_NAME} --role-name peachycloudsecurity-redteam-${REPO_SUFFIX}
sleep 5  # Increased sleep for consistency

echo "Associating instance profile ${INSTANCE_PROFILE_NAME} for the Instance:$INSTANCE_ID..."
echo "Running command: aws ec2 associate-iam-instance-profile --instance-id ${INSTANCE_ID} --iam-instance-profile Name=${INSTANCE_PROFILE_NAME} --region ${REGION}"

aws ec2 associate-iam-instance-profile --instance-id $INSTANCE_ID --iam-instance-profile Name=${INSTANCE_PROFILE_NAME} --region ${REGION}
if [ $? -eq 0 ]; then
    echo "Successfully associated instance profile."
else
    echo "Failed to associate instance profile." >&2
fi


echo "Detaching EKS role policy..."
aws iam detach-role-policy --role-name ${EKS_ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
if [ $? -eq 0 ]; then
    
    aws iam detach-role-policy --role-name ${EKS_ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
    aws iam detach-role-policy --role-name ${EKS_ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

else
    echo "Failed to detach eks role policy ." >&2
fi
#Detach permissions from EKS Node which are not required.

# Create bucket for flag.txt
echo "Create bucket for flag.txt..."
export RANDOM_FLAG=${REPO_SUFFIX}
    export BUCKET_NAME="peachycloudsecurity-${RANDOM_FLAG}"
    aws s3 mb s3://${BUCKET_NAME} --region ${REGION} && echo "peachycloudsecurity_flag_${RANDOM_FLAG}${RANDOM_FLAG}" > flag.txt 
if [ $? -eq 0 ]; then
    aws s3 cp flag.txt s3://${BUCKET_NAME}/flag.txt --region ${REGION}
else
    echo "Failed to copy flag to bucket." >&2
fi


echo "Repo Suffix: ${REPO_SUFFIX}" > $OUTPUT_FILE
echo "ECR Repository Name: ${REPO_NAME}" >> $OUTPUT_FILE
echo "ECR Repository URL: ${REPO_URL}" >> $OUTPUT_FILE
echo "EKS Cluster Name: ${EKS_CLUSTER_NAME}" >> $OUTPUT_FILE
echo "EC2 Role Name: ${ROLE_NAME}" >> $OUTPUT_FILE
echo "EKS Node Role Name: ${EKS_ROLE_NAME}" >> $OUTPUT_FILE
echo "S3 Bucket Name: ${BUCKET_NAME}" >> $OUTPUT_FILE
echo "S3 Flag: peachycloudsecurity_flag_${RANDOM_FLAG}${RANDOM_FLAG}" >> $OUTPUT_FILE
echo "EC2 Instance Output: $(jq -r . < ec2_output.json)" >> $OUTPUT_FILE
echo "------------------" >> $OUTPUT_FILE
echo "------------------" >> $OUTPUT_FILE
echo "Authenticate to EKS cluster via: aws eks update-kubeconfig --region ${REGION} --name  ${EKS_CLUSTER_NAME}" >> $OUTPUT_FILE
echo "Access the application at: http://$(jq -r '.instance_public_ip.value' < ec2_output.json)" >> $OUTPUT_FILE

# Output important values
echo "------------------"
echo "------------------"
echo "Deployment Summary:"
cat $OUTPUT_FILE
echo "------------------"
echo "------------------"
