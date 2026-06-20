# Flutter Migration Notes

## Dart defines after proxy deployment

Use the proxy for LLM requests without storing provider tokens:

```json
{
  "API_PROXY_BASE_URL": "https://<api-id>.execute-api.<region>.amazonaws.com",
  "LLM_BASE_URL": "https://<api-id>.execute-api.<region>.amazonaws.com/v1/llm",
  "LLM_API_PATH": "/chat/completions",
  "LLM_AUTH_MODE": "cognito_proxy",
  "LLM_MODEL": "deepseek-chat"
}
```

The current app path uses the Cognito proxy mode. The minimal safe migration
for any remaining caller is:

1. Attach Cognito ID token only when request host equals `API_PROXY_BASE_URL`.
2. Route LLM calls to `/v1/llm/chat/completions`.
3. Replace any remaining Amap direct URLs with:
   - `/v1/amap/regeo`
   - `/v1/amap/place/text`
4. Replace any remaining Replicate calls with:
   - `/v1/replicate/predictions`
   - `/v1/replicate/predictions/{id}`

Do not create a client-side endpoint that requests raw provider tokens. A
short-lived app-specific token broker is possible later, but the proxy is safer
and smaller for the current app.
