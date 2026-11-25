# novatrix-sajtkoll: asks the site like a visitor and sends two metrics to CloudWatch,
# Available (1 or 0) and ResponseTimeMs. Paste into lambda_function.py and click Deploy.
#
# Configuration:
#   Timeout 20 seconds (General configuration)
#   Environment variables: SITE_URL = http://<DNS name of novatrix-alb>, SITE_NAME = novatrix
#   Trigger: EventBridge, schedule expression rate(5 minutes)
#
# Inline policy on the function's role (Add permissions, Create inline policy, JSON):
# {
#   "Version": "2012-10-17",
#   "Statement": [{
#     "Effect": "Allow",
#     "Action": "cloudwatch:PutMetricData",
#     "Resource": "*",
#     "Condition": {"StringEquals": {"cloudwatch:namespace": "Novatrix/SiteCheck"}}
#   }]
# }
import os
import time
import urllib.request

import boto3

cloudwatch = boto3.client("cloudwatch")


def lambda_handler(event, context):
    url = os.environ["SITE_URL"] + "/wp-login.php"
    start = time.time()
    try:
        with urllib.request.urlopen(url, timeout=10) as answer:
            ok = 1 if answer.status == 200 else 0
    except Exception as error:
        print("Check failed:", error)
        ok = 0
    ms = (time.time() - start) * 1000
    site = [{"Name": "Site", "Value": os.environ["SITE_NAME"]}]
    cloudwatch.put_metric_data(Namespace="Novatrix/SiteCheck", MetricData=[
        {"MetricName": "Available", "Dimensions": site, "Value": ok, "Unit": "Count"},
        {"MetricName": "ResponseTimeMs", "Dimensions": site, "Value": ms, "Unit": "Milliseconds"},
    ])
    print(f"{url} ok={ok} {ms:.0f} ms")
    return {"ok": ok, "ms": round(ms)}
