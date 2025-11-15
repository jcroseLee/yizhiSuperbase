-- Clean up duplicate profiles entries that share the same wechat_openid.
WITH ranked_profiles AS (
  SELECT
    id,
    wechat_openid,
    updated_at,
    created_at,
    ROW_NUMBER() OVER (
      PARTITION BY wechat_openid
      ORDER BY
        updated_at DESC NULLS LAST,
        created_at DESC NULLS LAST,
        id DESC
    ) AS rn
  FROM profiles
  WHERE wechat_openid IS NOT NULL
)
DELETE FROM profiles p
USING ranked_profiles r
WHERE p.id = r.id
  AND r.wechat_openid IS NOT NULL
  AND r.rn > 1;

-- Ensure wechat_openid remains unique moving forward.
CREATE UNIQUE INDEX IF NOT EXISTS profiles_wechat_openid_key
  ON profiles (wechat_openid)
  WHERE wechat_openid IS NOT NULL;

