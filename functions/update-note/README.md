# Update Note Edge Function

这个 Edge Function 用于更新占卜记录的笔记内容。

## 功能说明

- 验证用户身份（通过 Authorization header）
- 验证记录是否属于该用户
- 更新 `divination_records` 表中的 `note` 字段
- 返回更新后的记录

## 请求格式

**Endpoint:** `POST /functions/v1/update-note`

**Headers:**
```
Authorization: Bearer <access_token>
Content-Type: application/json
```

**Body:**
```json
{
  "userId": "user-uuid",
  "recordId": "record-uuid",
  "note": "笔记内容（可选，为空字符串表示删除笔记）"
}
```

## 响应格式

**成功响应 (200):**
```json
{
  "data": {
    "id": "record-uuid",
    "user_id": "user-uuid",
    "note": "笔记内容",
    ...
  }
}
```

**错误响应:**
```json
{
  "error": "错误消息"
}
```

## 部署

### 本地开发

```bash
# 启动本地 Supabase（如果还没有启动）
supabase start

# 在本地运行 edge function
supabase functions serve update-note --env-file .env.local
```

### 部署到生产环境

```bash
# 部署 edge function
supabase functions deploy update-note

# 或者部署所有 functions
supabase functions deploy
```

## 环境变量

Edge Function 需要以下环境变量（Supabase 会自动注入）：

- `SUPABASE_URL` - Supabase 项目 URL
- `SUPABASE_SERVICE_ROLE_KEY` - Supabase Service Role Key

这些变量在 Supabase Dashboard 中会自动配置，无需手动设置。

## 安全说明

- 函数会验证用户身份，确保只有记录的所有者才能更新笔记
- 使用 Service Role Key 进行数据库操作，确保有足够的权限
- 通过 `user_id` 和 `id` 双重验证，防止越权访问

