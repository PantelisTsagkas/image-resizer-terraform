# ── myApplications grouping ───────────────────────────────────────────────────
# Registers the whole stack as a single application in the myApplications
# console (AWS Service Catalog AppRegistry). This gives one pane for the app's
# cost, CloudWatch metrics, and security findings across every resource below.
#
# The application object, its Resource Group, and the dashboard are free. The
# dashboard's widgets read from Cost Explorer, CloudWatch, and Security Hub;
# only Security Hub would incur charges, and it is not enabled here.
#
# Resources join the application by carrying its `awsApplication` tag. Rather
# than tag out-of-band (which the next `terraform apply` would strip as drift),
# `local.app_tags` is merged into each billable resource's `tags` block, so the
# association is owned by this config and stays drift-free.
resource "aws_servicecatalogappregistry_application" "image_resizer" {
  name        = var.project_name
  description = "Serverless, event-driven image processing pipeline: presigned S3 upload -> resizer Lambda (thumb/medium/large) -> outputs bucket, fronted by an HTTP API Lambda."

  tags = {
    Project = var.project_name
  }
}

locals {
  # Tag that associates a resource with the application. Merge into each
  # billable resource's `tags` to make it appear in myApplications.
  app_tags = aws_servicecatalogappregistry_application.image_resizer.application_tag
}
