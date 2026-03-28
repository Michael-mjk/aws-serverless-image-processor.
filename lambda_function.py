import os
import uuid
import json
import boto3
import io
from PIL import Image

s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('DYNAMODB_TABLE_NAME', 'ImageMetadata')
table = dynamodb.Table(table_name)

def resize_image(image_content, size=(128, 128)):
    with Image.open(io.BytesIO(image_content)) as image:
        image.thumbnail(size)
        buffer = io.BytesIO()
        image.save(buffer, format=image.format)
        buffer.seek(0)
        return buffer

def lambda_handler(event, context):
    print(f"Received event: {json.dumps(event)}")
    
    for record in event['Records']:
        bucket_name = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        
        try:
            response = s3_client.get_object(Bucket=bucket_name, Key=key)
            image_content = response['Body'].read()
            
            resized_image_buffer = resize_image(image_content)
            
            destination_bucket_name = os.environ.get('DESTINATION_S3_BUCKET')
            if not destination_bucket_name:
                raise ValueError("DESTINATION_S3_BUCKET environment variable is missing")
            
            processed_key = f'processed/{key}'
            s3_client.upload_fileobj(resized_image_buffer, destination_bucket_name, processed_key)
            
            table.put_item(
                Item={
                    'image_id': str(uuid.uuid4()),
                    'original_key': key,
                    'original_bucket': bucket_name,
                    'processed_key': processed_key,
                    'processed_bucket': destination_bucket_name,
                    'status': 'processed',
                    'timestamp': boto3.util.current_time_millis()
                }
            )
            print(f"Successfully processed {key}")
            
        except Exception as e:
            print(f"Error processing {key}: {e}")
            raise e
            
    return {'statusCode': 200, 'body': 'Images processed successfully'}
