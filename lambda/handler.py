"""
Image Resizer Lambda
--------------------
Triggered by S3 ObjectCreated events on the uploads bucket.
Resizes the image to three sizes and writes them to the outputs bucket.
"""

import io
import os
import urllib.parse
from concurrent.futures import ThreadPoolExecutor

import boto3
from PIL import Image

s3 = boto3.client("s3")

OUTPUT_BUCKET = os.environ["OUTPUT_BUCKET"]
SIZES = {
    "thumb":  int(os.environ.get("THUMBNAIL_SIZE", 150)),
    "medium": int(os.environ.get("MEDIUM_SIZE",    600)),
    "large":  int(os.environ.get("LARGE_SIZE",    1200)),
}


def _resize_and_upload(img, original_width, aspect, size_name, width, output_prefix):
    if original_width <= width:
        target_width  = original_width
        target_height = int(original_width * aspect)
    else:
        target_width  = width
        target_height = int(width * aspect)

    resized = img.resize((target_width, target_height), Image.LANCZOS)

    buffer = io.BytesIO()
    resized.save(buffer, format="JPEG", quality=85, optimize=True)
    buffer.seek(0)

    output_key = f"{output_prefix}/{size_name}.jpg"
    s3.put_object(
        Bucket=OUTPUT_BUCKET,
        Key=output_key,
        Body=buffer,
        ContentType="image/jpeg",
    )
    print(f"  ✓ Wrote {output_key} ({target_width}x{target_height})")


def lambda_handler(event, context):
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key    = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        print(f"Processing s3://{bucket}/{key}")

        response = s3.get_object(Bucket=bucket, Key=key)
        original_bytes = response["Body"].read()

        with Image.open(io.BytesIO(original_bytes)) as img:
            img = img.convert("RGB")
            original_width, original_height = img.size
            aspect = original_height / original_width

            basename = key.replace("originals/", "").rsplit(".", 1)[0]
            output_prefix = f"resized/{basename}"

            # Resize + upload the three variants in parallel. The PUTs are
            # I/O-bound, so threading meaningfully cuts total processing time
            # and shrinks the window where partial results could be visible.
            with ThreadPoolExecutor(max_workers=len(SIZES)) as pool:
                futures = [
                    pool.submit(
                        _resize_and_upload,
                        img, original_width, aspect,
                        size_name, width, output_prefix,
                    )
                    for size_name, width in SIZES.items()
                ]
                for f in futures:
                    f.result()

    return {"statusCode": 200, "body": "Resizing complete"}
