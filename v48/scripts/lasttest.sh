#!/bin/bash
# A simple load test: keep both vCPUs of a t3.micro busy for a while.
# Run ON EACH server in the Auto Scaling group (ssh to their public IPs).
# The group scales on the AVERAGE CPU. Load on one of two servers gives about 50 percent,
# which is exactly the target, and then nothing happens.
# Watch: Auto Scaling group, Monitoring and Activity. Scaling out takes several minutes.
for i in 1 2; do
  timeout 15m yes > /dev/null &
done
echo "Load running for 15 minutes. Stop it earlier with: pkill yes"
# T3 instances can use more CPU than their baseline for a while, longer runs can cost
# extra, so do not let the load run longer than needed.
