# POC Fargate - ECS Fargate Infrastructure as Code

A production-ready Proof of Concept for deploying containerized applications on AWS ECS Fargate with Application Load Balancer (ALB), featuring advanced logging with Kinesis Firehose and Fluent Bit.

## Overview

This project demonstrates a scalable, cloud-native architecture for running containerized workloads on AWS using Infrastructure as Code (Terraform). It includes:

- **ECS Fargate cluster** with multiple services (blue/green deployments)
- **Application Load Balancer (ALB)** with HTTPS support via ACM
- **Advanced logging pipeline** using Fluent Bit and Kinesis Firehose
- **Service discovery** using AWS Cloud Map
- **Security groups** and IAM policies for least privilege access
- **Multi-container support** with fluent-bit sidecar for log aggregation

## Features

### Core Services

- **ECS Fargate**: Serverless container orchestration
  - Two services: `poc-ecs-service` and `veera-service`
  - Capacity providers: FARGATE (50% base + weight) and FARGATE_SPOT (50% weight)
  - Configurable CPU (256-4096 units) and memory (512-4096 MB)
  - Auto-scaling ready (desired_count configurable)

- **Application Load Balancer (ALB)**
  - HTTP listener with automatic redirect to HTTPS
  - HTTPS listener with ACM certificate
  - Blue/green deployment support via weighted routing rules
  - Health checks configured per target group
  - Cross-zone load balancing enabled

- **Logging & Monitoring**
  - **Fluent Bit sidecar** container for log aggregation
  - **Kinesis Firehose** for streaming logs
  - **CloudWatch Logs** for application logs
  - Configurable log retention (default: 7 days)

- **Networking**
  - Service discovery with AWS Cloud Map
  - Custom VPC with public/private subnets
  - Security groups with minimal required permissions
  - Support for cross-subnet communication

### Advanced Features

- **SSL/TLS Support**
  - ACM certificate provisioning with DNS validation
  - Support for using existing wildcard certificates
  - Automatic HTTP→HTTPS redirect
  - SSLv3 cipher suite support

- **Blue/Green Deployments**
  - Primary target group (`poc-ecs-tg`) for production traffic
  - Alternate target group (`poc-ecs-tg-alternate`) for blue/green testing
  - Weighted routing rules for gradual traffic shifting

- **IAM Security**
  - Task execution role with ECR access
  - Task role with Firehose and CloudWatch Logs permissions
  - Container-level health checks
  - Execute command support for debugging

## Architecture

```
![POC Fargate Architecture Diagram](./images/POC-Fargate.png)
┌─────────────────────────────────────────────────────────────┐
│                        Internet                              │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
            ┌────────────────────────┐
            │    ALB (Port 80/443)   │
            │  - HTTP → HTTPS Redirect
            │  - ACM Certificate     │
            └────────────┬───────────┘
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
   ┌─────────────┐ ┌──────────────┐ ┌────────────┐
   │ TG: POC-ECS │ │ TG: Alternate │ │ Health CHK │
   └──────┬──────┘ └──────┬───────┘ └────────────┘
          │               │
          └───────┬───────┘
                  ▼
      ┌───────────────────────┐
      │   ECS Cluster         │
      │ (ecs-integrated)      │
      └───────┬───────────────┘
              │
    ┌─────────┴─────────┐
    ▼                   ▼
┌───────────────┐  ┌──────────────┐
│ poc-ecs-svc   │  │ veera-svc    │
│               │  │              │
│ ┌───────────┐ │  │ ┌──────────┐ │
│ │ fluent-bit│ │  │ │fluent-bit│ │
│ └───────────┘ │  │ └──────────┘ │
│ ┌───────────┐ │  │ ┌──────────┐ │
│ │ app       │ │  │ │nginx     │ │
│ │(port 3000)│ │  │ │(port 80) │ │
│ └────┬──────┘ │  │ └──────────┘ │
└──────┼────────┘  └──────┬───────┘
       │                  │
       └──────────┬───────┘
                  ▼
    ┌─────────────────────────┐
    │  Kinesis Firehose       │
    │  (Log Delivery Stream)  │
    └─────────────────────────┘
                  │
                  ▼
        ┌──────────────────┐
        │  S3 / Redshift   │
        │  (Final Storage) │
        └──────────────────┘
```

## Prerequisites

### AWS Account Requirements
- AWS account with appropriate IAM permissions
- VPC with public and private subnets already created
- Route 53 hosted zone (for domain validation)
- ACM certificate (either created via Terraform or existing in same/different account)

### Tools
- **Terraform** >= 1.0
- **AWS CLI** >= 2.0
- **jq** (optional, for CLI output parsing)

### AWS Credentials
```bash
export AWS_REGION=us-east-2
export AWS_ACCESS_KEY_ID=<your_key>
export AWS_SECRET_ACCESS_KEY=<your_secret>
```

## Deployment

### 1. Clone Repository
```bash
git clone <repository-url>
cd poc-fargate
```

### 2. Configure Variables

Edit `inputs.tfvars` with your environment-specific values:

```hcl
# AWS & Networking
region                 = "us-east-2"
vpc_id                 = "vpc-xxxxxxxx"
vpc_cidr               = "10.0.0.0/16"
public_subnets         = ["subnet-xxxxxxxx", "subnet-xxxxxxxx"]
private_subnets        = ["subnet-xxxxxxxx", "subnet-xxxxxxxx"]

# Domain & SSL
domain_name            = "example.com"
hosted_zone_id         = "Z1234567890ABC"
create_acm_certificate = false  # Use existing certificate
acm_certificate_arn    = "arn:aws:acm:us-east-2:123456789:certificate/xxxxxxxx"

# Container Configuration
poc_app_image          = "public.ecr.aws/aws-containers/ecsdemo-frontend:776fd50"
nginx_image            = "docker.io/library/nginx:latest"
fluent_bit_image       = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"

# Service Configuration
service_cpu            = "1024"
service_memory         = "4096"
desired_count          = 2
poc_container_port     = 3000
app_container_port     = 80
external_port          = 80
```

### 3. Initialize Terraform
```bash
terraform init
```

### 4. Validate Configuration
```bash
terraform validate
terraform plan -var-file=inputs.tfvars
```

### 5. Deploy
```bash
terraform apply -var-file=inputs.tfvars
```

### 6. Verify Deployment
```bash
# Get ALB DNS name
terraform output module_alb_dns_name

# Check ECS services
aws ecs list-services --cluster ecs-integrated --region us-east-2

# View logs
aws logs tail /aws/ecs/veera-service --follow --region us-east-2
```

## Configuration

### Environment Variables

Services can access environment variables via container definitions:

```hcl
environment = [
  {
    name  = "FIREHOSE_STREAM"
    value = aws_kinesis_firehose_delivery_stream.firehose_stream.name
  },
  {
    name  = "LOG_GROUP"
    value = "/aws/ecs/poc-ecs-service/poc-ecs-app"
  },
  {
    name  = "AWS_REGION"
    value = local.region
  }
]
```

### Scaling

Modify `inputs.tfvars` to scale services:

```hcl
desired_count    = 3              # Number of task replicas
service_cpu      = "2048"         # CPU units (256, 512, 1024, 2048, 4096)
service_memory   = "8192"         # Memory in MB
```

### Log Retention

```hcl
log_retention = 14  # Days (default: 7)
```

## Monitoring & Logging

### CloudWatch Logs

Application logs are streamed to CloudWatch:
- POC Service: `/aws/ecs/poc-ecs-service/poc-ecs-app`
- Nginx Service: `/aws/ecs/veera-service`

View logs:
```bash
aws logs tail /aws/ecs/veera-service --follow
```

### Firehose Integration

Logs are captured via Fluent Bit and delivered to Kinesis Firehose:

```bash
# Check Firehose delivery stream
aws firehose describe-delivery-stream \
  --delivery-stream-name poc-fargate-firehose-stream
```

### Health Checks

ALB performs health checks on target groups:
- **POC Service**: HTTP 200-399 status, 30s interval
- **Nginx Service**: HTTP 200 status, 30s interval

## Blue/Green Deployments

This architecture supports blue/green deployments via weighted routing:

```hcl
rules = {
  production = {
    priority = 1
    actions = [{
      weighted_forward = {
        target_groups = [
          {
            target_group_key = "poc-ecs-tg"          # Production (100%)
            weight = 100
          },
          {
            target_group_key = "poc-ecs-tg-alternate" # Staging (0%)
            weight = 0
          }
        ]
      }
    }]
  }
}
```

To switch traffic: Update weights in `main.tf` listeners and re-run `terraform apply`.

## File Structure

```
poc-fargate/
├── main.tf              # ECS cluster, ALB, service definitions
├── acm.tf               # ACM certificate provisioning & validation
├── firehose.tf          # Kinesis Firehose configuration
├── fluent-bit.tf        # Fluent Bit log router configuration
├── sg.tf                # Security groups
├── providers.tf         # AWS provider configuration
├── variables.tf         # Input variable definitions
├── outputs.tf           # Output values
├── inputs.tfvars        # Environment-specific values
└── README.md            # This file
```

## Security Considerations

### ✅ Implemented
- **Least privilege IAM policies** - Tasks have only required permissions
- **Security groups** - Restricted ingress/egress rules
- **HTTPS/TLS** - ACM certificate enforcement
- **Private subnets** - ECS tasks run in private subnets
- **Task execution roles** - Separate task role and exec role

### ⚠️ Production Recommendations

See [Production Improvements](#production-improvements) section below.

## Production Improvements

### 1. **Auto-Scaling**
```hcl
# Add target tracking scaling policy
resource "aws_appautoscaling_target" "ecs_service_scaling" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/ecs-integrated/poc-ecs-service"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}
```

### 2. **Enhanced Monitoring**
- CloudWatch container insights
- Custom metrics and alarms
- X-Ray tracing integration
- VPC Flow Logs for network analysis

### 3. **State Management**
- **Remote Terraform state** in S3 with DynamoDB locking
```hcl
terraform {
  backend "s3" {
    bucket         = "your-tf-state-bucket"
    key            = "poc-fargate/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

### 4. **Disaster Recovery**
- Multi-region deployment
- Automated backups
- Disaster recovery plan documentation
- Regular failover testing

### 5. **Cost Optimization**
- FARGATE_SPOT for non-critical workloads (50% cost savings)
- Reserved capacity for baseline traffic
- Scheduled scaling (scale down non-production hours)
- Data transfer optimization

### 6. **Compliance & Audits**
- CloudTrail logging for all API calls
- Config rules for compliance checking
- Encryption at rest and in transit
- Regular security assessments

### 7. **CI/CD Integration**
- GitHub Actions / GitLab CI for automated deployments
- Blue/green deployment automation
- Automated testing before production
- Rollback mechanisms

### 8. **High Availability**
- Multi-AZ deployment across 3+ availability zones
- Database failover (RDS with Multi-AZ)
- Load balancer with health-based routing
- Circuit breakers for resilience

### 9. **Secrets Management**
```hcl
# Use AWS Secrets Manager instead of environment variables
resource "aws_secretsmanager_secret" "db_password" {
  name = "poc-fargate/db-password"
}
```

### 10. **Network Security**
- WAF rules on ALB for DDoS/attack protection
- Network ACLs for subnet-level filtering
- VPC endpoints for AWS service access
- Private link for cross-account access

### 11. **Observability**
- ECS Exec for container debugging
- CloudWatch alarms for key metrics
- Distributed tracing (X-Ray)
- Log aggregation and analysis

### 12. **Infrastructure**
- Terraform modules for code reuse
- Separate dev/staging/prod environments
- GitOps workflow (ArgoCD, Flux)
- Immutable infrastructure with container versioning

## Troubleshooting

### ALB Health Check Failures
```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:... \
  --region us-east-2
```

### ECS Task Failures
```bash
# View task logs
aws ecs describe-tasks \
  --cluster ecs-integrated \
  --tasks arn:aws:ecs:... \
  --region us-east-2
```

### Firehose Delivery Failures
```bash
# Check delivery stream status
aws firehose describe-delivery-stream \
  --delivery-stream-name poc-fargate-firehose-stream
```

### ACM Certificate Issues
```bash
# List certificates
aws acm list-certificates --region us-east-2

# Get certificate details
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:... \
  --region us-east-2
```

## Cleanup

To destroy all resources:
```bash
terraform destroy -var-file=inputs.tfvars
```

⚠️ **Warning**: This will delete:
- ECS cluster and services
- ALB and target groups
- Kinesis Firehose stream
- CloudWatch log groups
- IAM roles and policies
- Security groups

## Contributing

1. Create a feature branch
2. Make changes and test locally
3. Submit pull request with description
4. Ensure CI/CD pipeline passes

## License

MIT License - See LICENSE file for details

## Support

For issues, questions, or suggestions:
1. Check [Troubleshooting](#troubleshooting) section
2. Review AWS documentation
3. Open an issue in the repository

## Additional Resources

- [AWS ECS Fargate Documentation](https://docs.aws.amazon.com/ecs/latest/developerguide/launch_types.html#launch-type-fargate)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Fluent Bit for AWS](https://docs.aws.fluentbit.io/manual/installation/sources/aws-plugin)
- [Kinesis Firehose User Guide](https://docs.aws.amazon.com/kinesis/latest/dev/firehose-what-is.html)
- [AWS ALB Documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)

---

**Last Updated**: February 2026  
**Version**: 1.0  
**Status**: Production-Ready POC
