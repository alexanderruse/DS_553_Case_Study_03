# AWS ECS Fargate

Create AWS Budgets alerts before provisioning resources. Avoid a NAT Gateway;
for this short-lived class deployment, use public subnets, assign the Fargate
task a public IP, and place an Application Load Balancer in front of the service
for a stable DNS URL.

Build and push the image:

```bash
aws configure
export AWS_REGION="us-east-1"
./cloud/aws/build-and-push.sh
```

Then:

1. Create the `/ecs/resumelens-api` CloudWatch log group.
2. Replace `<AWS_ACCOUNT_ID>`, `<AWS_REGION>`, and `<IMAGE_TAG>` in
   `task-definition.json`; do not commit the rendered file.
3. Register the Fargate task definition.
4. Create an ECS service with desired count 1 and an Application Load Balancer.
5. Use container port 8080 and health path `/` with a 60--120 second grace
   period.
6. Allow task port 8080 only from the load balancer security group.
7. Enter the load balancer DNS URL in the class Sheet.

The load balancer and running Fargate task can generate charges even when idle.
Remove them after grading if continued availability is not required.
