import requests

url = "https://szw0407-memoria-librosa-api-beta.hf.space/"
headers = {"Authorization": f"Bearer "}
payload = {"data": ["hello world"]}

response = requests.post(url, headers=headers, json=payload)
print(response.json())
