import json
import os
import logging
import boto3
import requests

# Initialize the S3 client outside of the handler
s3_client = boto3.client('s3')

# Initialize the logger
logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))


def build_daily_data_key(symbol, daily_data):
    """Build the S3 key using the oldest and newest dates in the daily series."""

    time_series = daily_data.get("Time Series (Daily)", {})
    if not time_series:
        raise ValueError("Daily data response does not contain 'Time Series (Daily)'")

    dates = sorted(time_series.keys())
    oldest_date = dates[0]
    newest_date = dates[-1]

    return f"finance_data/daily/{symbol}/{oldest_date}_to_{newest_date}.json"

def upload_finance_data_to_s3(bucket_name, key, finance_data):
    """Helper function to upload finance data to S3"""

    try:
        s3_client.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=bytes(json.dumps(finance_data).encode('UTF-8'))
        )
    except Exception as e:
        logger.error(f"Failed to upload finance data to S3: {str(e)}")
        raise

# returns last 100 days of daily data for the symbol
def get_daily_data(symbol):
    url = f'https://www.alphavantage.co/query?function=TIME_SERIES_DAILY&symbol={symbol}&outputsize=compact&apikey={os.environ.get("ALPHA_VANTAGE_API_KEY", "demo")}'
    try:
        response = requests.get(url, timeout=1)
        response.raise_for_status()  # Raise an exception for HTTP errors

    except requests.exceptions.RequestException as e:
        logger.error(f"HTTP request failed: {str(e)}")
        raise

    data = response.json()
    if 'Time Series (Daily)' not in data:
        logger.error(f"Unexpected response format: {data}")
        raise ValueError("API response does not contain 'Time Series (Daily)'")
    return data

def ingest_handler(event, context):
    """
    Main Lambda handler function
    Parameters:
        event: Dict containing the Lambda function event data
        context: Lambda runtime context
    Returns:
        Dict containing status message
    """
    try:
        # Parse the input event
        symbol = event['symbol']
        
        # Access environment variables
        bucket_name = os.environ.get('FINANCE_DATA_BUCKET')
        if not bucket_name:
            raise ValueError("Missing required environment variable FINANCE_DATA_BUCKET")

        # Create the finance data content and key destination
        daily_data = get_daily_data(symbol)

        key_daily = build_daily_data_key(symbol, daily_data)

        # Upload the finance data to S3
        upload_finance_data_to_s3(bucket_name, key_daily, daily_data)

        #logger.info(f"Successfully processed order {symbol} and stored finance data in S3 bucket {bucket_name}")
        
        return {
            "statusCode": 200,
            "message": "Finance data processed successfully"
        }

    except Exception as e:
        logger.error(f"Error processing order: {str(e)}")
        raise
