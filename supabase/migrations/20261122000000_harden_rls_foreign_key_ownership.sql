-- ============================================================================
-- NOTEFLOW AI - MIGRATION: HARDEN ROW-LEVEL SECURITY & FOREIGN KEY OWNERSHIP
-- Timestamp: 20261122000000
-- Phase 1 Iteration 1 Refinement: SEC-01 & SEC-05 & SEC-06
--
-- Objective:
-- 1. Prevent Cross-User Foreign Key Manipulation (IDOR) on all child tables:
--    - public.documents (validates subject_id belongs to auth.uid())
--    - public.study_sets (validates document_id belongs to auth.uid())
--    - public.flashcards (validates study_set_id belongs to auth.uid())
--    - public.quiz_questions (validates study_set_id belongs to auth.uid())
--    - public.study_sessions (validates study_set_id belongs to auth.uid())
-- 2. Add missing DELETE policy on public.study_sessions.
-- 3. Add missing UPDATE and DELETE policies on storage.objects for 'study_documents'.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. HARDEN POLICIES FOR: public.documents
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can insert own documents" ON public.documents;
DROP POLICY IF EXISTS "Users can update own documents" ON public.documents;

CREATE POLICY "Users can insert own documents" ON public.documents
FOR INSERT WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
        SELECT 1 FROM public.subjects s
        WHERE s.id = subject_id
          AND s.user_id = auth.uid()
    )
);

CREATE POLICY "Users can update own documents" ON public.documents
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
        SELECT 1 FROM public.subjects s
        WHERE s.id = subject_id
          AND s.user_id = auth.uid()
    )
);

-- ----------------------------------------------------------------------------
-- 2. HARDEN POLICIES FOR: public.study_sets
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can insert own study_sets" ON public.study_sets;
DROP POLICY IF EXISTS "Users can update own study_sets" ON public.study_sets;

CREATE POLICY "Users can insert own study_sets" ON public.study_sets
FOR INSERT WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
        SELECT 1 FROM public.documents d
        WHERE d.id = document_id
          AND d.user_id = auth.uid()
    )
);

CREATE POLICY "Users can update own study_sets" ON public.study_sets
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
        SELECT 1 FROM public.documents d
        WHERE d.id = document_id
          AND d.user_id = auth.uid()
    )
);

-- ----------------------------------------------------------------------------
-- 3. HARDEN POLICIES FOR: public.flashcards
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can insert own flashcards" ON public.flashcards;
DROP POLICY IF EXISTS "Users can update own flashcards" ON public.flashcards;

CREATE POLICY "Users can insert own flashcards" ON public.flashcards
FOR INSERT WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
        SELECT 1 FROM public.study_sets ss
        WHERE ss.id = study_set_id
          AND ss.user_id = auth.uid()
    )
);

CREATE POLICY "Users can update own flashcards" ON public.flashcards
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
        SELECT 1 FROM public.study_sets ss
        WHERE ss.id = study_set_id
          AND ss.user_id = auth.uid()
    )
);

-- ----------------------------------------------------------------------------
-- 4. HARDEN POLICIES FOR: public.quiz_questions
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can insert own quiz_questions" ON public.quiz_questions;
DROP POLICY IF EXISTS "Users can update own quiz_questions" ON public.quiz_questions;

CREATE POLICY "Users can insert own quiz_questions" ON public.quiz_questions
FOR INSERT WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
        SELECT 1 FROM public.study_sets ss
        WHERE ss.id = study_set_id
          AND ss.user_id = auth.uid()
    )
);

CREATE POLICY "Users can update own quiz_questions" ON public.quiz_questions
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
        SELECT 1 FROM public.study_sets ss
        WHERE ss.id = study_set_id
          AND ss.user_id = auth.uid()
    )
);

-- ----------------------------------------------------------------------------
-- 5. HARDEN POLICIES FOR: public.study_sessions
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can insert own study_sessions" ON public.study_sessions;
DROP POLICY IF EXISTS "Users can update own study_sessions" ON public.study_sessions;
DROP POLICY IF EXISTS "Users can delete own study_sessions" ON public.study_sessions;

CREATE POLICY "Users can insert own study_sessions" ON public.study_sessions
FOR INSERT WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
        SELECT 1 FROM public.study_sets ss
        WHERE ss.id = study_set_id
          AND ss.user_id = auth.uid()
    )
);

CREATE POLICY "Users can update own study_sessions" ON public.study_sessions
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
        SELECT 1 FROM public.study_sets ss
        WHERE ss.id = study_set_id
          AND ss.user_id = auth.uid()
    )
);

CREATE POLICY "Users can delete own study_sessions" ON public.study_sessions
FOR DELETE USING (auth.uid() = user_id);

-- ----------------------------------------------------------------------------
-- 6. STORAGE BUCKET POLICIES FOR: 'study_documents' (UPDATE & DELETE)
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Authenticated users can update own study documents" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can delete own study documents" ON storage.objects;

CREATE POLICY "Authenticated users can update own study documents"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'study_documents' AND (storage.foldername(name))[1] = auth.uid()::text)
WITH CHECK (bucket_id = 'study_documents' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Authenticated users can delete own study documents"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'study_documents' AND (storage.foldername(name))[1] = auth.uid()::text);

-- ============================================================================
-- VERIFICATION GUIDE & TEST SCENARIOS
-- ============================================================================
-- Execute in Supabase SQL Editor as role authenticated:
--
-- Scenario 1 (Allowed): User A creates document referencing own subject:
--   SET LOCAL ROLE authenticated;
--   SET LOCAL "request.jwt.claims" = '{"sub": "11111111-1111-1111-1111-111111111111"}';
--   INSERT INTO public.documents (subject_id, title, file_type)
--   VALUES ('<USER_A_SUBJECT_ID>', 'Lecture 1', 'IMAGE');
--   -- Result: SUCCESS
--
-- Scenario 2 (Rejected - Foreign Key IDOR Attack):
--   SET LOCAL ROLE authenticated;
--   SET LOCAL "request.jwt.claims" = '{"sub": "22222222-2222-2222-2222-222222222222"}';
--   INSERT INTO public.documents (subject_id, title, file_type)
--   VALUES ('<USER_A_SUBJECT_ID>', 'Malicious Document', 'IMAGE');
--   -- Result: ERROR (violates row-level security policy for table "documents")
-- ============================================================================
