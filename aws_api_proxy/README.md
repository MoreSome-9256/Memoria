# Memoria AWS API Proxy

This folder contains a small Cognito-protected AWS Lambda proxy for APIs that
must not expose tokens in the Flutter app.

## Goal

The app should stop shipping provider tokens such as:

- `AMAP_WEB_KEY`
- `LLM_API_KEY`
- `REPLICATE_API_TOKEN`

Instead, the app sends its Cognito ID token to API Gateway. API Gateway verifies
the token against the Cognito User Pool, then Lambda forwards only approved
routes and injects provider credentials from server-side configuration.

## Shape

```text
Flutter app
  -> Authorization: Bearer <Cognito ID token>
  -> API Gateway HTTP API with JWT authorizer
  -> Lambda proxy
  -> approved upstream APIs only
```

Supported routes:

| App route | Upstream |
| --- | --- |
| `POST /v1/llm/chat/completions` | OpenAI-compatible LLM endpoint, e.g. DeepSeek |
| `GET /v1/amap/regeo` | Amap reverse geocode |
| `GET /v1/amap/place/text` | Amap place text search |
| `POST /v1/replicate/predictions` | Replicate prediction creation |
| `GET /v1/replicate/predictions/{id}` | Replicate prediction polling |

This is intentionally not a generic URL proxy. Every route is hard-coded and
validated to avoid turning the Lambda into an open relay.

## Deploy

1. Create or reuse a Cognito User Pool and app client.
2. Copy `env.example.json` to a private values file, fill in real values.
3. Deploy with AWS CLI only:

```powershell
cd aws_api_proxy
.\scripts\deploy.ps1 -ConfigProfilePath <private-server-secret-profile.json>
```

The deployment profile is server-side only and must not be committed. It should
contain provider credentials for Secrets Manager. The app profile must contain
only `API_PROXY_BASE_URL`, Cognito ids, and non-secret runtime flags.

Or deploy with SAM if you already have it installed:

```powershell
cd aws_api_proxy
sam build
sam deploy --guided
```

Recommended SAM parameters:

```text
AwsRegion=ap-southeast-1
CognitoUserPoolId=ap-southeast-1_xxxxx
CognitoAppClientId=xxxxxxxxxxxxxxxxxxxxxxxxxx
AllowedOrigins=*
```

For production, replace `AllowedOrigins=*` with your expected origins. Mobile
apps do not rely on CORS for security, but web/debug clients do.

## Secrets

For the lowest operational complexity, set Lambda environment variables:

```text
LLM_BASE_URL=https://api.deepseek.com/v1
LLM_API_KEY=...
LLM_MODEL=deepseek-chat
AMAP_WEB_KEY=...
REPLICATE_API_TOKEN=...
```

For better operational hygiene, put a JSON secret in AWS Secrets Manager and set
`SECRET_ID`:

```json
{
  "LLM_BASE_URL": "https://api.deepseek.com/v1",
  "LLM_API_KEY": "sk-...",
  "LLM_MODEL": "deepseek-chat",
  "AMAP_WEB_KEY": "...",
  "REPLICATE_API_TOKEN": "..."
}
```

Environment variables override secret values, so emergency rotation can be done
without changing code.

## Flutter migration

Migration should be done by adding a proxy-aware cloud client in the app, then
moving each service onto it. Do not rely on provider API keys in app profile
files.

- `API_PROXY_BASE_URL=https://<api-id>.execute-api.<region>.amazonaws.com`
- `LLM_BASE_URL=https://<api-id>.execute-api.<region>.amazonaws.com/v1/llm`
- `LLM_API_PATH=/chat/completions`
- `LLM_AUTH_MODE=cognito_proxy`

Then update the app HTTP client to attach a Cognito ID token for requests to
the proxy. A starter client is provided at `flutter/api_proxy_client.dart`.
The Flutter app now uses `LLM_AUTH_MODE=cognito_proxy` and sends Cognito ID
tokens to the proxy. Provider keys must stay only in Lambda configuration or
Secrets Manager.

For Amap and Replicate, prefer replacing direct calls with the proxy client:

- `GET /v1/amap/regeo?location=lon,lat&extensions=base&coordsys=gps`
- `GET /v1/amap/place/text?keywords=...&city=...`
- `POST /v1/replicate/predictions`
- `GET /v1/replicate/predictions/{id}`

## Security Notes

- Do not expose a route that accepts arbitrary upstream URLs.
- Do not return provider keys to the app.
- Keep request/response payload size bounded. API Gateway and Lambda are not
  suitable for large media uploads.
- Add WAF or usage plans later if public abuse becomes a concern.
- Use provider-side spending limits. Cognito authentication is not a billing
  guard by itself.
