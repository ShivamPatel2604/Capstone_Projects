# Project 10: Internal DNS Setup

## Objective
Configure an internal DNS server to access a web application using a hostname instead of an IP address.

## Environment
- Operating System: Windows Server
- DNS Server: AZ-LKM-JAV-01
- DNS Server IP: 10.5.3.141
- DNS Zone: shivam.local
- Web Server: IIS (Internet Information Services)

## Implementation

### 1. DNS Server Configuration
- Opened DNS Manager.
- Used the existing Forward Lookup Zone: `shivam.local`.
- Verified the DNS server configuration.

### 2. IIS Installation
- Installed the Web Server (IIS) role using Server Manager.
- Verified IIS by accessing `http://localhost`.
- Confirmed that the IIS Welcome page loaded successfully.

### 3. DNS A Record Creation
Created the following Host (A) record:

| Property | Value |
|---|---|
| Record Name | app |
| Fully Qualified Domain Name | app.shivam.local |
| Record Type | A |
| IP Address | 10.5.3.141 |

### 4. Hostname Verification
Accessed the website using:

`http://app.shivam.local`

The IIS Welcome page loaded successfully.

### 5. DNS Lookup Verification

Command executed:

`nslookup app.shivam.local`

Result:

- Hostname: app.shivam.local
- Resolved IP: 10.5.3.141

DNS resolution was successful.

## Outcome
Successfully configured internal DNS resolution and accessed the IIS-hosted website using a custom hostname.

## Evidence
See the screenshots in the `screenshots/` directory.
