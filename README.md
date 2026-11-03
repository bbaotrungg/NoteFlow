# 🧠 NOTEFLOW AI — Smart Study Notes & Personalized Revision

**Đồ án Capstone Học phần Phát triển Ứng dụng Di động Đa nền tảng (Flutter & Dart 3)**
**Khoa Khoa học Máy tính — Trường Đại học Công nghệ Thông tin và Truyền thông Việt - Hàn (VKU)**
**Giảng viên hướng dẫn:** TS. Nguyễn Thanh Tuấn

---

## 1. Kiến trúc Tổng thể & 3 Phân hệ Kỹ thuật Cốt lõi (3 Core Pillars)

Dự án **NoteFlow AI** tuân thủ nghiêm ngặt kiến trúc **Clean Architecture 3 lớp** (`domain`, `data`, `presentation`) kết hợp **Riverpod 2 (`Notifier` / `AsyncNotifier` / `StreamProvider`)**:

```text
noteflow_ai/
├── lib/
│   ├── main.dart                                      # Entrypoint, khởi tạo Supabase & ProviderScope
│   ├── core/
│   │   ├── constants/app_constants.dart               # Cấu hình hằng số & --dart-define env
│   │   ├── errors/failures.dart                       # Phân cấp lỗi chuẩn Clean Architecture
│   │   ├── theme/app_theme.dart                       # Material 3 Design System (#0284C7 & #0F172A)
│   │   └── utils/date_time_utils.dart                 # Định dạng thời gian & lịch ôn tập tiếng Việt
│   ├── domain/                                        # TẦNG DOMAIN (Độc lập 100% với UI & DB)
│   │   ├── entities/                                  # 7 Thực thể cốt lõi + OCR & AI Entities
│   │   ├── repositories/i_study_repository.dart       # Hợp đồng giao tiếp Repository Interface
│   │   ├── services/sm2_spaced_repetition_service.dart# Thuật toán Khoa học Nhận thức SuperMemo SM-2
│   │   └── usecases/                                  # ReviewFlashcardUseCase & SaveVerifiedStudySetUseCase
│   ├── data/                                          # TẦNG DATA (Drift SQLite, Supabase, ML Kit, Gemini)
│   │   ├── local/
│   │   │   ├── tables/noteflow_tables.dart            # Định nghĩa 7 bảng Drift ORM chuẩn ERD
│   │   │   ├── database/app_database.dart             # Drift Database + Safe Migrations + VKU Seed Data
│   │   │   ├── database/app_database.g.dart           # Generated part file (Biên dịch chạy ngay)
│   │   │   └── daos/                                  # SubjectDao, StudyDao, SyncDao (Reactive Streams)
│   │   ├── services/
│   │   │   ├── ocr_spatial_clustering_service.dart    # On-Device ML Kit OCR + Spatial Row Clustering
│   │   │   └── gemini_ai_service.dart                 # Gemini 1.5 Flash Structured JSON Schema + Retry
│   │   ├── sync/
│   │   │   └── offline_sync_engine.dart               # Đồng bộ 2 chiều Offline-First (LWW & Tombstone)
│   │   └── repositories/study_repository_impl.dart    # Hiện thực hóa Repository với Atomic Transactions
│   └── presentation/                                  # TẦNG PRESENTATION (Material 3, 60 FPS Canvas)
│       ├── providers/app_providers.dart               # Riverpod 2 DI, Reactive Streams & Notifiers
│       ├── widgets/
│       │   ├── charts/
│       │   │   ├── retention_curve_painter.dart       # Đường cong ghi nhớ Ebbinghaus (CustomPainter)
│       │   │   ├── subject_donut_painter.dart         # Biểu đồ tròn tương tác chạm (CustomPainter)
│       │   │   └── weekly_activity_bar_painter.dart   # Biểu đồ cột đôi 7 ngày (CustomPainter)
│       │   └── flashcard/
│       │       └── interactive_3d_flashcard.dart      # Thẻ lật 3D Matrix4 + Cử chỉ vuốt 3 hướng
│       └── screens/
│           ├── home_dashboard_screen.dart             # Màn hình chính thích ứng Mobile & Tablet
│           ├── ocr_ai_pipeline_screen.dart            # Luồng Quét OCR -> Duyệt Text -> Sinh AI -> Lưu
│           ├── study_set_detail_screen.dart           # Xem Markdown Summary & Danh sách thẻ SM-2
│           ├── flashcard_study_screen.dart            # Phòng luyện Flashcard 3D theo lịch SM-2
│           └── quiz_challenge_screen.dart             # Phòng thi Quiz bấm giờ & Giải thích chi tiết
├── supabase/
│   └── migrations/20261026000000_noteflow_schema_and_rls.sql # PostgreSQL Schema & RLS Policies
├── test/                                              # Bộ Unit Test kiểm thử SM-2 & Spatial OCR
├── android/ & ios/                                    # Cấu hình UCropActivity, ML Kit OCR & Permissions
└── .github/workflows/flutter_ci_release.yml           # CI/CD tự động chạy test & xuất file APK
```

---

## 2. Hướng dẫn Cài đặt & Chạy Dự án

### Bước 1: Cài đặt thư viện

```bash
cd noteflow_ai
flutter pub get
```

### Bước 2: Chạy Kiểm thử Tự động (Unit Tests)

```bash
flutter test
```

### Bước 3: Chạy Ứng dụng (Hỗ trợ cả chế độ có API Key hoặc Offline Demo tự động)

```bash
# Chạy ngay lập tức với dữ liệu học thuật mẫu VKU và bộ tổng hợp Offline thông minh:
flutter run

# Hoặc chạy với khóa Google Gemini 1.5 Flash & Supabase Cloud thực tế:
flutter run   --dart-define=GEMINI_API_KEY=AIzaSyYourKey   --dart-define=SUPABASE_URL=https://your-project.supabase.co   --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

### Bước 4: Khởi tạo Cơ sở dữ liệu Supabase Cloud

Copy toàn bộ nội dung file `supabase/migrations/20261026000000_noteflow_schema_and_rls.sql` và chạy trực tiếp trong **Supabase SQL Editor** để khởi tạo 6 bảng dữ liệu, Indexes, Storage Bucket và chính sách bảo mật **Row-Level Security (RLS)**.
