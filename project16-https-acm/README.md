# Project 16: Enable HTTPS using ACM

## Objective
Secure web access to an app by putting it behind an **Application Load Balancer (ALB)** with an **HTTPS listener** that uses a certificate from **AWS Certificate Manager (ACM)**, and **block plain HTTP**.

## Setup
- Workstation: the Ubuntu 24.04 Linux VM used for previous projects (Terraform + AWS CLI + curl + openssl)
- Web server: Amazon Linux 2023 EC2 (`t3.micro`) running Apache, managed via SSM (no SSH / port 22)
- Load balancer: internet-facing ALB `shivam-project16-alb` with an **HTTPS :443 listener** (TLS terminated on the ALB)
- TLS policy: `ELBSecurityPolicy-TLS13-1-2-2021-06` (TLS 1.2 and TLS 1.3 only)
- Region: ap-south-1 (Mumbai)

## Certificate options
The ACM certificate is chosen automatically from the `domain_name` variable:

| Mode | When | Certificate | Browser |
| --- | --- | --- | --- |
| **A - Public ACM certificate** | `domain_name` set (needs a Route 53 public hosted zone) | Issued by Amazon, validated with a DNS CNAME that Terraform creates in Route 53; an alias `A` record points the domain at the ALB | Padlock, fully trusted |
| **B - Imported self-signed** (default) | `domain_name` empty | Terraform generates an RSA 2048 self-signed certificate for the ALB DNS name and **imports it into ACM** | Encrypted, but shows "Not secure / certificate not trusted" warning - click *Advanced > Proceed* |

ACM cannot issue public certificates for the `*.elb.amazonaws.com` name, which is why mode B imports a self-signed certificate.

## How HTTP is blocked
Controlled by the `http_mode` variable:

| `http_mode` | ALB security group | Port 80 listener | Result for `http://...` |
| --- | --- | --- | --- |
| `block` (default) | Only **443** open | none | Connection times out - HTTP is never served |
| `redirect` | 443 and 80 open | Redirect only (`301` to `https://`) | Browser is sent to HTTPS; content is never served over HTTP |

In both modes the web server only accepts traffic from the ALB security group, so the instance cannot be reached directly over HTTP. Apache also sends a `Strict-Transport-Security` (HSTS) header so browsers keep using HTTPS.

## Architecture
```
                      Internet
          https://<alb-dns or domain>:443      http://...:80
                      |                              |
                      v                              x  blocked (SG has no port 80)
   +------------ ALB: shivam-project16-alb (SG: 443 from 0.0.0.0/0) -------------+
   |  HTTPS :443 listener   SSL policy TLS13-1-2-2021-06                          |
   |  Certificate: ACM  (A: Amazon issued via Route 53 DNS | B: imported self-signed)
   |  TLS terminated here -> forward to target group shivam-project16-tg          |
   +--------------------------------------+---------------------------------------+
            VPC 10.16.0.0/16              | HTTP 80 inside the VPC (SG: ALB only)
   +--------------------------------------v--------------+   +---------------------------+
   | ap-south-1a public subnet 10.16.1.0/24              |   | ap-south-1b 10.16.2.0/24  |
   |  EC2 shivam-project16-web (Apache, /health, HSTS)   |   | (second ALB subnet)       |
   +-----------------------------------------------------+   +---------------------------+

   Mode A only:  Route 53  app.example.com  --alias-->  ALB
                 Route 53  _xxxx.app.example.com CNAME -> ACM DNS validation
```

## Project Structure
```
project16-https-acm/
|-- terraform/
|   |-- providers.tf             # AWS + TLS providers
|   |-- variables.tf             # Region, CIDRs, domain_name, http_mode, ssl_policy
|   |-- main.tf                  # VPC, SGs (443 only), IAM (SSM), EC2, ALB, target group,
|   |                            # ACM cert (Route 53 validated or imported self-signed),
|   |                            # HTTPS listener, optional HTTP->HTTPS redirect listener
|   |-- outputs.tf               # HTTPS/HTTP URLs, certificate ARN + mode, ACM console URL
|   `-- templates/user_data.sh   # Apache page, /health, HSTS header
`-- scripts/
    |-- show-https-config.sh     # Listeners, SG inbound rules, ACM certificate, target health
    `-- test-https.sh            # HTTPS request, certificate, TLS versions, HTTP blocked check
```

## Technologies Used
- AWS Certificate Manager (ACM)
- Elastic Load Balancing - Application Load Balancer, HTTPS listener, SSL policy
- Amazon Route 53 (mode A)
- Amazon EC2 / VPC / IAM / Security Groups / Systems Manager
- Terraform (AWS + TLS providers)
- Apache HTTP Server, Bash, curl, OpenSSL

## Implementation Steps (run on the Linux VM)

### 1. Pull the latest code and verify AWS access
```bash
cd ~/aws-terraform-capstone
git pull
aws sts get-caller-identity
```

### 2. Choose the certificate mode
- **Mode B (default, no domain):** nothing to do.
- **Mode A (own domain in Route 53):** check the hosted zone exists, then create `terraform/terraform.tfvars` (ignored by git):
  ```bash
  aws route53 list-hosted-zones --query "HostedZones[?Config.PrivateZone==\`false\`].Name" --output text
  cat > ~/aws-terraform-capstone/project16-https-acm/terraform/terraform.tfvars <<'EOF'
  domain_name      = "app.example.com"
  hosted_zone_name = "example.com"
  EOF
  ```
- Optional: add `http_mode = "redirect"` to `terraform.tfvars` to redirect HTTP to HTTPS instead of closing port 80.

### 3. Provision the infrastructure
```bash
cd ~/aws-terraform-capstone/project16-https-acm/terraform
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```
In mode A, `terraform apply` waits until ACM shows the certificate as **Issued** (usually 1-5 minutes).

Save the values for later steps:
```bash
HTTPS_URL=$(terraform output -raw https_url)
HTTP_URL=$(terraform output -raw http_url)
ALB_ARN=$(terraform output -raw alb_arn)
CERT_ARN=$(terraform output -raw certificate_arn)
chmod +x ../scripts/*.sh
```

### 4. Check the HTTPS configuration
Wait 2-3 minutes after apply (user_data installs Apache), then:
```bash
../scripts/show-https-config.sh $ALB_ARN $CERT_ARN
```
Expected:
- Listeners: only `443 HTTPS` with policy `ELBSecurityPolicy-TLS13-1-2-2021-06` forwarding to the target group (plus `80 HTTP redirect` in redirect mode)
- Security group inbound: only port `443` (plus `80` in redirect mode)
- ACM certificate: `Type AMAZON_ISSUED` + `Status ISSUED` (mode A) or `Type IMPORTED` (mode B), `InUseBy` = the ALB
- Target: `healthy`

Also open the certificate in the ACM console:
```bash
terraform output -raw acm_console_url
```

### 5. Test HTTPS and blocked HTTP
Mode A:
```bash
../scripts/test-https.sh $HTTPS_URL
```
Mode B (self-signed - skip trust check):
```bash
../scripts/test-https.sh $HTTPS_URL --self-signed
```
Expected:
1. HTTPS returns `200` over TLS 1.2/1.3, with an HSTS header
2. Certificate subject/issuer/SAN = your domain + Amazon (mode A) or the ALB DNS name, self-signed (mode B)
3. `tls1_1 rejected`, `tls1_2 accepted`, `tls1_3 accepted`
4. `PASS - HTTP blocked` (block mode) or `PASS - HTTP not served: 301 redirect to https://...` (redirect mode)

### 6. HTTPS in the browser (deliverable)
```bash
echo $HTTPS_URL
```
Open the URL in a browser:
- Mode A: the padlock shows a valid connection - click it to view the Amazon-issued certificate.
- Mode B: click **Advanced > Proceed** past the warning; click *Not secure > Certificate* to show the self-signed certificate for the ALB DNS name.

The page shows "Secure connection", the certificate mode and that plain HTTP is blocked.

Then try `$HTTP_URL` in the browser: it never loads (block mode) or jumps to `https://` (redirect mode).

## Proof Screenshots
Save the screenshots in this folder:
- `1.png` - `terraform apply` complete with outputs (step 3)
- `2.png` - `show-https-config.sh`: HTTPS listener, 443-only security group, ACM certificate, healthy target (step 4)
- `3.png` - ACM console showing the certificate and that it is in use by the ALB
- `4.png` - **Browser showing the app over `https://` with the certificate details** (deliverable)
- `5.png` - `test-https.sh` output: HTTPS 200, TLS versions, HTTP blocked (step 5)
- `6.png` - Browser/curl showing `http://` blocked (timeout) or redirected to HTTPS

## Troubleshooting
- `terraform apply` stuck on `aws_acm_certificate_validation` (mode A): the hosted zone is not the one your registrar delegates to - compare its NS records with the domain's name servers.
- `no matching Route 53 Hosted Zone found`: set `hosted_zone_name` to the zone (e.g. `example.com`) when `domain_name` is a subdomain.
- Browser `NET::ERR_CERT_AUTHORITY_INVALID` in mode B: expected for a self-signed certificate - traffic is still encrypted.
- `502` / `503` over HTTPS: the target is still starting or unhealthy - wait for user_data and check `show-https-config.sh`.
- `curl: (60) SSL certificate problem` in mode B: add `--self-signed` to the test script (`curl -k`).

## Security Notes
- TLS is terminated on the ALB; traffic from the ALB to the instance stays inside the VPC on port 80 and is restricted to the ALB security group.
- The self-signed private key (mode B) is generated by Terraform and stored in the Terraform state - fine for a lab, use mode A (Amazon-managed keys, auto-renewal) for real workloads.
- ACM public certificates in mode A renew automatically as long as the validation CNAME stays in Route 53.

## Cleanup
```bash
cd ~/aws-terraform-capstone/project16-https-acm/terraform
terraform destroy
```
The ALB is billed per hour - destroy it once the screenshots are taken. In mode A the validation and alias records are removed too; the hosted zone itself is not touched.

## Verification
- The ALB has an HTTPS listener on port 443 using an ACM certificate and a TLS 1.2+/1.3 security policy.
- The app is reachable over `https://` and the certificate is visible in the browser.
- Plain HTTP is blocked (port 80 closed) or only redirected to HTTPS - content is never served over HTTP.
- The instance is only reachable through the ALB.

## Deliverables
- HTTPS screenshot: `4.png` (plus supporting screenshots `1.png` - `3.png`, `5.png`, `6.png`)
