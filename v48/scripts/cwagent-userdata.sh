#!/bin/bash
# User data for version 2 of novatrix-web-lt (G). The AMI from v47 already has WordPress,
# this only adds the CloudWatch agent. Runs once, at the first boot of every new server.
# Needs: CloudWatchAgentServerPolicy on the role, and the parameter AmazonCloudWatch-novatrix.
# Log: /var/log/cloud-init-output.log, the agent's own log: /opt/aws/amazon-cloudwatch-agent/logs/
set -euxo pipefail
dnf install -y amazon-cloudwatch-agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config \
  -m ec2 -s -c ssm:AmazonCloudWatch-novatrix
