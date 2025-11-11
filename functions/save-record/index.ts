// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

Deno.serve(async (req: any) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: corsHeaders,
    });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Missing Supabase environment variables");
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401,
        headers: corsHeaders,
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });

    const body = await req.json();
    const { userId, record } = body ?? {};
    if (!userId || !record) {
      return new Response(JSON.stringify({ error: "Invalid payload" }), {
        status: 422,
        headers: corsHeaders,
      });
    }

    // 检查是否已存在相同的占卜记录（通过 original_key, changed_key, user_id 判断）
    const { data: existingRecord } = await supabase
      .from("divination_records")
      .select("id")
      .eq("user_id", userId)
      .eq("original_key", record.original_key)
      .eq("changed_key", record.changed_key)
      .maybeSingle();

    if (existingRecord) {
      // 记录已存在，返回错误提示
      return new Response(JSON.stringify({ 
        error: "该占卜记录已保存过，不能重复保存",
        existingId: existingRecord.id,
        isDuplicate: true
      }), {
        status: 409, // Conflict
        headers: corsHeaders,
      });
    }

    const { data, error } = await supabase
      .from("divination_records")
      .insert({
        user_id: userId,
        question: record.question ?? null,
        divination_time: record.divination_time ?? new Date().toISOString(),
        method: record.method ?? 0,
        lines: record.lines,
        changing_flags: record.changing_flags,
        original_key: record.original_key,
        changed_key: record.changed_key,
        original_json: record.original_json,
        changed_json: record.changed_json,
      })
      .select()
      .single();

    if (error) {
      console.error("save-record error", error);
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: corsHeaders,
      });
    }

    return new Response(JSON.stringify({ data }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("save-record unexpected error", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});