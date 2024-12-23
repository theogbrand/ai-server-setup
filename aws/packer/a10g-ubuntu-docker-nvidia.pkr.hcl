packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "ubuntu_ami" {
  ami_name      = "ubuntu-with-docker-and-nvidia-560-cuda-12-6-ami"
  region        = "us-east-2"
  instance_type = "g5.xlarge"

  source_ami_filter {
    filters = {
      name             = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-20240801"
      root-device-type = "ebs"
      architecture     = "x86_64"
    }
    # Canonical
    owners      = ["099720109477"]
    most_recent = true
  }

  ssh_username = "ubuntu"
  # Allow reboots
  ssh_read_write_timeout = "5m"

  # Increase root drive storage amount
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 50
    volume_type           = "gp3"
    delete_on_termination = true
  }
}

build {
  name    = "ubuntu_with_docker_and_nvidia_560_cuda_12_6"
  sources = ["source.amazon-ebs.ubuntu_ami"]

  # Installing Required Packages
  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y curl apt-transport-https ca-certificates software-properties-common",
    ]
  }

  # Installing Docker
  # This is techinally the distro package, not official
  provisioner "shell" {
    inline = [
      "sudo apt-get install -y docker.io",
    ]
  }

  # Installing Docker Compose
  provisioner "shell" {
    inline = [
      "DOCKER_CONFIG=/usr/local/lib/docker",
      "sudo mkdir -p $DOCKER_CONFIG/cli-plugins",
      "sudo curl -SL https://github.com/docker/compose/releases/download/v2.29.0/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose",
      "sudo chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose",
    ]
  }

  # Add user to docker group
  # https://docs.docker.com/engine/install/linux-postinstall/#manage-docker-as-a-non-root-user
  provisioner "shell" {
    inline = [
      "sudo usermod -aG docker $USER",
    ]
  }

  # Installing Ubuntu Drivers Tool
  provisioner "shell" {
    inline = [
      "sudo apt-get install -y ubuntu-drivers-common",
    ]
  }

  # Installing NVIDIA CUDA Toolkit
  provisioner "shell" {
    inline = [
      "ubuntu_version='ubuntu2404/x86_64'",
      "sudo apt-get install -y linux-headers-$(uname -r)",
      "sudo apt-key del 7fa2af80 || true",
      "wget https://developer.download.nvidia.com/compute/cuda/repos/$ubuntu_version/cuda-keyring_1.1-1_all.deb",
      "sudo dpkg -i cuda-keyring_1.1-1_all.deb",
      "sudo apt-get update",
      "sudo apt-get install -y cuda-toolkit",
      "echo -e '# Add NVIDIA CUDA to path\nexport PATH=/usr/local/cuda-12.6/bin$${PATH:+:$${PATH}}' >> ~/.profile"
    ]
  }

  # Install NVIDIA Container Toolkit
  provisioner "shell" {
    inline = [
      "curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg",
      "curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list",
      "sudo sed -i -e '/experimental/ s/^#//g' /etc/apt/sources.list.d/nvidia-container-toolkit.list",
      "sudo apt-get update",
      "sudo apt-get install -y nvidia-container-toolkit",
      "sudo nvidia-ctk runtime configure --runtime=docker",
      "sudo systemctl restart docker",
    ]
  }

  # Setting Virtual Memory Map (for OpenSearch)
  provisioner "shell" {
    inline = [
      "echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf",
      "sudo sysctl -p",
    ]
  }

  # Installing make and c++ compiler
  provisioner "shell" {
    inline = [
      "sudo apt-get install -y make g++",
    ]
  }

  # Update existing packages
  provisioner "shell" {
    inline = [
      "sudo apt-get upgrade -y",
      "sudo apt autoremove -y"
    ]
  }

  # Reboot
  provisioner "shell" {
    expect_disconnect = true
    inline = [
      "sudo reboot now",
    ]
    pause_after = "10s"
  }

  # Installing NVIDIA Drivers
  # Running this last seemed to work best
  provisioner "shell" {
    inline = [
      "sudo ubuntu-drivers install nvidia:560",
    ]
  }
}
