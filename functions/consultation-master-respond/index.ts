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

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const cleaned = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '')
  const binary = atob(cleaned)
  const len = binary.length
  const bytes = new Uint8Array(len)
  for (let i = 0; i < len; i++) {
    bytes[i] = binary.charCodeAt(i)
  }
  return bytes.buffer
}

async function signWechatMessage(message: string, privateKeyPem: string): Promise<string> {
  const keyData = pemToArrayBuffer(privateKeyPem)
  const key = await crypto.subtle.importKey(
    'pkcs8',
    keyData,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign']
  )

  const signature = await crypto.subtle.sign(
    {
      name: 'RSASSA-PKCS1-v1_5',
    },
    key,
    encoder.encode(message)
  )

  const uint8Signature = new Uint8Array(signature)
  let binary = ''
  for (let i = 0; i < uint8Signature.byteLength; i++) {
    binary += String.fromCharCode(uint8Signature[i])
  }
  return btoa(binary)
}

function generateNonce(): string {
  return crypto.randomUUID().replace(/-/g, '')
}

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
    const appId = Deno.env.get('WECHAT_MINI_APPID')
    const mchId = Deno.env.get('WECHAT_MCH_ID')
    const privateKeyPem = Deno.env.get('WECHAT_MCH_PRIVATE_KEY')
    const mchSerial = Deno.env.get('WECHAT_MCH_SERIAL_NO')
    const refundNotifyUrl = Deno.env.get('WECHAT_REFUND_NOTIFY_URL') || ''

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
        '*, masters(id, user_id, name), payment_transactions(id, provider_trade_no, status, amount), master_services(name)'
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

    // Reject flow with refund
    if (consultation.status !== 'awaiting_master') {
      return new Response(JSON.stringify({ error: '当前状态不可拒单' }), {
        status: BAD_REQUEST,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (consultation.payment_status !== 'paid') {
      const { data: cancelledConsultation, error: cancelError } = await supabase
        .from('consultations')
        .update({
          status: 'cancelled',
        })
        .eq('id', consultationId)
        .select('*')
        .maybeSingle()

      if (cancelError || !cancelledConsultation) {
        console.error('Failed to cancel unpaid consultation', cancelError)
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
    }

    const price = Number(consultation.price ?? 0)
    if (!price || price <= 0) {
      return new Response(JSON.stringify({ error: '订单金额有误，无法退款' }), {
        status: BAD_REQUEST,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    let refundSucceeded = false
    let refundResponse: any = null

    // Update escrow status to refunded
    await supabase
      .from('platform_escrow')
      .update({
        status: 'refunded',
        released_at: new Date().toISOString(),
      })
      .eq('consultation_id', consultationId)
      .catch((err) => {
        // Log but don't fail if escrow record doesn't exist
        console.error('Failed to update escrow status', err)
      })

    if (consultation.payment_method === 'balance') {
      const { error: walletError } = await supabase.rpc('adjust_user_wallet', {
        p_user_id: consultation.user_id,
        p_amount: price,
        p_direction: 'credit',
        p_consultation_id: consultationId,
        p_description: '卦师拒单自动退款',
      })

      if (walletError) {
        console.error('Balance refund failed', walletError)
        return new Response(JSON.stringify({ error: walletError.message || '余额退款失败' }), {
          status: INTERNAL_ERROR,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      refundSucceeded = true
    } else if (consultation.payment_method === 'wechat') {
      if (!appId || !mchId || !privateKeyPem || !mchSerial) {
        return new Response(JSON.stringify({ error: '微信支付未配置，无法退款' }), {
          status: BAD_REQUEST,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      const payment = consultation.payment_transactions?.[0]
      if (!payment?.provider_trade_no) {
        return new Response(JSON.stringify({ error: '缺少支付流水号，无法退款' }), {
          status: INTERNAL_ERROR,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      const refundAmount = Math.round(price * 100)
      const urlPath = '/v3/refund/domestic/refunds'
      const wxApi = `https://api.mch.weixin.qq.com${urlPath}`
      const outRefundNo = crypto.randomUUID().replace(/-/g, '')
      const body = JSON.stringify({
        out_trade_no: payment.provider_trade_no,
        out_refund_no: outRefundNo,
        notify_url: refundNotifyUrl || undefined,
        amount: {
          refund: refundAmount,
          total: refundAmount,
          currency: 'CNY',
        },
        reason: reason || '卦师未接单自动退款',
      })

      const timestamp = Math.floor(Date.now() / 1000).toString()
      const nonceStr = generateNonce()
      const message = `POST\n${urlPath}\n${timestamp}\n${nonceStr}\n${body}\n`
      const signature = await signWechatMessage(message, privateKeyPem)
      const authHeaderValue = `WECHATPAY2-SHA256-RSA2048 mchid="${mchId}",nonce_str="${nonceStr}",timestamp="${timestamp}",serial_no="${mchSerial}",signature="${signature}"`

      const resp = await fetch(wxApi, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: authHeaderValue,
        },
        body,
      })

      const respBody = await resp.json().catch(() => ({}))
      if (!resp.ok) {
        console.error('Wechat refund failed', resp.status, respBody)
        return new Response(
          JSON.stringify({
            error: respBody?.message || '微信退款失败',
          }),
          {
            status: INTERNAL_ERROR,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        )
      }

      refundSucceeded = true
      refundResponse = respBody

      await supabase
        .from('payment_transactions')
        .update({
          status: 'refunded',
          raw_response: respBody,
        })
        .eq('id', payment.id)
    }

    if (!refundSucceeded) {
      return new Response(JSON.stringify({ error: '退款处理失败' }), {
        status: INTERNAL_ERROR,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { data: refundedConsultation, error: refundUpdateError } = await supabase
      .from('consultations')
      .update({
        status: 'refunded',
        payment_status: 'refunded',
      })
      .eq('id', consultationId)
      .select('*')
      .maybeSingle()

    if (refundUpdateError || !refundedConsultation) {
      console.error('Failed to update consultation after refund', refundUpdateError)
      return new Response(JSON.stringify({ error: '更新订单状态失败' }), {
        status: INTERNAL_ERROR,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    await supabase.from('messages').insert({
      sender_id: userId,
      receiver_id: refundedConsultation.user_id,
      consultation_id: consultationId,
      content: '卦师暂时无法接单，费用已退回，请稍后重新选择服务。',
      message_type: 'system',
      metadata: {
        event: 'order_rejected',
        consultation_id: consultationId,
        reason: reason ?? null,
        refund: refundResponse,
      },
    })

    return new Response(
      JSON.stringify({
        consultation: refundedConsultation,
        refund: refundResponse,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('Unexpected error in consultation-master-respond', error)
    return new Response(JSON.stringify({ error: (error as Error).message ?? '未知错误' }), {
      status: INTERNAL_ERROR,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})

