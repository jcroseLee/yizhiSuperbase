
-- 允许帖子作者采纳评论（更新评论的 is_adopted 等字段）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
    AND tablename = 'comments' 
    AND policyname = 'comments_update_by_post_author'
  ) THEN
    CREATE POLICY "comments_update_by_post_author"
      ON public.comments FOR UPDATE
      USING (
        EXISTS (
          SELECT 1 FROM public.posts
          WHERE posts.id = comments.post_id
          AND posts.user_id = auth.uid()
        )
      );
  END IF;
END $$;
