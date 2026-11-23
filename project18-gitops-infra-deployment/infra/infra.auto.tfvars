# Desired state of the infrastructure.
# Change values here in a pull request -> plan is posted on the PR ->
# merge to main -> approve the "production" deployment -> terraform apply.

environment             = "production"
app_version             = "1.0.0"
artifact_retention_days = 30

feature_flags = {
  new_checkout = false
  dark_mode    = true
}
