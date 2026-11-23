// Coffee Shop App, delete-account edge function, Sprint 6 (Story S14).
// Deletes the calling user's auth account. Their rows (visits, Want To
// Go, companions, settings) cascade from auth.users, so deleting the
// user deletes the data; this function also removes their photos from
// the visit-photos bucket first, since storage does not cascade.
//
// The app calls this only after it has already deleted the remote rows
// itself, so if this function is not deployed yet the app fails the
// deletion and keeps the local log, instead of leaving the user with no
// copy at all. Deploy with: supabase functions deploy delete-account
//
// Auth: the caller passes their own access token as the Authorization
// header. The function verifies the token, then uses the service role
// key (server side only, never in the app) to delete the user. A caller
// can only ever delete their own account.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(
      JSON.stringify({ error: "Server is not configured." }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(
      JSON.stringify({ error: "Missing authorization." }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Verify the caller's token and learn who they are. The token, not
  // any request body, decides whose account is deleted.
  const { data: userData, error: userError } = await supabase.auth.getUser(
    authHeader.replace("Bearer ", ""),
  );
  if (userError || !userData.user) {
    return new Response(
      JSON.stringify({ error: "Session is not valid." }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
  const userId = userData.user.id;

  // Photos first: list the owner's folder and remove every object.
  // Storage does not cascade, so this step is what makes the deletion
  // complete. A failure here stops the deletion; the user keeps their
  // local log and can try again.
  const { data: files, error: listError } = await supabase.storage
    .from("visit-photos")
    .list(userId, { limit: 1000 });
  if (listError) {
    return new Response(
      JSON.stringify({ error: "Could not list visit photos." }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
  if (files && files.length > 0) {
    const paths = files.map((file) => `${userId}/${file.name}`);
    const { error: removeError } = await supabase.storage
      .from("visit-photos")
      .remove(paths);
    if (removeError) {
      return new Response(
        JSON.stringify({ error: "Could not delete visit photos." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
  }

  // The auth user goes last. Visits, Want To Go, companions, and
  // settings cascade from auth.users (see schema-user-data.sql), so
  // this one call finishes the deletion.
  const { error: deleteError } = await supabase.auth.admin.deleteUser(userId);
  if (deleteError) {
    return new Response(
      JSON.stringify({ error: "Could not delete the account." }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  return new Response(
    JSON.stringify({ deleted: true }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
