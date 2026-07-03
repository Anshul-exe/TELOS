terraform {
  backend "s3" {
    # ---------------------------------------------------------------------
    # Values below come from the outputs of terraform/bootstrap.
    # Run `terraform output` there and paste the real values in.
    #   bucket         <- state_bucket_name  (has a random suffix)
    #   dynamodb_table <- lock_table_name
    #   region         <- region
    # ---------------------------------------------------------------------
    bucket         = "telos-tfstate-23c1b86e"
    key            = "envs/dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "telos-tf-locks"
    encrypt        = true
  }
}
