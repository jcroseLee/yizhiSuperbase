// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

/**
 * Diagnose user data by WeChat openid.
 * Requires caller to be an admin (profiles.role = 'admin').
 * Returns candidate user IDs and counts of messages & divination records.
 */
Deno.serve(async (req: any) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  try {
    const authHeader = req.headers.get('Authorization') || req.headers.get('authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing authorization header' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') || Deno.env.get('PROJECT_URL')
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || Deno.env.get('SERVICE_ROLE_KEY')
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('Missing Supabase environment variables')
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    })

    // Verify caller is admin
    const token = authHeader.replace('Bearer ', '')
    const { data: userData, error: userErr } = await admin.auth.getUser(token)
    if (userErr || !userData?.user?.id) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
    const callerId = userData.user.id
    const { data: callerProfile } = await admin.from('profiles').select('role').eq('id', callerId).maybeSingle()
    if (!callerProfile || callerProfile.role !== 'admin') {
      return new Response(JSON.stringify({ error: 'Forbidden: Admin access required' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Parse body
    const body = await req.json()
    const openid: string = body?.openid
    if (!openid || typeof openid !== 'string') {
      return new Response(JSON.stringify({ error: 'Missing or invalid openid' }), {
        status: 422,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Helper to find auth user by email via admin.listUsers scanning
    const findUserByEmail = async (emailLookup: string) => {
      try {
        for (let page = 1; page <= 5; page++) {
          const { data: listData, error: listError } = await admin.auth.admin.listUsers({ page, perPage: 200 })
          if (listError) break
          const users = (listData as any)?.users || listData || []
          const found = users.find((u: any) => u?.email === emailLookup)
          if (found) return found
          if (Array.isArray(users) && users.length < 200) break
        }
      } catch (_) {}
      return null
    }

    // Collect candidate user IDs via profiles.wechat_openid and auth.users email formats
    const candidates: { source: string; id: string }[] = []

    // 1) profiles by wechat_openid
    const { data: profileByOpenid } = await admin
      .from('profiles')
      .select('id, wechat_openid')
      .eq('wechat_openid', openid)
      .maybeSingle()
    if (profileByOpenid?.id) {
      candidates.push({ source: 'profiles.wechat_openid', id: profileByOpenid.id })
    }

    // 2) auth user by derived emails
    const emailApp = `${openid}@wechat.app`
    const emailOld = `${openid}@wechat.user`
    const userApp = await findUserByEmail(emailApp)
    if (userApp?.id) candidates.push({ source: 'auth.email@wechat.app', id: userApp.id })
    const userOld = await findUserByEmail(emailOld)
    if (userOld?.id) candidates.push({ source: 'auth.email@wechat.user', id: userOld.id })

    // De-duplicate candidates
    const uniqueCandidates = [] as { source: string; id: string }[]
    const seen = new Set<string>()
    for (const c of candidates) {
      if (!seen.has(c.id)) {
        seen.add(c.id)
        uniqueCandidates.push(c)
      }
    }

    // For each candidate, compute counts for messages and divination_records
    const results = [] as any[]
    for (const c of uniqueCandidates) {
      // messages count
      const { count: messagesCount } = await admin
        .from('messages')
        .select('id', { count: 'exact', head: true })
        .or(`sender_id.eq.${c.id},receiver_id.eq.${c.id}`)

      // records count
      const { count: recordsCount } = await admin
        .from('divination_records')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', c.id)

      results.push({ source: c.source, user_id: c.id, messages_count: messagesCount ?? 0, records_count: recordsCount ?? 0 })
    }

    return new Response(
      JSON.stringify({ openid, candidates: results }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error: any) {
    console.error('diagnose-openid error:', error)
    return new Response(JSON.stringify({ error: error?.message || 'Internal error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})