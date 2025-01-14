# AWS Account Auditing Tools Guide

## Primary Auditing Tools

### 1. AWS Config
```hcl
# Enable AWS Config across all accounts via Terraform
resource "aws_config_configuration_recorder" "config" {
  name     = "config-recorder"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported = true
    include_global_resources = true
  }
}

resource "aws_config_configuration_recorder_status" "config" {
  name       = aws_config_configuration_recorder.config.name
  is_enabled = true
}
```

Benefits:
- Continuous monitoring of resources
- Automated compliance checking
- Historical configuration tracking
- Multi-account support via AWS Organizations

### 2. AWS CloudFormation StackSets
```yaml
# Example StackSet for enabling Security Hub
AWSTemplateFormatVersion: '2010-09-09'
Resources:
  EnableSecurityHub:
    Type: 'AWS::SecurityHub::Hub'
    Properties: {}
```

Benefits:
- Deploy consistent configurations across accounts
- Automated stack operations
- Centralized management
- Region-specific deployments

### 3. AWS IAM Access Analyzer
```hcl
# Enable IAM Access Analyzer via Terraform
resource "aws_accessanalyzer_analyzer" "organization" {
  analyzer_name = "organization-analyzer"
  type          = "ORGANIZATION"
}
```

Benefits:
- Identifies resources shared with external entities
- Continuous security monitoring
- Policy validation
- Cross-account access review

## Automated Auditing Scripts

### 1. AWS Organizations List Script
```python
import boto3
import csv
from datetime import datetime

def audit_organizations():
    org_client = boto3.client('organizations')
    accounts = []
    
    paginator = org_client.get_paginator('list_accounts')
    for page in paginator.paginate():
        accounts.extend(page['Accounts'])
    
    with open(f'aws_accounts_audit_{datetime.now().strftime("%Y%m%d")}.csv', 'w') as f:
        writer = csv.writer(f)
        writer.writerow(['Account ID', 'Name', 'Email', 'Status', 'Joined Date'])
        for account in accounts:
            writer.writerow([
                account['Id'],
                account['Name'],
                account['Email'],
                account['Status'],
                account['JoinedTimestamp'].strftime("%Y-%m-%d")
            ])

if __name__ == '__main__':
    audit_organizations()
```

### 2. IAM User Audit Script
```python
import boto3
import csv
from datetime import datetime

def audit_iam_users(account_id):
    session = boto3.Session()
    iam = session.client('iam')
    
    users = []
    paginator = iam.get_paginator('list_users')
    
    for page in paginator.paginate():
        for user in page['Users']:
            access_keys = iam.list_access_keys(UserName=user['UserName'])
            mfa_devices = iam.list_mfa_devices(UserName=user['UserName'])
            
            users.append({
                'UserName': user['UserName'],
                'CreateDate': user['CreateDate'],
                'PasswordLastUsed': user.get('PasswordLastUsed', 'Never'),
                'AccessKeys': len(access_keys['AccessKeyMetadata']),
                'MFAEnabled': len(mfa_devices['MFADevices']) > 0
            })
    
    with open(f'iam_audit_{account_id}_{datetime.now().strftime("%Y%m%d")}.csv', 'w') as f:
        writer = csv.writer(f)
        writer.writerow(['Username', 'Created', 'Password Last Used', 'Access Keys', 'MFA Enabled'])
        for user in users:
            writer.writerow([
                user['UserName'],
                user['CreateDate'].strftime("%Y-%m-%d"),
                user['PasswordLastUsed'],
                user['AccessKeys'],
                user['MFAEnabled']
            ])

if __name__ == '__main__':
    audit_iam_users('ACCOUNT_ID')
```

### 3. Resource Audit Script
```python
import boto3
import json
from datetime import datetime

def audit_resources(account_id):
    session = boto3.Session()
    resource_groups = session.client('resource-groups')
    
    query = {
        "ResourceTypeFilters": ["AWS::AllSupported"],
        "TagFilters": []
    }
    
    resources = []
    paginator = resource_groups.get_paginator('search_resources')
    
    for page in paginator.paginate(ResourceQuery={'Type': 'TAG_FILTERS_1_0', 'Query': json.dumps(query)}):
        resources.extend(page['ResourceIdentifiers'])
    
    with open(f'resources_audit_{account_id}_{datetime.now().strftime("%Y%m%d")}.json', 'w') as f:
        json.dump(resources, f, indent=2, default=str)

if __name__ == '__main__':
    audit_resources('ACCOUNT_ID')
```

## Comprehensive Audit Tool: AWS Audit Manager

### Enable AWS Audit Manager
```hcl
# Enable Audit Manager via Terraform
resource "aws_auditmanager_organization_admin_account_registration" "admin" {
  admin_account_id = "ADMIN_ACCOUNT_ID"
  depends_on       = [aws_organizations_organization.org]
}

resource "aws_auditmanager_assessment" "compliance" {
  name = "compliance-assessment"
  
  assessment_reports_destination {
    destination      = "S3"
    destination_type = "S3"
  }

  framework_id = "Control Tower Guardrails"
  
  roles {
    role_arn  = aws_iam_role.audit_manager.arn
    role_type = "PROCESS_OWNER"
  }

  scope {
    aws_accounts {
      id = data.aws_caller_identity.current.account_id
    }
    aws_services {
      service_name = "AWS_ALL"
    }
  }
}
```

Benefits:
- Continuous auditing
- Automated evidence collection
- Compliance framework mapping
- Centralized findings

## AWS Security Hub

### Enable Security Hub
```hcl
# Enable Security Hub via Terraform
resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_organization_admin_account" "main" {
  admin_account_id = "ADMIN_ACCOUNT_ID"
}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/cis-aws-foundations-benchmark/v1.2.0"
  depends_on    = [aws_securityhub_account.main]
}
```

Benefits:
- Security findings aggregation
- Automated security checks
- Compliance status tracking
- Integration with other security tools

## Implementation Steps

1. **Initial Setup**
   - Enable AWS Organizations
   - Configure master account
   - Enable required services

2. **Deploy Audit Tools**
   - Enable AWS Config
   - Configure Security Hub
   - Setup Audit Manager
   - Deploy IAM Access Analyzer

3. **Run Audit Scripts**
   - Execute account inventory
   - Run IAM user audit
   - Perform resource audit
   - Generate reports

4. **Review and Remediate**
   - Analyze audit findings
   - Implement required changes
   - Document compliance status
   - Setup continuous monitoring

## Best Practices

1. **Centralized Logging**
   - Use CloudWatch Logs
   - Enable AWS CloudTrail
   - Configure S3 bucket policies
   - Implement log retention

2. **Automated Remediation**
   - Use AWS Systems Manager
   - Configure AWS Config Rules
   - Implement Lambda functions
   - Setup EventBridge rules

3. **Regular Auditing**
   - Weekly security reviews
   - Monthly compliance checks
   - Quarterly access reviews
   - Annual comprehensive audits

## Additional Tools

1. **AWS Trusted Advisor**
   - Cost optimization
   - Performance
   - Security
   - Fault tolerance

2. **Amazon Detective**
   - Security investigation
   - Root cause analysis
   - Threat detection
   - Behavioral analytics

3. **Amazon Inspector**
   - Vulnerability assessment
   - Network accessibility
   - Security best practices
   - Compliance validation
