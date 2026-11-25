#!/bin/bash
# The CPU alarm for the whole group as a command (same as the console steps in Del 19),
# and a test of the whole chain: alarm, topic, subscription, mail. Run in CloudShell.

# The topic's ARN, looked up by name
TOPIC_ARN=$(aws sns list-topics \
  --query "Topics[?ends_with(TopicArn, ':novatrix-larm')].TopicArn" --output text)
echo "Topic: $TOPIC_ARN"

# Average CPU in the group above 70 for five minutes
aws cloudwatch put-metric-alarm --alarm-name novatrix-cpu-hog \
  --alarm-description "Average CPU in the web group is high, check scaling and Activity" \
  --namespace AWS/EC2 --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=novatrix-web-asg \
  --statistic Average --period 300 --evaluation-periods 1 \
  --threshold 70 --comparison-operator GreaterThanThreshold \
  --alarm-actions "$TOPIC_ARN" --ok-actions "$TOPIC_ARN"

# Test the chain: force ALARM, a mail should arrive within a minute.
# The next evaluation sets the real state again, OK in a quiet group.
aws cloudwatch set-alarm-state --alarm-name novatrix-cpu-hog \
  --state-value ALARM --state-reason "Test av larmkedjan"

# All Novatrix alarms and their state, as text for the documentation
aws cloudwatch describe-alarms --alarm-name-prefix novatrix- \
  --query "MetricAlarms[].[AlarmName,StateValue,Threshold]" --output table
