#!/bin/bash

dnf update -y

dnf install -y httpd

systemctl enable httpd
systemctl start httpd

cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>AWS Terraform Capstone</title>
    <style>
        body {
            font-family: Arial;
            background: #101827;
            color: white;
            text-align: center;
            padding: 100px 20px;
        }
        .container {
            background: #1e293b;
            padding: 40px;
            border-radius: 15px;
            max-width: 650px;
            margin: auto;
        }
        h1 {
            color: #38bdf8;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>AWS Cloud Infrastructure Automation</h1>
        <h2>Terraform EC2 Web Server</h2>
        <p>Successfully deployed using Infrastructure as Code!</p>
        <p>Platform: Amazon Web Services</p>
        <p>Web Server: Apache</p>
        <p>Operating System: Amazon Linux 2023</p>
        <p>Region: US East (Ohio) - us-east-2</p>
    </div>
</body>
</html>
EOF
