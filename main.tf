provider "aws" {
  region = "us-east-1"
}

# 1. Source S3 Bucket
resource "aws_s3_bucket" "source_bucket" {
  bucket = "ayman-image-processor-source-2026" # غير الاسم ليكون فريداً
}

# 2. Destination S3 Bucket
resource "aws_s3_bucket" "destination_bucket" {
  bucket = "ayman-image-processor-dist-2026" # غير الاسم ليكون فريداً
}

# 3. DynamoDB Table for Metadata
resource "aws_dynamodb_table" "image_metadata" {
  name           = "ImageMetadata"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "image_id"

  attribute {
    name = "image_id"
    type = "S"
  }
}

# 4. IAM Role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "image_processor_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# 5. IAM Policy for S3 and DynamoDB Access
resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_processor_policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:GetObject", "s3:PutObject"]
        Effect   = "Allow"
        Resource = ["${aws_s3_bucket.source_bucket.arn}/*", "${aws_s3_bucket.destination_bucket.arn}/*"]
      },
      {
        Action   = ["dynamodb:PutItem"]
        Effect   = "Allow"
        Resource = [aws_dynamodb_table.image_metadata.arn]
      },
      {
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# 6. Lambda Function
resource "aws_lambda_function" "image_processor" {
  filename      = "lambda_function.zip"
  function_name = "ImageProcessor"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"

  environment {
    variables = {
      DESTINATION_S3_BUCKET = aws_s3_bucket.destination_bucket.bucket
      DYNAMODB_TABLE_NAME   = aws_dynamodb_table.image_metadata.name
    }
  }
}

# 7. S3 Bucket Notification (Trigger)
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.source_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_processor.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# 8. Allow S3 to Invoke Lambda
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.source_bucket.arn
}
