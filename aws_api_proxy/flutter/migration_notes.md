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

The existing `LLMService` still treats `LLM_API_KEY` as the provider-token
configuration flag. Do not set `LLM_API_KEY` to an empty string and expect the
old path to work. The minimal safe migration is:

1. Add `LLM_AUTH_MODE=cognito_proxy` support to `LLMService.isConfigured`.
2. Attach Cognito ID token only when request host equals `API_PROXY_BASE_URL`.
3. Route `LLMService` to `/v1/llm/chat/completions`.
4. Replace `AmapGeoService` direct URLs with:
   - `/v1/amap/regeo`
   - `/v1/amap/place/text`
5. Replace `MusicGenService` direct Replicate calls with:
   - `/v1/replicate/predictions`
   - `/v1/replicate/predictions/{id}`

Do not create a client-side endpoint that requests raw provider tokens. A
short-lived app-specific token broker is possible later, but the proxy is safer
and smaller for the current app.
