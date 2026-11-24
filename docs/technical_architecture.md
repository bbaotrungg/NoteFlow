# TÀI LIỆU THIẾT KẾ KIẾN TRÚC KỸ THUẬT NOTEFLOW AI
## Technical Architecture Specification & Deep-Dive Engineering Reference

- **Dự án:** NoteFlow (VKU Intelligent Learning Assistant)
- **Cơ quan:** Khoa Khoa học Máy tính — Trường Đại học Công nghệ Thông tin và Truyền thông Việt - Hàn (VKU)
- **Phiên bản:** 1.0.0 (Release Candidate / Phase 5)
- **Tác giả:** Đội ngũ Kiến trúc sư Phần mềm & Kỹ sư An ninh NoteFlow

---

## 1. KIẾN TRÚC TỔNG THỂ HỆ THỐNG (SYSTEM ARCHITECTURE)

NoteFlow được xây dựng theo kiến trúc **Clean Architecture 3 lớp** kết hợp với mô hình quản lý trạng thái phản ứng **Riverpod 2**. Hệ thống tuân thủ nguyên tắc Dependency Inversion: tầng Domain hoàn toàn độc lập với UI framework và các thư viện bên ngoài.

```mermaid
graph TD
    subgraph UI_Layer["Presentation Layer (Flutter 3.22+)"]
        Screens["Screens (Dashboard, StudySet, Flashcard, Quiz, AI Assistant)"]
        Widgets["Reusable Widgets (3D Card, Charts, Weakness, Review Plan)"]
        Notifiers["Riverpod Notifiers & AsyncNotifiers"]
    end

    subgraph Domain_Layer["Domain Layer (Pure Business Logic)"]
        Entities["Core Domain Entities (11 Entities)"]
        UseCases["Application Use Cases"]
        SM2Service["Sm2SpacedRepetitionService"]
        WeaknessService["WeaknessDetectionService"]
        PlannerService["ReviewPlannerService"]
    end

    subgraph Data_Layer["Data Layer (Local & Remote)"]
        RepoImpl["StudyRepositoryImpl"]
        DriftDB["AppDatabase (Drift SQLite Multi-Account Isolation)"]
        OCRService["OcrSpatialClusteringService (On-Device ML Kit)"]
        SyncEngine["OfflineSyncEngine (Two-Way LWW Engine)"]
        GeminiService["GeminiAiService & AiStudyAssistantService"]
    end

    subgraph Cloud_Backend["Cloud & Backend Infrastructure"]
        SupabaseAuth["Supabase Auth (JWT Bearer)"]
        SupabaseDB["Supabase PostgreSQL (Hardened RLS & Cascades)"]
        EdgeFunction["Supabase Edge Function Proxy (Deno Runtime)"]
        GeminiAPI["Google Gemini 1.5 Flash API"]
    end

    Screens --> Notifiers
    Notifiers --> UseCases
    Notifiers --> WeaknessService
    Notifiers --> PlannerService
    UseCases --> RepoImpl
    RepoImpl --> DriftDB
    RepoImpl --> SyncEngine
    RepoImpl --> OCRService
    RepoImpl --> GeminiService
    SyncEngine <-->|Incremental Sync| SupabaseDB
    GeminiService -->|Secure Proxy| EdgeFunction
    EdgeFunction -->|Validate JWT| SupabaseAuth
    EdgeFunction -->|Server API Key| GeminiAPI
```

---

## 2. BIỂU ĐỒ TRƯỜNG HỢP SỬ DỤNG (USE CASE DIAGRAM)

```mermaid
graph LR
    actor Student as "Sinh viên VKU"
    
    subgraph NoteFlow_System["Hệ thống Trợ lý Học tập NoteFlow AI"]
        UC1["1. Quét tài liệu & Nhận diện chữ OCR"]
        UC2["2. Sinh bộ học liệu AI (Tóm tắt, Flashcard, Quiz)"]
        UC3["3. Ôn tập Flashcard theo lịch SuperMemo SM-2"]
        UC4["4. Tham gia phòng thi trắc nghiệm Quiz bấm giờ"]
        UC5["5. Hỏi đáp chuyên sâu cùng Trợ lý AI Study Assistant"]
        UC6["6. Theo dõi phân tích điểm yếu học tập (Weakness Diagnosis)"]
        UC7["7. Thực hiện kế hoạch ôn tập cá nhân hóa hằng ngày"]
        UC8["8. Đồng bộ học liệu hai chiều ngoại tuyến (Offline-First Sync)"]
    end

    Student --> UC1
    Student --> UC2
    Student --> UC3
    Student --> UC4
    Student --> UC5
    Student --> UC6
    Student --> UC7
    Student --> UC8
```

---

## 3. THIẾT KẾ CƠ SỞ DỮ LIỆU & QUAN HỆ THỰC THỂ (DATABASE ERD)

Dữ liệu cục bộ được quản lý bằng Drift ORM (SQLite) và đồng bộ 1:1 với PostgreSQL trên Supabase Cloud.

```mermaid
erDiagram
    SUBJECTS ||--o{ DOCUMENTS : "chứa"
    DOCUMENTS ||--o{ STUDY_SETS : "chuyển hóa thành"
    STUDY_SETS ||--o{ FLASHCARDS : "gồm các thẻ"
    STUDY_SETS ||--o{ QUIZ_QUESTIONS : "gồm các câu hỏi"
    STUDY_SETS ||--o{ STUDY_SESSIONS : "ghi nhận lịch sử"

    SUBJECTS {
        uuid id PK
        uuid user_id FK
        text title
        text code
        text color_hex
        timestamp updated_at
        boolean is_deleted
    }

    DOCUMENTS {
        uuid id PK
        uuid user_id FK
        uuid subject_id FK
        text title
        text file_type
        text local_file_path
        text raw_extracted_text
        timestamp updated_at
        boolean is_deleted
    }

    STUDY_SETS {
        uuid id PK
        uuid user_id FK
        uuid document_id FK
        text title
        text summary_markdown
        timestamp updated_at
        boolean is_deleted
    }

    FLASHCARDS {
        uuid id PK
        uuid user_id FK
        uuid study_set_id FK
        text front_text
        text back_text
        text hint
        double ease_factor
        int interval_days
        int repetition_count
        timestamp next_review_at
        timestamp updated_at
        boolean is_deleted
    }

    QUIZ_QUESTIONS {
        uuid id PK
        uuid user_id FK
        uuid study_set_id FK
        text question_text
        text options_json
        int correct_index
        text explanation
        int times_answered
        int times_correct
        timestamp updated_at
        boolean is_deleted
    }

    STUDY_SESSIONS {
        uuid id PK
        uuid user_id FK
        uuid study_set_id FK
        text session_type
        double score
        int total_items
        int duration_seconds
        timestamp completed_at
    }
```

---

## 4. XÁC THỰC, PHÂN QUYỀN & BẢO VỆ DỮ LIỆU (AUTH & RLS SECURITY)

### 4.1. Row-Level Security (RLS) & Chống IDOR
Toàn bộ 6 bảng dữ liệu trên Supabase đều kích hoạt `ENABLE ROW LEVEL SECURITY`.
Trong bản di trú hardening `20261122000000_harden_rls_foreign_key_ownership.sql`, lỗ hổng Insecure Direct Object Reference (IDOR) bị triệt tiêu bằng cách xác thực quyền sở hữu quan hệ cha-con:
```sql
CREATE POLICY "Users can insert own flashcards" ON public.flashcards
FOR INSERT WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
        SELECT 1 FROM public.study_sets ss
        WHERE ss.id = study_set_id
          AND ss.user_id = auth.uid()
    )
);
```

### 4.2. Cách ly Tài khoản Cục bộ (SQLite Multi-Account Isolation)
Mỗi tài khoản đăng nhập sở hữu một tệp cơ sở dữ liệu vật lý riêng biệt:
- Người dùng khách (chưa đăng nhập): `noteflow_ai_guest.sqlite`
- Người dùng đã xác thực: `noteflow_user_<sanitized_user_id>.sqlite`
Khi người dùng đăng xuất hoặc chuyển tài khoản, Riverpod tự động giải phóng (`ref.onDispose(db.close)`) và mở tệp tương ứng với user mới, ngăn chặn tuyệt đối tình trạng rò rỉ dữ liệu giữa các sinh viên dùng chung thiết bị.

---

## 5. ĐỒNG BỘ HAI CHIỀU NGOẠI TUYẾN (OFFLINE-FIRST SYNC ENGINE)

### 5.1. Luồng Hoạt động Đồng bộ (Flowchart)

```mermaid
flowchart TD
    Start([Khởi động Đồng bộ Sync]) --> CheckNet{Kiểm tra Kết nối Mạng?}
    CheckNet -- Không có mạng --> OfflineMode[Lưu vào bảng sync_queue cục bộ]
    CheckNet -- Có mạng --> FetchPending[Lấy các bản ghi PENDING từ sync_queue]
    FetchPending --> HasItems{Có bản ghi cần gửi?}
    HasItems -- Có --> PushChanges[Gửi đột biến lên Supabase REST API]
    PushChanges --> PushSuccess{Thành công?}
    PushSuccess -- Có --> MarkSynced[Xóa hoặc đánh dấu SYNCED trong queue]
    PushSuccess -- Lỗi 4xx/5xx --> IncRetry[Tăng retry_count & Backoff]
    HasItems -- Không --> PullRemote[Lấy dữ liệu từ Cloud cập nhật sau last_sync_time]
    MarkSynced --> PullRemote
    PullRemote --> ResolveLWW[Giải quyết xung đột theo Last-Write-Wins]
    ResolveLWW --> HandleTombstone{Bản ghi is_deleted = true?}
    HandleTombstone -- Đúng --> CascadeSoftDelete[Xóa mềm cascade các con]
    HandleTombstone -- Sai --> UpsertLocal[Ghi đè bản ghi mới vào SQLite]
    UpsertLocal --> Complete([Hoàn tất chu trình đồng bộ])
    CascadeSoftDelete --> Complete
    IncRetry --> Complete
```

---

## 6. ĐƯỜNG ỐNG XỬ LÝ OCR (ON-DEVICE VISION PIPELINE)

1. **Thu nhận ảnh & Cắt chuẩn hóa:** `image_picker` chụp ảnh tài liệu, `image_cropper` (`UCropActivity`) hỗ trợ xoay và nắn góc nhìn.
2. **On-Device Text Recognition:** Google ML Kit Text Recognition phân tích các `TextBlock`, `TextLine` và `TextElement` trực tiếp trên CPU/NPU thiết bị (hoàn toàn ngoại tuyến).
3. **Spatial Row Clustering:**
   - Sắp xếp các phần tử từ trên xuống dưới theo `boundingBox.top`.
   - Gom các phần tử có độ chồng lấp trục tung $\ge 55\%$ vào cùng một dòng ảo:
     $$\text{Overlap}(A, B) = \frac{\min(A_{\text{bottom}}, B_{\text{bottom}}) - \max(A_{\text{top}}, B_{\text{top}})}{\min(A_{\text{height}}, B_{\text{height}})} \ge 0.55$$
   - Phân tách cột: Nếu khoảng cách ngang vượt quá $2.4\times$ chiều cao ký tự trung bình, hệ thống giữ nguyên khoảng cách định dạng đa cột.

---

## 7. TÍCH HỢP GEMINI AI & SUPABASE EDGE FUNCTION PROXY

### 7.1. Trình tự Gọi API Bảo mật (Sequence Diagram)

```mermaid
sequenceDiagram
    autonumber
    actor User as Sinh viên (NoteFlow Client)
    participant ClientService as AiStudyAssistantService / GeminiAiService
    participant EdgeProxy as Supabase Edge Function (gemini-study-assistant)
    participant CloudAI as Google Gemini 1.5 Flash API

    User->>ClientService: Gửi câu hỏi hoặc Yêu cầu phân tích tài liệu
    
    alt Có phiên đăng nhập Supabase (Production Mode)
        ClientService->>EdgeProxy: POST /functions/v1/gemini-study-assistant<br/>Header: Authorization: Bearer <Supabase_JWT><br/>Body: { action, prompt, context }
        activate EdgeProxy
        EdgeProxy->>EdgeProxy: Xác thực JWT & Kiểm tra Rate Limit (30 req/min)
        EdgeProxy->>CloudAI: POST https://generativelanguage.googleapis.com/...<br/>(Dùng GEMINI_API_KEY lưu trong Deno.env)
        activate CloudAI
        CloudAI-->>EdgeProxy: Trả về nội dung AI JSON / Markdown
        deactivate CloudAI
        EdgeProxy->>EdgeProxy: Hậu kiểm & Khử thông tin nhạy cảm
        EdgeProxy-->>ClientService: 200 OK: { success: true, reply / data }
        deactivate EdgeProxy
    else Chế độ Dev Cục bộ (Local Dev Key)
        ClientService->>CloudAI: Gọi trực tiếp SDK google_generative_ai
        CloudAI-->>ClientService: Phản hồi AI
    else Chế độ Ngoại tuyến (Offline Fallback)
        ClientService->>ClientService: Kích hoạt Offline Heuristic Synthesis<br/>(Gắn banner minh bạch & isOfflineFallback: true)
    end

    ClientService-->>User: Hiển thị phản hồi, căn cứ trích dẫn & bản nháp tự luyện
```

---

## 8. THUẬT TOÁN KHOA HỌC NHẬN THỨC SUPERMEMO SM-2

Hàm cập nhật chu kỳ ôn tập Spaced Repetition thực thi độc lập tại `Sm2SpacedRepetitionService`:
- **Đánh giá phản hồi $q \in \{1, 2, 4, 5\}$:**
  - $q = 1$ (Again)
  - $q = 2$ (Hard)
  - $q = 4$ (Good)
  - $q = 5$ (Easy)
- **Hệ số dễ (Ease Factor $EF'$):**
  $$EF' = \max\left(1.3, EF + \left(0.1 - (5 - q) \cdot (0.08 + (5 - q) \cdot 0.02)\right)\right)$$
- **Khoảng cách ngày ôn tập tiếp theo ($I$):**
  $$I(n) = \begin{cases} 
  1 & \text{khi } q < 3 \\ 
  1 & \text{khi } q \ge 3 \text{ và } n = 1 \\ 
  6 & \text{khi } q \ge 3 \text{ và } n = 2 \\ 
  \text{round}(I(n-1) \cdot EF') & \text{khi } q \ge 3 \text{ và } n > 2 
  \end{cases}$$

---

## 9. THUẬT TOÁN CHẨN ĐOÁN ĐIỂM YẾU HỌC TẬP (WEAKNESS DETECTION)

Điểm tổng hợp độ yếu $S \in [0, 100]$:
$$S = w_f \cdot S_f + w_q \cdot S_q$$
- $S_f = \text{clamp}\left(0, 100, \frac{\overline{\text{ease}}}{2.5} \cdot 100 - \min(30, \text{overdueCount} \cdot 5)\right)$
- $S_q = \left(\frac{\text{correctAnswers}}{\text{totalAnswered}}\right) \cdot 100$

**Trọng số thích ứng:**
- Khi có cả Flashcard và Quiz: $w_f = 0.6, w_q = 0.4$.
- Khi chưa có Quiz (Case A) hoặc chỉ học Flashcard (Case C): $w_f = 1.0, w_q = 0.0$.
- Khi chỉ làm Quiz mà chưa ôn Flashcard (Case D): $w_f = 0.0, w_q = 1.0$ (tránh hiện tượng điểm flashcard mặc định kéo sai lệch kết quả).
- Mẫu thử nhỏ (Case B) và thiếu dữ liệu tương tác (Case E: $< 3$ tương tác): Gắn cờ cảnh báo `isInsufficientData: true`.

---

## 10. KẾ HOẠCH ÔN TẬP CÁ NHÂN HÓA (PERSONALIZED REVIEW PLANNER)

Nhiệm vụ được tạo ra theo 3 nhóm ưu tiên:
1. **Nhiệm vụ Khẩn cấp (`urgent`):** Các thẻ flashcard quá hạn ôn tập ($next\_review\_at \le now$).
2. **Nhiệm vụ Điểm yếu (`weaknessDrill`):** Các chủ đề có mức độ nghiêm trọng `critical` ($S < 40$) hoặc `moderate` ($40 \le S < 60$).
3. **Nhiệm vụ Củng cố (`quizReinforcement`):** Ôn lại các câu hỏi trắc nghiệm có tỷ lệ trả lời đúng thấp.

**Quy tắc an toàn hoàn thành (Session Safety):**
Chỉ đánh dấu hoàn thành nhiệm vụ khi tổng số thẻ thực học trong ngày thỏa mãn:
$$\text{totalReviewedCardsToday} \ge \text{overdueCardsCount}$$

---

## 11. CHIẾN LƯỢC KIỂM THỬ TOÀN DIỆN (TESTING STRATEGY)

Hệ thống kiểm thử tự động gồm 76 bài test phân tầng nghiêm ngặt:
- **Unit Tests (test/domain, test/data):** Kiểm thử thuật toán SM-2, OcrSpatialClustering, WeaknessDetectionService (Cases A-E), ReviewPlannerService (Session Safety), Citation Validation.
- **Widget Tests (test/presentation):** Kiểm thử giao diện M3, Sticky Action Bar, AI Study Assistant screen, Daily Review Plan card.
- **Local Integration Tests (test/integration):** Kiểm thử đường ống end-to-end với Drift in-memory SQLite (`NativeDatabase.memory()`).
- **External Cloud Boundary:** Kiểm thử tự động tuyệt đối không kết nối mạng ra ngoài; sử dụng Heuristic Fallback và Fake Repositories để đảm bảo tính tất định (deterministic) 100%.

---

## 12. QUY TRÌNH ĐÓNG GÓI BẢN PHÁT HÀNH (RELEASE PROCESS)

1. **Kiểm tra an toàn tĩnh:** Chạy `flutter analyze` (đạt 0 lỗi) và `dart format`.
2. **Chạy kiểm thử hồi quy:** Chạy `flutter test` (đảm bảo 100% 76 tests pass).
3. **Biên dịch Release APK an toàn:**
   ```bash
   flutter build apk --release --dart-define=GEMINI_API_KEY=""
   ```
4. **Kiểm tra Artifact:** File APK được tạo tại `build/app/outputs/flutter-apk/app-release.apk` (dung lượng 95.4MB), đảm bảo không chứa API Key nhúng nguyên văn trong `libapp.so`.
