// deno-lint-ignore-file no-explicit-any
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const INTERNAL_ERROR = 500

Deno.serve(async (req: Request) => {
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
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('Server configuration error')
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey)

    const nowIso = new Date().toISOString()

    // Find consultations ready for settlement (T+7, status is pending_settlement, review submitted)
    const { data: readyForSettlement, error: settlementError } = await supabase
      .from('consultations')
      .select(
        'id, master_id, user_id, price, master_payout_amount, settlement_status, settlement_scheduled_at, masters(user_id, name)'
      )
      .eq('status', 'pending_settlement')
      .eq('settlement_status', 'pending')
      .eq('review_submitted', true)
      .lte('settlement_scheduled_at', nowIso)
      .limit(50)

    if (settlementError) {
      throw settlementError
    }

    const processed: any[] = []
    const failures: { id: string; error: string }[] = []

    for (const consultation of readyForSettlement ?? []) {
      try {
        const price = Number(consultation.price ?? 0)
        const payoutAmount = Number(consultation.master_payout_amount ?? 0)

        if (price <= 0) {
          throw new Error('订单金额无效')
        }

        // Update escrow status to released
        await supabase
          .from('platform_escrow')
          .update({
            status: 'released',
            released_at: nowIso,
          })
          .eq('consultation_id', consultation.id)

        // Update settlement record status
        const { data: settlement, error: settlementUpdateError } = await supabase
          .from('master_settlements')
          .update({
            settlement_status: 'completed',
            completed_at: nowIso,
          })
          .eq('consultation_id', consultation.id)
          .select('id')
          .maybeSingle()

        if (settlementUpdateError) {
          throw settlementUpdateError
        }

        // Update consultation settlement status
        const { data: updatedConsultation, error: consultationUpdateError } = await supabase
          .from('consultations')
          .update({
            settlement_status: 'settled',
            settlement_completed_at: nowIso,
            status: 'completed',
          })
          .eq('id', consultation.id)
          .select('id, master_id, masters(user_id)')
          .maybeSingle()

        if (consultationUpdateError || !updatedConsultation) {
          throw consultationUpdateError || new Error('更新订单结算状态失败')
        }

        // Credit master's wallet (or prepare for external payout)
        // For now, we'll credit to master's wallet
        // In production, this might be an external payout to master's bank/wechat account
        const masterUserId = consultation.masters?.user_id
        if (masterUserId && payoutAmount > 0) {
          const { error: walletError } = await supabase.rpc('adjust_user_wallet', {
            p_user_id: masterUserId,
            p_amount: payoutAmount,
            p_direction: 'credit',
            p_consultation_id: consultation.id,
            p_description: `咨询订单结算：${consultation.masters?.name || '卦师'}，订单金额¥${price.toFixed(2)}，实际结算¥${payoutAmount.toFixed(2)}`,
          })

          if (walletError) {
            console.error('Failed to credit master wallet', walletError)
            // Don't fail the settlement, but log the error
            // In production, you might want to retry or use a different payout method
          }
        }

        // Send notification messages
        if (masterUserId) {
          await supabase.from('messages').insert({
            sender_id: masterUserId,
            receiver_id: masterUserId,
            consultation_id: consultation.id,
            content: `订单结算完成：订单金额¥${price.toFixed(2)}，已结算¥${payoutAmount.toFixed(2)}至您的账户。`,
            message_type: 'system',
            metadata: {
              event: 'settlement_completed',
              consultation_id: consultation.id,
              payout_amount: payoutAmount,
            },
          })
        }

        await supabase.from('messages').insert({
          sender_id: consultation.user_id,
          receiver_id: consultation.user_id,
          consultation_id: consultation.id,
          content: '订单结算已完成，感谢您的使用。',
          message_type: 'system',
          metadata: {
            event: 'settlement_completed',
            consultation_id: consultation.id,
          },
        })

        processed.push({
          id: consultation.id,
          payout_amount: payoutAmount,
        })
      } catch (error: any) {
        console.error('Failed to process settlement', consultation.id, error)
        failures.push({ id: consultation.id, error: error.message || '未知错误' })
      }
    }

    return new Response(
      JSON.stringify({
        processed,
        failures,
        summary: {
          total: readyForSettlement?.length || 0,
          processed: processed.length,
          failed: failures.length,
        },
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('Unexpected error in consultation-settlement-worker', error)
    return new Response(JSON.stringify({ error: (error as Error).message ?? '未知错误' }), {
      status: INTERNAL_ERROR,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})

