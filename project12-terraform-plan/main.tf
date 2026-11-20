terraform {
  required_version = ">= 1.4.0"
}

resource "terraform_data" "infrastructure" {
  input = {
    project     = "Project 12"
    environment = "development"
    owner       = "Shivam"
  }
}
