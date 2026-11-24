# BÁO CÁO THUYẾT TRÌNH ĐỒ ÁN CAPSTONE
## NoteFlow AI — Trợ lý Học tập Thông minh & Ôn tập Cá nhân hóa

**Khoa Khoa học Máy tính — Trường Đại học Công nghệ Thông tin và Truyền thông Việt - Hàn (VKU)**  
**Học phần:** Phát triển Ứng dụng Di động Đa nền tảng (Flutter & Dart 3)  
**Giảng viên hướng dẫn:** TS. Nguyễn Thanh Tuấn  
**Nhóm sinh viên thực hiện:** Đội ngũ NoteFlow AI VKU  
**Thời lượng dự kiến:** 15 - 20 phút

---

## SLIDE 1: TRANG TIÊU ĐỀ & THÔNG TIN DỰ ÁN
- **Tên đồ án:** NOTEFLOW AI — Smart Study Notes & Personalized Revision.
- **Nền tảng phát triển:** Flutter 3, Dart 3, Material 3, Clean Architecture.
- **Chủ đề chính:** Ứng dụng Trí tuệ Nhân tạo (Vision AI + Generative AI) và Khoa học Nhận thức (Cognitive Science) nâng cao hiệu suất học tập cho sinh viên CNTT.

---

## SLIDE 2: BỐI CẢNH & ĐẶT VẤN ĐỀ (PROBLEM STATEMENT)
1. **Quá tải thông tin học thuật:** Sinh viên ngành Khoa học Máy tính phải tiếp nhận lượng lớn kiến thức lý thuyết, công thức toán và mã nguồn từ nhiều nguồn rời rạc (ảnh chụp slide, bảng viết, tài liệu PDF).
2. **Thiếu tính cấu trúc:** Ghi chép thường hỗn loạn, không được phân cấp rõ ràng thành các khái niệm cốt lõi, flashcard và câu hỏi tự luyện.
3. **Hiện tượng lãng quên nhanh (Ebbinghaus Forgetting Curve):** Hơn 70% kiến thức bị lãng quên chỉ sau 48 giờ nếu không được củng cố theo chu kỳ lặp lại ngắt quãng khoa học.
4. **Phụ thuộc kết nối mạng:** Nhiều ứng dụng học tập trực tuyến hiện nay không hoạt động được khi sinh viên học tập tại thư viện hoặc khu vực mạng kém.

---

## SLIDE 3: MỤC TIÊU ĐỒ ÁN & GIẢI PHÁP ĐỀ XUẤT (PROPOSED SOLUTION)
- **Mục tiêu:** Xây dựng ứng dụng di động thông minh, hoạt động ngoại tuyến trước tiên (**Offline-First**), tự động số hóa và chuyển hóa tài liệu bài giảng thành tài nguyên học tập cá nhân hóa.
- **Giải pháp NoteFlow:**
  - **Số hóa thị giác tại biên (Edge Vision):** Trích xuất văn bản on-device bằng Google ML Kit Text Recognition kết hợp thuật toán phân tách cột hình học **Spatial Row Clustering**.
  - **Tạo học liệu có cấu trúc bằng Generative AI:** Google Gemini 1.5 Flash sinh đồng thời Bản tóm tắt học thuật Markdown, Flashcard SM-2 và Câu hỏi trắc nghiệm Quiz 4 lựa chọn.
  - **Bộ máy Khoa học Nhận thức SuperMemo SM-2:** Lên lịch ôn tập tự động tối ưu hóa đường cong trí nhớ.
  - **Phân tích điểm yếu thích ứng & Lập kế hoạch ôn tập cá nhân hóa:** Tự động phát hiện các chủ đề sinh viên chưa nắm vững và đề xuất nhiệm vụ ưu tiên hằng ngày.

---

## SLIDE 4: KIẾN TRÚC HỆ THỐNG & CÔNG NGHỆ (SYSTEM ARCHITECTURE)
- **Kiến trúc Clean Architecture 3 lớp:**
  - `Domain Layer`: Độc lập 100%, chứa 11 Entity nghiệp vụ và các Service thuật toán (SM-2, Weakness, Planner).
  - `Data Layer`: Drift SQLite ORM (cách ly đa tài khoản), Supabase BaaS, Google ML Kit và Gemini AI Service.
  - `Presentation Layer`: Flutter Material 3, State Management bằng Riverpod 2 (`StateNotifier`, `StreamProvider`), Canvas CustomPainter vẽ biểu đồ 60 FPS.
- **Mô hình bảo vệ API Key Production:** Kiến trúc Supabase Edge Function Proxy (`gemini-study-assistant`) bảo mật khóa bí mật trên server Deno, xác thực người dùng qua JWT.

---

## SLIDE 5: 3 TRỤ CỘT KỸ THUẬT CỐT LÕI (3 TECHNICAL PILLARS)

### Trụ cột 1: Xử lý OCR Hình học Không gian (Spatial Row Clustering)
- Vấn đề: ML Kit OCR thường làm lẫn lộn trật tự đọc của tài liệu chia nhiều cột (multi-column) hoặc slide bài giảng.
- Giải pháp NoteFlow: Thuật toán phân tích tọa độ `boundingBox`, tính độ chồng lấp trục tung $\ge 55\%$ và khoảng cách cột $2.4\times$ để tái lập văn bản tự nhiên 2 chiều.

### Trụ cột 2: Thuật toán Khoa học Nhận thức SuperMemo SM-2
- Cập nhật hệ số dễ $EF'$ và khoảng cách ngày ôn tập $I(n)$ dựa trên đánh giá 4 mức độ của sinh viên (Again, Hard, Good, Easy).
- Hỗ trợ lưu phiên học dở dang (Partial Session Persistence) bảo vệ toàn vẹn dữ liệu.

### Trụ cột 3: Đồng bộ Hai chiều Offline-First
- Sử dụng mô hình Last-Write-Wins (LWW) giải quyết xung đột dựa trên `updated_at`.
- Lưu vết xóa mềm (Tombstones) và tự động khôi phục hàng đợi đột biến (`sync_queue`) khi có mạng trở lại.

---

## SLIDE 6: BỘ 3 TÍNH NĂNG AI THÔNG MINH (INTELLIGENT AI FEATURES)

1. **AI Study Assistant (Trợ lý Học tập AI):**
   - Hoạt động theo nguyên tắc **Context Grounding**: Chỉ trả lời dựa trên học liệu thực tế của sinh viên.
   - Thuật toán thẩm tra căn cứ (`validateGroundedCitations`): Loại bỏ triệt để ảo giác trích dẫn (hallucinations).
   - Tự động sinh câu hỏi trắc nghiệm tự luyện dạng bản nháp an toàn (Draft Mode).
2. **Smart Weakness Detection (Chẩn đoán Điểm Yếu Thích Ứng):**
   - Mô hình toán học trọng số thích ứng $S = w_f \cdot S_f + w_q \cdot S_q$ xử lý linh hoạt 5 kịch bản (Cases A–E).
3. **Personalized Review Planner (Kế hoạch Ôn tập Cá nhân Hóa):**
   - Phân loại 3 mức độ nhiệm vụ: Khẩn cấp (thẻ quá hạn), Trọng tâm (chủ đề yếu) và Củng cố (quiz sai nhiều).
   - Kiểm tra an toàn hoàn thành phiên học (`totalReviewedCardsToday >= overdueCardsCount`).

---

## SLIDE 7: KẾT QUẢ ĐO KIỂM & ĐẢM BẢO CHẤT LƯỢNG (QA & VERIFICATION RESULTS)

- **Kiểm thử Tự động Toàn diện (`flutter test`):**
  - **75/75 ca kiểm thử VƯỢT QUA 100% (0 failed, 0 skipped).**
  - Bao quát Unit Tests, Widget Tests và Local Integration Tests (in-memory SQLite).
- **Phân tích Tĩnh (`flutter analyze`):**
  - **0 lỗi, 0 cảnh báo, 0 lint.**
- **Chuẩn Định dạng Mã nguồn (`dart format`):**
  - **100% tệp mã nguồn tuân thủ tiêu chuẩn.**
- **Biên dịch Bản Release APK:**
  - Biên dịch thành công tệp APK Release (`NoteFlow-AI-v1.0.0.apk` - 95.4MB).
  - Tích hợp cờ **Release Safety Guard** ngăn chặn lộ API Key ra bản build công khai.

---

## SLIDE 8: KẾT LUẬN & HƯỚNG PHÁT TRIỂN
- **Kết luận:**
  - NoteFlow AI đã hoàn thành xuất sắc toàn bộ 5 Giai đoạn trong Lộ trình Cải tiến & Hoàn thiện Đồ án Capstone.
  - Ứng dụng đáp ứng đầy đủ các tiêu chuẩn kỹ thuật phần mềm di động hiện đại: Clean Architecture, Offline-First, An ninh dữ liệu RLS, Thiết kế M3 công thái học và AI có căn cứ.
- **Hướng phát triển tiếp theo:**
  - Triển khai Edge Function Proxy lên Supabase Cloud chính thức sau khi được cấp quyền hạ tầng.
  - Tích hợp mô hình ngôn ngữ nhỏ cục bộ (On-Device SLM) qua MediaPipe GenAI để giải thích bài giảng offline.
  - Bổ sung tính năng tạo sơ đồ tư duy (Mindmap) tự động.
