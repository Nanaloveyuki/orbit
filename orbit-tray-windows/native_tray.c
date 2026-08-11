#include <moonbit.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#include <shellapi.h>

#define ORBIT_TRAY_CALLBACK (WM_APP + 117)
#define ORBIT_TRAY_MENU_BASE 0x4000

typedef struct orbit_tray_item {
  UINT slot;
  HICON icon;
  BOOL visible;
  WCHAR tip[128];
  struct orbit_tray_item *next;
} orbit_tray_item_t;

typedef struct {
  UINT slot;
  uint8_t kind;
  uint16_t command;
} orbit_tray_event_t;

static HWND orbit_tray_window = NULL;
static UINT orbit_tray_taskbar_created = 0;
static UINT orbit_tray_next_slot = 1;
static orbit_tray_item_t *orbit_tray_items = NULL;
static orbit_tray_event_t orbit_tray_events[64];
static UINT orbit_tray_event_head = 0;
static UINT orbit_tray_event_tail = 0;

static void orbit_tray_unlink(orbit_tray_item_t *item) {
  orbit_tray_item_t **cursor = &orbit_tray_items;
  while (*cursor != NULL) {
    if (*cursor == item) { *cursor = item->next; return; }
    cursor = &(*cursor)->next;
  }
}

static void orbit_tray_push(UINT slot, uint8_t kind, uint16_t command) {
  UINT next = (orbit_tray_event_tail + 1) % 64;
  if (next == orbit_tray_event_head) return;
  orbit_tray_events[orbit_tray_event_tail] = (orbit_tray_event_t){slot, kind, command};
  orbit_tray_event_tail = next;
}

static void orbit_tray_fill_tip(WCHAR tip[128], moonbit_bytes_t bytes) {
  int32_t length = Moonbit_array_length(bytes);
  if (length <= 0) { tip[0] = L'\0'; return; }
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)bytes, length, tip, 127);
  tip[127] = L'\0';
}

static BOOL orbit_tray_notify(orbit_tray_item_t *item, DWORD action, const WCHAR *tip) {
  NOTIFYICONDATAW data;
  memset(&data, 0, sizeof(data));
  data.cbSize = sizeof(data);
  data.hWnd = orbit_tray_window;
  data.uID = item->slot;
  data.uCallbackMessage = ORBIT_TRAY_CALLBACK;
  data.hIcon = item->icon;
  data.uFlags = NIF_MESSAGE | NIF_ICON;
  if (tip != NULL) {
    data.uFlags |= NIF_TIP;
    wcsncpy_s(data.szTip, 128, tip, _TRUNCATE);
  }
  return Shell_NotifyIconW(action, &data);
}

static LRESULT CALLBACK orbit_tray_wndproc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == orbit_tray_taskbar_created) {
    for (orbit_tray_item_t *item = orbit_tray_items; item != NULL; item = item->next) {
      if (item->visible) orbit_tray_notify(item, NIM_ADD, item->tip);
    }
    return 0;
  }
  if (message == ORBIT_TRAY_CALLBACK) {
    switch ((UINT)lparam) {
      case WM_LBUTTONUP: orbit_tray_push((UINT)wparam, 1, 0); break;
      case WM_RBUTTONUP:
      case WM_CONTEXTMENU: orbit_tray_push((UINT)wparam, 2, 0); break;
    }
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

static BOOL orbit_tray_ensure_window(void) {
  if (orbit_tray_window != NULL) return TRUE;
  WNDCLASSW cls;
  memset(&cls, 0, sizeof(cls));
  cls.lpfnWndProc = orbit_tray_wndproc;
  cls.hInstance = GetModuleHandleW(NULL);
  cls.lpszClassName = L"OrbitTrayMessageWindow";
  RegisterClassW(&cls);
  orbit_tray_window = CreateWindowExW(0, cls.lpszClassName, L"Orbit", 0, 0, 0, 0, 0, HWND_MESSAGE, NULL, cls.hInstance, NULL);
  orbit_tray_taskbar_created = RegisterWindowMessageW(L"TaskbarCreated");
  return orbit_tray_window != NULL;
}

static HICON orbit_tray_icon(moonbit_bytes_t pixels, int32_t width, int32_t height) {
  if (width <= 0 || height <= 0 || width > 1024 || height > 1024 || Moonbit_array_length(pixels) != width * height * 4) return NULL;
  BITMAPV5HEADER header;
  memset(&header, 0, sizeof(header));
  header.bV5Size = sizeof(header); header.bV5Width = width; header.bV5Height = -height;
  header.bV5Planes = 1; header.bV5BitCount = 32; header.bV5Compression = BI_BITFIELDS;
  header.bV5RedMask = 0x00FF0000; header.bV5GreenMask = 0x0000FF00; header.bV5BlueMask = 0x000000FF; header.bV5AlphaMask = 0xFF000000;
  void *bits = NULL;
  HDC dc = GetDC(NULL);
  HBITMAP color = CreateDIBSection(dc, (BITMAPINFO *)&header, DIB_RGB_COLORS, &bits, NULL, 0);
  ReleaseDC(NULL, dc);
  if (color == NULL || bits == NULL) return NULL;
  const uint8_t *src = (const uint8_t *)pixels; uint8_t *dst = (uint8_t *)bits;
  for (int32_t i = 0; i < width * height; i++) { dst[i * 4] = src[i * 4 + 2]; dst[i * 4 + 1] = src[i * 4 + 1]; dst[i * 4 + 2] = src[i * 4]; dst[i * 4 + 3] = src[i * 4 + 3]; }
  ICONINFO info; memset(&info, 0, sizeof(info)); info.fIcon = TRUE; info.hbmColor = color; info.hbmMask = color;
  HICON icon = CreateIconIndirect(&info); DeleteObject(color); return icon;
}

static void orbit_tray_finalize(void *ptr) {
  orbit_tray_item_t *item = (orbit_tray_item_t *)ptr;
  if (item->visible && orbit_tray_window != NULL) orbit_tray_notify(item, NIM_DELETE, NULL);
  if (item->icon != NULL) DestroyIcon(item->icon);
  orbit_tray_unlink(item);
}

MOONBIT_FFI_EXPORT orbit_tray_item_t *orbit_tray_windows_create_item(moonbit_bytes_t pixels, int32_t width, int32_t height, moonbit_bytes_t tooltip, int32_t visible, int32_t *status) {
  *status = 0; if (!orbit_tray_ensure_window()) { *status = 1; return NULL; }
  HICON icon = orbit_tray_icon(pixels, width, height); if (icon == NULL) { *status = 2; return NULL; }
  orbit_tray_item_t *item = moonbit_make_external_object(orbit_tray_finalize, sizeof(*item));
  item->slot = orbit_tray_next_slot++; item->icon = icon; item->visible = visible != 0; item->next = orbit_tray_items; orbit_tray_items = item;
  orbit_tray_fill_tip(item->tip, tooltip);
  if (item->visible && !orbit_tray_notify(item, NIM_ADD, item->tip)) { *status = 3; item->visible = FALSE; }
  return item;
}

MOONBIT_FFI_EXPORT void orbit_tray_windows_replace_item(orbit_tray_item_t *item, moonbit_bytes_t pixels, int32_t width, int32_t height, moonbit_bytes_t tooltip, int32_t visible, int32_t *status) {
  *status = 0; if (item == NULL) { *status = 1; return; }
  HICON icon = orbit_tray_icon(pixels, width, height); if (icon == NULL) { *status = 2; return; }
  if (item->visible) orbit_tray_notify(item, NIM_DELETE, NULL); if (item->icon != NULL) DestroyIcon(item->icon);
  item->icon = icon; item->visible = visible != 0; orbit_tray_fill_tip(item->tip, tooltip);
  if (item->visible && !orbit_tray_notify(item, NIM_ADD, item->tip)) { *status = 3; item->visible = FALSE; }
}

MOONBIT_FFI_EXPORT void orbit_tray_windows_destroy_item(orbit_tray_item_t *item) { if (item != NULL && item->visible) { orbit_tray_notify(item, NIM_DELETE, NULL); item->visible = FALSE; } }
MOONBIT_FFI_EXPORT int32_t orbit_tray_windows_item_slot(orbit_tray_item_t *item) { return item == NULL ? 0 : (int32_t)item->slot; }
static uint16_t orbit_tray_u16(const uint8_t **cursor, const uint8_t *end, int *ok) { if (*cursor + 2 > end) { *ok = 0; return 0; } uint16_t value = (uint16_t)(*cursor)[0] | ((uint16_t)(*cursor)[1] << 8); *cursor += 2; return value; }
static WCHAR *orbit_tray_text(const uint8_t **cursor, const uint8_t *end, int *ok) { uint16_t length = orbit_tray_u16(cursor, end, ok); if (!*ok || *cursor + length > end) { *ok = 0; return NULL; } int needed = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)*cursor, length, NULL, 0); if (needed <= 0) { *ok = 0; return NULL; } WCHAR *text = calloc((size_t)needed + 1, sizeof(WCHAR)); if (text == NULL || !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)*cursor, length, text, needed)) { free(text); *ok = 0; return NULL; } *cursor += length; return text; }
static HMENU orbit_tray_parse_menu(const uint8_t **cursor, const uint8_t *end, int *ok) { HMENU menu = CreatePopupMenu(); if (menu == NULL) { *ok = 0; return NULL; } while (*cursor < end && *ok) { uint8_t tag = *(*cursor)++; if (tag == 2) { AppendMenuW(menu, MF_SEPARATOR, 0, NULL); continue; } WCHAR *label = orbit_tray_text(cursor, end, ok); if (!*ok) break; if (tag == 1) { if (*cursor + 4 > end) { free(label); *ok = 0; break; } uint8_t enabled = *(*cursor)++; uint8_t checked = *(*cursor)++; uint16_t index = orbit_tray_u16(cursor, end, ok); UINT flags = MF_STRING | (enabled ? MF_ENABLED : MF_GRAYED) | (checked ? MF_CHECKED : MF_UNCHECKED); AppendMenuW(menu, flags, ORBIT_TRAY_MENU_BASE + index, label); free(label); } else if (tag == 3) { uint16_t child_length = orbit_tray_u16(cursor, end, ok); if (!*ok || *cursor + child_length > end) { free(label); *ok = 0; break; } const uint8_t *child_cursor = *cursor; const uint8_t *child_end = child_cursor + child_length; HMENU child = orbit_tray_parse_menu(&child_cursor, child_end, ok); if (!*ok || child_cursor != child_end || child == NULL) { free(label); if (child != NULL) DestroyMenu(child); *ok = 0; break; } *cursor = child_end; AppendMenuW(menu, MF_POPUP | MF_STRING, (UINT_PTR)child, label); free(label); } else { free(label); *ok = 0; break; } } if (!*ok) { DestroyMenu(menu); return NULL; } return menu; }
MOONBIT_FFI_EXPORT void orbit_tray_windows_open_menu(orbit_tray_item_t *item, moonbit_bytes_t menu, int32_t *status) { *status = 0; if (item == NULL || orbit_tray_window == NULL) { *status = 1; return; } const uint8_t *cursor = menu; const uint8_t *end = cursor + Moonbit_array_length(menu); int ok = 1; HMENU popup = orbit_tray_parse_menu(&cursor, end, &ok); if (!ok || cursor != end || popup == NULL) { *status = 2; return; } POINT point; GetCursorPos(&point); SetForegroundWindow(orbit_tray_window); UINT selected = TrackPopupMenuEx(popup, TPM_RETURNCMD | TPM_RIGHTBUTTON, point.x, point.y, orbit_tray_window, NULL); PostMessageW(orbit_tray_window, WM_NULL, 0, 0); DestroyMenu(popup); if (selected >= ORBIT_TRAY_MENU_BASE) orbit_tray_push(item->slot, 3, (uint16_t)(selected - ORBIT_TRAY_MENU_BASE)); }
MOONBIT_FFI_EXPORT moonbit_bytes_t orbit_tray_windows_next_event(void) { if (orbit_tray_event_head == orbit_tray_event_tail) return moonbit_make_bytes(0, 0); orbit_tray_event_t event = orbit_tray_events[orbit_tray_event_head]; orbit_tray_event_head = (orbit_tray_event_head + 1) % 64; moonbit_bytes_t out = moonbit_make_bytes(7, 0); out[0] = event.slot; out[1] = event.slot >> 8; out[2] = event.slot >> 16; out[3] = event.slot >> 24; out[4] = event.kind; out[5] = event.command; out[6] = event.command >> 8; return out; }
#else
typedef void *orbit_tray_item_t;
MOONBIT_FFI_EXPORT orbit_tray_item_t orbit_tray_windows_create_item(void *a, int32_t b, int32_t c, void *d, int32_t e, int32_t *status) { (void)a;(void)b;(void)c;(void)d;(void)e;*status=1;return NULL; }
MOONBIT_FFI_EXPORT void orbit_tray_windows_replace_item(void *a,void*b,int32_t c,int32_t d,void*e,int32_t f,int32_t*status){(void)a;(void)b;(void)c;(void)d;(void)e;(void)f;*status=1;}
MOONBIT_FFI_EXPORT void orbit_tray_windows_destroy_item(void *item){(void)item;}
MOONBIT_FFI_EXPORT int32_t orbit_tray_windows_item_slot(void *item){(void)item;return 0;}
MOONBIT_FFI_EXPORT void orbit_tray_windows_open_menu(void *item,void*menu,int32_t*status){(void)item;(void)menu;*status=1;}
MOONBIT_FFI_EXPORT moonbit_bytes_t orbit_tray_windows_next_event(void){return moonbit_make_bytes(0,0);}
#endif
