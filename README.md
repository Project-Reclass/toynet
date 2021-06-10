This is to allow anyone to quickly provision the infrastructure on which toynet lives

This infrastructure is built on AWS you must have a vaild AWS_ACCESS_KEY_ID and AWS_SECRET_KEY 
in order to run to build this properly. 

The Infrastructure depends on the an S3 bucket that must be created first

From your desired deployment state execute `cd backend`

The simplest way to do this is to `cd backend` and run the .tf file there

Then `cd ../` and `terraform apply toynet-deployment-*.tf`


