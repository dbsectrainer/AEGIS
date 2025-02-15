# Cloud Service Provider Inherited Controls

## Overview
This document details the security controls inherited from AWS GovCloud and Azure Government under their shared responsibility models, mapped to FedRAMP High baseline controls. It clarifies which security requirements are managed by the Cloud Service Provider (CSP) versus USCG responsibilities.

## Shared Responsibility Model Overview

### AWS GovCloud
1. CSP Responsibilities (Inherited)
   - Physical security of data centers
   - Hardware infrastructure
   - Network infrastructure
   - Virtualization infrastructure
   - Environmental controls
   - Personnel security (AWS staff)

2. Shared Responsibilities
   - Patch management
   - Configuration management
   - Awareness and training
   - Incident response

3. Customer Responsibilities (USCG)
   - Data classification and accountability
   - Access management
   - Application security
   - Identity and access management
   - Network security controls
   - Operating system security

### Azure Government
1. CSP Responsibilities (Inherited)
   - Physical datacenter security
   - Network infrastructure
   - Host infrastructure
   - Environmental systems
   - Personnel security (Microsoft staff)

2. Shared Responsibilities
   - Identity and access management
   - Threat detection and response
   - Network security
   - Service configuration

3. Customer Responsibilities (USCG)
   - Data governance
   - Application security
   - Resource configuration
   - Access management
   - Endpoint security

## Inherited Controls Mapping

### Physical and Environmental Protection (PE)

#### AWS GovCloud Inherited Controls
| Control ID | Control Name | Implementation | Validation Evidence |
|------------|--------------|----------------|-------------------|
| PE-1 | Physical and Environmental Protection Policy and Procedures | Fully Inherited | AWS FedRAMP Package |
| PE-2 | Physical Access Authorizations | Fully Inherited | AWS FedRAMP Package |
| PE-3 | Physical Access Control | Fully Inherited | AWS FedRAMP Package |
| PE-4 | Access Control for Transmission Medium | Fully Inherited | AWS FedRAMP Package |
| PE-5 | Access Control for Output Devices | Fully Inherited | AWS FedRAMP Package |
| PE-6 | Monitoring Physical Access | Fully Inherited | AWS FedRAMP Package |
| PE-8 | Visitor Access Records | Fully Inherited | AWS FedRAMP Package |
| PE-9 | Power Equipment and Cabling | Fully Inherited | AWS FedRAMP Package |
| PE-10 | Emergency Shutoff | Fully Inherited | AWS FedRAMP Package |
| PE-11 | Emergency Power | Fully Inherited | AWS FedRAMP Package |
| PE-12 | Emergency Lighting | Fully Inherited | AWS FedRAMP Package |
| PE-13 | Fire Protection | Fully Inherited | AWS FedRAMP Package |
| PE-14 | Temperature and Humidity Controls | Fully Inherited | AWS FedRAMP Package |
| PE-15 | Water Damage Protection | Fully Inherited | AWS FedRAMP Package |
| PE-16 | Delivery and Removal | Fully Inherited | AWS FedRAMP Package |
| PE-17 | Alternate Work Site | Partially Inherited | AWS FedRAMP Package |

#### Azure Government Inherited Controls
| Control ID | Control Name | Implementation | Validation Evidence |
|------------|--------------|----------------|-------------------|
| PE-1 | Physical and Environmental Protection Policy and Procedures | Fully Inherited | Azure FedRAMP Package |
| PE-2 | Physical Access Authorizations | Fully Inherited | Azure FedRAMP Package |
| PE-3 | Physical Access Control | Fully Inherited | Azure FedRAMP Package |
| PE-4 | Access Control for Transmission Medium | Fully Inherited | Azure FedRAMP Package |
| PE-5 | Access Control for Output Devices | Fully Inherited | Azure FedRAMP Package |
| PE-6 | Monitoring Physical Access | Fully Inherited | Azure FedRAMP Package |
| PE-8 | Visitor Access Records | Fully Inherited | Azure FedRAMP Package |
| PE-9 | Power Equipment and Cabling | Fully Inherited | Azure FedRAMP Package |
| PE-10 | Emergency Shutoff | Fully Inherited | Azure FedRAMP Package |
| PE-11 | Emergency Power | Fully Inherited | Azure FedRAMP Package |
| PE-12 | Emergency Lighting | Fully Inherited | Azure FedRAMP Package |
| PE-13 | Fire Protection | Fully Inherited | Azure FedRAMP Package |
| PE-14 | Temperature and Humidity Controls | Fully Inherited | Azure FedRAMP Package |
| PE-15 | Water Damage Protection | Fully Inherited | Azure FedRAMP Package |
| PE-16 | Delivery and Removal | Fully Inherited | Azure FedRAMP Package |
| PE-17 | Alternate Work Site | Partially Inherited | Azure FedRAMP Package |

### System and Communications Protection (SC)

#### AWS GovCloud Inherited Controls
| Control ID | Control Name | Implementation | Validation Evidence |
|------------|--------------|----------------|-------------------|
| SC-1 | System and Communications Protection Policy and Procedures | Partially Inherited | AWS FedRAMP Package |
| SC-5 | Denial of Service Protection | Partially Inherited | AWS FedRAMP Package |
| SC-7 | Boundary Protection | Partially Inherited | AWS FedRAMP Package |
| SC-8 | Transmission Confidentiality and Integrity | Partially Inherited | AWS FedRAMP Package |
| SC-13 | Cryptographic Protection | Partially Inherited | AWS FedRAMP Package |
| SC-19 | Voice Over Internet Protocol | Partially Inherited | AWS FedRAMP Package |
| SC-22 | Architecture and Provisioning for Name/Address Resolution Service | Fully Inherited | AWS FedRAMP Package |
| SC-23 | Session Authenticity | Partially Inherited | AWS FedRAMP Package |

#### Azure Government Inherited Controls
| Control ID | Control Name | Implementation | Validation Evidence |
|------------|--------------|----------------|-------------------|
| SC-1 | System and Communications Protection Policy and Procedures | Partially Inherited | Azure FedRAMP Package |
| SC-5 | Denial of Service Protection | Partially Inherited | Azure FedRAMP Package |
| SC-7 | Boundary Protection | Partially Inherited | Azure FedRAMP Package |
| SC-8 | Transmission Confidentiality and Integrity | Partially Inherited | Azure FedRAMP Package |
| SC-13 | Cryptographic Protection | Partially Inherited | Azure FedRAMP Package |
| SC-19 | Voice Over Internet Protocol | Partially Inherited | Azure FedRAMP Package |
| SC-22 | Architecture and Provisioning for Name/Address Resolution Service | Fully Inherited | Azure FedRAMP Package |
| SC-23 | Session Authenticity | Partially Inherited | Azure FedRAMP Package |

### Maintenance (MA)

#### AWS GovCloud Inherited Controls
| Control ID | Control Name | Implementation | Validation Evidence |
|------------|--------------|----------------|-------------------|
| MA-1 | System Maintenance Policy and Procedures | Fully Inherited | AWS FedRAMP Package |
| MA-2 | Controlled Maintenance | Fully Inherited | AWS FedRAMP Package |
| MA-3 | Maintenance Tools | Fully Inherited | AWS FedRAMP Package |
| MA-4 | Nonlocal Maintenance | Fully Inherited | AWS FedRAMP Package |
| MA-5 | Maintenance Personnel | Fully Inherited | AWS FedRAMP Package |
| MA-6 | Timely Maintenance | Fully Inherited | AWS FedRAMP Package |

#### Azure Government Inherited Controls
| Control ID | Control Name | Implementation | Validation Evidence |
|------------|--------------|----------------|-------------------|
| MA-1 | System Maintenance Policy and Procedures | Fully Inherited | Azure FedRAMP Package |
| MA-2 | Controlled Maintenance | Fully Inherited | Azure FedRAMP Package |
| MA-3 | Maintenance Tools | Fully Inherited | Azure FedRAMP Package |
| MA-4 | Nonlocal Maintenance | Fully Inherited | Azure FedRAMP Package |
| MA-5 | Maintenance Personnel | Fully Inherited | Azure FedRAMP Package |
| MA-6 | Timely Maintenance | Fully Inherited | Azure FedRAMP Package |

## Shared Control Implementation

### Configuration Management (CM)

#### AWS GovCloud Shared Controls
| Control ID | Control Name | CSP Responsibility | Customer Responsibility |
|------------|--------------|-------------------|------------------------|
| CM-1 | Configuration Management Policy and Procedures | Infrastructure CM | Application CM |
| CM-2 | Baseline Configuration | Infrastructure Baseline | Application Baseline |
| CM-3 | Configuration Change Control | Infrastructure Changes | Application Changes |
| CM-4 | Security Impact Analysis | Platform Analysis | Application Analysis |
| CM-6 | Configuration Settings | Infrastructure Settings | Application Settings |
| CM-7 | Least Functionality | Infrastructure Services | Application Services |
| CM-8 | Information System Component Inventory | Infrastructure Inventory | Application Inventory |

#### Azure Government Shared Controls
| Control ID | Control Name | CSP Responsibility | Customer Responsibility |
|------------|--------------|-------------------|------------------------|
| CM-1 | Configuration Management Policy and Procedures | Infrastructure CM | Application CM |
| CM-2 | Baseline Configuration | Infrastructure Baseline | Application Baseline |
| CM-3 | Configuration Change Control | Infrastructure Changes | Application Changes |
| CM-4 | Security Impact Analysis | Platform Analysis | Application Analysis |
| CM-6 | Configuration Settings | Infrastructure Settings | Application Settings |
| CM-7 | Least Functionality | Infrastructure Services | Application Services |
| CM-8 | Information System Component Inventory | Infrastructure Inventory | Application Inventory |

## Validation and Documentation Requirements

### Evidence Collection
1. CSP FedRAMP Authorization Packages
   - Annual review and documentation
   - Continuous monitoring reports
   - Third-party assessment results

2. Customer Implementation Evidence
   - Configuration compliance reports
   - Security assessment results
   - Continuous monitoring data
   - Change management records

### Continuous Monitoring
1. CSP Responsibilities
   - Infrastructure security monitoring
   - Physical security monitoring
   - Environmental controls monitoring
   - Personnel security monitoring

2. Customer Responsibilities
   - Application security monitoring
   - Data security monitoring
   - Access control monitoring
   - Configuration monitoring

## Annual Review and Updates

### Review Requirements
1. Annual review of inherited controls
2. Validation of CSP compliance
3. Update of shared responsibility documentation
4. Assessment of control effectiveness

### Documentation Updates
1. Update control implementations
2. Revise responsibility matrices
3. Refresh evidence collections
4. Maintain audit trails

## References
1. FedRAMP High Security Controls Baseline
2. AWS GovCloud Security Controls
3. Azure Government Security Controls
4. NIST SP 800-53 Rev 5
5. DoD Cloud Computing SRG
