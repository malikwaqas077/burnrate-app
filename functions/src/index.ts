import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import Anthropic from "@anthropic-ai/sdk";

admin.initializeApp();

const MODEL = "claude-haiku-4-5-20251001";
const MAX_HISTORY = 12;
const MAX_PROMPT_CHARS = 18000;

function setCorsHeaders(res: functions.Response): void {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
}

async function verifyAuth(req: functions.Request): Promise<string> {
  const authHeader = req.headers.authorization ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Missing bearer token."
    );
  }
  const token = authHeader.slice(7);
  const decoded = await admin.auth().verifyIdToken(token);
  return decoded.uid;
}

function safeHistory(input: unknown): Array<{ role: string; content: string }> {
  if (!Array.isArray(input)) return [];
  return input
    .slice(-MAX_HISTORY)
    .map((item) => {
      const row = item as Record<string, unknown>;
      const role = row.role === "assistant" ? "assistant" : "user";
      const content = String(row.content ?? "").trim();
      return { role, content };
    })
    .filter((m) => m.content.length > 0);
}

function buildUserPrompt(args: {
  message: string;
  financialContext: Record<string, unknown>;
  history: Array<{ role: string; content: string }>;
  deepInsights: boolean;
}): string {
  const historyText =
    args.history.length === 0
      ? "No previous chat yet."
      : args.history
          .map((m) => `${m.role === "assistant" ? "Advisor" : "User"}: ${m.content}`)
          .join("\n");

  const contextText =
    Object.keys(args.financialContext).length === 0
      ? "No financial snapshot available."
      : JSON.stringify(args.financialContext, null, 2);

  const raw = [
    `Insight mode: ${args.deepInsights ? "Deep" : "Standard"}`,
    "",
    "Recent conversation:",
    historyText,
    "",
    "Latest user question:",
    args.message.trim(),
    "",
    "User financial snapshot:",
    contextText,
  ].join("\n");

  return raw.length > MAX_PROMPT_CHARS ? raw.slice(0, MAX_PROMPT_CHARS) : raw;
}

export const onlineCoachChat = functions
  .runWith({ secrets: ["ANTHROPIC_API_KEY"], timeoutSeconds: 60, memory: "1GB" })
  .https.onRequest(async (req, res) => {
    setCorsHeaders(res);
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed." });
      return;
    }

    try {
      await verifyAuth(req);

      const {
        message,
        history,
        financialContext,
        deepInsights,
      } = req.body as {
        message?: string;
        history?: unknown;
        financialContext?: unknown;
        deepInsights?: boolean;
      };

      const safeMessage = String(message ?? "").trim();
      if (safeMessage.length === 0) {
        res.status(400).json({ error: "Message is required." });
        return;
      }

      const apiKey = process.env.ANTHROPIC_API_KEY;
      if (!apiKey) {
        functions.logger.error("ANTHROPIC_API_KEY is not configured.");
        res.status(500).json({ error: "AI service not configured." });
        return;
      }

      const parsedHistory = safeHistory(history);
      const parsedContext =
        financialContext && typeof financialContext === "object"
          ? (financialContext as Record<string, unknown>)
          : {};

      const systemPrompt = `You are BurnRate AI, a friendly personal finance advisor.

Primary goals:
- Explain burn rate and spending patterns clearly.
- Suggest practical, low-effort actions to improve cash flow.
- Use the provided data directly and cite specific values.
- Keep tone encouraging and non-judgmental.
- Use GBP (£) for currency.

Safety boundaries:
- Do not recommend specific investment products, stocks, or funds.
- Do not give legally binding tax, legal, or regulatory advice.
- For complex decisions, recommend consulting a licensed professional.
- Stay focused on budgeting, spending analysis, and burn rate planning.

Response style:
- Keep response concise and structured (short paragraphs or bullets).
- Prefer insights tied to trends, anomalies, and recurring costs when available.`;

      const userPrompt = buildUserPrompt({
        message: safeMessage,
        history: parsedHistory,
        financialContext: parsedContext,
        deepInsights: deepInsights === true,
      });

      const anthropic = new Anthropic({ apiKey });
      const aiResponse = await anthropic.messages.create({
        model: MODEL,
        max_tokens: 650,
        system: systemPrompt,
        messages: [{ role: "user", content: userPrompt }],
      });

      const text =
        aiResponse.content[0]?.type === "text"
          ? aiResponse.content[0].text.trim()
          : "";
      if (!text) {
        res.status(502).json({ error: "Empty response from AI provider." });
        return;
      }

      res.status(200).json({ text, provider: "claude", model: MODEL });
    } catch (error) {
      functions.logger.error("onlineCoachChat error:", error);
      res.status(500).json({ error: "Failed to generate online advisor reply." });
    }
  });
