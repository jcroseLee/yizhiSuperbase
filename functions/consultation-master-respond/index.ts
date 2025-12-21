// deno-lint-ignore-file no-explicit-any
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface MasterRespondPayload {
  consultationId?: string
  action?: 'accept' | 'reject'
  reason?: string
}

const BAD_REQUEST = 400
const UNAUTHORIZED = 401
const METHOD_NOT_ALLOWED = 405
const INTERNAL_ERROR = 500

const encoder = new TextEncoder()


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

    const payload = (await req.json().catch(() => ({}))) as MasterRespondPayload
    const { consultationId, action, reason } = payload

    if (!consultationId || !action) {
      return new Response(JSON.stringify({ error: '缺少必要参数' }), {
        status: BAD_REQUEST,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (action !== 'accept' && action !== 'reject') {
      return new Response(JSON.stringify({ error: '无效的操作类型' }), {
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
      .select(
        '*, masters(id, user_id, name), master_services(name)'
      )
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

    if (!consultation.masters?.user_id || consultation.masters.user_id !== userId) {
      return new Response(JSON.stringify({ error: '无权操作该订单' }), {
        status: UNAUTHORIZED,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (action === 'accept') {
      if (consultation.status !== 'awaiting_master') {
        return new Response(JSON.stringify({ error: '当前状态不可接单' }), {
          status: BAD_REQUEST,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      const { data: updatedConsultation, error: updateError } = await supabase
        .from('consultations')
        .update({
          status: 'in_progress',
        })
        .eq('id', consultationId)
        .select('*, masters(user_id), master_services(name)')
        .maybeSingle()

      if (updateError || !updatedConsultation) {
        console.error('Failed to update consultation status to in_progress', updateError)
        return new Response(JSON.stringify({ error: '接单失败' }), {
          status: INTERNAL_ERROR,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      await supabase.from('messages').insert({
        sender_id: userId,
        receiver_id: updatedConsultation.user_id,
        consultation_id: consultationId,
        content: `卦师已接单，服务即将开始，项目：${consultation.master_services?.name ?? '咨询服务'}`,
        message_type: 'system',
        metadata: {
          event: 'order_accepted',
          consultation_id: consultationId,
        },
      })

      return new Response(JSON.stringify({ consultation: updatedConsultation }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Reject flow
    if (consultation.status !== 'awaiting_master') {
      return new Response(JSON.stringify({ error: '当前状态不可拒单' }), {
        status: BAD_REQUEST,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { data: cancelledConsultation, error: cancelError } = await supabase
      .from('consultations')
      .update({
        status: 'cancelled',
      })
      .eq('id', consultationId)
      .select('*')
      .maybeSingle()

    if (cancelError || !cancelledConsultation) {
      console.error('Failed to cancel consultation', cancelError)
      return new Response(JSON.stringify({ error: '拒单失败' }), {
        status: INTERNAL_ERROR,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    await supabase.from('messages').insert({
      sender_id: userId,
      receiver_id: cancelledConsultation.user_id,
      consultation_id: consultationId,
      content: '卦师暂时无法接单，订单已取消。',
      message_type: 'system',
      metadata: {
        event: 'order_rejected',
        consultation_id: consultationId,
        reason: reason ?? null,
      },
    })

    return new Response(JSON.stringify({ consultation: cancelledConsultation }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Unexpected error in consultation-master-respond', error)
    return new Response(JSON.stringify({ error: (error as Error).message ?? '未知错误' }), {
      status: INTERNAL_ERROR,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})

