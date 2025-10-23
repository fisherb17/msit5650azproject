#!/bin/bash
set -e

apt update -y
apt install -y python3 python3-pip
pip3 install flask azure-storage-blob

mkdir -p /var/www/html
cd /var/www/html

# flask app
cat << 'EOF' > /var/www/html/upload_app.py
from flask import Flask, request, render_template_string
from azure.storage.blob import BlobServiceClient
import os

app = Flask(__name__)

AZURE_CONNECTION_STRING = os.getenv("AZURE_STORAGE_CONNECTION_STRING")
if not AZURE_CONNECTION_STRING:
    raise ValueError("Azure Storage connection string not found in environment variables.")

CONTAINER_NAME = "uploads"
blob_service_client = BlobServiceClient.from_connection_string(AZURE_CONNECTION_STRING)

HTML = """
<!doctype html>
<title>File Upload</title>
<h1>Upload a file to Azure Blob Storage</h1>
<form method=post enctype=multipart/form-data>
  <input type=file name=file>
  <input type=submit value=Upload>
</form>
{{ message }}
"""

@app.route("/", methods=["GET", "POST"])
def upload_file():
    message = ""
    if request.method == "POST":
        f = request.files["file"]
        if f:
            blob_client = blob_service_client.get_blob_client(container=CONTAINER_NAME, blob=f.filename)
            blob_client.upload_blob(f, overwrite=True)
            message = f"<p>Successfully uploaded '{f.filename}'!</p>"
    return render_template_string(HTML, message=message)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF

# azure Storage connection string dynamically set
storage_connection_string=$1
echo "AZURE_STORAGE_CONNECTION_STRING=${storage_connection_string}" >> /etc/environment


# systemd service for the Flask app
cat << 'EOF' > /etc/systemd/system/uploadapp.service
[Unit]
Description=Flask Upload App
After=network.target

[Service]
User=root
WorkingDirectory=/var/www/html
EnvironmentFile=-/etc/environment
ExecStart=/usr/bin/python3 /var/www/html/upload_app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# reload systemd and enable service
systemctl daemon-reload
systemctl enable uploadapp
systemctl start uploadapp

echo "Flask upload app setup complete and running on port 8080."
