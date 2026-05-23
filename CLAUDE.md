# CLAUDE.md — Studio Design App: localStorage → Supabase Migration

## 1. Mô tả dự án

**App:** Studio Design — quản lý dự án kiến trúc phối cảnh JP/VN  
**File chính:** `index.html` — single HTML file, 7584 dòng, toàn bộ app trong 1 file  
**Không có framework, không có build step** — chạy thẳng trong trình duyệt  
**Thư mục làm việc:** `E:\Dropbox\Bảng kết quả (Selective Sync Conflict)\`

### Cấu trúc dữ liệu hiện tại

```
D (global JS object — nguồn render DUY NHẤT)
├── D.activeMonth          → "YYYY-MM"
├── D.settings
│   ├── staffList[]        → 10 nhân viên, prefix SGN/HAN/Management
│   ├── staffProfiles{}    → {name: {role, salary, leaves[], lateLog[], trips[]}}
│   ├── typeList[]         → loại phối cảnh JP
│   ├── contactList[]      → danh sách liên hệ
│   └── sync{}             → password hashes (adminHash, editHash, viewHash)
└── D.months{}
    └── [YYYY-MM]
        ├── projects[]     → dự án JP
        ├── projectsVN[]   → dự án VN
        ├── targetNew      → target số lượng mới
        └── targetRev      → target số lượng sửa
            └── projects[i]
                ├── id, nameVN, nameJP, office, contact, mainStaff
                ├── groups[]
                │   └── {id, type, rows[]}
                │       └── rows[i]: {id, staff, status, qty, dateFrom, dateTo,
                │                     upTime, doneAt, upScore, ot, otNote,
                │                     note, rate0..rate13}
                ├── photos[]   → base64 strings (tốn bộ nhớ)
                ├── otLog[]    → [{staff, hours, date, note}]
                └── tlTasks[]  → Gantt tasks VN
```

### Auth hiện tại (3 role)

| Role | Password | Quyền |
|------|----------|-------|
| admin | 204290 | Toàn quyền |
| edit | 123456 | Nhập liệu, sửa |
| view | 280510 | Chỉ xem |

Hash lưu trong `D.settings.sync.adminHash/editHash/viewHash`

### Các function quan trọng

| Function | Vị trí | Mô tả |
|----------|--------|-------|
| `freshData()` | dòng 654 | Tạo D rỗng mặc định |
| `persistD()` / `save()` | dòng 726, 803 | Ghi D → localStorage |
| `renderAll()` | dòng 6979 | Re-render toàn bộ UI từ D |
| `_splashLogin()` | dòng 7503 | Xử lý đăng nhập splash |
| `initSplash()` | dòng 7501 | IIFE khởi động auth |
| `syncPush/Pull()` | dòng 6250, 6285 | Sync GitHub Gist (sẽ thay) |
| `addGroup/Row()` | dòng 3979, 3986 | Thêm hạng mục/dòng |
| `updRow()` | dòng 4023 | Cập nhật dòng (hotpath) |
| `markRowDone()` | dòng 3499 | Đánh dấu hoàn thành |
| `saveStaffProfile()` | dòng 4904 | Lưu hồ sơ nhân viên |

---

## 2. Supabase Configuration

```
URL:      https://kefwrfxeneropihedght.supabase.co
ANON KEY: sb_publishable__B9f2R2Y1JMsvQ2NkmTU9Q_T8f4McGZ
```

Chi tiết trong `supabase_config.js`.  
Service role key: truyền qua biến môi trường `SUPABASE_SERVICE_KEY`.

### 12 bảng đã tạo (xem `SUPABASE_SCHEMA.sql`)

```
settings · months · projects · project_photos
groups · rows · tl_tasks · ot_log
staff · staff_leaves · staff_late_log · business_trips
```

### 3 views

```
v_project_totals · v_staff_monthly_kpi · v_upcoming_deadlines
```

### Mapping tên field JS → Supabase column

| JS (D object) | Supabase column |
|---|---|
| `nameVN` / `nameJP` | `name_vn` / `name_jp` |
| `mainStaff` | `main_staff` |
| `dateFrom` / `dateTo` | `date_from` / `date_to` |
| `upTime` | `up_time` |
| `doneAt` | `done_at` |
| `upScore` | `up_score` |
| `otNote` | `ot_note` |
| `targetNew` / `targetRev` | `target_new` / `target_rev` |
| `salaryGross` / `salaryNet` | `salary_gross` / `salary_net` |
| `contractEnd` | `contract_end` |
| `_carryover` | `is_carryover` |
| `rate0..rate13` | `rate0..rate13` (giữ nguyên) |

---

## 3. Nguyên tắc BẮT BUỘC (không được vi phạm)

### 3.1 Kiểm tra syntax sau MỌI thay đổi index.html

```bash
python check_syntax3.py
```

Script này nằm ở thư mục gốc. Nếu báo lỗi syntax → **DỪNG NGAY**, sửa
lỗi trước khi tiếp tục. Không bao giờ bỏ qua bước này.

Nếu `check_syntax3.py` không còn tồn tại, tạo lại từ logic sau:
- Extract JS từ `<script>` tag
- Preprocess: `?.` → `.`, `??` → `||`, `||=` → `=`, `?.[` → `[`
- Parse bằng `esprima.parseScript(js, tolerant=True)`
- Report lỗi nếu có

### 3.2 Không xóa tính năng cũ

- **localStorage vẫn phải hoạt động** sau mỗi phase
- **GitHub Gist sync** giữ nguyên đến Phase 9
- **Mọi Supabase call là THÊM VÀO**, không thay thế code cũ
- Pattern: `existingCode(); await sbNewCode();`

### 3.3 D object là nguồn render duy nhất

- KHÔNG render trực tiếp từ Supabase response
- Luôn cập nhật D trước (`D.months[mid].projects.push(p)`)
- Sau đó mới gọi Supabase async
- `renderAll()` / `renderContent()` chỉ đọc từ D

### 3.4 Optimistic update — UI không chờ Supabase

```js
// ĐÚNG: cập nhật D + render ngay, Supabase async sau
p.notes = val
save()
renderContent()
sbSaveProject(p, mid, section)  // không await ở UI path

// SAI: chờ Supabase xong mới render
await sbSaveProject(p, mid, section)
renderContent()
```

Ngoại lệ: `markRowDone()` — ghi ngay không debounce vì quan trọng.

### 3.5 Bảo vệ file backup

**TUYỆT ĐỐI KHÔNG** đọc, sửa, hoặc tham chiếu để sửa file:
```
index_backup_20260429.html
```
File này là bản gốc để rollback. Chỉ được đọc nếu cần so sánh logic.

### 3.6 Debounce cho updRow()

`updRow()` trigger sau mỗi keystroke. Supabase call phải debounce 1500ms:

```js
const _sbRowDebounce = {}
function sbSaveRowDebounced(groupId, rowId, colData) {
  clearTimeout(_sbRowDebounce[rowId])
  _sbRowDebounce[rowId] = setTimeout(() =>
    _sb.from('rows').upsert({ id: rowId, group_id: groupId, ...colData }, { onConflict: 'id' })
  , 1500)
}
```

### 3.7 Xử lý lỗi Supabase — không crash app

```js
// Mọi Supabase call phải wrap try/catch
try {
  await _sb.from('rows').upsert(...)
} catch(e) {
  console.warn('[Supabase] row upsert failed:', e.message)
  // App vẫn chạy bình thường qua localStorage
}
```

---

## 4. Thứ tự thực hiện

Thực hiện theo đúng thứ tự Phase 0 → 6. KHÔNG bỏ qua phase.
KHÔNG thực hiện Phase 7, 8, 9 trừ khi được yêu cầu rõ ràng.

### PHASE 0 — Setup SDK

**Mục tiêu:** Thêm Supabase CDN vào index.html, không đổi logic.

**Vị trí chèn:** Tìm dòng `<script>` đầu tiên trong `<head>`, chèn TRƯỚC nó:

```html
<!-- Supabase SDK — Phase 0 migration -->
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js"></script>
<script>
  const _sb = supabase.createClient(
    'https://kefwrfxeneropihedght.supabase.co',
    'sb_publishable__B9f2R2Y1JMsvQ2NkmTU9Q_T8f4McGZ',
    { auth: { persistSession: false, autoRefreshToken: false } }
  )
  window._sbReady = true
</script>
```

**Verify:** `python check_syntax3.py` → OK, mở app → console không có lỗi.

---

### PHASE 1 — Auth via Supabase

**Mục tiêu:** `_splashLogin()` kiểm tra password qua Supabase settings
thay vì `SPLASH_PW` hardcode. Giữ nguyên `SPLASH_PW` làm fallback.

**Vị trí sửa:** Hàm `_splashLogin` trong IIFE `initSplash` (dòng ~7503).

**Logic mới** (thêm TRƯỚC `const role = SPLASH_PW[pw] || null`):

```js
// Thử Supabase trước (nếu có network)
let role = null
try {
  const h = await hashPw(pw)
  // Fast path: kiểm tra local D.settings.sync hashes
  const sc = D?.settings?.sync || {}
  if (h === sc.adminHash) role = 'admin'
  else if (h === sc.editHash) role = 'edit'
  else if (h === sc.viewHash) role = 'view'

  // Fallback: query Supabase (thiết bị mới, D chưa load)
  if (!role && window._sbReady) {
    const { data } = await _sb.from('settings').select('sync_config').single()
    const cfg = data?.sync_config || {}
    if (h === cfg.adminHash) role = 'admin'
    else if (h === cfg.editHash) role = 'edit'
    else if (h === cfg.viewHash) role = 'view'
  }
} catch(e) {
  console.warn('[Auth] Supabase check failed, fallback to local:', e.message)
}
// Legacy fallback — giữ nguyên
if (!role) role = SPLASH_PW[pw] || null
```

**Verify:** Đăng nhập 3 role → đúng. Sai password → báo lỗi.

---

### PHASE 2 — Load D từ Supabase

**Mục tiêu:** Sau login, fetch data từ Supabase để D luôn up-to-date.
localStorage vẫn là primary source khi offline.

**Thêm hàm `sbLoadAll()`** vào đầu `<script>` chính (sau phần `const SK = ...`):

Xem code đầy đủ trong `MIGRATION_PLAN.md` → mục "PHASE 2 — Hàm cần viết: sbLoadAll()".

**Sửa `_splashLogin()`** — sau khi xác định role thành công, thêm:

```js
// Load data từ Supabase (sau khi xác định role)
if (window._sbReady) {
  try {
    setSyncStatus('syncing', 'Đang tải…')
    const sbData = await sbLoadAll()
    if (sbData) {
      D = sbData
      try { localStorage.setItem(SK, JSON.stringify(D)) } catch(e) {}
    }
  } catch(e) {
    console.warn('[Phase 2] sbLoadAll failed, dùng localStorage:', e.message)
  }
}
// Tiếp tục renderAll() như cũ
```

**Verify:** Login → network tab thấy request đến Supabase → data đúng.

---

### PHASE 3 — Write: Settings & Months

**Mục tiêu:** Thay đổi settings và tháng được ghi lên Supabase.

**3a. Cache settings ID** — trong `sbLoadAll()`, sau khi fetch settings:
```js
window._sbSettingsId = settingsRow?.id
```

**3b. Sửa `saveSettings()` (dòng ~6038)** — thêm vào cuối trước `toast()`:
```js
if (window._sbReady && window._sbSettingsId) {
  try {
    await _sb.from('settings').update({
      staff_list: D.settings.staffList,
      type_list: D.settings.typeList,
      type_list_vn: D.settings.typeListVN,
      contact_list: D.settings.contactList,
      contact_list_vn: D.settings.contactListVN,
      holidays: D.settings.holidays,
    }).eq('id', window._sbSettingsId)
  } catch(e) { console.warn('[Phase 3] settings update failed:', e.message) }
}
```

**3c. Sửa `updateMonthTarget(field, val)` (dòng ~2050)**:
```js
if (window._sbReady) {
  const col = field === 'targetNew' ? 'target_new' : 'target_rev'
  try { await _sb.from('months').update({ [col]: +val }).eq('id', D.activeMonth) }
  catch(e) { console.warn('[Phase 3] month update failed:', e.message) }
}
```

**3d. Sửa `doAddMonth()` (dòng ~1016)** — sau khi tạo D.months[newMid]:
```js
if (window._sbReady) {
  try { await _sb.from('months').upsert({ id: newMid, target_new: 0, target_rev: 0 }) }
  catch(e) { console.warn('[Phase 3] addMonth failed:', e.message) }
}
```

**Verify:** Sửa settings → xem Supabase Table Editor → bảng settings cập nhật.

---

### PHASE 4 — Write: Projects CRUD

**Mục tiêu:** Thêm/sửa/xóa dự án ghi lên Supabase.

**Thêm helper** vào đầu script:
```js
async function _sbSaveProject(p, monthId, section) {
  if (!window._sbReady) return
  try {
    await _sb.from('projects').upsert({
      id: p.id, month_id: monthId, section,
      name_vn: p.nameVN || '', name_jp: p.nameJP || '',
      office: p.office || '', contact: p.contact || '',
      main_staff: p.mainStaff || '', notes: p.notes || '',
      is_carryover: !!p._carryover,
    }, { onConflict: 'id' })
  } catch(e) { console.warn('[Phase 4] saveProject failed:', e.message) }
}
```

**Sửa `confirmAddPj()` (dòng ~4134)** — sau `save()`:
```js
_sbSaveProject(pj, D.activeMonth, activeSection)
```

**Sửa `confirmEditPj(id)` (dòng ~4180)** — sau `save()`:
```js
_sbSaveProject(p, D.activeMonth, activeSection)
```

**Sửa `deletePj(id)` (dòng ~4435)** — sau xác nhận xóa khỏi D, trước `save()`:
```js
if (window._sbReady) {
  try { await _sb.from('projects').delete().eq('id', id) }
  catch(e) { console.warn('[Phase 4] deletePj failed:', e.message) }
}
```

**Verify:** Thêm dự án → Supabase Table Editor → thấy row mới trong `projects`.

---

### PHASE 5 — Write: Groups & Rows

**Mục tiêu:** Mọi thay đổi group/row ghi lên Supabase (hotpath).

**Thêm helpers**:
```js
const _sbRowDebounce = {}
function _sbSaveRowDebounced(groupId, rowId, colData) {
  if (!window._sbReady) return
  clearTimeout(_sbRowDebounce[rowId])
  _sbRowDebounce[rowId] = setTimeout(async () => {
    try {
      await _sb.from('rows').upsert(
        { id: rowId, group_id: groupId, ...colData },
        { onConflict: 'id' }
      )
    } catch(e) { console.warn('[Phase 5] row upsert failed:', e.message) }
  }, 1500)
}

const _COL_MAP = {
  staff:'staff', status:'status', qty:'qty', note:'note',
  ot:'ot', otNote:'ot_note', dateFrom:'date_from', dateTo:'date_to',
  upTime:'up_time', doneAt:'done_at', upScore:'up_score',
  rate0:'rate0',rate1:'rate1',rate2:'rate2',rate3:'rate3',rate4:'rate4',
  rate5:'rate5',rate6:'rate6',rate7:'rate7',rate8:'rate8',rate9:'rate9',
  rate10:'rate10',rate11:'rate11',rate12:'rate12',rate13:'rate13',
}
```

**Sửa `addGroup(pjId)` (dòng ~3979)** — sau `save()`:
```js
if (window._sbReady) {
  const g = p.groups[p.groups.length - 1]
  try {
    await _sb.from('groups').insert({ id: g.id, project_id: pjId, type: '', sort_order: p.groups.length - 1 })
    await _sb.from('rows').insert({ id: g.rows[0].id, group_id: g.id, status: 'new', qty: 0, ot: 0 })
  } catch(e) { console.warn('[Phase 5] addGroup failed:', e.message) }
}
```

**Sửa `addRow(pjId, gid)` (dòng ~3986)** — sau `save()`:
```js
if (window._sbReady) {
  const r = g.rows[g.rows.length - 1]
  try { await _sb.from('rows').insert({ id: r.id, group_id: gid, status: 'new', qty: 0, ot: 0 }) }
  catch(e) { console.warn('[Phase 5] addRow failed:', e.message) }
}
```

**Sửa `updRow(pjId, gid2, rid, field, val)` (dòng ~4023)** — sau `persistD()`:
```js
const col = _COL_MAP[field]
if (col) _sbSaveRowDebounced(gid2, rid, { [col]: val || null })
```

**Sửa `markRowDone(pjId, gid, rid)` (dòng ~3499)** — ghi ngay, không debounce:
```js
if (window._sbReady) {
  try { await _sb.from('rows').update({ done_at: r.doneAt, up_score: r.upScore }).eq('id', rid) }
  catch(e) { console.warn('[Phase 5] markRowDone failed:', e.message) }
}
```

**Sửa `delGroup(pjId, gid2)` (dòng ~3992)** — sau confirm, trước `save()`:
```js
if (window._sbReady) {
  try { await _sb.from('groups').delete().eq('id', gid2) }
  catch(e) { console.warn('[Phase 5] delGroup failed:', e.message) }
}
```

**Sửa `delRow(pjId, gid2, rid)` (dòng ~3998)** — sau tìm được row:
```js
if (window._sbReady) {
  try { await _sb.from('rows').delete().eq('id', rid) }
  catch(e) { console.warn('[Phase 5] delRow failed:', e.message) }
}
```

**Sửa `updGroup(pjId, gid2, field, val)` (dòng ~4018)** — sau `save()`:
```js
if (window._sbReady && field === 'type') {
  try { await _sb.from('groups').update({ type: val }).eq('id', gid2) }
  catch(e) { console.warn('[Phase 5] updGroup failed:', e.message) }
}
```

**Verify:** Thay đổi qty/staff/deadline → sau 1.5s → Supabase rows cập nhật.
Bấm "✓ UP" → Supabase `done_at` cập nhật ngay.

---

### PHASE 6 — Write: Staff

**Mục tiêu:** Thay đổi profile, leave, late log, trips ghi lên Supabase.

**Cache staff ID map** — trong `sbLoadAll()` sau khi build staffProfiles:
```js
window._sbStaffIdByName = {}
for (const s of (staffRows || [])) window._sbStaffIdByName[s.full_name] = s.id
```

**Sửa `saveStaffProfile(name, field, val)` (dòng ~4904)**:
```js
const COL_STAFF = {
  role:'role', salaryGross:'salary_gross', salaryNet:'salary_net',
  contractEnd:'contract_end', order:'sort_order'
}
const col = COL_STAFF[field]
if (col && window._sbReady) {
  try { await _sb.from('staff').update({ [col]: val }).eq('full_name', name) }
  catch(e) { console.warn('[Phase 6] saveStaffProfile failed:', e.message) }
}
```

**Sửa `addLateRecord(name, date, minutes, note)` (dòng ~4914)**:
```js
const sid = window._sbStaffIdByName?.[name]
if (sid && window._sbReady) {
  try {
    await _sb.from('staff_late_log').upsert(
      { staff_id: sid, late_date: date, minutes: +minutes, note: note || '' },
      { onConflict: 'staff_id,late_date' }
    )
  } catch(e) { console.warn('[Phase 6] addLateRecord failed:', e.message) }
}
```

**Sửa `deleteLateRecord(name, date)` (dòng ~4923)**:
```js
const sid = window._sbStaffIdByName?.[name]
if (sid && window._sbReady) {
  try { await _sb.from('staff_late_log').delete().eq('staff_id', sid).eq('late_date', date) }
  catch(e) { console.warn('[Phase 6] deleteLateRecord failed:', e.message) }
}
```

**Sửa `confirmAddLeave(name)` (dòng ~5170)**:
```js
const sid = window._sbStaffIdByName?.[name]
if (sid && window._sbReady) {
  const lv = prof.leaves[prof.leaves.length - 1]
  try {
    await _sb.from('staff_leaves').insert({
      staff_id: sid, date_from: lv.from, date_to: lv.to || null,
      session: lv.session || 'all', reason: lv.reason || ''
    })
  } catch(e) { console.warn('[Phase 6] addLeave failed:', e.message) }
}
```

**Sửa `delLeave(staffName, leaveId)` (dòng ~5184)**:
```js
if (window._sbReady) {
  try { await _sb.from('staff_leaves').delete().eq('id', leaveId) }
  catch(e) { console.warn('[Phase 6] delLeave failed:', e.message) }
}
```

**Sửa `addTrip(name)` (dòng ~5109)**:
```js
const sid = window._sbStaffIdByName?.[name]
if (sid && window._sbReady) {
  const t = prof.trips[prof.trips.length - 1]
  try {
    await _sb.from('business_trips').insert({
      staff_id: sid, date_from: t.from, date_to: t.to || null, destination: t.note || ''
    })
  } catch(e) { console.warn('[Phase 6] addTrip failed:', e.message) }
}
```

**Sửa `deleteTrip(name, id)` (dòng ~5121)**:
```js
if (window._sbReady) {
  try { await _sb.from('business_trips').delete().eq('id', id) }
  catch(e) { console.warn('[Phase 6] deleteTrip failed:', e.message) }
}
```

**Verify:** Thêm nghỉ phép → Supabase `staff_leaves` có row mới. Xóa → mất.

---

## 5. Sau mỗi phase: tạo file PHASE_X_DONE.md

Sau khi hoàn thành và verify xong một phase, tạo file:
`PHASE_X_DONE.md` (X = số phase: 0, 1, 2, ...)

Nội dung bắt buộc:

```markdown
# Phase X — [Tên phase] — DONE

**Ngày hoàn thành:** YYYY-MM-DD  
**Syntax check:** PASS (python check_syntax3.py)

## Thay đổi đã thực hiện
- [liệt kê từng hàm đã sửa, dòng số cụ thể]

## Verify kết quả
- [mô tả đã kiểm tra như thế nào]

## Dòng số trong index.html đã thay đổi
- [danh sách dòng và nội dung thay đổi]

## Vấn đề gặp phải (nếu có)
- [mô tả nếu có, hoặc "Không có"]
```

---

## 6. Xử lý lỗi: ERRORS.md

Nếu gặp bất kỳ lỗi nào KHÔNG tự xử lý được, thực hiện 3 bước sau rồi DỪNG:

**Bước 1:** Khôi phục `index.html` về trạng thái trước khi bắt đầu phase đó
(dùng nội dung từ file PHASE trước hoặc từ `index_backup_20260429.html` làm tham chiếu).

**Bước 2:** Tạo/cập nhật `ERRORS.md`:

```markdown
# ERRORS LOG

## [Timestamp] Phase X — [Tên phase]

**Lỗi:** [mô tả lỗi đầy đủ]  
**File:** [tên file, dòng số]  
**Code gây lỗi:**
```
[code snippet]
```
**Đã thử:**
- [các cách đã thử]

**Cần làm:**
- [gợi ý hướng xử lý cho lần sau]
```

**Bước 3:** Dừng hoàn toàn. Không tiếp tục phase tiếp theo.
Thông báo cho người dùng nội dung của `ERRORS.md`.

---

## 7. Checklist trước khi bắt đầu mỗi phase

Trước khi bắt đầu Phase X, kiểm tra:

- [ ] File `PHASE_{X-1}_DONE.md` tồn tại (phase trước đã xong)
- [ ] `python check_syntax3.py` → PASS trên `index.html` hiện tại
- [ ] `index_backup_20260429.html` KHÔNG bị sửa (so sánh size với 788202 bytes)
- [ ] Supabase project còn hoạt động (ping: `_sb.from('settings').select('id').single()`)
- [ ] Không có file `ERRORS.md` còn mở (nếu có, phải xử lý xong mới tiếp)

---

## 8. Files trong thư mục

```
index.html                    ← FILE CHÍNH — đang sửa
index_backup_20260429.html    ← BẢN GỐC — KHÔNG BAO GIỜ SỬA
SUPABASE_SCHEMA.sql           ← Schema 12 bảng đã tạo
MIGRATION_PLAN.md             ← Kế hoạch chi tiết từng phase
supabase_config.js            ← URL + anon key
migrate_to_supabase.js        ← Script migration data (đã chạy xong)
package.json                  ← Node.js config (type: module)
node_modules/                 ← @supabase/supabase-js đã cài
check_syntax3.py              ← Bắt buộc chạy sau mỗi thay đổi index.html
PHASE_X_DONE.md               ← Tạo sau mỗi phase hoàn thành
ERRORS.md                     ← Tạo khi có lỗi không xử lý được
CLAUDE.md                     ← File này
```

---

## 9. Lệnh thường dùng

```bash
# Kiểm tra syntax JS sau khi sửa index.html
python check_syntax3.py

# Chạy migration data (đã chạy rồi, chỉ dùng lại nếu cần)
$env:SUPABASE_SERVICE_KEY="..."; node migrate_to_supabase.js phoicanh_backup_2026-04-29.json

# Kiểm tra Node.js (full path vì không trong PATH)
& "C:\Program Files\nodejs\node.exe" --version

# Kiểm tra Python
python --version
```

---

## 10. Những điều KHÔNG được làm

1. **Không sửa `index_backup_20260429.html`** — bất kỳ lý do gì
2. **Không xóa bất kỳ function nào** trong Phase 0-6
3. **Không dùng `await` trực tiếp ở top-level** trong `<script>` (không phải module)
4. **Không thêm `type="module"`** vào thẻ `<script>` của index.html
   (app dùng global scope, `type="module"` sẽ phá vỡ tất cả)
5. **Không gọi `renderAll()` từ bên trong Supabase callback** mà không debounce
   (gây infinite loop nếu callback trigger write)
6. **Không skip `python check_syntax3.py`** dù thay đổi nhỏ
7. **Không tiếp tục phase tiếp theo** khi còn lỗi chưa giải quyết

---

## Mac setup
Setup hoàn tất ngày 2026-05-23. Workflow: sửa code → chạy ./deploy.sh
