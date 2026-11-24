// ============================================================================
// NOTEFLOW AI — SUPABASE EDGE FUNCTION PROXY FOR GOOGLE GEMINI AI
// Function: gemini-study-assistant
// Runtime: Deno (TypeScript)
// Security:
//   1. Validates Supabase JWT (Bearer Token) via Supabase Auth
//   2. Server-side GEMINI_API_KEY stored securely in Deno.env (never exposed to client)
//   3. Enforces user rate limits (max 30 requests/min per user)
//   4. Enforces strict input validation & size limits to prevent token exhaustion
//   5. Sanitizes all upstream error messages before returning to client
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ----------------------------------------------------------------------------
// Rate Limiter (In-Memory sliding window per user)
// ----------------------------------------------------------------------------
interface RateLimitBucket {
  count: number;
  resetAt: number;
}
const rateLimits = new Map<string, RateLimitBucket>();
const RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute
const MAX_REQUESTS_PER_WINDOW = 30;

function checkRateLimit(userId: string): { allowed: boolean; remaining: number } {
  const now = Date.now();
  const bucket = rateLimits.get(userId);

  if (!bucket || now > bucket.resetAt) {
    rateLimits.set(userId, { count: 1, resetAt: now + RATE_LIMIT_WINDOW_MS });
    return { allowed: true, remaining: MAX_REQUESTS_PER_WINDOW - 1 };
  }

  if (bucket.count >= MAX_REQUESTS_PER_WINDOW) {
    return { allowed: false, remaining: 0 };
  }

  bucket.count += 1;
  return { allowed: true, remaining: MAX_REQUESTS_PER_WINDOW - bucket.count };
}

// ----------------------------------------------------------------------------
// Input Size Limits
// ----------------------------------------------------------------------------
const MAX_DOCUMENT_TITLE_CHARS = 250;
const MAX_EXTRACTED_TEXT_CHARS = 30000;
const MAX_USER_PROMPT_CHARS = 2000;
const MAX_GROUNDED_CONTEXT_CHARS = 15000;
const GEMINI_MODEL = "gemini-1.5-flash";

Deno.serve(async (req: Request) => {
  // 1. Handle CORS Pre-flight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed. Only POST is accepted." }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  try {
    // 2. Validate Server Environment Configuration
    const geminiApiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiApiKey || geminiApiKey.trim() === "") {
      return new Response(
        JSON.stringify({
          error:
            "Server configuration error: GEMINI_API_KEY is not configured on the Supabase Edge Function environment.",
        }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    // 3. Authenticate User via Bearer JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({
          error: "Unauthorized: Missing or invalid Authorization Bearer header.",
        }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });

    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser();

    if (userError || !user) {
      return new Response(
        JSON.stringify({
          error: "Unauthorized: Invalid, expired, or revoked Supabase user token.",
        }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 4. Rate Limiting Check
    const rateCheck = checkRateLimit(user.id);
    if (!rateCheck.allowed) {
      return new Response(
        JSON.stringify({
          error:
            "Rate limit exceeded: You have reached the maximum quota of 30 requests per minute. Please try again shortly.",
        }),
        {
          status: 429,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
            "Retry-After": "60",
          },
        }
      );
    }

    // 5. Parse and Validate Request Payload
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return new Response(
        JSON.stringify({ error: "Invalid JSON request body." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const action = String(body.action || "").trim();

    // ------------------------------------------------------------------------
    // Action A: generate_study_content (OCR -> Structured Study Set)
    // ------------------------------------------------------------------------
    if (action === "generate_study_content") {
      const documentTitle = String(body.documentTitle || "Tài liệu học tập").trim();
      const extractedText = String(body.extractedText || "").trim();

      if (!extractedText) {
        return new Response(
          JSON.stringify({ error: "extractedText cannot be empty." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (extractedText.length > MAX_EXTRACTED_TEXT_CHARS) {
        return new Response(
          JSON.stringify({
            error: `extractedText exceeds maximum allowed length of ${MAX_EXTRACTED_TEXT_CHARS} characters.`,
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const safeTitle =
        documentTitle.length > MAX_DOCUMENT_TITLE_CHARS
          ? documentTitle.substring(0, MAX_DOCUMENT_TITLE_CHARS)
          : documentTitle;

      const systemPrompt = `Bạn là Trợ lý Học tập AI NoteFlow chuyên gia Sư phạm & Khoa học Máy tính - Đại học VKU.
Nhiệm vụ: Phân tích bài giảng "${safeTitle}" và trích xuất thành bộ học liệu chuẩn:
1. Bản tóm tắt học thuật Markdown (tiêu đề, ý chính).
2. Danh sách 3-10 Flashcard SM-2 (front, back, hint).
3. Danh sách 2-5 câu hỏi trắc nghiệm 4 lựa chọn (question, options, correct_index, explanation).
BẮT BUỘC trả về đúng định dạng JSON object với 3 trường: "summary", "flashcards", "quiz".`;

      const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${geminiApiKey}`;

      const geminiPayload = {
        contents: [
          {
            role: "user",
            parts: [
              {
                text: `${systemPrompt}\n\nNỘI DUNG VĂN BẢN TRÍCH XUẤT TỪ OCR:\n${extractedText}`,
              },
            ],
          },
        ],
        generationConfig: {
          responseMimeType: "application/json",
          temperature: 0.2,
          topP: 0.8,
          maxOutputTokens: 4096,
        },
      };

      const upstreamRes = await fetch(geminiUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(geminiPayload),
      });

      if (!upstreamRes.ok) {
        const errorText = await upstreamRes.text();
        console.error("Gemini Upstream Error (Generate):", errorText);
        return new Response(
          JSON.stringify({
            error: "Google Gemini AI service temporarily failed to process the document. Please try again.",
          }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const geminiData = await upstreamRes.json();
      const rawJsonText =
        geminiData?.candidates?.[0]?.content?.parts?.[0]?.text || "{}";

      let parsedStudyContent: Record<string, unknown>;
      try {
        parsedStudyContent = JSON.parse(rawJsonText);
      } catch {
        return new Response(
          JSON.stringify({ error: "Failed to parse structured JSON from AI output." }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({
          success: true,
          data: parsedStudyContent,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ------------------------------------------------------------------------
    // Action B: ask_assistant (Grounded AI Study Assistant)
    // ------------------------------------------------------------------------
    if (action === "ask_assistant") {
      const userPrompt = String(body.userPrompt || "").trim();
      const groundedContext = String(body.groundedContext || "").trim();
      const history = Array.isArray(body.history) ? body.history : [];

      if (!userPrompt) {
        return new Response(
          JSON.stringify({ error: "userPrompt cannot be empty." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (userPrompt.length > MAX_USER_PROMPT_CHARS) {
        return new Response(
          JSON.stringify({
            error: `userPrompt exceeds maximum allowed length of ${MAX_USER_PROMPT_CHARS} characters.`,
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const boundedContext =
        groundedContext.length > MAX_GROUNDED_CONTEXT_CHARS
          ? groundedContext.substring(0, MAX_GROUNDED_CONTEXT_CHARS) + "\n\n[...Trích đoạn rút gọn...]"
          : groundedContext;

      const systemInstruction = `Bạn là Trợ lý Học tập AI NoteFlow (Đại học VKU).
NGUYÊN TẮC:
1. Bạn PHẢI trả lời dựa trên học liệu được cung cấp (Grounded Context).
2. Hãy trích dẫn cụ thể căn cứ trong câu trả lời (ví dụ: [Căn cứ: Thẻ ghi nhớ 2] hoặc [Căn cứ: Bản tóm tắt bài giảng]).
3. Nếu câu hỏi nằm ngoài tài liệu, lịch sự thông báo cho sinh viên biết nội dung này không có trong tài liệu bài giảng. Không bịa đặt kiến thức.
4. Trả lời bằng Markdown rõ ràng, thân thiện.
5. Cuối câu trả lời, hãy gợi ý 2 câu hỏi tiếp nối trong ngoặc nhọn dạng: {{Gợi ý: ...}}`;

      const contents = [
        {
          role: "user",
          parts: [{ text: `NGỮ CẢNH HỌC LIỆU ĐƯỢC CUNG CẤP:\n${boundedContext}` }],
        },
      ];

      // Add last 6 turns from history
      const recentHistory = history.slice(-6);
      for (const h of recentHistory) {
        const role = h.isUser ? "user" : "model";
        const content = String(h.content || "");
        if (content) {
          contents.push({
            role: role,
            parts: [{ text: content }],
          });
        }
      }

      // Add current question
      contents.push({
        role: "user",
        parts: [{ text: userPrompt }],
      });

      const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${geminiApiKey}`;

      const geminiPayload = {
        systemInstruction: {
          parts: [{ text: systemInstruction }],
        },
        contents: contents,
        generationConfig: {
          temperature: 0.3,
          topP: 0.85,
          maxOutputTokens: 2048,
        },
      };

      const upstreamRes = await fetch(geminiUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(geminiPayload),
      });

      if (!upstreamRes.ok) {
        const errorText = await upstreamRes.text();
        console.error("Gemini Upstream Error (Ask):", errorText);
        return new Response(
          JSON.stringify({
            error: "Gemini AI was unable to generate an answer at this time.",
          }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const geminiData = await upstreamRes.json();
      const replyText =
        geminiData?.candidates?.[0]?.content?.parts?.[0]?.text ||
        "Xin lỗi, tôi không thể tìm thấy câu trả lời phù hợp trong tài liệu của bạn.";

      return new Response(
        JSON.stringify({
          success: true,
          reply: replyText,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        error: `Unknown action: "${action}". Supported actions: "generate_study_content", "ask_assistant".`,
      }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    console.error("Unhandled Edge Function Exception:", errorMsg);
    // Sanitize any key leaking in message
    const cleanMsg = errorMsg
      .replace(/AIza[0-9A-Za-z-_]{35}/g, "[REDACTED_KEY]")
      .replace(/key=[0-9A-Za-z-_]+/g, "key=[REDACTED]");

    return new Response(
      JSON.stringify({
        error: "Internal server error occurred while processing AI request.",
        details: cleanMsg,
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
