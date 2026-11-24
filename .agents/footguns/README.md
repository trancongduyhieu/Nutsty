# Nutsty Footguns: mỗi pattern một file

Thư viện bẫy lỗi và pattern ĐÃ CHỨNG MINH của Nutsty, tổ chức giống
`references/kotlin-footguns` (SimpMusic). Mỗi pattern chung nằm trong một thư mục riêng:

```
.agents/footguns/
├── README.md            # file này: cách dùng, cách viết thêm
├── CATALOG.md           # mục lục theo nhóm, mỗi pattern một dòng
└── skills/<ten-kebab>/SKILL.md
```

## Khác gì `.agents/rules/`

- `.agents/rules/` là bản đồ kiến trúc theo domain, có ngân sách cứng ≤100 dòng mỗi file. Nó trả
  lời câu hỏi "phần này nằm ở đâu, chạy thế nào".
- `.agents/footguns/` là các bẫy cụ thể, KHÔNG có giới hạn 100 dòng. Mỗi file viết đủ dài để
  người sửa sau hiểu vì sao code trông "thừa" mà không dám xoá. Nó trả lời câu hỏi "sửa chỗ này
  thì đã có ai ngã ở đâu".
- Rule có thể trỏ sang footgun bằng một dòng (`xem footguns/<tên>`), không chép nội dung sang.

## Khi nào đọc

Trước khi sửa một vùng code, mở `CATALOG.md`, tìm theo triệu chứng hoặc tên file, rồi đọc
SKILL.md tương ứng. Phần `description` trong frontmatter ghi cả triệu chứng người dùng thấy, để
tìm được ngay cả khi chưa biết nguyên nhân.

## Giải phẫu một SKILL.md

1. **Frontmatter**: `name` trùng tên thư mục. `description` một đoạn gồm: pattern là gì, dùng khi
   nào, triệu chứng nào báo hiệu nó.
2. **Mở đầu** (một tiêu đề, 1–3 đoạn) kèm một khối code `// adapted:` trỏ về file thật, tối đa
   khoảng 25 dòng. Đây là hình dạng của lời giải, không phải bản copy.
3. **`## Traps`** là phần chính. Mỗi bẫy là một đoạn mở bằng câu **in đậm** nói kết luận, sau đó
   là cơ chế (vì sao hỏng) và cách sửa. Ghi cả nhánh KHÔNG được chặn, vì bản vá hay chặn quá tay.
4. **`## Verifying it`** gồm các lệnh chạy được ngay từ gốc repo, kèm mô tả kết quả đúng trông
   như thế nào. Ưu tiên test có sẵn và grep kiểm kê (mọi chỗ gọi đều phải có X).

Độ dài thường khoảng 60–140 dòng. Dài hơn thì tách thành hai pattern.

## Quy tắc khi thêm pattern

- Chỉ ghi điều đã được chứng minh: có test, có harness tái hiện, hoặc đã quan sát trên app thật.
  Phần nào chưa đo thì ghi rõ "CHƯA kiểm chứng".
- Tên mô tả hành vi (`drop-late-async-responses`), không đặt theo tên file hay tên tính năng.
- Thêm một dòng vào `CATALOG.md` đúng nhóm. Nhóm chưa có thì tạo nhóm mới.
- Liên kết chéo bằng tên pattern trong backtick. Bản Kotlin tương ứng ghi dạng
  `references/kotlin-footguns/skills/<tên>`.
- Không emoji, không đường dẫn tuyệt đối tới home của ai.
