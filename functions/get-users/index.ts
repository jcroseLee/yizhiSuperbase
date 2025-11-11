// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

Deno.serve(async (req: any) => {
  console.log('get-users function invoked.');
  
  if (req.method === 'OPTIONS') {
    console.log('Handling OPTIONS request.');
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Get authorization header
    const authHeader = req.headers.get('authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 401 
        }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || Deno.env.get("PROJECT_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SERVICE_ROLE_KEY");
    
    if (!supabaseUrl || !serviceRoleKey) {
      console.error('Missing Supabase environment variables.');
      throw new Error('Missing Supabase environment variables.');
    }
    
    // Create admin client to access auth.users
    const supabaseAdmin = createClient(
      supabaseUrl,
      serviceRoleKey,
      {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
          detectSessionInUrl: false,
        },
      }
    );

    // Verify the requesting user is an admin
    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token);
    
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 401 
        }
      );
    }

    // Check if user is admin
    const { data: profile } = await supabaseAdmin
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .single();

    if (!profile || profile.role !== 'admin') {
      return new Response(
        JSON.stringify({ error: 'Forbidden: Admin access required' }),
        { 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 403 
        }
      );
    }

    // Get all profiles
    // Try to select with wechat_openid first, fallback if column doesn't exist
    let profiles: any[] = [];
    let profilesError: any = null;
    
    const { data: profilesWithOpenid, error: errorWithOpenid } = await supabaseAdmin
      .from('profiles')
      .select('id, nickname, avatar_url, role, wechat_openid, created_at')
      .order('created_at', { ascending: false });

    if (errorWithOpenid && (errorWithOpenid.message?.includes('wechat_openid') || errorWithOpenid.message?.includes('does not exist'))) {
      // Column doesn't exist, select without it
      console.log('wechat_openid column not found, selecting without it:', errorWithOpenid.message);
      const { data: profilesWithoutOpenid, error: errorWithoutOpenid } = await supabaseAdmin
        .from('profiles')
        .select('id, nickname, avatar_url, role, created_at')
        .order('created_at', { ascending: false });
      
      if (errorWithoutOpenid) {
        profilesError = errorWithoutOpenid;
      } else {
        profiles = (profilesWithoutOpenid || []).map((p: any) => ({ ...p, wechat_openid: null }));
      }
    } else if (errorWithOpenid) {
      profilesError = errorWithOpenid;
    } else {
      profiles = profilesWithOpenid || [];
    }

    if (profilesError) {
      throw profilesError;
    }

    // Get user details from auth.users for each profile
    const usersWithDetails = await Promise.all(
      (profiles || []).map(async (profile) => {
        try {
          const { data: authUser, error: userError } = await supabaseAdmin.auth.admin.getUserById(profile.id);
          
          if (userError || !authUser) {
            return {
              id: profile.id,
              email: null,
              phone: null,
              nickname: profile.nickname,
              avatar_url: profile.avatar_url,
              role: profile.role || 'user',
              wechat_openid: profile.wechat_openid,
              login_type: 'unknown',
              created_at: profile.created_at,
            };
          }

          // Determine login type based on email format
          const email = authUser.email || '';
          const isWechatUser = email.endsWith('@wechat.user');
          const loginType = isWechatUser ? 'wechat' : 'email';

          return {
            id: profile.id,
            email: email || null,
            phone: authUser.phone || authUser.user_metadata?.phone || null,
            nickname: profile.nickname,
            avatar_url: profile.avatar_url,
            role: profile.role || 'user',
            wechat_openid: profile.wechat_openid,
            login_type: loginType,
            created_at: profile.created_at,
          };
        } catch (error) {
          console.error(`Error fetching user ${profile.id}:`, error);
          return {
            id: profile.id,
            email: null,
            phone: null,
            nickname: profile.nickname,
            avatar_url: profile.avatar_url,
            role: profile.role || 'user',
            wechat_openid: profile.wechat_openid,
            login_type: 'unknown',
            created_at: profile.created_at,
          };
        }
      })
    );

    return new Response(
      JSON.stringify({ users: usersWithDetails }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    );
  } catch (error: any) {
    console.error('Unhandled error in get-users function:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      }
    );
  }
});

