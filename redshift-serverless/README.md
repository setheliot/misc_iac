# Redshift Serverless Terraform Configuration

This project provides a Terraform configuration to deploy Amazon Redshift Serverless resources.

## Prerequisites

- Terraform installed (version 1.3 or higher)
- AWS account with necessary permissions to create Redshift Serverless resources
- AWS CLI configured with appropriate credentials

## Project Structure

- `main.tf`: Contains the main configuration for deploying Redshift Serverless resources.
- `variables.tf`: Defines input variables for the Terraform configuration.
- `outputs.tf`: Specifies the outputs of the Terraform configuration.
- `versions.tf`: Specifies the required Terraform and provider versions.
- `README.md`: Documentation for the project.

## Deployment Instructions

1. Clone the repository or download the project files.
2. Navigate to the `redshift-serverless` directory.
3. Initialize Terraform:

   ```
   terraform init
   ```

4. Review the configuration and make any necessary changes to `variables.tf`.
5. Plan the deployment:

   ```
   terraform plan
   ```

6. Apply the configuration to deploy the resources:

   ```
   terraform apply
   ```

7. After deployment, review the outputs for important information such as `namespace_id` and `workgroup_id`.

## Cleanup

To remove the deployed resources, run:

```
terraform destroy
```

## License

This project is licensed under the MIT License. See the LICENSE file for more details.