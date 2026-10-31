import os, subprocess
from openai import OpenAI
client = OpenAI()

def bad_exec(q):
    # ruleid: sb-llm-call-without-max-tokens-py
    r = client.chat.completions.create(model="m", messages=[{"role": "user", "content": q}])
    cmd = r.choices[0].message.content
    # ruleid: sb-llm-output-to-code-execution
    os.system(cmd)

def bad_shell(q):
    r = client.chat.completions.create(model="m", messages=[], max_tokens=200)
    out = r.choices[0].message.content
    # ruleid: sb-llm-output-to-code-execution
    subprocess.run(out, shell=True)

def ok_limited(q):
    # ok: sb-llm-call-without-max-tokens-py
    r = client.chat.completions.create(model="m", messages=[], max_completion_tokens=300)
    text = r.choices[0].message.content
    # ok: sb-llm-output-to-code-execution
    subprocess.run(["echo", "done"])
    return text
