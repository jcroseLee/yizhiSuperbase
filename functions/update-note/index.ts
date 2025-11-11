import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Only allow POST requests
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      { status: 405, headers: corsHeaders }
    );
  }

  try {
    // Get environment variables
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Missing Supabase environment variables");
    }

    // Get authorization header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: corsHeaders }
      );
    }

    // Create Supabase client with service role key for admin operations
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);

    // Verify the user's token
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired token" }),
        { status: 401, headers: corsHeaders }
      );
    }

    // Parse request body
    const { userId, recordId, note } = await req.json();

    // Validate input
    if (!userId || !recordId) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: userId and recordId" }),
        { status: 422, headers: corsHeaders }
      );
    }

    // Verify that the userId matches the authenticated user
    if (userId !== user.id) {
      return new Response(
        JSON.stringify({ error: "Unauthorized: userId does not match authenticated user" }),
        { status: 403, headers: corsHeaders }
      );
    }

    // Update the note in the database
    const { data, error } = await supabaseAdmin
      .from("divination_records")
      .update({ note: note || null })
      .eq("id", recordId)
      .eq("user_id", userId) // Ensure the record belongs to the user
      .select()
      .single();

    if (error) {
      console.error("Database error:", error);
      return new Response(
        JSON.stringify({ error: error.message || "Failed to update note" }),
        { status: 500, headers: corsHeaders }
      );
    }

    if (!data) {
      return new Response(
        JSON.stringify({ error: "Record not found or access denied" }),
        { status: 404, headers: corsHeaders }
      );
    }

    // Return success response
    return new Response(
      JSON.stringify({ data }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Error in update-note function:", error);
    return new Response(
      JSON.stringify({ error: error.message || "Internal server error" }),
      { status: 500, headers: corsHeaders }
    );
  }
});

