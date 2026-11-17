from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_application_honors_cloud_port() -> None:
    app = (ROOT / "app.py").read_text()
    assert 'os.getenv("PORT", os.getenv("APP_PORT", "7860"))' in app
    assert "server_port=APP_PORT" in app


def test_cloud_image_is_api_only_and_uses_one_ingress_port() -> None:
    dockerfile = (ROOT / "Dockerfile.cloud").read_text()
    requirements = (ROOT / "requirements-cloud.txt").read_text()
    assert "PRODUCT_MODE=api" in dockerfile
    assert "EXPOSE 8080" in dockerfile
    assert "requirements-cloud.txt" in dockerfile
    assert "prometheus-node-exporter" not in dockerfile
    assert "llama-cpp-python" not in requirements


def test_provider_scaffolding_has_no_embedded_credentials() -> None:
    paths = [
        ROOT / "cloud/gcp/deploy.sh",
        ROOT / "cloud/azure/deploy.sh",
        ROOT / "cloud/aws/build-and-push.sh",
        ROOT / ".github/workflows/deploy-azure.yml",
    ]
    combined = "\n".join(path.read_text() for path in paths)
    for forbidden in ("hf_", "AKIA", "client_secret=", "password="):
        assert forbidden not in combined


def test_azure_workflow_uses_cloud_dockerfile() -> None:
    workflow = (ROOT / ".github/workflows/deploy-azure.yml").read_text()
    assert "azure/container-apps-deploy-action@v1" in workflow
    assert "dockerfilePath: Dockerfile.cloud" in workflow
    assert "targetPort: 8080" in workflow
    assert "AZURE_DEPLOY_ENABLED == 'true'" in workflow
    assert "secrets.AZURE_CREDENTIALS" in workflow
