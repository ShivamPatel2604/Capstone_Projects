# Project 9: Domain Controller Setup

## Overview
Configured a Windows Server as an Active Directory Domain Controller to practice centralized authentication and user management.

## Objectives
- Install Active Directory Domain Services (AD DS).
- Configure a new Active Directory forest.
- Promote Windows Server to Domain Controller.
- Create and manage domain users.
- Verify domain user accounts.

## Environment
- Operating System: Windows Server
- Server IP: `10.5.3.141`
- Server Name: `AZ-LKM-JAV-01`
- Domain Name: `shivam.local`
- DNS: Installed with AD DS

## Implementation

1. Installed Active Directory Domain Services.
2. Configured a new forest named `shivam.local`.
3. Promoted the server to Domain Controller.
4. Installed and configured DNS.
5. Created two domain users:
   - `shivam.admin`
   - `shivam.user`
6. Verified both accounts using PowerShell `Get-ADUser`.

## Technologies Used
- Windows Server
- Active Directory Domain Services
- DNS
- PowerShell

## Deliverables
- AD DS installation screenshot
- Domain Controller configuration screenshot
- Active Directory Users and Computers screenshot
- PowerShell user verification screenshot
- Domain authentication proof screenshots

## Outcome
Successfully configured an Active Directory Domain Controller and created two enabled domain user accounts for authentication practice.
