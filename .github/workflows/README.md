# GitHub Actions Workflow Setup

This directory contains the GitHub Actions workflow for building and deploying the Shoppollama application.

## Required GitHub Secrets

Before using this workflow, you must configure the following secrets in your GitHub repository:

### AWS Role ARN
- **Name**: `AWS_ROLE_ARN`
- **Description**: The ARN of the AWS IAM role that GitHub Actions will assume
- **Format**: `arn:aws:iam::<account-id>:role/<role-name>`

### Required AWS IAM Role Permissions

The IAM role referenced by `AWS_ROLE_ARN` needs the following permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:CreateRepository",
                "ecr:DescribeRepositories",
                "ecr:GetAuthorizationToken",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:PutImage"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "pulumi:*"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:*"
            ],
            "Resource": [
                "arn:aws:s3:::shoppollama-pulumi-state",
                "arn:aws:s3:::shoppollama-pulumi-state/*"
            ]
        }
    ]
}
```

## Workflow Triggers

The workflow is triggered on:
- Push to the `main` branch

## Workflow Steps

1. **Checkout**: Downloads the repository code
2. **Configure AWS**: Sets up AWS credentials using the provided role
3. **Login to ECR**: Authenticates with Amazon ECR
4. **Create ECR Repository**: Creates the repository if it doesn't exist
5. **Build and Push**: Builds the Docker image and pushes to ECR with the commit SHA as tag
6. **Install Pulumi**: Sets up Pulumi CLI
7. **Configure Pulumi**: Logs into Pulumi and selects the prod stack
8. **Update Pulumi Config**: Sets the new ECR image URI in Pulumi config
9. **Deploy**: Runs `pulumi up` to update the infrastructure
10. **Export Outputs**: Saves the load balancer URL

## Image Tagging Strategy

Images are tagged with the GitHub commit SHA, ensuring each deployment uses a unique, traceable image version.

## Pulumi State

Pulumi state is stored in an S3 bucket named `shoppollama-pulumi-state`. This bucket must be created before running the workflow.
