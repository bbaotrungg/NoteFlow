-- ============================================================================
-- NOTEFLOW AI - SUPABASE POSTGRESQL SCHEMA & ROW-LEVEL SECURITY (RLS)
-- Khoa Khoa học Máy tính - Đại học CNTT & TT Việt - Hàn (VKU)
-- Đồng bộ 1:1 với Drift SQLite Local Schema (Hỗ trợ Offline-First LWW Sync)
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. BẢNG SUBJECTS (Môn học)
CREATE TABLE IF NOT EXISTS public.subjects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    code TEXT NOT NULL,
    color_hex TEXT NOT NULL DEFAULT '#0284C7',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE
);

-- 2. BẢNG DOCUMENTS (Tài liệu học tập)
CREATE TABLE IF NOT EXISTS public.documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    subject_id UUID NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    file_type TEXT NOT NULL CHECK (file_type IN ('IMAGE', 'PDF', 'TEXT')),
    local_file_path TEXT NOT NULL DEFAULT '',
    remote_storage_path TEXT,
    raw_extracted_text TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE
);

-- 3. BẢNG STUDY_SETS (Bộ học liệu do AI sinh ra)
CREATE TABLE IF NOT EXISTS public.study_sets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    document_id UUID NOT NULL REFERENCES public.documents(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    summary_markdown TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE
);

-- 4. BẢNG FLASHCARDS (Thẻ ghi nhớ với tham số SuperMemo SM-2)
CREATE TABLE IF NOT EXISTS public.flashcards (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    study_set_id UUID NOT NULL REFERENCES public.study_sets(id) ON DELETE CASCADE,
    front_text TEXT NOT NULL,
    back_text TEXT NOT NULL,
    hint TEXT,
    ease_factor DOUBLE PRECISION NOT NULL DEFAULT 2.5,
    interval_days INTEGER NOT NULL DEFAULT 0,
    repetition_count INTEGER NOT NULL DEFAULT 0,
    next_review_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE
);

-- 5. BẢNG QUIZ_QUESTIONS (Câu hỏi trắc nghiệm)
CREATE TABLE IF NOT EXISTS public.quiz_questions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    study_set_id UUID NOT NULL REFERENCES public.study_sets(id) ON DELETE CASCADE,
    question_text TEXT NOT NULL,
    options_json TEXT NOT NULL, -- JSON array 4 lựa chọn
    correct_index INTEGER NOT NULL CHECK (correct_index >= 0 AND correct_index <= 3),
    explanation TEXT NOT NULL DEFAULT '',
    times_answered INTEGER NOT NULL DEFAULT 0,
    times_correct INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE
);

-- 6. BẢNG STUDY_SESSIONS (Lịch sử phiên học)
CREATE TABLE IF NOT EXISTS public.study_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    study_set_id UUID NOT NULL REFERENCES public.study_sets(id) ON DELETE CASCADE,
    session_type TEXT NOT NULL CHECK (session_type IN ('FLASHCARD', 'QUIZ')),
    score DOUBLE PRECISION,
    total_items INTEGER NOT NULL DEFAULT 0,
    duration_seconds INTEGER NOT NULL DEFAULT 0,
    completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- INDEXES TỐI ƯU TRUY VẤN INCREMENTAL SYNC & ÔN TẬP SM-2
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_subjects_updated_at ON public.subjects(user_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_documents_subject_id ON public.documents(subject_id, is_deleted);
CREATE INDEX IF NOT EXISTS idx_study_sets_document_id ON public.study_sets(document_id, is_deleted);
CREATE INDEX IF NOT EXISTS idx_flashcards_next_review ON public.flashcards(user_id, next_review_at) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_quiz_study_set ON public.quiz_questions(study_set_id, is_deleted);
CREATE INDEX IF NOT EXISTS idx_sessions_completed_at ON public.study_sessions(user_id, completed_at);

-- ============================================================================
-- ROW-LEVEL SECURITY (RLS) POLICIES - BẢO MẬT DỮ LIỆU CÁ NHÂN SINH VIÊN
-- ============================================================================
ALTER TABLE public.subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.study_sets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.flashcards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quiz_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.study_sessions ENABLE ROW LEVEL SECURITY;

-- Policies cho SUBJECTS
CREATE POLICY "Users can select own subjects" ON public.subjects FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own subjects" ON public.subjects FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own subjects" ON public.subjects FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete own subjects" ON public.subjects FOR DELETE USING (auth.uid() = user_id);

-- Policies cho DOCUMENTS
CREATE POLICY "Users can select own documents" ON public.documents FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own documents" ON public.documents FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own documents" ON public.documents FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete own documents" ON public.documents FOR DELETE USING (auth.uid() = user_id);

-- Policies cho STUDY_SETS
CREATE POLICY "Users can select own study_sets" ON public.study_sets FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own study_sets" ON public.study_sets FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own study_sets" ON public.study_sets FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete own study_sets" ON public.study_sets FOR DELETE USING (auth.uid() = user_id);

-- Policies cho FLASHCARDS
CREATE POLICY "Users can select own flashcards" ON public.flashcards FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own flashcards" ON public.flashcards FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own flashcards" ON public.flashcards FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete own flashcards" ON public.flashcards FOR DELETE USING (auth.uid() = user_id);

-- Policies cho QUIZ_QUESTIONS
CREATE POLICY "Users can select own quiz_questions" ON public.quiz_questions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own quiz_questions" ON public.quiz_questions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own quiz_questions" ON public.quiz_questions FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete own quiz_questions" ON public.quiz_questions FOR DELETE USING (auth.uid() = user_id);

-- Policies cho STUDY_SESSIONS
CREATE POLICY "Users can select own study_sessions" ON public.study_sessions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own study_sessions" ON public.study_sessions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own study_sessions" ON public.study_sessions FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- STORAGE BUCKET POLICY CHO FILE PDF & ẢNH BÀI GIẢNG GỐC
-- ============================================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('study_documents', 'study_documents', false)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Authenticated users can upload study documents"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'study_documents' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Authenticated users can read own study documents"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'study_documents' AND (storage.foldername(name))[1] = auth.uid()::text);
