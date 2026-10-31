import OpenAI from "openai";
const client = new OpenAI();
export async function bad(q: string) {
  // ruleid: sb-llm-call-without-max-tokens-js
  return client.chat.completions.create({ model: "m", messages: [{ role: "user", content: q }] });
}
export async function ok(q: string) {
  // ok: sb-llm-call-without-max-tokens-js
  return client.chat.completions.create({ model: "m", messages: [], max_tokens: 200 });
}
