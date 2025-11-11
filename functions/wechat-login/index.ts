// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

const wechatApiBase = 'https://api.weixin.qq.com';

// Exchange the code for a session key and openid
async function getWechatSession(code) {
  console.log('Getting WeChat session for code:', code);
  const WECHAT_APPID = Deno.env.get('WECHAT_APPID');
  const WECHAT_APPSECRET = Deno.env.get('WECHAT_APPSECRET');

  if (!WECHAT_APPID || !WECHAT_APPSECRET) {
    console.error('Missing WeChat environment variables.', {
      hasAppId: !!WECHAT_APPID,
      hasAppSecret: !!WECHAT_APPSECRET,
    });
    throw new Error('Missing WeChat environment variables. Please check WECHAT_APPID and WECHAT_APPSECRET are set in function secrets.');
  }

  // Log appid length for debugging (without exposing the actual value)
  console.log('WeChat AppID configured:', {
    appIdLength: WECHAT_APPID.length,
    appSecretLength: WECHAT_APPSECRET.length,
  });

  const url = `${wechatApiBase}/sns/jscode2session?appid=${WECHAT_APPID}&secret=${WECHAT_APPSECRET}&js_code=${code}&grant_type=authorization_code`;
  console.log('Fetching WeChat session from WeChat API');
  const res = await fetch(url);
  const data = await res.json();
  console.log('WeChat API response:', {
    hasErrcode: !!data.errcode,
    errcode: data.errcode,
    errmsg: data.errmsg,
    hasOpenid: !!data.openid,
  });

  if (data.errcode) {
    console.error('WeChat API error:', {
      errcode: data.errcode,
      errmsg: data.errmsg,
      rid: data.rid,
    });
    
    // Provide more helpful error messages for common error codes
    let errorMessage = data.errmsg || 'Failed to get WeChat session.';
    if (data.errcode === 40013) {
      errorMessage = 'Invalid WeChat AppID. Please verify WECHAT_APPID is correct in function secrets.';
    } else if (data.errcode === 40125) {
      errorMessage = 'Invalid WeChat AppSecret. Please verify WECHAT_APPSECRET is correct in function secrets.';
    } else if (data.errcode === 40029) {
      errorMessage = 'Invalid WeChat code. The code may have expired or been used already.';
    }
    
    throw new Error(errorMessage);
  }
  
  if (!data.openid) {
    console.error('WeChat API response missing openid:', data);
    throw new Error('WeChat API response is missing openid.');
  }
  
  return data; // { openid, session_key, unionid }
}

Deno.serve(async (req: any) => {
  console.log('wechat-login function invoked.');
  // This is needed if you're planning to invoke your function from a browser.
  if (req.method === 'OPTIONS') {
    console.log('Handling OPTIONS request.');
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    console.log('Parsing request body.');
    const { code, userInfo } = await req.json();
    if (!code) {
      console.error('Missing code in request body.');
      throw new Error('Missing code in request body.');
    }
    console.log('Received code:', code);
    console.log('Received userInfo:', userInfo);

    const wechatSession = await getWechatSession(code);
    const { openid, session_key, unionid } = wechatSession;
    console.log('WeChat session details:', { openid, session_key, unionid });

    if (!openid) {
      console.error('Failed to get openid from WeChat.');
      throw new Error('Failed to get openid from WeChat.');
    }

    console.log('Creating Supabase clients (admin + anon).');
    // Support both local dev (PROJECT_URL, SERVICE_ROLE_KEY, ANON_KEY) and production (SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY)
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || Deno.env.get('PROJECT_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || Deno.env.get('SERVICE_ROLE_KEY');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') || Deno.env.get('ANON_KEY');

    if (!supabaseUrl || !serviceRoleKey) {
      console.error('Missing Supabase environment variables:', { supabaseUrl: !!supabaseUrl, serviceRoleKey: !!serviceRoleKey });
      throw new Error('Missing Supabase environment variables.');
    }

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

    const supabaseAnon = anonKey
      ? createClient(
          supabaseUrl,
          anonKey,
          {
            auth: {
              persistSession: false,
              autoRefreshToken: false,
              detectSessionInUrl: false,
            },
          }
        )
      : null;

    // Use .app TLD which is a valid TLD and should pass email validation
    const email = `${openid}@wechat.app`;
    const emailOld = `${openid}@wechat.user`; // For backward compatibility with existing users
    const password = `${openid}-wechat-password`;
    console.log('Generated user credentials:', { email });

    // Helper function to sync profile to profiles table
    const syncProfileToTable = async (userId: string, nickname: string | null, avatarUrl: string | null, wechatOpenId?: string, wechatUnionId?: string | null) => {
      console.log('Syncing profile to profiles table:', { userId, nickname, avatarUrl, wechatOpenId, wechatUnionId });
      
      // Get current user data to sync unionid if not provided
      let unionIdToSync = wechatUnionId;
      if (!unionIdToSync && data?.user) {
        unionIdToSync = data.user.user_metadata?.wechat_unionid || null;
      }
      
      const profileData: any = {
        id: userId,
        nickname: nickname || null,
        avatar_url: avatarUrl || null,
      };
      if (wechatOpenId) {
        profileData.wechat_openid = wechatOpenId;
      }
      if (unionIdToSync !== undefined && unionIdToSync !== null) {
        profileData.wechat_unionid = unionIdToSync;
      }
      
      const { error: profileError } = await supabaseAdmin
        .from('profiles')
        .upsert(profileData, {
          onConflict: 'id'
        });
      
      if (profileError) {
        console.error('Failed to sync profile to profiles table:', profileError);
        // Don't throw, just log the error
      } else {
        console.log('Successfully synced profile to profiles table');
      }
    };

    // Check if user with this openId already exists in profiles table
    console.log('Checking if user with openId exists:', openid);
    const {
      data: existingProfile,
      error: existingProfileError,
    } = await supabaseAdmin
      .from('profiles')
      .select('id, wechat_openid')
      .eq('wechat_openid', openid)
      .maybeSingle();

    if (existingProfileError) {
      if (existingProfileError.code !== 'PGRST116') {
        console.warn('Failed to fetch existing profile by openid:', existingProfileError);
      }
    }

    console.log('Ensuring auth user exists and email is confirmed.');
    let ensuredUser: any = null;
    let createdNewUser = false;
    // If we acquire a session earlier (e.g., OTP fallback during ensure-user), store it here
    let preAuthData: any = null;

    // Helper: scan users to find by email when direct lookup is unavailable
    const findUserByEmail = async (client: any, emailLookup: string) => {
      try {
        // Try first page with larger perPage to reduce requests
        for (let page = 1; page <= 5; page++) {
          const { data: listData, error: listError } = await client.auth.admin.listUsers({ page, perPage: 200 });
          if (listError) {
            console.warn('listUsers error:', listError);
            break;
          }
          const users = (listData as any)?.users || listData || [];
          const found = users.find((u: any) => u?.email === emailLookup);
          if (found) return found;
          // If fewer than perPage returned, likely no more pages
          if (Array.isArray(users) && users.length < 200) break;
        }
      } catch (e) {
        console.warn('findUserByEmail threw:', e);
      }
      return null;
    };

    // Resolve existing auth user: prefer profiles.id -> getUserById, else scan by email
    let userToProcess: any = null;
    if (existingProfile?.id) {
      const { data: byIdData, error: byIdError } = await supabaseAdmin.auth.admin.getUserById(existingProfile.id);
      if (byIdError) {
        console.warn('getUserById error for existing profile id:', byIdError);
      } else {
        const candidate = (byIdData as any)?.user ?? byIdData;
        if (candidate?.id) {
          userToProcess = candidate;
        }
      }
    }
    if (!userToProcess) {
      userToProcess = await findUserByEmail(supabaseAdmin, email);
    }
    if (!userToProcess && emailOld) {
      userToProcess = await findUserByEmail(supabaseAdmin, emailOld);
    }

    // If user exists, update them. If not, create them.
    if (userToProcess) {
      console.log('Found existing user:', { id: userToProcess.id, email: userToProcess.email });
      // Check if update is needed (old email format or not confirmed)
      if (userToProcess.email !== email || !userToProcess.email_confirmed_at) {
        console.log('Updating user to new email format and confirming email.');
        const { data: updatedUser, error: updateUserError } = await supabaseAdmin.auth.admin.updateUserById(
          userToProcess.id,
          {
            email: email, // Update to new format
            email_confirm: true, // Ensure confirmed
            password: password,
          }
        );
        if (updateUserError) {
          console.error('Failed to update user:', updateUserError);
          throw updateUserError;
        }
        
        // Refetch the user to ensure the email_confirmed_at is updated before signing in
         const { data: refetchedUserData, error: refetchError } = await supabaseAdmin.auth.admin.getUserById(
           userToProcess.id
         );
        if (refetchError) {
          console.error('Failed to refetch user after update:', refetchError);
          throw refetchError;
        }

        console.log('Refetched user confirmed at:', refetchedUserData.user.email_confirmed_at);
        ensuredUser = refetchedUserData.user;
      } else {
        console.log('User is already up-to-date and confirmed.');
        ensuredUser = userToProcess;
      }
    } else {
      console.log('User not found, creating new user.');
      const { data: signUpData, error: signUpError } = await supabaseAdmin.auth.admin.createUser({
        email: email, // Create with new format
        password,
        email_confirm: true, // Create as confirmed
        user_metadata: {
          wechat_openid: openid,
          wechat_unionid: unionid,
          avatar_url: userInfo?.avatarUrl || null,
          nickname: userInfo?.nickname || null,
        },
      });

      if (signUpError) {
        console.error('Failed to create user:', signUpError);
        // If user already exists, fallback to scanning again to acquire id
        const fallbackUser = await findUserByEmail(supabaseAdmin, email) || await findUserByEmail(supabaseAdmin, emailOld);
        if (fallbackUser) {
          ensuredUser = fallbackUser;
        } else if ((signUpError as any)?.code === 'email_exists' || (signUpError as any)?.status === 422) {
          // User exists but we couldn't resolve their record via listUsers.
          // Fall back to OTP login immediately to obtain session & user reliably.
          console.log('Email already exists, initiating OTP fallback during ensure-user.');
          const { data: linkData, error: linkError } = await supabaseAdmin.auth.admin.generateLink({
            type: 'magiclink',
            email,
          });
          if (linkError) {
            console.error('Failed to generate magiclink:', linkError);
            throw linkError;
          }
          const emailOtpEnsure = (linkData as any)?.properties?.email_otp;
          if (!emailOtpEnsure) {
            console.error('Magiclink generation did not include email_otp.');
            throw new Error('Failed to generate email OTP');
          }
          const signInClientEnsure = supabaseAnon || supabaseAdmin;
          console.log('Verifying OTP to create session (ensure-user flow).');
          const { data: otpDataEnsure, error: otpErrorEnsure } = await signInClientEnsure.auth.verifyOtp({
            email,
            token: emailOtpEnsure,
            type: 'email',
          });
          if (otpErrorEnsure) {
            console.error('OTP verification failed (ensure-user):', otpErrorEnsure);
            throw otpErrorEnsure;
          }
          preAuthData = otpDataEnsure;
          ensuredUser = otpDataEnsure?.user;
        } else {
          throw signUpError;
        }
      } else {
        ensuredUser = (signUpData as any)?.user ?? signUpData;
        createdNewUser = true;
      }
    }

    if (!ensuredUser) {
      console.error('Could not ensure user exists.');
      throw new Error('Failed to create or update user.');
    }

    // Helper: attempt sign-in with retries when email_not_confirmed
    const attemptSignInWithRetries = async (
      client: any,
      emailToUse: string,
      pwd: string,
      adminClient: any,
      ensured: any
    ) => {
      let lastError: any = null;
      for (let i = 0; i < 3; i++) {
        console.log(`Sign-in attempt ${i + 1} for email:`, emailToUse);
        const { data: signInData, error: signInError } = await client.auth.signInWithPassword({
          email: emailToUse,
          password: pwd,
        });
        if (!signInError && signInData) {
          return { data: signInData };
        }
        lastError = signInError;
        const code = (signInError as any)?.code;
        const status = (signInError as any)?.status;
        console.warn('Sign-in error:', { code, status, message: signInError?.message });
        if (code === 'email_not_confirmed') {
          console.log('Email not confirmed; forcing confirm and retry.');
          const { error: confirmErr } = await adminClient.auth.admin.updateUserById(ensured.id, {
            email_confirm: true,
          });
          if (confirmErr) {
            console.warn('Forced confirm failed:', confirmErr);
          }
          // tiny backoff
          await new Promise((r) => setTimeout(r, 300 * (i + 1)));
          continue;
        }
        // Non-confirmation error, break early
        break;
      }
      throw lastError || new Error('Sign-in failed');
    };

    // Always sign in with the new, confirmed email
    console.log('Attempting final sign-in with ensured user.', {
      ensured_email: ensuredUser.email,
      ensured_email_confirmed_at: ensuredUser.email_confirmed_at,
      ensured_is_anonymous: ensuredUser.is_anonymous,
    });
    const signInClient = supabaseAnon || supabaseAdmin;
    let data: any = preAuthData || null;
    if (!data) {
      try {
        const result = await attemptSignInWithRetries(signInClient, ensuredUser.email, password, supabaseAdmin, ensuredUser);
        data = result.data;
      } catch (signErr: any) {
        const code = signErr?.code;
        const status = signErr?.status;
        console.warn('Password sign-in failed after retries:', { code, status, message: signErr?.message });
        if (code === 'email_not_confirmed' || status === 400) {
          console.log('Falling back to OTP login via admin.generateLink.');
          const { data: linkData, error: linkError } = await supabaseAdmin.auth.admin.generateLink({
            type: 'magiclink',
            email: ensuredUser.email,
          });
          if (linkError) {
            console.error('Failed to generate magiclink:', linkError);
            throw linkError;
          }
          const emailOtp = (linkData as any)?.properties?.email_otp;
          if (!emailOtp) {
            console.error('Magiclink generation did not include email_otp.');
            throw new Error('Failed to generate email OTP');
          }
          console.log('Verifying OTP to create session.');
          const { data: otpData, error: otpError } = await signInClient.auth.verifyOtp({
            email: ensuredUser.email,
            token: emailOtp,
            type: 'email',
          });
          if (otpError) {
            console.error('OTP verification failed:', otpError);
            throw otpError;
          }
          data = otpData;
        } else {
          throw signErr;
        }
      }
    }

    // data must now contain user/session

    if (!data || !data.user) {
      console.error('Sign-in succeeded but missing user data.');
      throw new Error('Failed to retrieve user data after sign-in.');
    }

    if (createdNewUser || !existingProfile || existingProfile.wechat_openid !== openid) {
      console.log('Syncing profile to ensure openid linkage.');
      await syncProfileToTable(
        data.user.id,
        userInfo?.nickname || data.user.user_metadata?.nickname || ensuredUser?.user_metadata?.nickname || null,
        userInfo?.avatarUrl || data.user.user_metadata?.avatar_url || ensuredUser?.user_metadata?.avatar_url || null,
        openid,
        unionid || data.user.user_metadata?.wechat_unionid || ensuredUser?.user_metadata?.wechat_unionid || null
      );
    }

    // Update user metadata if userInfo is provided and user already exists
    if (data && data.user && userInfo && (userInfo.avatarUrl || userInfo.nickname)) {
      console.log('Updating user metadata with userInfo.');
      // Use admin API to update user metadata
      const { data: updatedUser, error: updateError } = await supabaseAdmin.auth.admin.updateUserById(
        data.user.id,
        {
          user_metadata: {
            ...data.user.user_metadata,
            avatar_url: userInfo.avatarUrl || data.user.user_metadata?.avatar_url,
            nickname: userInfo.nickname || data.user.user_metadata?.nickname,
          },
        }
      );
      if (updateError) {
        console.error('Update user metadata error:', updateError);
        // Don't throw, just log the error
      } else if (updatedUser) {
        // Update the user in response data
        data.user = updatedUser;
        
        // Sync profile to profiles table
        await syncProfileToTable(
          updatedUser.id,
          userInfo.nickname || updatedUser.user_metadata?.nickname || null,
          userInfo.avatarUrl || updatedUser.user_metadata?.avatar_url || null,
          undefined,
          unionid || updatedUser.user_metadata?.wechat_unionid || null
        );
      }
    } else if (data && data.user && data.user.id) {
      // Even if no userInfo provided, ensure profile exists in profiles table
      // This handles the case where user was created before profiles table sync was added
      const { data: existingProfile } = await supabaseAdmin
        .from('profiles')
        .select('id')
        .eq('id', data.user.id)
        .single();
      
      if (!existingProfile) {
        console.log('Profile does not exist, creating it.');
        await syncProfileToTable(
          data.user.id,
          data.user.user_metadata?.nickname || null,
          data.user.user_metadata?.avatar_url || null,
          undefined,
          unionid || data.user.user_metadata?.wechat_unionid || null
        );
      }
    }

    // Ensure we have both session and user before returning
    if (!data || !data.session) {
      console.error('No session available after login.');
      throw new Error('Failed to create session.');
    }
    
    if (!data.user) {
      console.error('No user data available after login.');
      throw new Error('Failed to get user data.');
    }
    
    console.log('Login successful, returning data.');
    // Transform the response to match the expected format: { access_token, user, ... }
    // Supabase auth returns { session: { access_token, ... }, user }
    // We need to flatten it to match what the client expects
    const responseData = {
      ...data.session,
      access_token: data.session.access_token,
      user: data.user,
    };
    
    return new Response(JSON.stringify(responseData), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    });
  } catch (error: any) {
    console.error('Unhandled error in wechat-login function:', error);
    const status = typeof error?.status === 'number' ? error.status : 500;
    const message = error?.message || 'Internal server error';
    return new Response(JSON.stringify({ error: message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status,
    });
  }
});