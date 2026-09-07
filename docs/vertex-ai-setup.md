# Vertex AI Setup on Ubuntu VM

Guide for configuring Google Cloud Vertex AI on your ITUP Ubuntu VM.

---

## Prerequisites

1. Ubuntu VM running on ITUP (see main [README.md](../README.md))
2. Google Cloud project with Vertex AI API enabled
3. SSH access to your VM
4. Service account with appropriate Vertex AI permissions

---

## Step 1 — Install Google Cloud SDK

SSH into your VM:

```bash
virtctl -n "${NAMESPACE}" ssh ubuntu@vmi/ubuntu-noble-vm \
  --identity-file="$HOME/.ssh/id_rsa" \
  --local-ssh-opts="-o IdentitiesOnly=yes"
```

Install the Google Cloud SDK:

```bash
# Add Google Cloud SDK repository
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates gnupg curl

# Add Google Cloud public key
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg

# Add the gcloud CLI repository
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
  sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

# Update and install gcloud
sudo apt-get update
sudo apt-get install -y google-cloud-cli
```

Verify installation:

```bash
gcloud version
```

---

## Step 2 — Authenticate with Service Account

### Option A: Using Service Account Key File

If you have a service account JSON key file:

1. Copy the key file to your VM (from your local machine):

```bash
# On your local machine
scp /path/to/service-account-key.json \
  ubuntu@itup-ubuntu-noble-vm:/home/ubuntu/gcp-key.json
```

2. On the VM, authenticate:

```bash
gcloud auth activate-service-account \
  --key-file=/home/ubuntu/gcp-key.json

# Set default project
gcloud config set project YOUR_PROJECT_ID
```

### Option B: Using Workload Identity (if available)

If your ITUP cluster is configured with Workload Identity:

```bash
# This requires additional cluster configuration
# Contact your ITUP admin for setup
```

---

## Step 3 — Install Python and Vertex AI SDK

Install Python 3 and pip (if not already installed):

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv
```

Create a virtual environment:

```bash
mkdir -p ~/vertex-ai-workspace
cd ~/vertex-ai-workspace
python3 -m venv venv
source venv/bin/activate
```

Install Vertex AI SDK:

```bash
pip install --upgrade pip
pip install google-cloud-aiplatform
pip install google-auth google-auth-oauthlib google-auth-httplib2
```

---

## Step 4 — Verify Vertex AI Access

Create a test script to verify access:

```bash
cat > test_vertex_ai.py <<'EOF'
#!/usr/bin/env python3
"""Test Vertex AI connectivity and authentication."""

from google.cloud import aiplatform
import sys

def test_vertex_ai_access(project_id, location="us-central1"):
    """Test Vertex AI access by listing models."""
    try:
        # Initialize Vertex AI
        aiplatform.init(project=project_id, location=location)
        
        print(f"✓ Successfully initialized Vertex AI")
        print(f"  Project: {project_id}")
        print(f"  Location: {location}")
        
        # Try to list models (will be empty if no models exist)
        models = aiplatform.Model.list(filter='labels.test:*', order_by='create_time')
        print(f"✓ Successfully queried Vertex AI")
        print(f"  Found {len(list(models))} models")
        
        return True
        
    except Exception as e:
        print(f"✗ Error accessing Vertex AI: {e}", file=sys.stderr)
        return False

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python test_vertex_ai.py PROJECT_ID [LOCATION]")
        sys.exit(1)
    
    project_id = sys.argv[1]
    location = sys.argv[2] if len(sys.argv) > 2 else "us-central1"
    
    success = test_vertex_ai_access(project_id, location)
    sys.exit(0 if success else 1)
EOF

chmod +x test_vertex_ai.py
```

Run the test:

```bash
python test_vertex_ai.py YOUR_PROJECT_ID us-central1
```

---

## Step 5 — Example: Using Vertex AI for Predictions

Create a sample script that uses Vertex AI:

```bash
cat > vertex_ai_example.py <<'EOF'
#!/usr/bin/env python3
"""Example Vertex AI usage."""

from google.cloud import aiplatform
from google.protobuf import json_format
from google.protobuf.struct_pb2 import Value

def predict_text_classification(
    project_id: str,
    endpoint_id: str,
    location: str = "us-central1",
    text_input: str = "Sample text to classify"
):
    """Make a prediction using a Vertex AI endpoint."""
    
    # Initialize Vertex AI
    aiplatform.init(project=project_id, location=location)
    
    # Get the endpoint
    endpoint = aiplatform.Endpoint(endpoint_id)
    
    # Prepare the instance
    instance = json_format.ParseDict({"content": text_input}, Value())
    instances = [instance]
    
    # Make prediction
    response = endpoint.predict(instances=instances)
    
    print("Prediction results:")
    for prediction in response.predictions:
        print(prediction)
    
    return response

if __name__ == "__main__":
    # Replace with your values
    PROJECT_ID = "your-project-id"
    ENDPOINT_ID = "your-endpoint-id"
    LOCATION = "us-central1"
    
    predict_text_classification(
        project_id=PROJECT_ID,
        endpoint_id=ENDPOINT_ID,
        location=LOCATION,
        text_input="This is a test input"
    )
EOF
```

---

## Step 6 — Configure Environment Variables

Add Vertex AI configuration to your shell profile:

```bash
cat >> ~/.bashrc <<'EOF'

# Google Cloud / Vertex AI Configuration
export GOOGLE_CLOUD_PROJECT="your-project-id"
export VERTEX_AI_LOCATION="us-central1"
export GOOGLE_APPLICATION_CREDENTIALS="/home/ubuntu/gcp-key.json"
EOF

source ~/.bashrc
```

---

## Step 7 — Install Additional ML Tools (Optional)

Install common ML libraries:

```bash
# Activate your virtual environment
source ~/vertex-ai-workspace/venv/bin/activate

# Install ML libraries
pip install \
  tensorflow \
  torch \
  transformers \
  scikit-learn \
  pandas \
  numpy \
  jupyter

# For working with Vertex AI Pipelines
pip install kfp google-cloud-pipeline-components
```

---

## Required Vertex AI Permissions

Your service account needs the following IAM roles:

| Role | Purpose |
|------|---------|
| `roles/aiplatform.user` | Use Vertex AI resources |
| `roles/aiplatform.admin` | Manage Vertex AI resources |
| `roles/storage.objectAdmin` | Access GCS buckets for model artifacts |
| `roles/bigquery.dataViewer` | Read training data from BigQuery (optional) |

Grant permissions (run from your local machine with appropriate GCP permissions):

```bash
PROJECT_ID="your-project-id"
SERVICE_ACCOUNT="your-service-account@project.iam.gserviceaccount.com"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/aiplatform.user"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/storage.objectAdmin"
```

---

## Troubleshooting

### Permission Denied Errors

```bash
# Verify service account authentication
gcloud auth list

# Check current project
gcloud config get-value project

# Test API access
gcloud ai models list --region=us-central1
```

### Network/Egress Issues

If you get connection errors, ensure the TenantEgress includes Google API domains:

```yaml
# In tenant-egress-domains.yaml
- domain: "*.googleapis.com"
  ports:
  - protocol: tcp
    port: 443
- domain: "storage.googleapis.com"
  ports:
  - protocol: tcp
    port: 443
```

Apply the updated egress rules:

```bash
oc apply -f tenant-egress-domains.yaml
```

### Package Installation Issues

```bash
# If pip install fails, try upgrading pip and setuptools
python3 -m pip install --upgrade pip setuptools wheel

# Use --no-cache-dir if you encounter cache issues
pip install --no-cache-dir google-cloud-aiplatform
```

---

## Example Vertex AI Workloads

### 1. Training a Custom Model

```python
from google.cloud import aiplatform

aiplatform.init(project='your-project-id', location='us-central1')

job = aiplatform.CustomTrainingJob(
    display_name='custom-training-job',
    script_path='train.py',
    container_uri='gcr.io/cloud-aiplatform/training/tf-cpu.2-8:latest',
    requirements=['pandas', 'scikit-learn'],
    model_serving_container_image_uri='gcr.io/cloud-aiplatform/prediction/tf2-cpu.2-8:latest',
)

model = job.run(
    dataset=my_dataset,
    replica_count=1,
    machine_type='n1-standard-4',
    training_fraction_split=0.8,
    validation_fraction_split=0.1,
    test_fraction_split=0.1,
)
```

### 2. Batch Prediction

```python
from google.cloud import aiplatform

aiplatform.init(project='your-project-id', location='us-central1')

model = aiplatform.Model('projects/PROJECT_ID/locations/LOCATION/models/MODEL_ID')

batch_prediction_job = model.batch_predict(
    job_display_name='batch-prediction-job',
    gcs_source='gs://your-bucket/input-data/*.jsonl',
    gcs_destination_prefix='gs://your-bucket/output/',
    machine_type='n1-standard-4',
    starting_replica_count=1,
    max_replica_count=5,
)

batch_prediction_job.wait()
```

### 3. Using Pre-trained Models

```python
from google.cloud import aiplatform

aiplatform.init(project='your-project-id', location='us-central1')

# Use AutoML or pre-trained models
endpoint = aiplatform.Endpoint('projects/PROJECT_ID/locations/LOCATION/endpoints/ENDPOINT_ID')

prediction = endpoint.predict(instances=[{
    "content": "Your input text here"
}])

print(prediction.predictions)
```

---

## Additional Resources

- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Vertex AI Python SDK Reference](https://cloud.google.com/python/docs/reference/aiplatform/latest)
- [Vertex AI Samples](https://github.com/GoogleCloudPlatform/vertex-ai-samples)
- [Vertex AI Pricing](https://cloud.google.com/vertex-ai/pricing)

---

## Next Steps

1. Enable required APIs in your GCP project:
   - Vertex AI API
   - Cloud Storage API
   - BigQuery API (if using BigQuery data)

2. Set up a GCS bucket for storing model artifacts:
   ```bash
   gsutil mb -l us-central1 gs://your-vertex-ai-bucket
   ```

3. Consider using Vertex AI Workbench for interactive development:
   - More integrated environment than a standard VM
   - Managed Jupyter notebooks
   - Pre-installed ML libraries
