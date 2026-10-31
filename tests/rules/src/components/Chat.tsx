export async function ask() {
  // ruleid: sb-llm-api-in-frontend
  return fetch("https://api.openai.com/v1/chat/completions", { method: "POST" });
}
