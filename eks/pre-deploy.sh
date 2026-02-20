#!/bin/bash

# Trap signals for graceful exit
INTERRUPTED=false
trap 'echo; echo "Script interrupted. It will exit after the current operation completes."; INTERRUPTED=true' SIGINT SIGTERM SIGHUP

# Check if the script is being sourced
# If the script is executed directly, exit with a helpful message.
# If the script is sourced, continue.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script must be sourced to work correctly (e.g. 'source $0' or '. $0')"
    return 1 2>/dev/null || exit 1
fi

# Attempt to fix Yarn APT key/source if a Yarn repo is present and the keyring is missing.
# This function is idempotent and will not abort the script if it fails.
fix_yarn_key_if_needed() {
    if grep -R --quiet "dl.yarnpkg.com" /etc/apt 2>/dev/null; then

        # Remove broken repo first
        sudo rm -f /etc/apt/sources.list.d/yarn.list

        # if keyring already present, still continue (we want fresh repo definition)
        echo "Fixing Yarn APT repo (non-fatal)..."
        sudo mkdir -p /usr/share/keyrings

        if curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg | sudo gpg --dearmor -o /usr/share/keyrings/yarn-archive-keyring.gpg; then
            echo "Yarn keyring added."

            echo "deb [signed-by=/usr/share/keyrings/yarn-archive-keyring.gpg] https://dl.yarnpkg.com/debian stable main" \
                | sudo tee /etc/apt/sources.list.d/yarn.list > /dev/null

            # optional but useful → refresh apt once here
            sudo apt-get update || true
        else
            echo "Warning: failed to fix Yarn key; continuing..."
        fi
    fi
    return 0
}

# Function to install AWS CLI
install_aws() {
    echo "Installing AWS CLI..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf awscliv2.zip aws
    echo "AWS CLI installation complete."

    if [ "$INTERRUPTED" = true ]; then
        echo "Exiting as requested after installing AWS CLI."
        exit 1
    fi
}

# Function to install eksctl
install_eksctl() {
    echo "Installing eksctl..."
    PLATFORM=$(uname -s)_amd64
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
    sudo mv /tmp/eksctl /usr/local/bin
    echo "eksctl installation complete."

    if [ "$INTERRUPTED" = true ]; then
        echo "Exiting as requested after installing eksctl."
        exit 1
    fi
}

# Function to install kubectl
install_kubectl() {
    echo "Installing kubectl..."
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) BIN_ARCH="amd64" ;;
        aarch64) BIN_ARCH="arm64" ;;
        *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$BIN_ARCH/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    echo "kubectl installation complete."

    if [ "$INTERRUPTED" = true ]; then
        echo "Exiting as requested after installing kubectl."
        exit 1
    fi
}

# Function to install Terraform
install_terraform() {
    echo "Installing Terraform..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        echo "Cannot determine OS type. Exiting."
        exit 1
    fi

    if [[ "$OS" == "ubuntu" ]]; then
        # try to fix Yarn key/source if present but missing key; non-fatal
        fix_yarn_key_if_needed || true

        sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl
        curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        # attempt update/install; if apt-get update errors due to other repos, attempt install anyway
        sudo apt-get update || echo "Warning: apt-get update reported errors; attempting to install terraform anyway..."
        sudo apt-get install -y terraform || { echo "terraform install failed"; return 1; }

    elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "fedora" ]]; then
        sudo yum install -y yum-utils uuid-runtime jq
        sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
        sudo yum -y install terraform
    elif [[ "$OS" == "amzn" ]]; then
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
        sudo yum -y install terraform
    else
        echo "Unsupported OS: $OS. Please install Terraform manually."
        exit 1
    fi
    echo "Terraform installation complete."

    if [ "$INTERRUPTED" = true ]; then
        echo "Exiting as requested after installing Terraform."
        exit 1
    fi
}

# Function to install jq
install_jq() {
    echo "Installing jq..."
    # try to fix Yarn key/source if present but missing key; non-fatal
    fix_yarn_key_if_needed || true

    if [[ "$OS" == "ubuntu" ]]; then
        sudo apt-get update && sudo apt-get install -y jq uuid-runtime
    elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "fedora" ]]; then
        sudo yum install -y jq
    else
        echo "Unsupported OS: $OS. Please install jq manually."
        exit 1
    fi
    echo "jq installation complete."

    if [ "$INTERRUPTED" = true ]; then
        echo "Exiting as requested after installing jq."
        exit 1
    fi
}

# Function to check if a binary is installed
check_binary() {
    if ! command -v $1 &> /dev/null; then
        echo "$1 could not be found. Installing $1..."
        install_$1
    else
        echo "$1 is already installed."
    fi

    if [ "$INTERRUPTED" = true ]; then
        echo "Exiting as requested after checking $1."
        exit 1
    fi
}

# Check CPU architecture
ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" ]]; then
    echo "Error: This script only supports Intel/AMD64 or ARM64 architectures. Detected architecture: $ARCH."
    exit 1
fi

# Determine OS type
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    echo "Operating System detected: $OS."
else
    echo "Cannot determine operating system type. Exiting."
    exit 1
fi

# Check and install required binaries
echo "Checking and installing required binaries..."
check_binary aws
check_binary eksctl
check_binary kubectl
check_binary terraform
check_binary jq

echo "Pre-deployment checks and installations are complete."
