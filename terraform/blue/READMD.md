This is to allow anyone to quickly provision the infrastructure on which toynet lives

The Infrastructure depends on the an S3 bucket that must be created first

The simplest way to do this is to `cd backend` and run the .tf file there

Then `cd ../` and `terraform apply toynet-deployment-*.tf`
