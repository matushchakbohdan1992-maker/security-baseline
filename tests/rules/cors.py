from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
app = FastAPI()
# ruleid: sb-cors-wildcard-with-credentials
app.add_middleware(CORSMiddleware, allow_credentials=True, allow_origins=["*"], allow_methods=["*"])
# ok: sb-cors-wildcard-with-credentials
app.add_middleware(CORSMiddleware, allow_origins=["https://example.com"], allow_credentials=True)
