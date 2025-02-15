#!/bin/bash
# ECS Container Instance User Data Script

# Update system packages
yum update -y

# Install necessary packages
yum install -y ecs-init aws-cli jq amazon-cloudwatch-agent

# Start ECS service
systemctl enable ecs
systemctl start ecs

# Configure ECS agent
echo "ECS_CLUSTER=${cluster_name}" >> /etc/ecs/ecs.config
echo "ECS_ENABLE_CONTAINER_METADATA=true" >> /etc/ecs/ecs.config
echo "ECS_ENABLE_SPOT_INSTANCE_DRAINING=true" >> /etc/ecs/ecs.config
echo "ECS_CONTAINER_STOP_TIMEOUT=30s" >> /etc/ecs/ecs.config
echo "ECS_AVAILABLE_LOGGING_DRIVERS=[\"json-file\",\"awslogs\"]" >> /etc/ecs/ecs.config

# Configure CloudWatch agent
cat <<'EOF' > /opt/aws/amazon-cloudwatch-agent/bin/config.json
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "root"
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/ecs/ecs-agent.log",
                        "log_group_name": "/aws/ecs/${cluster_name}/agent",
                        "log_stream_name": "{instance_id}",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/ecs/ecs-init.log",
                        "log_group_name": "/aws/ecs/${cluster_name}/init",
                        "log_stream_name": "{instance_id}",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/messages",
                        "log_group_name": "/aws/ecs/${cluster_name}/system",
                        "log_stream_name": "{instance_id}",
                        "timezone": "UTC"
                    }
                ]
            }
        }
    },
    "metrics": {
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60,
                "totalcpu": false
            },
            "disk": {
                "measurement": [
                    "used_percent",
                    "inodes_free"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "diskio": {
                "measurement": [
                    "io_time",
                    "write_bytes",
                    "read_bytes",
                    "writes",
                    "reads"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            },
            "netstat": {
                "measurement": [
                    "tcp_established",
                    "tcp_time_wait"
                ],
                "metrics_collection_interval": 60
            },
            "swap": {
                "measurement": [
                    "swap_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

# Start CloudWatch agent
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Configure Docker daemon
cat <<'EOF' > /etc/docker/daemon.json
{
    "log-driver": "awslogs",
    "log-opts": {
        "awslogs-region": "us-gov-east-1",
        "awslogs-group": "/aws/ecs/${cluster_name}/containers",
        "awslogs-stream-prefix": "ecs"
    },
    "metrics-addr" : "0.0.0.0:9323",
    "experimental" : true
}
EOF

# Restart Docker to apply changes
systemctl restart docker

# Set up SSM agent
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Add instance to ECS cluster
echo "Adding instance to ECS cluster ${cluster_name}"
start ecs

# Final system hardening
# Disable unused services
systemctl disable postfix
systemctl stop postfix

# Set proper file permissions
chmod 700 /root/.aws

# Configure system limits for containers
cat <<'EOF' >> /etc/sysctl.conf
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_max_syn_backlog = 20480
net.ipv4.tcp_max_tw_buckets = 400000
net.ipv4.tcp_max_orphans = 60000
net.ipv4.tcp_syncookies = 1
EOF

sysctl -p

# Set proper umask for ECS agent
echo "umask 022" >> /etc/profile

# Enable enhanced networking
ethtool -K eth0 sg on
ethtool -K eth0 tso on
ethtool -K eth0 ufo on
ethtool -K eth0 gso on
ethtool -K eth0 gro on

# Signal completion
/opt/aws/bin/cfn-signal -e $? --stack ${cluster_name} --resource ECSAutoScalingGroup --region us-gov-east-1
