# Case Study 4 cloud deployment

This directory deploys the same API-only ResumeLens image to all three required
providers. Account identifiers are supplied as environment variables. Do not
commit credentials, access tokens, subscription secrets, or downloaded key
files.

## Common local validation

```bash
docker build -f Dockerfile.cloud -t resumelens-api:cs4 .
docker run --rm -p 8080:8080 \
  -e PRODUCT_MODE=api \
  -e APP_PORT=8080 \
  resumelens-api:cs4
```

Open <http://localhost:8080>, enter a personal Hugging Face inference token in
the password field, and submit a synthetic resume. The token is used only for
that request and is not stored in the image.

## Provider order

1. Create the provider account and a low budget with email alerts.
2. Run the provider's deployment script from the repository root.
3. Test the printed public URL from a separate browser/network.
4. Save timestamped screenshots of the budget, deployment, public URL, and a
   successful synthetic request.
5. Enter the URL in the class Google Sheet.

The scripts create billable resources. Budgets are alerts, not hard spending
caps. Remove provider resources after grading if they are no longer required.
