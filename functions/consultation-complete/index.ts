// deno-lint-ignore-file no-explicit-any
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface CompletePayload {
  consultationId?: string
}

const BAD_REQUEST = 400
const UNAUTHORIZED = 401
const METHOD_NOT_ALLOWED = 405
const INTERNAL_ERROR = 500

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: METHOD_NOT_ALLOWED,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('Server configuration error')
    }

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
        status: UNAUTHORIZED,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const token = authHeader.replace('Bearer ', '')
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      global: {
        headers: { Authorization: `Bearer ${token}` },
      },
    })

    const payload = (await req.json().catch(() => ({}))) as CompletePayload
    const { consultationId } = payload

    if (!consultationId) {
      return new Response(JSON.stringify({ error: '缺少订单信息' }), {
        status: BAD_REQUEST,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { data: authUser, error: authError } = await supabase.auth.getUser()
    if (authError || !authUser?.user) {
      console.error('Failed to get auth user:', authError)
      return new Response(JSON.stringify({ error: '用户未登录' }), {
        status: UNAUTHORIZED,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const userId = authUser.user.id

    const { data: consultation, error: consultationError } = await supabase
      .from('consultations')
      .select('*, masters(user_id)')
      .eq('id', consultationId)
      .maybeSingle()

    if (consultationError) {
      console.error('Failed to fetch consultation', consultationError)
      return new Response(JSON.stringify({ error: '订单查询失败' }), {
        status: INTERNAL_ERROR,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!consultation) {
      return new Response(JSON.stringify({ error: '订单不存在' }), {
        status: BAD_REQUEST,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const isParticipant =
      consultation.user_id === userId || consultation.masters?.user_id === userId
    if (!isParticipant) {
      return new Response(JSON.stringify({ error: '无权操作该订单' }), {
        status: UNAUTHORIZED,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (consultation.status !== 'in_progress') {
      return new Response(JSON.stringify({ error: '当前状态不可结束咨询' }), {
        status: BAD_REQUEST,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Update consultation status to pending_settlement (requires review before settlement)
    const { data: completedConsultation, error: updateError } = await supabase
      .from('consultations')
      .update({
        status: 'pending_settlement',
        remaining_minutes: 0,
        remaining_sessions: 0,
        review_required: true,
      })
      .eq('id', consultationId)
      .select('*, masters(user_id)')
      .maybeSingle()

    if (updateError || !completedConsultation) {
      console.error('Failed to complete consultation', updateError)
      return new Response(JSON.stringify({ error: '结束咨询失败' }), {
        status: INTERNAL_ERROR,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Schedule settlement will be called after review is submitted
    // For now, just mark that review is required

    const otherUserId =
      userId === completedConsultation.user_id
        ? completedConsultation.masters?.user_id
        : completedConsultation.user_id

    if (otherUserId) {
      await supabase.from('messages').insert({
        sender_id: userId,
        receiver_id: otherUserId,
        consultation_id: consultationId,
        content: '本次咨询已结束，订单已进入结算流程。请对本次服务进行评价。',
        message_type: 'system',
        metadata: {
          event: 'consultation_completed',
          consultation_id: consultationId,
        },
      })
    }

    // Send message to user about review requirement if not submitted
    if (completedConsultation.review_required && !completedConsultation.review_submitted) {
      await supabase.from('messages').insert({
        sender_id: userId,
        receiver_id: userId,
        consultation_id: consultationId,
        content: '咨询已结束，请对本次服务进行评价。评价完成后订单将进入结算流程（T+7）。',
        message_type: 'system',
        metadata: {
          event: 'review_required',
          consultation_id: consultationId,
        },
      })
    }

    return new Response(JSON.stringify({ consultation: completedConsultation }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Unexpected error in consultation-complete', error)
    return new Response(JSON.stringify({ error: (error as Error).message ?? '未知错误' }), {
      status: INTERNAL_ERROR,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})

