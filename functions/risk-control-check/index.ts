// deno-lint-ignore-file no-explicit-any
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface CheckMessagePayload {
  messageId?: string
  content?: string
  consultationId?: string
  userId?: string
}

const BAD_REQUEST = 400
const UNAUTHORIZED = 401
const METHOD_NOT_ALLOWED = 405
const INTERNAL_ERROR = 500

// Sensitive keywords for private transaction detection
const PRIVATE_TRANSACTION_KEYWORDS = [
  '私下',
  '私聊',
  '微信转账',
  '支付宝',
  '直接付款',
  '绕过平台',
  '平台外',
  '加微信',
  '加我微信',
  '微信联系',
  '私下交易',
  '线下交易',
  '不走平台',
  '跳过平台',
  '平台外支付',
  '微信支付',
  '支付宝转账',
  '直接给我',
  '私下给钱',
  '平台外付款',
]

function detectPrivateTransaction(content: string): boolean {
  const lowerContent = content.toLowerCase()
  return PRIVATE_TRANSACTION_KEYWORDS.some((keyword) => lowerContent.includes(keyword.toLowerCase()))
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

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('Server configuration error')
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey)

    const payload = (await req.json().catch(() => ({}))) as CheckMessagePayload
    const { messageId, content, consultationId, userId } = payload

    if (!content) {
      return new Response(JSON.stringify({ error: '缺少消息内容' }), {
        status: BAD_REQUEST,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Check for private transaction keywords
    const hasViolation = detectPrivateTransaction(content)

    if (!hasViolation) {
      return new Response(
        JSON.stringify({
          violation_detected: false,
          message: '消息内容正常',
        }),
        {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Violation detected - record it
    if (consultationId && userId) {
      const { data: violation, error: violationError } = await supabase
        .from('risk_control_violations')
        .insert({
          consultation_id: consultationId,
          user_id: userId,
          violation_type: 'private_transaction',
          detected_content: content,
          message_id: messageId || null,
          action_taken: 'warning',
          is_resolved: false,
        })
        .select('id')
        .maybeSingle()

      if (violationError) {
        console.error('Failed to record violation', violationError)
      }

      // Send warning message to user
      if (consultationId) {
        // Get consultation info to find the other participant
        const { data: consultation } = await supabase
          .from('consultations')
          .select('user_id, masters(user_id)')
          .eq('id', consultationId)
          .maybeSingle()

        if (consultation) {
          const otherUserId =
            userId === consultation.user_id
              ? consultation.masters?.user_id
              : consultation.user_id

          if (otherUserId) {
            await supabase.from('messages').insert({
              sender_id: userId,
              receiver_id: otherUserId,
              consultation_id: consultationId,
              content: '⚠️ 系统提示：检测到可能涉及私下交易的内容。请通过平台完成交易，以保障双方权益。',
              message_type: 'system',
              metadata: {
                event: 'risk_control_warning',
                consultation_id: consultationId,
                violation_type: 'private_transaction',
              },
            })
          }

          // Also send warning to the sender
          await supabase.from('messages').insert({
            sender_id: userId,
            receiver_id: userId,
            consultation_id: consultationId,
            content: '⚠️ 系统提示：检测到可能涉及私下交易的内容。请通过平台完成交易，以保障双方权益。',
            message_type: 'system',
            metadata: {
              event: 'risk_control_warning',
              consultation_id: consultationId,
              violation_type: 'private_transaction',
            },
          })
        }
      }
    }

    return new Response(
      JSON.stringify({
        violation_detected: true,
        violation_type: 'private_transaction',
        action_taken: 'warning',
        message: '检测到可能涉及私下交易的内容，已记录并发送警告',
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('Unexpected error in risk-control-check', error)
    return new Response(JSON.stringify({ error: (error as Error).message ?? '未知错误' }), {
      status: INTERNAL_ERROR,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})

