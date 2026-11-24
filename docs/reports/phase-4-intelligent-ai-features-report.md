# NoteFlow — Báo Cáo Kỹ Thuật Giai Đoạn 4: Phân Hệ Tính Năng AI Thông Minh
## Phase 4 — Intelligent AI Features Engineering Report

- **Dự án:** NoteFlow (VKU AI-Powered Spaced Repetition & Study App)
- **Framework & Ngôn ngữ:** Flutter 3.47.7 • Dart 3.13.5
- **Kiến trúc:** Clean Architecture (Domain - Data - Presentation)
- **Quản lý trạng thái:** Flutter Riverpod 2 (Reactive Stream Providers & State Notifiers)
- **Cơ sở dữ liệu cục bộ & Đám mây:** Drift / SQLite (Multi-tenant Account Isolation) • Supabase BaaS
- **AI Core:** Google Gemini 1.5 Flash API (Structured Grounding & Context Bounding) • ML Kit OCR
- **Trạng thái hoàn thành:** **COMPLETED** (Hoàn thành 100% mục tiêu, 68/68 unit/widget/integration tests passed, 0 flutter analyze warnings)
- **Thời gian thực hiện:** 24/11/2026

---

## 1. TỔNG QUAN DỰ ÁN & MỤC TIÊU GIAI ĐOẠN 4 (EXECUTIVE SUMMARY)

Tiếp nối thành công của **Giai đoạn 1 (Foundation & Code Quality)**, **Giai đoạn 2 (Core Feature Refinement)** và **Giai đoạn 3 (UI/UX Enhancement)**, Giai đoạn 4 tập trung vào việc hiện thực hóa 3 trụ cột thông minh cốt lõi của NoteFlow:

1. **Trợ lý Học tập AI (AI Study Assistant):** Hệ thống hỏi đáp và giải thích kiến thức ngữ cảnh, neo chặt chẽ (Context Grounding) vào học liệu thực tế của sinh viên (Study Sets, Flashcards, Quiz questions, OCR text), kiểm soát Token Bounding nghiêm ngặt, tự động trích dẫn căn cứ học thuật, có khả năng sinh câu hỏi tự luyện (Practice Generation) dưới dạng bản nháp an toàn không tự ý ghi đè dữ liệu người dùng, cùng cơ chế Offline Synthesis thông minh khi mất mạng hoặc chưa cấu hình Gemini API Key.
2. **Hệ thống Phát hiện Điểm yếu Thông minh (Smart Weakness Detection):** Phân tích toán học xác định (Deterministic Mathematical Analysis) không võ đoán dựa trên độ khó SuperMemo SM-2 (Ease Factor $< 2.0$), tỷ lệ trả lời đúng câu hỏi trắc nghiệm ($< 60\%$), và lịch sử các phiên học gần đây; tích hợp cơ chế bảo vệ dữ liệu tối thiểu (Insufficient Data Guard) và giải thích minh bạch chỉ số năng lực.
3. **Kế hoạch Ôn tập Cá nhân hóa Hàng ngày (Personalized Review Planner):** Hệ thống lập lịch ôn tập thích ứng hàng ngày, tuân thủ nghiêm ngặt thuật toán SM-2 làm nguồn chân lý, phân cấp ưu tiên thông minh (Khẩn cấp: Thẻ quá hạn $\rightarrow$ Quan trọng: Thẻ đến hạn hôm nay & Củng cố điểm yếu $\rightarrow$ Tiêu chuẩn: Kiểm tra trắc nghiệm), tự động thích ứng tức thì (Dynamic Session Completion) khi sinh viên hoàn thành phiên học.

---

## 2. KIẾN TRÚC TỔNG THỂ & NGUYÊN TẮC THIẾT KẾ (ARCHITECTURE & DESIGN PRINCIPLES)

Phân hệ AI Thông minh được xây dựng bám sát chuẩn **Clean Architecture** và nguyên tắc **Offline-First Resilience**:

```
lib/
├── domain/
│   ├── entities/
│   │   ├── study_assistant_message.dart      # Thực thể tin nhắn trợ lý & bản nháp tự luyện
│   │   ├── weakness_analysis_result.dart     # Thực thể mức độ thông thạo (Mastery) & điểm yếu
│   │   └── review_plan_entity.dart           # Thực thể nhiệm vụ ôn tập & kế hoạch hàng ngày
│   └── services/
│       ├── weakness_detection_service.dart   # Dịch vụ phân tích toán học thuần xác định
│       └── review_planner_service.dart       # Dịch vụ lập lịch ưu tiên thích ứng theo SM-2
├── data/
│   └── services/
│       └── ai_study_assistant_service.dart   # Service gọi Gemini 1.5 Flash + Context Grounding & Offline Fallback
└── presentation/
    ├── providers/
    │   └── app_providers.dart                # Riverpod 2 DI, Notifier & Reactive Stream providers
    ├── screens/
    │   ├── ai_study_assistant_screen.dart    # Màn hình Chatbot trợ lý học tập AI chuẩn Accessibility
    │   ├── home_dashboard_screen.dart        # Tích hợp DailyReviewPlanCard & WeaknessInsightsSection
    │   └── study_set_detail_screen.dart      # Nút mở Trợ lý AI & Banner cảnh báo điểm yếu theo bộ học liệu
    └── widgets/
        ├── review_plan/
        │   └── daily_review_plan_card.dart   # Thẻ kế hoạch ôn tập hôm nay kèm nút hành động 1 chạm
        └── weakness/
            └── weakness_insights_section.dart# Phân tích năng lực tổng thể & Top nội dung cần củng cố
```

### Các nguyên tắc thiết kế bất biến:
- **Clean Architecture & Separation of Concerns:** Domain layer hoàn toàn độc lập, không phụ thuộc Flutter framework hay API bên thứ ba. Dịch vụ phân tích điểm yếu và lập kế hoạch là pure Dart services, dễ dàng kiểm thử cô lập.
- **Context Grounding & Anti-Hallucination:** Trợ lý AI được neo chặt chẽ vào dữ liệu học tập đã OCR của người dùng, ép buộc trích dẫn `[Căn cứ: Thẻ ghi nhớ X]` hoặc `[Căn cứ: Tóm tắt bài giảng]`.
- **Data Preservation & No Auto-Overwrite:** Các câu hỏi tự luyện do AI sinh được biểu diễn dưới dạng bản nháp (`practiceFlashcards`, `practiceQuizzes`). Người dùng phải chủ động bấm "Lưu vào Thẻ" để lưu vào SQLite qua `updateStudySetContent`.
- **Data Minimization & Token Bounding:** Ngữ cảnh nạp vào prompt được giới hạn tối đa $10.000$ ký tự, ngăn ngừa tràn token context, giảm độ trễ và chi phí API.
- **Multi-Tenant SQLite Isolation:** Tôn trọng toàn bộ cơ chế cô lập tài khoản cục bộ `AppDatabase.forUser(userId)` đã thiết lập từ Giai đoạn 1.

---

## 3. CHI TIẾT HIỆN THỰC HÓA 3 GIAI ĐOẠN

### 3.1. Stage A — AI Study Assistant (Trợ lý Học tập AI)
- **File triển khai:**
  - `lib/domain/entities/study_assistant_message.dart`
  - `lib/data/services/ai_study_assistant_service.dart`
  - `lib/presentation/providers/app_providers.dart` (`StudyAssistantNotifier`, `studyAssistantNotifierProvider`)
  - `lib/presentation/screens/ai_study_assistant_screen.dart`
- **Các tính năng kỹ thuật nổi bật:**
  - **Context Grounding Builder:** Phương thức `buildGroundedContext()` tự động tổng hợp tiêu đề bộ học liệu, môn học, bản tóm tắt Markdown, danh sách câu hỏi/đáp Flashcard kèm gợi ý, và câu hỏi trắc nghiệm kèm giải thích; tự động cắt tỉa an toàn ở ngưỡng $10.000$ ký tự.
  - **Prompt Engineering & System Instruction:** Ràng buộc Gemini 1.5 Flash chỉ phát biểu dựa trên tài liệu được cung cấp, trả về trích dẫn `[Căn cứ: ...]` và gợi ý câu hỏi tiếp nối `{{Gợi ý: ...}}`.
  - **Practice Generation:** Tự động nhận diện cú pháp câu hỏi trắc nghiệm hoặc flashcard nháp trong văn bản trả về của AI để hiển thị khối "Câu hỏi Tự luyện được sinh bởi AI", cho phép người dùng bấm "Lưu vào Thẻ" mà không làm mất dữ liệu hiện tại.
  - **Offline Synthesis Fallback:** Khi chạy không có API key hoặc mất mạng, thuật toán tự động phân tích từ khóa câu hỏi người dùng, đối chiếu với flashcards và summary để trả về câu trả lời có cấu trúc và câu hỏi tự luyện tương thích, đảm bảo ứng dụng không bao giờ bị crash hay tê liệt.
  - **UI/UX Trợ lý:** Màn hình chat trực quan với Popup chọn ngữ cảnh bộ học liệu, banner hiển thị số thẻ/quiz đang neo, danh sách gợi ý câu hỏi nhanh (Quick Prompts), bong bóng chat phân biệt rõ rệt người dùng/trợ lý, trình kết xuất Markdown chuẩn mực, nút sao chép, và nút "Thử lại" khi gặp lỗi mạng.

### 3.2. Stage B — Smart Weakness Detection (Phát hiện Điểm yếu Thông minh)
- **File triển khai:**
  - `lib/domain/entities/weakness_analysis_result.dart`
  - `lib/domain/services/weakness_detection_service.dart`
  - `lib/presentation/widgets/weakness/weakness_insights_section.dart`
- **Mô hình Toán học Xác định (Deterministic Scoring Model):**
  - **Hệ số Ease Factor SM-2:** Thẻ có $EF < 2.0$ (mức khởi tạo chuẩn là $2.5$, mức sàn chống Ease-Hell là $1.3$) hoặc có $repetitionCount \ge 3$ nhưng $intervalDays \le 2$ được phân loại là **Thẻ yếu / Điểm yếu nghiêm trọng**.
  - **Độ chính xác Quiz:** Câu hỏi trắc nghiệm có $timesAnswered \ge 1$ và $accuracyRate < 60\%$ được phân loại là **Câu hỏi trắc nghiệm yếu**.
  - **Insufficient Data Guard:** Nếu bộ học liệu có tổng số lượt tương tác $< 3$ và số thẻ đã ôn $< 2$, hệ thống phân loại vào `MasteryLevel.insufficientData` kèm lời khuyên "Cần thêm dữ liệu ôn tập" thay vì đưa ra nhận định sai lệch.
  - **Chỉ số Thông thạo (Mastery Score: 0.0 - 100.0):**
    $$\text{Score} = 0.6 \times \text{FlashcardScore} + 0.4 \times \text{QuizScore}$$
    Trong đó $\text{FlashcardScore}$ chuẩn hóa từ Ease Factor trung bình ($1.3 \rightarrow 0\%$, $2.5+ \rightarrow 100\%$) trừ đi điểm phạt theo tỷ lệ thẻ yếu.
  - **Phân cấp Thông thạo:**
    - `MasteryLevel.strong` (Vững chắc): $\text{Score} \ge 78.0\%$ và không có thẻ yếu.
    - `MasteryLevel.weak` (Cần củng cố): $\text{Score} < 60.0\%$ hoặc có từ 2 thẻ yếu trở lên.
    - `MasteryLevel.moderate` (Trung bình): Các trường hợp còn lại.
  - **Tính giải thích được (Explainability):** Mỗi điểm yếu đều hiển thị rõ lý do: ví dụ `"Hệ số ghi nhớ SM-2 thấp (EF: 1.50 < 2.0). Đã quên hoặc gặp khó khăn nhiều lần."` hoặc `"Độ chính xác trắc nghiệm thấp: 20% (1/5 câu đúng)."`.

### 3.3. Stage C — Personalized Review Planner (Kế hoạch Ôn tập Cá nhân hóa)
- **File triển khai:**
  - `lib/domain/entities/review_plan_entity.dart`
  - `lib/domain/services/review_planner_service.dart`
  - `lib/presentation/widgets/review_plan/daily_review_plan_card.dart`
- **Thuật toán Phân loại Ưu tiên (Adaptive Spaced Repetition Prioritization):**
  1. **KHẨN CẤP (`ReviewTaskPriority.urgent`):** Thẻ Flashcard đã quá hạn ôn tập so với đầu ngày hôm nay ($nextReviewAt < startOfToday$). Ước tính thời gian $\max(3, \lceil n \times 0.6 \rceil)$ phút.
  2. **QUAN TRỌNG (`ReviewTaskPriority.high`):** Thẻ Flashcard đến hạn trong ngày hôm nay ($nextReviewAt \le endOfToday$) VÀ các chủ đề điểm yếu (`ReviewTaskType.weaknessDrill`) phát hiện từ Stage B.
  3. **TIÊU CHUẨN (`ReviewTaskPriority.normal`):** Luyện trắc nghiệm củng cố (`ReviewTaskType.quizReinforcement`) đối với các bộ học liệu có bài thi gần nhất $< 70\%$ hoặc đã quá 3 ngày chưa làm quiz.
  4. **DUY TRÌ (`ReviewTaskPriority.maintenance`):** Các chủ đề vững chắc để duy trì trí nhớ dài hạn.
- **Thích ứng Động theo Phiên học (Dynamic Session Completion):**
  - Hệ thống tự động quét các bản ghi `StudySessionEntity` hoàn thành trong ngày hôm nay.
  - Nếu sinh viên vừa hoàn thành một phiên Flashcard hoặc Quiz cho bộ học liệu tương ứng, nhiệm vụ lập tức chuyển sang trạng thái `isCompleted = true`, thanh tiến trình cập nhật tỷ lệ hoàn thành ngày, và nhiệm vụ được gạch ngang trực quan.

---

## 4. QUẢN LÝ TRẠNG THÁI VÀ ĐỒNG BỘ GIAO DIỆN (RIVERPOD 2 REACTIVE PIPELINE)

Các providers trong `lib/presentation/providers/app_providers.dart` tạo thành một đường ống phản ứng khép kín:

```
studySetsStreamProvider ───┐
subjectsStreamProvider  ───┼──> weaknessAnalysisProvider ──┐
recentSessionsStreamProvider┘                              │
                                                           ├──> dailyReviewPlanProvider
                                                           │
                                   aiStudyAssistantServiceProvider
                                                   │
                                      studyAssistantNotifierProvider
```

- Khi người dùng đánh giá thẻ (SM-2) trong `FlashcardStudyScreen` hoặc nộp bài Quiz trong `QuizChallengeScreen`, repository ghi nhận xuống Drift SQLite và bắn sự kiện qua `watchAllStudySets` và `watchRecentSessions`.
- `weaknessAnalysisProvider` và `dailyReviewPlanProvider` tự động tính toán lại mà không cần reload trang hay gọi API bên ngoài, đảm bảo trải nghiệm 60 FPS mượt mà.

---

## 5. BẢNG DANH MỤC THAY ĐỔI MÃ NGUỒN (CODE IMPACT SUMMARY)

| STT | File đường dẫn | Layer | Loại thay đổi | Mô tả chi tiết |
|---|---|---|---|---|
| 1 | `lib/domain/entities/study_assistant_message.dart` | Domain | Mới | Định nghĩa thực thể tin nhắn hội thoại, trích dẫn học liệu, gợi ý hành động và bản nháp câu hỏi tự luyện |
| 2 | `lib/domain/entities/weakness_analysis_result.dart` | Domain | Mới | Định nghĩa Enum `MasteryLevel`, `WeakItemType`, các thực thể `WeakItemEntity`, `TopicWeaknessEntity`, `WeaknessAnalysisResult` |
| 3 | `lib/domain/entities/review_plan_entity.dart` | Domain | Mới | Định nghĩa Enum `ReviewTaskPriority`, `ReviewTaskType`, thực thể `ReviewPlanTaskEntity`, `DailyReviewPlan` |
| 4 | `lib/domain/services/weakness_detection_service.dart` | Domain | Mới | Pure Dart service tính toán năng lực học tập, phát hiện thẻ yếu ($EF < 2.0$), quiz accuracy thấp, Insufficient Data Guard |
| 5 | `lib/domain/services/review_planner_service.dart` | Domain | Mới | Pure Dart service lập kế hoạch học tập cá nhân hóa thích ứng động theo phiên học hôm nay |
| 6 | `lib/data/services/ai_study_assistant_service.dart` | Data | Mới | Service gọi Gemini 1.5 Flash, context grounding bounding 10.000 ký tự, trích dẫn căn cứ, và offline synthesis fallback |
| 7 | `lib/presentation/providers/app_providers.dart` | Presentation | Cập nhật | Bổ sung DI providers, reactive providers cho Weakness & Review Plan, và Notifier cho AI Study Assistant |
| 8 | `lib/presentation/screens/ai_study_assistant_screen.dart` | Presentation | Mới | Màn hình chat Trợ lý AI toàn diện với Context selector, Quick prompts, Markdown body, và Practice item review |
| 9 | `lib/presentation/widgets/review_plan/daily_review_plan_card.dart` | Presentation | Mới | Widget hiển thị Kế hoạch ôn tập hàng ngày, tiến độ phần trăm, huy hiệu ưu tiên và nút mở phiên học 1 chạm |
| 10 | `lib/presentation/widgets/weakness/weakness_insights_section.dart` | Presentation | Mới | Widget hiển thị chẩn đoán năng lực học tập, thẻ thống kê, Top nội dung cần củng cố và nút hỏi AI |
| 11 | `lib/presentation/screens/home_dashboard_screen.dart` | Presentation | Cập nhật | Tích hợp nút AppBar mở Trợ lý AI, nhúng `DailyReviewPlanCard` và `WeaknessInsightsSection` vào Tab Tổng quan & Thống kê |
| 12 | `lib/presentation/screens/study_set_detail_screen.dart` | Presentation | Cập nhật | Thêm nút "Hỏi đáp Trợ lý AI" và Banner cảnh báo điểm yếu theo từng bộ học liệu |
| 13 | `test/domain/weakness_detection_service_test.dart` | Test | Mới | Bộ 4 unit tests kiểm thử toàn diện thuật toán phát hiện điểm yếu toán học, ngưỡng EF, quiz accuracy, insufficient data |
| 14 | `test/domain/review_planner_service_test.dart` | Test | Mới | Bộ 4 unit tests kiểm thử phân cấp ưu tiên SM-2 (Urgent/High/Normal), thích ứng động theo session, weakness drill |
| 15 | `test/data/ai_study_assistant_service_test.dart` | Test | Mới | Bộ 4 unit tests kiểm thử context grounding bounding, offline synthesis, sinh câu hỏi nháp an toàn không đè DB |
| 16 | `test/presentation/ai_study_assistant_screen_test.dart` | Test | Mới | Bộ 2 widget tests kiểm thử render màn hình trợ lý AI, empty state, quick prompt chips và gửi câu hỏi |
| 17 | `test/presentation/weakness_and_review_plan_widget_test.dart` | Test | Mới | Bộ 2 widget tests kiểm thử render `DailyReviewPlanCard` và `WeaknessInsightsSection` |
| 18 | `test/integration/phase4_intelligent_ai_features_test.dart` | Test | Mới | Integration test chu trình khép kín: SM-2 review -> Giảm EF -> Phát hiện điểm yếu -> Lập kế hoạch -> Session done -> AI grounding |

---

## 6. KẾT QUẢ KIỂM THỬ VÀ ĐẢM BẢO CHẤT LƯỢNG (VERIFICATION & QUALITY ASSURANCE)

### 6.1. Kiểm thử Tĩnh (Static Analysis)
- **Lệnh thực thi:** `flutter analyze`
- **Kết quả:** `No issues found! (ran in 5.1s)`
- **Số lượng cảnh báo / lỗi:** **0 warnings, 0 errors, 0 lints**.
- **Chuẩn định dạng mã nguồn:** `dart format --output=none --set-exit-if-changed .` đạt chuẩn 100% (63 files formatted, 0 changed).

### 6.2. Kiểm thử Tự động Toàn diện (Full Automated Test Suite)
- **Lệnh thực thi:** `flutter test`
- **Tổng số ca kiểm thử:** **68 test cases**
- **Kết quả:** **68 / 68 tests passed (100% Pass Rate)**
- **Thời gian chạy:** ~5 giây
- **Phân bổ bài test:**
  - `test/domain/sm2_spaced_repetition_service_test.dart`: 6 tests passed
  - `test/domain/study_entities_and_sm2_test.dart`: 8 tests passed
  - `test/domain/weakness_detection_service_test.dart`: 4 tests passed
  - `test/domain/review_planner_service_test.dart`: 4 tests passed
  - `test/data/ai_study_assistant_service_test.dart`: 4 tests passed
  - `test/data/cascade_soft_delete_and_zombie_prevention_test.dart`: 7 tests passed
  - `test/data/core_feature_refinement_test.dart`: 7 tests passed
  - `test/data/multi_account_isolation_and_session_sync_test.dart`: 7 tests passed
  - `test/data/ocr_spatial_clustering_and_lww_test.dart`: 8 tests passed
  - `test/data/offline_sync_engine_lww_test.dart`: 5 tests passed
  - `test/presentation/ai_study_assistant_screen_test.dart`: 2 tests passed
  - `test/presentation/weakness_and_review_plan_widget_test.dart`: 2 tests passed
  - `test/presentation/ui_ux_enhancement_widget_test.dart`: 3 tests passed
  - `test/integration/full_learning_workflow_integration_test.dart`: 7 tests passed
  - `test/integration/phase4_intelligent_ai_features_test.dart`: 1 full end-to-end integration test passed

---

## 7. ĐÁNH GIÁ AN TOÀN DỮ LIỆU & BẢO MẬT (DATA SAFETY & SECURITY AUDIT)

1. **Bảo vệ Tính toàn vẹn Dữ liệu Học tập (Data Integrity):**
   - Trợ lý AI tuyệt đối không tự động tạo mới hay ghi đè bản ghi trong bảng `flashcards` hoặc `quiz_questions`.
   - Các câu hỏi trắc nghiệm hoặc flashcard tự luyện do AI gợi ý được đưa vào danh sách bản nháp và hiển thị giao diện phê duyệt rõ ràng. Chỉ khi người dùng bấm "Lưu vào Thẻ", hệ thống mới gọi `StudyRepository.updateStudySetContent()`.
2. **Bảo mật Khóa API (No Secret Leakage):**
   - Gemini API Key được nạp qua hằng số `AppConstants.geminiApiKey` (hỗ trợ `--dart-define` khi build production).
   - Khi chạy ở môi trường không có khóa bí mật, dịch vụ chuyển đổi mượt mà sang cơ chế Offline Synthesis mà không log ra console bất kỳ thông tin nhạy cảm nào.
3. **Kiểm soát Tải & Chi phí (Cost & Token Control):**
   - Ràng buộc cứng $10.000$ ký tự tối đa cho Grounded Context.
   - Giới hạn lịch sử hội thoại gửi lên AI chỉ lấy 6 lượt tương tác gần nhất để triệt tiêu nguy cơ bùng nổ token.
   - Tích hợp Exponential Backoff Retry (1s, 2s, 4s...) với timeout 30s để tránh nghẽn thread.

---

## 8. KẾT LUẬN & TRẠNG THÁI CUỐI CÙNG (FINAL COMPLETION STATUS)

- **Trạng thái chính thức:** **`COMPLETED`**
- **Đánh giá tổng kết:** Toàn bộ 3 giai đoạn của **Phase 4 — Intelligent AI Features** (AI Study Assistant, Smart Weakness Detection, Personalized Review Planner) đã được hiện thực hóa trọn vẹn, tuân thủ Clean Architecture, kiểm thử 68/68 bài test thành công, đạt 0 lỗi phân tích tĩnh, và tích hợp hài hòa vào NoteFlow mà không phá vỡ bất kỳ tính năng hiện có nào.
